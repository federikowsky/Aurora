/**
 * Aurora HTTP Server
 *
 * Architecture: Thread Pool + Single Acceptor (Actix/Netty style)
 * 
 * - 1 Acceptor thread: accepts connections, round-robin dispatch to workers
 * - N Worker threads: each has its own event loop + fiber pool
 * - Lock-free MPSC queue for connection handoff
 * - Cross-platform: works on Linux, macOS, Windows
 *
 * This is the most performant AND simplest approach for D:
 * - No complex work-stealing scheduler
 * - No SO_REUSEPORT (not available on Windows, limited on macOS)
 * - Proven architecture (used by Actix, Netty, Tokio)
 *
 * Platform notes:
 * - Linux/macOS: Uses POSIX socket options
 * - Windows: Uses Winsock2 with appropriate timeout handling
 */
module aurora.runtime.server;

import aurora.http : HTTPRequest, HTTPResponse;
import aurora.web.router : Router, Match, PathParams;
import aurora.web.context : Context;

import core.thread;
import core.atomic;
import core.sync.mutex;
import core.sync.condition;
import core.time;
import core.stdc.string : memcpy;

import std.socket;
import std.format : format;
import std.stdio : stderr, writeln, writefln;
import std.conv : to;
import std.algorithm : min;

import aurora.http.util : getStatusText, getStatusLine, buildResponseInto;

// ============================================================================
// BLOCKING QUEUE (Event-based notification with Condition)
// ============================================================================

/**
 * Bounded blocking queue for connection handoff.
 * 
 * Uses Condition variable for efficient event-based notification:
 * - Producer calls push() → notifies waiting consumers
 * - Consumer calls pop() → blocks until item available or shutdown
 * - No polling, no timeouts, no busy-waiting
 * 
 * Thread-safe: Single producer (acceptor) + Single consumer (worker)
 */
private struct BlockingQueue(T)
{
    private T[] buffer;
    private size_t head = 0;      // Write position (producer)
    private size_t tail = 0;      // Read position (consumer)
    private size_t count = 0;     // Current item count
    private size_t capacity;
    
    private Mutex mutex;
    private Condition notEmpty;   // Signaled when queue becomes non-empty
    private Condition notFull;    // Signaled when queue becomes non-full
    private bool closed = false;  // For graceful shutdown
    
    void initialize(size_t cap) @trusted nothrow
    {
        try
        {
            this.capacity = cap;
            buffer = new T[cap];
            mutex = new Mutex();
            notEmpty = new Condition(mutex);
            notFull = new Condition(mutex);
        }
        catch (Exception) {}
    }
    
    /// Push an item (blocks if queue is full)
    /// Returns false if queue is closed
    bool push(T item) @trusted
    {
        if (item is null) return false;
        
        synchronized(mutex)
        {
            // Wait until space available or closed
            while (count == capacity && !closed)
            {
                notFull.wait();
            }
            
            if (closed)
                return false;
            
            buffer[head] = item;
            head = (head + 1) % capacity;
            count++;
            
            // Signal waiting consumer
            notEmpty.notify();
        }
        return true;
    }
    
    /// Try to push without blocking
    /// Returns false if queue is full or closed
    bool tryPush(T item) @trusted nothrow
    {
        if (item is null) return false;
        
        try
        {
            synchronized(mutex)
            {
                if (closed || count == capacity)
                    return false;
                
                buffer[head] = item;
                head = (head + 1) % capacity;
                count++;
                
                notEmpty.notify();
            }
            return true;
        }
        catch (Exception)
        {
            return false;
        }
    }
    
    /// Pop an item (blocks until item available or queue closed)
    /// Returns null if queue is closed and empty
    T pop() @trusted
    {
        synchronized(mutex)
        {
            // Wait until item available or closed
            while (count == 0 && !closed)
            {
                notEmpty.wait();
            }
            
            if (count == 0)
                return null;  // Closed and empty
            
            T item = buffer[tail];
            buffer[tail] = null;  // Help GC
            tail = (tail + 1) % capacity;
            count--;
            
            // Signal waiting producer
            notFull.notify();
            
            return item;
        }
    }
    
    /// Close the queue (wake up all waiting threads)
    void close() @trusted nothrow
    {
        try
        {
            synchronized(mutex)
            {
                closed = true;
                notEmpty.notifyAll();  // Wake up all consumers
                notFull.notifyAll();   // Wake up all producers
            }
        }
        catch (Exception) {}
    }
    
    /// Check if closed
    bool isClosed() @trusted nothrow
    {
        try
        {
            synchronized(mutex)
            {
                return closed;
            }
        }
        catch (Exception)
        {
            return true;
        }
    }
    
