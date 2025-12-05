/**
 * Aurora HTTP Server - Fiber-based Architecture
 *
 * Architecture: vibe-core fiber pool with async I/O
 * 
 * Platform-specific optimizations:
 * - Linux/FreeBSD: SO_REUSEPORT with N worker threads (kernel load balancing)
 * - macOS/Windows: Single event loop with fiber pool
 *
 * All platforms use non-blocking I/O with fiber scheduling for high concurrency.
 * This provides 10-100x better performance under load compared to blocking I/O.
 */
module aurora.runtime.server;

// ============================================================================
// IMPORTS
// ============================================================================

// vibe-core networking
import vibe.core.net : listenTCP, TCPListener, TCPConnection, TCPListenOptions;
import vibe.core.core : runTask, runEventLoop, exitEventLoop, yield;
import vibe.core.log : logInfo, logWarn, logError, logDebug;

// Aurora modules
import aurora.http : HTTPRequest, HTTPResponse;
import aurora.web.router : Router, Match, PathParams;
import aurora.web.context : Context;
import aurora.web.middleware : MiddlewarePipeline;
import aurora.http.util : getStatusText, getStatusLine, buildResponseInto;
import aurora.runtime.hooks : ServerHooks, TypeErasedHandler, StartHook, StopHook, 
                               ErrorHook, RequestHook, ResponseHook, ExceptionHandler;

// Worker pool for multi-threaded mode (Linux/FreeBSD only)
version(linux)
{
    import aurora.runtime.worker : WorkerPool;
    private enum USE_WORKER_POOL = true;
}
else version(FreeBSD)
{
    import aurora.runtime.worker : WorkerPool;
    private enum USE_WORKER_POOL = true;
}
else
{
    private enum USE_WORKER_POOL = false;
}

// Standard library
import core.atomic;
import core.time;
import core.stdc.string : memcpy;
import std.format : format;
import std.stdio : stderr, writeln, writefln;
import std.conv : to;
import std.algorithm : min;

// ============================================================================
// PLATFORM DETECTION
// ============================================================================

version(linux) {
    private enum PLATFORM = "linux";
    private enum SUPPORT_REUSEPORT = true;
} else version(FreeBSD) {
    private enum PLATFORM = "freebsd";
    private enum SUPPORT_REUSEPORT = true;
} else version(OSX) {
    private enum PLATFORM = "macos";
    private enum SUPPORT_REUSEPORT = false;  // macOS reuseport doesn't load balance
} else version(Windows) {
    private enum PLATFORM = "windows";
    private enum SUPPORT_REUSEPORT = false;
} else {
    private enum PLATFORM = "other";
    private enum SUPPORT_REUSEPORT = false;
}

// ============================================================================
// SERVER CONFIGURATION
// ============================================================================

/// Behavior when server is overloaded
enum OverloadBehavior
{
    /// Return HTTP 503 Service Unavailable with Retry-After header
    reject503,
    
    /// Close connection immediately without response (faster but less graceful)
    closeConnection,
    
    /// Queue request if possible (bounded, may still reject)
    queueRequest
}

/// Server configuration (unchanged API from blocking version)
struct ServerConfig
{
    string host = "0.0.0.0";
    ushort port = 8080;
    uint numWorkers = 0;  // 0 = auto-detect (used for reusePort mode)
    uint connectionQueueSize = 4096;  // Not directly used in fiber mode
    uint listenBacklog = 1024;
    bool debugMode = false;
    
    // === Security Limits (Production Ready) ===
    
    /// Maximum header size in bytes (default 64KB, prevents header DoS)
    uint maxHeaderSize = 64 * 1024;
    
    /// Maximum body size in bytes (default 10MB, prevents memory exhaustion)
    size_t maxBodySize = 10 * 1024 * 1024;
    
    /// Read timeout - max time to wait for client data (prevents slowloris)
    Duration readTimeout = 30.seconds;
    
    /// Write timeout - max time to send response
    Duration writeTimeout = 30.seconds;
    
    /// Keep-alive timeout - max idle time before closing connection
    Duration keepAliveTimeout = 120.seconds;
    
    /// Maximum requests per connection (0 = unlimited)
    uint maxRequestsPerConnection = 1000;
    
    // === Connection Limits & Backpressure (Enterprise) ===
    
    /// Maximum concurrent connections (0 = unlimited, NOT recommended for production)
    uint maxConnections = 10_000;
    
    /// High water mark - start rejecting new connections when this % of maxConnections is reached
    float connectionHighWater = 0.8;
    
    /// Low water mark - resume accepting connections when below this % of maxConnections
    float connectionLowWater = 0.6;
    
    /// Maximum in-flight requests per worker (0 = unlimited)
    uint maxInFlightRequests = 1000;
    
    /// Behavior when server is overloaded
    OverloadBehavior overloadBehavior = OverloadBehavior.reject503;
    
    /// Retry-After header value in seconds (for 503 responses)
    uint retryAfterSeconds = 5;
    