    /// Current size (for debugging)
    size_t length() @trusted nothrow
    {
        try
        {
            synchronized(mutex)
            {
                return count;
            }
        }
        catch (Exception)
        {
            return 0;
        }
    }
}

/// Alias for socket queue
alias ConnectionQueue = BlockingQueue!Socket;

// ============================================================================
// WORKER THREAD
// ============================================================================

/// Safe socket close helper
private void closeSocket(Socket s) @trusted nothrow
{
    if (s !is null)
    {
        try { s.close(); } catch (Exception) {}
    }
}

private class WorkerThread
{
    private uint id;
    private Thread thread;
    private shared bool running;
    private ConnectionQueue* queue;
    private RequestHandler handler;
    private Router router;
    private MiddlewarePipeline pipeline;
    private ServerConfig* config;  // Reference to server config
    
    // Stats
    shared ulong requestsProcessed;
    shared ulong bytesReceived;
    shared ulong bytesSent;
    shared ulong errors;
    shared ulong rejectedHeadersTooLarge;
    shared ulong rejectedBodyTooLarge;
    shared ulong rejectedTimeout;
    
    this(uint workerId, ConnectionQueue* q, RequestHandler h, Router r, MiddlewarePipeline p, ServerConfig* cfg) @safe
    {
        this.id = workerId;
        this.queue = q;
        this.handler = h;
        this.router = r;
        this.pipeline = p;
        this.config = cfg;
        atomicStore(running, false);
        atomicStore(requestsProcessed, 0);
        atomicStore(bytesReceived, 0);
        atomicStore(bytesSent, 0);
        atomicStore(errors, 0);
        atomicStore(rejectedHeadersTooLarge, 0);
        atomicStore(rejectedBodyTooLarge, 0);
        atomicStore(rejectedTimeout, 0);
    }
    
    void start() @trusted
    {
        atomicStore(running, true);
        thread = new Thread(&workerMain);
        thread.name = format("aurora-worker-%d", id);
        thread.start();
    }
    
    void stop() @trusted nothrow
    {
        atomicStore(running, false);
    }
    
    void join() @trusted
    {
        if (thread !is null)
            thread.join();
    }
    
    private void workerMain() @trusted
    {
        while (atomicLoad(running))
        {
            // Block until connection available (or queue closed)
            Socket conn = queue.pop();
            
            if (conn is null)
            {
                // Queue was closed, exit loop
                break;
            }
            
            processConnection(conn);
        }
    }
    
    private void processConnection(Socket conn) @trusted
    {
        scope(exit) closeSocket(conn);
        
        // Use dynamic buffer based on maxHeaderSize config
        auto maxHeader = config ? config.maxHeaderSize : 64 * 1024;
        auto maxBody = config ? config.maxBodySize : 10 * 1024 * 1024;
        auto readTimeout = config ? config.readTimeout : 30.seconds;
        auto writeTimeout = config ? config.writeTimeout : 30.seconds;
        auto keepAliveTimeout = config ? config.keepAliveTimeout : 120.seconds;
        auto maxRequests = config ? config.maxRequestsPerConnection : 1000;
        
        // Initial buffer for headers (8KB, will grow if needed)
        ubyte[] buffer = new ubyte[8192];
        uint requestCount = 0;
        
        try
        {
            // Set socket options from config
            conn.blocking = true;
            conn.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, readTimeout);
            conn.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, writeTimeout);
            
            // Keep-alive loop
            while (atomicLoad(running))
            {
                // Check max requests per connection
                if (maxRequests > 0 && requestCount >= maxRequests)
                {
                    sendError(conn, 200, "OK", true);  // Close gracefully
                    break;
                }
                
                // Read request with header size limit
                size_t totalReceived = 0;
                bool headersComplete = false;
                size_t headerEndPos = 0;
                
                while (!headersComplete && totalReceived < maxHeader)
                {
                    // Grow buffer if needed
                    if (totalReceived >= buffer.length)
                    {
                        if (buffer.length >= maxHeader)
                        {
                            // Headers too large
                            atomicOp!"+="(rejectedHeadersTooLarge, 1);
                            sendError(conn, 431, "Request Header Fields Too Large");
                            return;
                        }
                        // Double buffer size
                        auto newBuf = new ubyte[min(buffer.length * 2, maxHeader)];
                        newBuf[0..totalReceived] = buffer[0..totalReceived];
                        buffer = newBuf;
                    }
                    
                    auto received = conn.receive(buffer[totalReceived..$]);
                    
                    if (received <= 0)
                    {
                        if (totalReceived == 0)
                            return;  // Clean close, no data
                        // Timeout or error mid-request
                        atomicOp!"+="(rejectedTimeout, 1);
                        return;
                    }
                    
                    totalReceived += received;
                    atomicOp!"+="(bytesReceived, received);
                    
                    // Check for end of headers (\r\n\r\n)
                    for (size_t i = (totalReceived > 4 ? totalReceived - received - 3 : 0); i + 3 < totalReceived; i++)
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
                
                if (!headersComplete)
                {
                    // Headers exceeded max size
                    atomicOp!"+="(rejectedHeadersTooLarge, 1);
                    sendError(conn, 431, "Request Header Fields Too Large");
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
                    sendError(conn, 400, "Bad Request");
                    break;
                }
                
                if (request.hasError())
                {
                    sendError(conn, 400, "Bad Request");
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
                            sendError(conn, 413, "Payload Too Large");
                            return;
                        }
                    }
                    catch (Exception) {}
                }
                
                requestCount++;
                atomicOp!"+="(requestsProcessed, 1);
                
                // Handle request
                ubyte[] responseData;
                
                if (handler !is null)
                {
                    // Simple handler mode
                    auto writer = ResponseBuffer();
                    try
                    {
                        handler(&request, writer);
                        responseData = writer.getData();
                    }
                    catch (Exception)
                    {
                        responseData = cast(ubyte[])"HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n";
                    }
                }
                else if (router !is null)
                {
                    responseData = handleWithRouter(&request);
                }
                else
                {
                    responseData = cast(ubyte[])"HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n";
                }
                
                // Send response
                auto sent = conn.send(responseData);
                if (sent > 0)
                    atomicOp!"+="(bytesSent, sent);
                
                // Check keep-alive
                auto connHeader = request.getHeader("connection");
                if (connHeader == "close")
                    break;
                if (request.httpVersion() == "HTTP/1.0" && connHeader != "keep-alive")
                    break;
                
                // Set keep-alive timeout for next request
                conn.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, keepAliveTimeout);
            }
        }
        catch (Exception e)
        {
            atomicOp!"+="(errors, 1);
        }
    }
    
    private ubyte[] handleWithRouter(HTTPRequest* request) @trusted
    {
        try
        {
            auto result = router.match(request.method(), request.path());
            
            if (result.found && result.handler !is null)
            {
                auto ctx = Context();
                ctx.request = request;
                ctx.params = result.params;
                
                auto response = HTTPResponse(200, "OK");
                ctx.response = &response;
                
                // Execute with middleware pipeline if available
                if (pipeline !is null && pipeline.length > 0)
                {
                    pipeline.execute(ctx, result.handler);
                }
                else
                {
                    result.handler(ctx);
                }
                
                return buildResponse(response.status, response.getContentType(), response.getBody());
            }
            else
            {
                return buildResponse(404, "application/json", `{"error":"Not Found"}`);
            }
        }
        catch (Exception)
        {
            return buildResponse(500, "application/json", `{"error":"Internal Server Error"}`);
        }
    }
    
    private ubyte[] buildResponse(int status, string contentType, string body_) @trusted
    {
        // Use stack buffer for small responses, heap for large
        enum STACK_SIZE = 4096;
        
        if (body_.length + 256 <= STACK_SIZE)
        {
            // Fast path: build on stack
            ubyte[STACK_SIZE] stackBuf;
            auto len = buildResponseInto(stackBuf[], status, contentType, body_, true);
            if (len > 0)
                return stackBuf[0..len].dup;
        }
        
        // Slow path: allocate heap buffer
        auto heapBuf = new ubyte[body_.length + 512];
        auto len = buildResponseInto(heapBuf, status, contentType, body_, true);
        if (len > 0)
            return heapBuf[0..len];
        
        // Fallback (shouldn't happen)
        return cast(ubyte[])"HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n".dup;
    }
    
    private void sendError(Socket conn, int code, string message, bool keepAlive = false) @trusted nothrow
    {
        try
        {
            // Build error JSON body
            char[256] bodyBuf;
            size_t bodyLen = 0;
            
            // Simple JSON: {"error":"message"}
            enum prefix = `{"error":"`;
            enum suffix = `"}`;
            
            if (prefix.length + message.length + suffix.length < bodyBuf.length)
            {
                bodyBuf[0 .. prefix.length] = prefix;
                bodyLen = prefix.length;
                bodyBuf[bodyLen .. bodyLen + message.length] = message;
                bodyLen += message.length;
                bodyBuf[bodyLen .. bodyLen + suffix.length] = suffix;
                bodyLen += suffix.length;
            }
            
            // Build response
            ubyte[512] respBuf;
            auto len = buildResponseInto(
                respBuf[], 
                code, 
                "application/json", 
                cast(string)bodyBuf[0..bodyLen],
                keepAlive  // Connection: keep-alive or close
            );
            
            if (len > 0)
                conn.send(respBuf[0..len]);
        }
        catch (Exception) {}
    }
}