    static ServerConfig defaults() @safe nothrow
    {
        return ServerConfig.init;
    }
    
    uint effectiveWorkers() const @safe nothrow
    {
        if (numWorkers > 0) return numWorkers;
        try
        {
            import std.parallelism : totalCPUs;
            return totalCPUs > 0 ? totalCPUs : 4;
        }
        catch (Exception) { return 4; }
    }
}

// ============================================================================
// RESPONSE WRITER (Fiber-compatible)
// ============================================================================

/// Response writer that writes directly to TCPConnection
struct ResponseWriter
{
    private TCPConnection conn;
    private bool headersSent;
    private shared(bool)* shutdownFlag;  // Reference to server shutdown flag
    
    @disable this();
    
    this(TCPConnection c, shared(bool)* shutdown = null) @safe nothrow
    {
        conn = c;
        headersSent = false;
        shutdownFlag = shutdown;
    }
    
    /// Write a complete HTTP response
    void write(int statusCode, string contentType, const(ubyte)[] body_, bool keepAlive = true) @trusted
    {
        if (headersSent) return;
        if (shutdownFlag !is null && atomicLoad(*shutdownFlag)) return;
        headersSent = true;
        
        // Stack buffer for small responses
        enum STACK_SIZE = 4096;
        if (body_.length + 256 <= STACK_SIZE)
        {
            ubyte[STACK_SIZE] stackBuf;
            auto len = buildResponseInto(stackBuf[], statusCode, contentType,
                                         cast(string)body_, keepAlive);
            if (len > 0)
            {
                conn.write(stackBuf[0..len]);
                return;
            }
        }
        
        // Heap fallback for large responses
        auto heapBuf = new ubyte[body_.length + 512];
        auto len = buildResponseInto(heapBuf, statusCode, contentType,
                                     cast(string)body_, keepAlive);
        if (len > 0)
            conn.write(heapBuf[0..len]);
    }
    
    /// Write a complete HTTP response (string version)
    void write(int statusCode, string contentType, string body_, bool keepAlive = true) @safe
    {
        write(statusCode, contentType, cast(const(ubyte)[])body_, keepAlive);
    }
    
    /// Write JSON response
    void writeJson(int statusCode, string json) @safe
    {
        write(statusCode, "application/json", json);
    }
    
    /// Write error response
    void writeError(int statusCode, string message, bool keepAlive = false) @trusted nothrow
    {
        if (headersSent) return;
        try
        {
            headersSent = true;
            ubyte[512] buf;
            auto body_ = `{"error":"` ~ message ~ `"}`;
            auto len = buildResponseInto(buf[], statusCode, "application/json", body_, keepAlive);
            if (len > 0)
                conn.write(buf[0..len]);
        }
        catch (Exception) {}
    }
    
    @property bool wasSent() const @safe nothrow { return headersSent; }
}

// ============================================================================
// LEGACY RESPONSE BUFFER (for simple handler mode compatibility)
// ============================================================================

/// Response buffer for simple handler mode (legacy API compatibility)
struct ResponseBuffer
{
    private ubyte[] data;
    private bool built;
    
    void write(int statusCode, string contentType, const(ubyte)[] body_) @trusted
    {
        if (built) return;
        built = true;
        
        auto bufSize = body_.length + 512;
        data = new ubyte[bufSize];
        
        auto len = buildResponseInto(data, statusCode, contentType, cast(string)body_, true);
        
        if (len > 0)
            data = data[0..len];
        else
            data = null;
    }
    
    void write(int statusCode, string contentType, string body_) @trusted
    {
        write(statusCode, contentType, cast(const(ubyte)[])body_);
    }
    
    void writeJson(int statusCode, string json) @safe
    {
        write(statusCode, "application/json", json);
    }
    
    ubyte[] getData() @safe nothrow
    {
        return data;
    }
}

// ============================================================================
// REQUEST HANDLER TYPES
// ============================================================================

/// Request handler delegate type (legacy compatibility)
alias RequestHandler = void delegate(scope HTTPRequest* request, scope ResponseBuffer writer) @safe;

// ============================================================================
// MAIN SERVER CLASS
// ============================================================================

/// Fiber-based HTTP Server
final class Server
{
    private
    {
        ServerConfig config;
        Router router;
        MiddlewarePipeline pipeline;
        RequestHandler handler;
        
        // Server hooks for lifecycle events
        ServerHooks _hooks;
        
        // Exception handlers (type hierarchy based)
        TypeErasedHandler[TypeInfo_Class] _exceptionHandlers;
        
        // State
        shared bool running;
        shared bool shuttingDown;
        
        // Single-listener mode (macOS/Windows)
        TCPListener listener;
        
        // Multi-worker mode (Linux/FreeBSD)
        static if (USE_WORKER_POOL)
        {
            WorkerPool workerPool;
        }
        
        // Stats (thread-safe) - used in single-listener mode
        // In multi-worker mode, stats are aggregated from WorkerPool
        shared ulong totalConnections;
        shared ulong activeConnections;
        shared ulong totalRequests;
        shared ulong totalErrors;
        shared ulong rejectedHeadersTooLarge;
        shared ulong rejectedBodyTooLarge;
        shared ulong rejectedTimeout;
        shared ulong rejectedDuringShutdown;
        
        // Backpressure state (Enterprise)
        shared bool inOverloadState;           // Whether we're in overload mode
        shared ulong rejectedOverload;         // Connections rejected due to overload
        shared ulong rejectedInFlight;         // Requests rejected due to in-flight limit
        shared ulong overloadStateTransitions; // Times we entered overload state
        shared ulong currentInFlightRequests;  // Current in-flight requests (global)
    }
    
    // ========================================
    // CONSTRUCTORS (unchanged API)
    // ========================================
    
    /// Create with router
    this(Router r, ServerConfig cfg = ServerConfig.defaults()) @safe
    {
        this.router = r;
        this.pipeline = null;
        this.handler = null;
        this.config = cfg;
        initStats();
    }
    
    /// Create with router and middleware pipeline
    this(Router r, MiddlewarePipeline p, ServerConfig cfg = ServerConfig.defaults()) @safe
    {
        this.router = r;
        this.pipeline = p;
        this.handler = null;
        this.config = cfg;
        initStats();
    }
    
    /// Create with simple handler
    this(RequestHandler h, ServerConfig cfg = ServerConfig.defaults()) @safe
    {
        this.router = null;
        this.pipeline = null;
        this.handler = h;
        this.config = cfg;
        initStats();
    }
    
    private void initStats() @safe nothrow
    {
        atomicStore(running, false);
        atomicStore(shuttingDown, false);
        atomicStore(totalConnections, 0UL);
        atomicStore(activeConnections, 0UL);
        atomicStore(totalRequests, 0UL);
        atomicStore(totalErrors, 0UL);
        atomicStore(rejectedHeadersTooLarge, 0UL);
        atomicStore(rejectedBodyTooLarge, 0UL);
        atomicStore(rejectedTimeout, 0UL);
        atomicStore(rejectedDuringShutdown, 0UL);
        
        // Backpressure state
        atomicStore(inOverloadState, false);
        atomicStore(rejectedOverload, 0UL);
        atomicStore(rejectedInFlight, 0UL);
        atomicStore(overloadStateTransitions, 0UL);
        atomicStore(currentInFlightRequests, 0UL);
    }
    
    // ========================================
    // HOOKS & EXCEPTION HANDLERS
    // ========================================
    
    /// Access server hooks for lifecycle events
    /// Example: server.hooks.onStart(() => writeln("Server starting!"));
    ref ServerHooks hooks() @safe nothrow
    {
        return _hooks;
    }
    
    /// Register a typed exception handler
    /// Example: server.addExceptionHandler!ValidationError((ctx, e) => ctx.response.json(...));
    void addExceptionHandler(E : Exception)(ExceptionHandler!E handler) @trusted
    {
        if (handler is null)
        {
            throw new Exception("Exception handler cannot be null");
        }
        
        // Wrap typed handler in type-erased form
        TypeErasedHandler wrapped = (ref Context ctx, Exception e) @trusted {
            // Safe downcast - we know the type matches when this is called
            if (auto typed = cast(E) e)
            {
                handler(ctx, typed);
            }
        };
        
        _exceptionHandlers[typeid(E)] = wrapped;
    }
    
    /// Check if an exception handler is registered for a type
    bool hasExceptionHandler(E : Exception)() const @safe nothrow
    {
        return (typeid(E) in _exceptionHandlers) !is null;
    }
    
    /// Get number of registered exception handlers
    size_t exceptionHandlerCount() const @safe nothrow
    {
        return _exceptionHandlers.length;
    }
    
    /// Add a type-erased exception handler directly (used by App)
    /// This is an internal API - prefer addExceptionHandler!E() for type safety
    void addExceptionHandlerDirect(TypeInfo_Class typeInfo, TypeErasedHandler handler) @safe
    {
        if (handler is null)
            throw new Exception("Exception handler cannot be null");
        _exceptionHandlers[typeInfo] = handler;
    }
    
    // ========================================
    // SERVER CONTROL (unchanged API)
    // ========================================
    