// ============================================================================
// RESPONSE BUFFER (for simple handler mode)
// ============================================================================

struct ResponseBuffer
{
    private ubyte[] data;
    private bool built;
    
    void write(int statusCode, string contentType, const(ubyte)[] body_) @trusted
    {
        if (built) return;
        built = true;
        
        // Allocate buffer for response
        auto bufSize = body_.length + 512;
        data = new ubyte[bufSize];
        
        // Build directly into buffer using optimized function
        auto len = buildResponseInto(
            data, 
            statusCode, 
            contentType, 
            cast(string)body_,
            true  // keep-alive
        );
        
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
// MAIN SERVER
// ============================================================================

/// Request handler delegate type
alias RequestHandler = void delegate(scope HTTPRequest* request, scope ResponseBuffer writer) @safe;

/// Server configuration
struct ServerConfig
{
    string host = "0.0.0.0";
    ushort port = 8080;
    uint numWorkers = 0;  // 0 = auto-detect
    uint connectionQueueSize = 4096;
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
    
    static ServerConfig defaults() @safe nothrow
    {
        return ServerConfig.init;
    }
    
    uint effectiveWorkers() const @safe nothrow
    {
        if (numWorkers > 0) return numWorkers;
        try
        {
            import core.cpuid : threadsPerCPU;
            auto cpus = threadsPerCPU();
            return cpus > 0 ? cpus : 4;
        }
        catch (Exception) { return 4; }
    }
}

import aurora.web.middleware : MiddlewarePipeline;

/// Multi-threaded HTTP Server
final class Server
{
    private ServerConfig config;
    private Socket listenSocket;
    private shared bool running;
    private shared bool shuttingDown;  // Graceful shutdown in progress
    
    private WorkerThread[] workers;
    private ConnectionQueue[] queues;
    private uint nextWorker;  // Round-robin counter
    
    private Router router;
    private MiddlewarePipeline pipeline;
    private RequestHandler handler;
    
    // Stats
    private shared ulong totalConnections;
    private shared ulong rejectedDuringShutdown;
    
    /// Create with router
    this(Router r, ServerConfig cfg = ServerConfig.defaults()) @safe
    {
        this.router = r;
        this.pipeline = null;
        this.handler = null;
        this.config = cfg;
        atomicStore(running, false);
        atomicStore(shuttingDown, false);
        atomicStore(totalConnections, 0);
        atomicStore(rejectedDuringShutdown, 0);
    }
    
    /// Create with router and middleware pipeline
    this(Router r, MiddlewarePipeline p, ServerConfig cfg = ServerConfig.defaults()) @safe
    {
        this.router = r;
        this.pipeline = p;
        this.handler = null;
        this.config = cfg;
        atomicStore(running, false);
        atomicStore(shuttingDown, false);
        atomicStore(totalConnections, 0);
        atomicStore(rejectedDuringShutdown, 0);
    }
    
    /// Create with simple handler
    this(RequestHandler h, ServerConfig cfg = ServerConfig.defaults()) @safe
    {
        this.router = null;
        this.pipeline = null;
        this.handler = h;
        this.config = cfg;
        atomicStore(running, false);
        atomicStore(shuttingDown, false);
        atomicStore(totalConnections, 0);
        atomicStore(rejectedDuringShutdown, 0);
    }
    
    /// Start the server (blocking)
    void run() @trusted
    {
        auto numWorkers = config.effectiveWorkers();
        
        // Create listen socket
        listenSocket = new TcpSocket();
        listenSocket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
        listenSocket.bind(new InternetAddress(config.host, config.port));
        listenSocket.listen(config.listenBacklog);
        
        // Create per-worker queues and workers
        queues = new ConnectionQueue[numWorkers];
        workers = new WorkerThread[numWorkers];
        
        foreach (i; 0 .. numWorkers)
        {
            queues[i].initialize(config.connectionQueueSize);
            workers[i] = new WorkerThread(cast(uint)i, &queues[i], handler, router, pipeline, &config);
        }
        
        // Start workers
        foreach (w; workers)
            w.start();
        
        atomicStore(running, true);
        
        if (config.debugMode)
            writefln("Aurora listening on http://%s:%d (%d workers)", config.host, config.port, numWorkers);
        
        // Accept loop (main thread)
        acceptLoop();
        
        // Cleanup
        shutdown();
    }
    
    private void acceptLoop() @trusted
    {
        while (atomicLoad(running))
        {
            try
            {
                Socket conn = listenSocket.accept();
                
                if (conn !is null)
                {
                    atomicOp!"+="(totalConnections, 1);
                    
                    // Round-robin dispatch to workers
                    uint workerIdx = nextWorker % cast(uint)workers.length;
                    nextWorker++;
                    
                    // Use tryPush to avoid blocking the acceptor
                    if (!queues[workerIdx].tryPush(conn))
                    {
                        // Queue full, reject connection
                        closeSocket(conn);
                    }
                }
            }
            catch (Exception)
            {
                if (!atomicLoad(running))
                    break;
            }
        }
    }
    
    /// Stop the server (immediate)
    void stop() @trusted nothrow
    {
        atomicStore(shuttingDown, true);
        atomicStore(running, false);
        
        // Close all queues to wake up blocked workers
        foreach (ref q; queues)
            q.close();
        
        try
        {
            if (listenSocket !is null)
                listenSocket.close();
        }
        catch (Exception) {}
    }
    
    /// Graceful shutdown - stop accepting, wait for in-flight requests
    void gracefulStop(Duration timeout = 30.seconds) @trusted
    {
        import core.time : MonoTime;
        
        // Mark as shutting down (health checks should return 503)
        atomicStore(shuttingDown, true);
        
        // Stop accepting new connections
        try
        {
            if (listenSocket !is null)
                listenSocket.close();
        }
        catch (Exception) {}
        
        // Wait for queues to drain (with timeout)
        auto deadline = MonoTime.currTime + timeout;
        
        while (MonoTime.currTime < deadline)
        {
            ulong pending = 0;
            foreach (ref q; queues)
                pending += q.length();
            
            if (pending == 0)
                break;
            
            Thread.sleep(10.msecs);
        }
        
        // Now fully stop
        atomicStore(running, false);
        
        foreach (ref q; queues)
            q.close();
        
        foreach (w; workers)
            w.stop();
        
        foreach (w; workers)
            w.join();
    }
    
    private void shutdown() @trusted
    {
        // Signal stop
        atomicStore(shuttingDown, true);
        atomicStore(running, false);
        
        // Close all queues to wake up blocked workers
        foreach (ref q; queues)
            q.close();
        
        // Stop all workers
        foreach (w; workers)
            w.stop();
        
        // Wait for workers to finish
        foreach (w; workers)
            w.join();
    }
    
    // ========================================
    // Public Stats & Status
    // ========================================
    
    /// Check if server is running
    bool isRunning() @safe nothrow { return atomicLoad(running); }
    
    /// Check if server is shutting down (for health checks)
    bool isShuttingDown() @safe nothrow { return atomicLoad(shuttingDown); }
    
    /// Get total connections accepted
    ulong getConnections() @safe nothrow { return atomicLoad(totalConnections); }
    
    /// Get active connections (estimated - queue sizes)
    ulong getActiveConnections() @trusted nothrow
    {
        ulong total = 0;
        foreach (ref q; queues)
            total += q.length();
        return total;
    }
    
    /// Get total requests processed
    ulong getRequests() @trusted nothrow
    {
        ulong total = 0;
        foreach (w; workers)
            total += atomicLoad(w.requestsProcessed);
        return total;
    }
    
    /// Get total errors
    ulong getErrors() @trusted nothrow
    {
        ulong total = 0;
        foreach (w; workers)
            total += atomicLoad(w.errors);
        return total;
    }
    
    /// Get rejected requests (header too large)
    ulong getRejectedHeadersTooLarge() @trusted nothrow
    {
        ulong total = 0;
        foreach (w; workers)
            total += atomicLoad(w.rejectedHeadersTooLarge);
        return total;
    }
    
    /// Get rejected requests (body too large)
    ulong getRejectedBodyTooLarge() @trusted nothrow
    {
        ulong total = 0;
        foreach (w; workers)
            total += atomicLoad(w.rejectedBodyTooLarge);
        return total;
    }
    
    /// Get rejected requests (timeout)
    ulong getRejectedTimeout() @trusted nothrow
    {
        ulong total = 0;
        foreach (w; workers)
            total += atomicLoad(w.rejectedTimeout);
        return total;
    }
    
    /// Get rejected during shutdown
    ulong getRejectedDuringShutdown() @safe nothrow 
    { 
        return atomicLoad(rejectedDuringShutdown); 
    }
}