    /// Start the server (blocking)
    void run() @trusted
    {
        atomicStore(running, true);
        atomicStore(shuttingDown, false);
        
        auto numWorkers = config.effectiveWorkers();
        
        if (config.debugMode)
        {
            writeln("╔════════════════════════════════════════╗");
            writeln("║      Aurora HTTP Server v0.3.0         ║");
            writeln("╠════════════════════════════════════════╣");
            writefln("║  Host:    %-27s ║", config.host);
            writefln("║  Port:    %-27d ║", config.port);
            writefln("║  Workers: %-27d ║", numWorkers);
            static if (USE_WORKER_POOL) {
                writeln("║  Mode:    Multi-worker (reusePort)     ║");
                writefln("║  Threads: %-27d ║", numWorkers);
            } else {
                writeln("║  Mode:    Single-listener (fiber pool) ║");
            }
            writefln("║  Platform: %-26s ║", PLATFORM);
            writeln("║  I/O:     Fiber-based (vibe-core)      ║");
            writeln("╚════════════════════════════════════════╝");
        }
        
        // Execute onStart hooks
        try
        {
            _hooks.executeOnStart();
        }
        catch (Exception e)
        {
            atomicStore(running, false);
            throw new Exception("onStart hook failed: " ~ e.msg);
        }
        
        // Platform-specific startup
        try
        {
            static if (USE_WORKER_POOL)
            {
                // Linux/FreeBSD: Multi-worker mode with SO_REUSEPORT
                // Each worker thread has its own listener and event loop
                // Kernel distributes connections across workers
                runWithWorkerPool(numWorkers);
            }
            else
            {
                // macOS/Windows: Single event loop with fiber pool
                runWithSingleListener();
            }
        }
        catch (Exception e)
        {
            atomicStore(running, false);
            // Execute onStop hooks even on failure
            try { _hooks.executeOnStop(); } catch (Exception) {}
            throw new Exception("Failed to start server: " ~ e.msg);
        }
        
        // Execute onStop hooks
        try
        {
            _hooks.executeOnStop();
        }
        catch (Exception) {}  // Don't fail on stop hook errors
        
        // Cleanup
        atomicStore(running, false);
    }
    
    // Platform-specific run implementations
    static if (USE_WORKER_POOL)
    {
        private void runWithWorkerPool(uint numWorkers) @trusted
        {
            // Create worker pool
            workerPool = new WorkerPool(
                numWorkers,
                config.port,
                config.host,
                &handleConnection
            );
            
            // Start all workers
            workerPool.start();
            
            // Run main thread's event loop (coordinates workers)
            runEventLoop();
            
            // Cleanup
            if (workerPool !is null)
            {
                workerPool.stop();
                workerPool.join(30.seconds);
            }
        }
    }
    
    private void runWithSingleListener() @trusted
    {
        // Create single listener
        listener = listenTCP(
            config.port,
            &handleConnection,
            config.host,
            TCPListenOptions.reuseAddress
        );
        
        // Run the event loop (blocking)
        runEventLoop();
        
        // Cleanup
        if (listener !is TCPListener.init)
        {
            try { listener.stopListening(); }
            catch (Exception) {}
        }
    }
    
    /// Stop the server immediately
    void stop() @trusted nothrow
    {
        atomicStore(shuttingDown, true);
        atomicStore(running, false);
        
        // Stop based on mode
        static if (USE_WORKER_POOL)
        {
            if (workerPool !is null)
            {
                workerPool.stop();
            }
        }
        
        if (listener !is TCPListener.init)
        {
            try { listener.stopListening(); }
            catch (Exception) {}
        }
        
        // Exit the event loop
        try { exitEventLoop(); }
        catch (Exception) {}
    }
    
    /// Graceful shutdown - stop accepting, wait for in-flight requests
    void gracefulStop(Duration timeout = 30.seconds) @trusted
    {
        import core.time : MonoTime;
        
        // Mark as shutting down
        atomicStore(shuttingDown, true);
        
        // Stop accepting new connections
        static if (USE_WORKER_POOL)
        {
            if (workerPool !is null)
            {
                workerPool.stop();
            }
        }
        
        if (listener !is TCPListener.init)
        {
            try { listener.stopListening(); }
            catch (Exception) {}
        }
        
        // Wait for active connections to finish (with timeout)
        auto deadline = MonoTime.currTime + timeout;
        
        while (MonoTime.currTime < deadline)
        {
            auto active = getActiveConnections();
            if (active == 0)
                break;
            
            // Yield to allow other fibers to complete
            try { yield(); }
            catch (Exception) {}
        }
        
        // Now fully stop
        atomicStore(running, false);
        
        try { exitEventLoop(); }
        catch (Exception) {}
    }
    
    // ========================================
    // STATUS (unchanged API)
    // ========================================
    
    /// Check if server is running
    bool isRunning() @safe nothrow { return atomicLoad(running); }
    
    /// Check if server is shutting down
    bool isShuttingDown() @safe nothrow { return atomicLoad(shuttingDown); }
    
    // ========================================
    // STATS (unchanged API)
    // Stats are aggregated from WorkerPool on Linux, local on macOS
    // ========================================
    
    /// Get total connections accepted
    ulong getConnections() @safe nothrow
    {
        static if (USE_WORKER_POOL)
        {
            if (workerPool !is null)
                return workerPool.getTotalConnections();
        }
        return atomicLoad(totalConnections);
    }
    
    /// Get currently active connections
    ulong getActiveConnections() @safe nothrow
    {
        static if (USE_WORKER_POOL)
        {
            if (workerPool !is null)
                return workerPool.getActiveConnections();
        }
        return atomicLoad(activeConnections);
    }
    
    /// Get total requests processed
    ulong getRequests() @safe nothrow
    {
        static if (USE_WORKER_POOL)
        {
            if (workerPool !is null)
                return workerPool.getTotalRequests();
        }
        return atomicLoad(totalRequests);
    }
    
    /// Get total errors
    ulong getErrors() @safe nothrow
    {
        static if (USE_WORKER_POOL)
        {
            if (workerPool !is null)
                return workerPool.getTotalErrors();
        }
        return atomicLoad(totalErrors);
    }
    
    /// Get rejected requests (header too large)
    ulong getRejectedHeadersTooLarge() @safe nothrow
    {
        static if (USE_WORKER_POOL)
        {
            if (workerPool !is null)
                return workerPool.getRejectedHeadersTooLarge();
        }
        return atomicLoad(rejectedHeadersTooLarge);
    }
    
    /// Get rejected requests (body too large)
    ulong getRejectedBodyTooLarge() @safe nothrow
    {
        static if (USE_WORKER_POOL)
        {
            if (workerPool !is null)
                return workerPool.getRejectedBodyTooLarge();
        }
        return atomicLoad(rejectedBodyTooLarge);
    }
    
    /// Get rejected requests (timeout)
    ulong getRejectedTimeout() @safe nothrow
    {
        static if (USE_WORKER_POOL)
        {
            if (workerPool !is null)
                return workerPool.getRejectedTimeout();
        }
        return atomicLoad(rejectedTimeout);
    }
    
    /// Get rejected during shutdown
    ulong getRejectedDuringShutdown() @safe nothrow
    {
        // This is always tracked locally in main thread
        return atomicLoad(rejectedDuringShutdown);
    }
    
    // ========================================
    // BACKPRESSURE METRICS (Enterprise)
    // ========================================
    
    /// Check if server is currently in overload state
    bool isInOverload() @safe nothrow
    {
        return atomicLoad(inOverloadState);
    }
    
    /// Get connections rejected due to overload
    ulong getRejectedOverload() @safe nothrow
    {
        return atomicLoad(rejectedOverload);
    }
    
    /// Get requests rejected due to in-flight limit
    ulong getRejectedInFlight() @safe nothrow
    {
        return atomicLoad(rejectedInFlight);
    }
    
    /// Get number of times server entered overload state
    ulong getOverloadTransitions() @safe nothrow
    {
        return atomicLoad(overloadStateTransitions);
    }
    
    /// Get current in-flight requests count
    ulong getCurrentInFlightRequests() @safe nothrow
    {
        return atomicLoad(currentInFlightRequests);
    }
    
    /// Get connection utilization ratio (0.0 - 1.0)
    float getConnectionUtilization() @safe nothrow
    {
        if (config.maxConnections == 0) return 0.0f;
        auto active = getActiveConnections();
        return cast(float)active / cast(float)config.maxConnections;
    }
    
    /// Get the high water mark threshold (absolute number)
    uint getConnectionHighWaterMark() const @safe nothrow
    {
        return cast(uint)(config.maxConnections * config.connectionHighWater);
    }
    
    /// Get the low water mark threshold (absolute number)
    uint getConnectionLowWaterMark() const @safe nothrow
    {
        return cast(uint)(config.maxConnections * config.connectionLowWater);
    }
    
    // ========================================
    // CONNECTION HANDLING (internal)
    // ========================================
    
    /// Safe close helper (nothrow)
    private static void safeClose(TCPConnection conn) @trusted nothrow
    {
        try { conn.close(); }
        catch (Exception) {}
    }
    
    /**
     * Handle an exception using the registered exception handlers.
     * 
     * Strategy:
     * 1. Execute all onError hooks first (for logging/monitoring)
     * 2. Search for an exact type match handler
     * 3. Walk up the class hierarchy looking for a handler
     * 4. If no handler found, rethrow the exception (like FastAPI/Express)
     *
     * Returns: true if exception was handled, false if it was rethrown
     */
    private bool handleException(ref Context ctx, Exception e) @trusted
    {
        // Step 1: Execute all onError hooks (for logging/monitoring)
        // These run regardless of whether a handler exists
        try
        {
            _hooks.executeOnError(e, ctx);
        }
        catch (Exception hookError)
        {
            // Hook failure should not prevent exception handling
            // But we could log this in debug mode
        }
        
        // Step 2: Find handler by walking up the type hierarchy
        TypeInfo_Class typeInfo = typeid(e);
        
        while (typeInfo !is null)
        {
            if (auto handler = typeInfo in _exceptionHandlers)
            {
                // Found a handler - execute it
                (*handler)(ctx, e);
                return true;
            }
            
            // Walk up to parent class
            typeInfo = typeInfo.base;
        }
        
        // Step 3: No handler found - propagate the exception
        throw e;
    }
    
    private void handleConnection(TCPConnection conn) @safe nothrow
    {
        // Check if shutting down
        if (atomicLoad(shuttingDown))
        {
            atomicOp!"+="(rejectedDuringShutdown, 1);
            safeClose(conn);
            return;
        }
        
        // === BACKPRESSURE CHECK ===
        if (!checkAndUpdateBackpressure(conn))
        {
            return;  // Connection rejected due to overload
        }
        
        atomicOp!"+="(totalConnections, 1);
        atomicOp!"+="(activeConnections, 1);
        
        scope(exit)
        {
            atomicOp!"-="(activeConnections, 1);
            safeClose(conn);
            
            // Check if we should exit overload state (hysteresis)
            checkOverloadRecovery();
        }
        
        try
        {
            processConnection(conn);
        }
        catch (Exception e)
        {
            atomicOp!"+="(totalErrors, 1);
        }
    }
    
    /// Check backpressure state and decide whether to accept connection
    /// Returns: true if connection should be accepted, false if rejected
    private bool checkAndUpdateBackpressure(TCPConnection conn) @safe nothrow
    {
        // Skip if maxConnections is 0 (unlimited)
        if (config.maxConnections == 0) return true;
        
        auto currentActive = atomicLoad(activeConnections);
        auto highMark = getConnectionHighWaterMark();
        auto lowMark = getConnectionLowWaterMark();
        
        // Check if we're already in overload state
        if (atomicLoad(inOverloadState))
        {
            // In overload: only accept if we've recovered below low water mark
            if (currentActive < lowMark)
            {
                // Recovery! Exit overload state
                atomicStore(inOverloadState, false);
                // Fall through to accept connection
            }
            else
            {
                // Still overloaded - reject
                rejectConnectionOverload(conn);
                return false;
            }
        }
        
        // Check if we should enter overload state
        if (currentActive >= highMark)
        {
            // Enter overload state
            if (!atomicLoad(inOverloadState))
            {
                atomicStore(inOverloadState, true);
                atomicOp!"+="(overloadStateTransitions, 1);
            }
            
            rejectConnectionOverload(conn);
            return false;
        }
        
        // Check hard limit
        if (currentActive >= config.maxConnections)
        {
            rejectConnectionOverload(conn);
            return false;
        }
        
        return true;
    }
    
    /// Check if we should exit overload state (called on connection close)
    private void checkOverloadRecovery() @safe nothrow
    {
        if (!atomicLoad(inOverloadState)) return;
        
        auto currentActive = atomicLoad(activeConnections);
        auto lowMark = getConnectionLowWaterMark();
        
        if (currentActive < lowMark)
        {
            atomicStore(inOverloadState, false);
        }
    }
    
    /// Reject connection due to overload
    private void rejectConnectionOverload(TCPConnection conn) @safe nothrow
    {
        atomicOp!"+="(rejectedOverload, 1);
        
        final switch (config.overloadBehavior)
        {
            case OverloadBehavior.reject503:
                send503Response(conn);
                safeClose(conn);
                break;
                
            case OverloadBehavior.closeConnection:
                safeClose(conn);
                break;
                
            case OverloadBehavior.queueRequest:
                // TODO: Implement request queuing in future version
                // For now, fall back to 503
                send503Response(conn);
                safeClose(conn);
                break;
        }
    }
    
    /// Send HTTP 503 response with Retry-After header
    private void send503Response(TCPConnection conn) @trusted nothrow
    {
        try
        {
            import std.format : format;
            
            immutable string body503 = `{"error":"Service temporarily unavailable","reason":"server_overloaded"}`;
            auto response = format(
                "HTTP/1.1 503 Service Unavailable\r\n" ~
                "Content-Type: application/json\r\n" ~
                "Retry-After: %d\r\n" ~
                "Connection: close\r\n" ~
                "Content-Length: %d\r\n" ~
                "\r\n%s",
                config.retryAfterSeconds,
                body503.length,
                body503
            );
            conn.write(cast(const(ubyte)[])response);
        }
        catch (Exception) 
        {
            // Ignore write errors on rejection
        }
    }
    
    private void processConnection(TCPConnection conn) @trusted
    {
        // Set timeouts
        conn.readTimeout = config.readTimeout;
        
        auto maxHeader = config.maxHeaderSize;
        auto maxBody = config.maxBodySize;
        auto maxRequests = config.maxRequestsPerConnection;
        
        // Initial buffer for headers
        ubyte[] buffer = new ubyte[8192];
        uint requestCount = 0;
        
        // Keep-alive loop
        while (atomicLoad(running) && !atomicLoad(shuttingDown))
        {
            // Check max requests per connection
            if (maxRequests > 0 && requestCount >= maxRequests)
                break;
            
            // Update timeout: first request uses readTimeout, subsequent use keepAliveTimeout
            if (requestCount > 0)
                conn.readTimeout = config.keepAliveTimeout;
            
            // Wait for data to be available first
            // This properly handles keep-alive: if client closes, we exit cleanly
            try
            {
                if (conn.empty)
                    return;  // Client closed connection - clean exit
            }
            catch (Exception)
            {
                return;  // Connection error
            }
            
            // Now read the request
            size_t totalReceived = 0;
            bool headersComplete = false;
            size_t headerEndPos = 0;
            
            // Read until we have complete headers
            readLoop: while (!headersComplete && totalReceived < maxHeader)
            {
                // Grow buffer if needed
                if (totalReceived >= buffer.length)
                {
                    if (buffer.length >= maxHeader)
                    {
                        atomicOp!"+="(rejectedHeadersTooLarge, 1);
                        auto writer = ResponseWriter(conn, &shuttingDown);
                        writer.writeError(431, "Request Header Fields Too Large");
                        return;
                    }
                    auto newBuf = new ubyte[min(buffer.length * 2, maxHeader)];
                    newBuf[0..totalReceived] = buffer[0..totalReceived];
                    buffer = newBuf;
                }
                
                // Peek at available data
                ubyte[] chunk;
                try
                {
                    chunk = cast(ubyte[])conn.peek();
                    
                    if (chunk.length == 0)
                    {
                        // No data available - check if connection closed
                        if (conn.empty)
                        {
                            if (totalReceived == 0)
                                return;  // Clean close, no partial data
                            // Partial data received but connection closed
                            atomicOp!"+="(totalErrors, 1);
                            return;
                        }
                        
                        // Connection still open, wait for more data
                        // waitForData will yield the fiber
                        if (!conn.waitForData())
                        {
                            // Timeout or error
                            if (totalReceived == 0)
                                return;  // Clean timeout on keep-alive
                            atomicOp!"+="(rejectedTimeout, 1);
                            return;
                        }
                        continue readLoop;
                    }
                    
                    // Copy available data to buffer
                    auto toCopy = min(chunk.length, buffer.length - totalReceived);
                    buffer[totalReceived .. totalReceived + toCopy] = chunk[0 .. toCopy];
                    conn.skip(toCopy);
                    totalReceived += toCopy;
                }
                catch (Exception)
                {
                    if (totalReceived == 0)
                        return;  // Clean close
                    atomicOp!"+="(totalErrors, 1);
                    return;
                }
                
                // Check for end of headers (\r\n\r\n)
                if (totalReceived >= 4)
                {
                    for (size_t i = 0; i + 3 < totalReceived; i++)
                    {
                        if (buffer[i] == '\r' && buffer[i+1] == '\n' && 
                            buffer[i+2] == '\r' && buffer[i+3] == '\n')
                        {
                            headersComplete = true;
                            headerEndPos = i + 4;
                            break;
                        }
                    }
                }
            }
            
            if (!headersComplete)
            {
                atomicOp!"+="(rejectedHeadersTooLarge, 1);
                auto writer = ResponseWriter(conn, &shuttingDown);
                writer.writeError(431, "Request Header Fields Too Large");
                return;
            }
            
            // Parse HTTP request
            HTTPRequest request;
            try
            {
                request = HTTPRequest.parse(buffer[0..totalReceived]);
            }
            catch (Exception)
            {
                auto writer = ResponseWriter(conn, &shuttingDown);
                writer.writeError(400, "Bad Request");
                break;
            }
            
            if (request.hasError())
            {
                auto writer = ResponseWriter(conn, &shuttingDown);
                writer.writeError(400, "Bad Request");
                break;
            }
            
            // Check Content-Length against maxBodySize
            auto contentLengthStr = request.getHeader("content-length");
            if (contentLengthStr.length > 0)
            {
                try
                {
                    auto contentLength = contentLengthStr.to!size_t;
                    if (contentLength > maxBody)
                    {
                        atomicOp!"+="(rejectedBodyTooLarge, 1);
                        auto writer = ResponseWriter(conn, &shuttingDown);
                        writer.writeError(413, "Payload Too Large");
                        return;
                    }
                }
                catch (Exception) {}
            }
            
            requestCount++;
            atomicOp!"+="(totalRequests, 1);
            
            // === IN-FLIGHT REQUEST LIMIT CHECK ===
            if (config.maxInFlightRequests > 0)
            {
                auto inFlight = atomicOp!"+="(currentInFlightRequests, 1);
                scope(exit) atomicOp!"-="(currentInFlightRequests, 1);
                
                if (inFlight > config.maxInFlightRequests)
                {
                    atomicOp!"+="(rejectedInFlight, 1);
                    auto writer = ResponseWriter(conn, &shuttingDown);
                    try
                    {
                        import std.format : format;
                        immutable string body429 = `{"error":"Too many requests in flight"}`;
                        auto response = format(
                            "HTTP/1.1 503 Service Unavailable\r\n" ~
                            "Content-Type: application/json\r\n" ~
                            "Retry-After: %d\r\n" ~
                            "Connection: close\r\n" ~
                            "Content-Length: %d\r\n" ~
                            "\r\n%s",
                            config.retryAfterSeconds,
                            body429.length,
                            body429
                        );
                        conn.write(cast(const(ubyte)[])response);
                    }
                    catch (Exception) {}
                    return;
                }
            }
            
            // Handle request
            ubyte[] responseData;
            bool wasHijacked = false;
            
            if (handler !is null)
            {
                // Simple handler mode
                auto respBuffer = ResponseBuffer();
                try
                {
                    handler(&request, respBuffer);
                    responseData = respBuffer.getData();
                }
                catch (Exception)
                {
                    responseData = cast(ubyte[])"HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n";
                }
            }
            else if (router !is null)
            {
                auto result = handleWithRouter(&request, conn);
                responseData = result.data;
                wasHijacked = result.hijacked;
            }
            else
            {
                responseData = cast(ubyte[])"HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n";
            }
            
            // If hijacked, external handler owns the connection
            if (wasHijacked)
                return;
            
            // Send response
            if (responseData.length > 0)
            {
                try
                {
                    conn.write(responseData);
                }
                catch (Exception)
                {
                    atomicOp!"+="(totalErrors, 1);
                    return;
                }
            }
            
            // Check keep-alive
            auto connHeader = request.getHeader("connection");
            if (connHeader == "close")
                break;
            if (request.httpVersion() == "HTTP/1.0" && connHeader != "keep-alive")
                break;
            
            // Update timeout for keep-alive
            conn.readTimeout = config.keepAliveTimeout;
        }
    }
    
    /// Result from handleWithRouter - includes hijack state
    private struct RouterResult
    {
        ubyte[] data;
        bool hijacked;
    }
    
    private RouterResult handleWithRouter(HTTPRequest* request, TCPConnection conn) @trusted
    {
        Context ctx;
        ctx.request = request;
        ctx.setRawConnection(conn);  // Pass connection for hijack support
        
        auto response = HTTPResponse(200, "OK");
        ctx.response = &response;
        
        try
        {
            // Execute onRequest hooks
            _hooks.executeOnRequest(ctx);
            
            auto result = router.match(request.method(), request.path());
            
            if (result.found && result.handler !is null)
            {
                ctx.params = result.params;
                
                // Execute with middleware pipeline if available
                if (pipeline !is null && pipeline.length > 0)
                {
                    pipeline.execute(ctx, result.handler);
                }
                else
                {
                    result.handler(ctx);
                }
            }
            else
            {
                response.setStatus(404);
                response.setHeader("Content-Type", "application/json");
                response.setBody(`{"error":"Not Found"}`);
            }
            
            // Check if connection was hijacked
            if (ctx.isHijacked())
            {
                // Connection is now owned by external handler
                // Do NOT send response, do NOT close connection
                return RouterResult(null, true);
            }
            
            // Execute onResponse hooks
            _hooks.executeOnResponse(ctx);
            
            auto respData = buildResponse(response.status, 
                response.getContentType(), response.getBody());
            return RouterResult(respData, false);
        }
        catch (Exception e)
        {
            // Check if hijacked before trying to send error response
            if (ctx.isHijacked())
            {
                // Cannot send error response on hijacked connection
                // Just log and return
                try { logError("Exception after hijack: " ~ e.msg); } catch (Exception) {}
                return RouterResult(null, true);
            }
            
            // Try to handle with registered exception handlers
            try
            {
                handleException(ctx, e);
                // Handler executed - return the response it set
                _hooks.executeOnResponse(ctx);
                auto respData = buildResponse(response.status, 
                    response.getContentType(), response.getBody());
                return RouterResult(respData, false);
            }
            catch (Exception)
            {
                // No handler found or handler failed - return 500
                return RouterResult(buildResponse(500, "application/json", 
                    `{"error":"Internal Server Error"}`), false);
            }
        }
    }
    
    private ubyte[] buildResponse(int status, string contentType, string body_) @trusted
    {
        enum STACK_SIZE = 4096;
        
        if (body_.length + 256 <= STACK_SIZE)
        {
            ubyte[STACK_SIZE] stackBuf;
            auto len = buildResponseInto(stackBuf[], status, contentType, body_, true);
            if (len > 0)
                return stackBuf[0..len].dup;
        }
        
        auto heapBuf = new ubyte[body_.length + 512];
        auto len = buildResponseInto(heapBuf, status, contentType, body_, true);
        if (len > 0)
            return heapBuf[0..len];
        
        return cast(ubyte[])"HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n".dup;
    }
}

// ============================================================================
// CONVENIENCE FUNCTIONS
// ============================================================================

/// Simple server runner (runs with default config)
void runServer(Router router, ushort port = 8080)
{
    auto config = ServerConfig.defaults();
    config.port = port;
    auto server = new Server(router, config);
    server.run();
}

/// Server runner with config
void runServer(Router router, ServerConfig config)
{
    auto server = new Server(router, config);
    server.run();
}

/// Server runner with middleware
void runServer(Router router, MiddlewarePipeline pipeline, ushort port = 8080)
{
    auto config = ServerConfig.defaults();
    config.port = port;
    auto server = new Server(router, pipeline, config);
    server.run();
}

/// Server runner with middleware and config
void runServer(Router router, MiddlewarePipeline pipeline, ServerConfig config)
{
    auto server = new Server(router, pipeline, config);
    server.run();
}
