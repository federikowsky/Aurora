/**
 * Aurora Application - Main Entry Point
 *
 * Provides a high-level, user-friendly API for building HTTP servers.
 * Brings together Router, Middleware, Workers, and all Aurora components.
 *
 * Usage:
 * ---
 * import aurora;
 *
 * void main() {
 *     auto app = new App();
 *     
 *     // Add routes
 *     app.get("/", (ref Context ctx) {
 *         ctx.send("Hello, Aurora!");
 *     });
 *     
 *     app.get("/users/:id", (ref Context ctx) {
 *         ctx.json(["id": ctx.params["id"]]);
 *     });
 *     
 *     // Add middleware
 *     app.use((ref Context ctx, NextFunction next) {
 *         // Log request
 *         writeln("Request: ", ctx.request.method, " ", ctx.request.path);
 *         next();
 *     });
 *     
 *     // Start server
 *     app.listen(8080);
 * }
 * ---
 */
module aurora.app;

import aurora.web.router;
import aurora.web.context;
import aurora.web.middleware;
import aurora.runtime.reactor;
import aurora.runtime.config;
import aurora.runtime.connection;
import aurora.mem.pool;
import aurora.http : HTTPRequest, HTTPResponse;

// Use fully qualified name for ConnectionState to avoid conflict with eventcore
alias AuroraConnectionState = aurora.runtime.connection.ConnectionState;

import vibe.core.core : runEventLoop, runTask, exitEventLoop, yield;
import eventcore.core : eventDriver;
import eventcore.driver;

import core.thread;
import core.atomic;
import std.socket : InternetAddress;
import std.stdio : writeln, writefln;
import std.conv : to;

/**
 * Server Configuration
 */
struct ServerConfig
{
    /// Listen address (default: 0.0.0.0)
    string host = "0.0.0.0";
    
    /// Listen port (default: 8080)
    ushort port = 8080;
    
    /// Number of worker threads (default: CPU cores - 1)
    uint workers = 0;  // 0 = auto-detect
    
    /// Connection configuration
    ConnectionConfig connection = ConnectionConfig.defaults();
    
    /// Enable debug logging
    bool debug_ = false;
    
    /// Create default configuration
    static ServerConfig defaults()
    {
        ServerConfig config;
        
        // Auto-detect worker count
        import std.parallelism : totalCPUs;
        config.workers = totalCPUs > 1 ? totalCPUs - 1 : 1;
        
        return config;
    }
}

/**
 * Aurora Application
 *
 * Main entry point for Aurora HTTP servers.
 * Provides Express.js-like API for D.
 */
class App
{
    private Router router;
    private MiddlewarePipeline pipeline;
    private ServerConfig config;
    private Thread[] workerThreads;
    private shared bool running;
    
    /**
     * Create new Aurora application
     *
     * Params:
     *   config = Server configuration (optional)
     */
    this(ServerConfig config = ServerConfig.defaults())
    {
        this.config = config;
        this.router = new Router();
        this.pipeline = new MiddlewarePipeline();
        this.running = false;
    }
    
    // ========================================
    // ROUTING API
    // ========================================
    
    /**
     * Register GET route
     */
    App get(string path, Handler handler)
    {
        router.get(path, handler);
        return this;
    }
    
    /**
     * Register POST route
     */
    App post(string path, Handler handler)
    {
        router.post(path, handler);
        return this;
    }
    
    /**
     * Register PUT route
     */
    App put(string path, Handler handler)
    {
        router.put(path, handler);
        return this;
    }
    
    /**
     * Register DELETE route
     */
    App delete_(string path, Handler handler)
    {
        router.delete_(path, handler);
        return this;
    }
    
    /**
     * Register PATCH route
     */
    App patch(string path, Handler handler)
    {
        router.patch(path, handler);
        return this;
    }
    
    /**
     * Register route for any HTTP method
     */
    App route(string method, string path, Handler handler)
    {
        router.addRoute(method, path, handler);
        return this;
    }
    
    /**
     * Include sub-router
     *
     * Example:
     * ---
     * auto api = new Router("/api");
     * api.get("/users", &getUsers);
     * 
     * app.includeRouter(api);  // Routes available at /api/users
     * ---
     */
    App includeRouter(Router subRouter)
    {
        router.includeRouter(subRouter);
        return this;
    }
    
    // ========================================
    // MIDDLEWARE API
    // ========================================
    
    /**
     * Add middleware to application
     *
     * Middleware executes in order of registration, before route handlers.
     *
     * Example:
     * ---
     * app.use((ref Context ctx, NextFunction next) {
     *     writeln("Before handler");
     *     next();
     *     writeln("After handler");
     * });
     * ---
     */
    App use(Middleware mw)
    {
        pipeline.use(mw);
        return this;
    }
    
    /**
     * Add middleware class instance
     *
     * For class-based middleware like CORSMiddleware, SecurityMiddleware.
     */
    App use(T)(T middleware) if (__traits(hasMember, T, "handle"))
    {
        pipeline.use((ref Context ctx, NextFunction next) {
            middleware.handle(ctx, next);
        });
        return this;
    }
    
    // ========================================
    // SERVER LIFECYCLE
    // ========================================
    
    /**
     * Start server and listen on specified port
     *
     * This method blocks until the server is stopped.
     *
     * Params:
     *   port = Port to listen on (overrides config)
     */
    void listen(ushort port)
    {
        config.port = port;
        listen();
    }
    
    /**
     * Start server with configured settings
     *
     * This method blocks until the server is stopped.
     */
    void listen()
    {
        writefln("🚀 Aurora Server starting on http://%s:%d", config.host, config.port);
        writefln("   Workers: %d", config.workers);
        
        atomicStore(running, true);
        
        // Create worker threads
        foreach (i; 0 .. config.workers)
        {
            uint id = cast(uint)i;
            auto t = new Thread(() { workerLoop(id); });
            t.start();
            workerThreads ~= t;
        }
        
        writeln("✅ Server ready! Press Ctrl+C to stop.");
        
        // Wait for all workers
        foreach (t; workerThreads)
        {
            t.join();
        }
    }
    
    /**
     * Stop server gracefully
     */
    void stop()
    {
        writeln("🛑 Shutting down server...");
        atomicStore(running, false);
        
        // Signal all workers to stop
        try
        {
            exitEventLoop();
        }
        catch (Exception e)
        {
            // Ignore
        }
    }
    
    /**
     * Check if server is running
     */
    @property bool isRunning()
    {
        return atomicLoad(running);
    }
    
    // ========================================
    // PRIVATE IMPLEMENTATION
    // ========================================
    
    private void workerLoop(uint id)
    {
        if (config.debug_)
            writefln("   Worker %d starting...", id);
        
        try
        {
            // Thread-local resources
            auto reactor = new Reactor();
            auto bufferPool = new BufferPool();
            
            scope(exit)
            {
                bufferPool.cleanup();
                reactor.shutdown();
                if (config.debug_)
                    writefln("   Worker %d stopped", id);
            }
            
            // Get event driver
            auto driver = eventDriver;
            
            // Listen on port
            auto addr = new InternetAddress(config.host, config.port);
            
            driver.sockets.listenStream(
                addr,
                (StreamListenSocketFD listenSock, StreamSocketFD clientSock, scope RefAddress remoteAddr) @safe nothrow {
                    (() @trusted {
                        try
                        {
                            handleConnection(clientSock, reactor, bufferPool);
                        }
                        catch (Exception e)
                        {
                            // Log error
                        }
                    })();
                }
            );
            
            if (config.debug_)
                writefln("   Worker %d listening on port %d", id, config.port);
            
            // Run event loop
            runEventLoop();
        }
        catch (Throwable t)
        {
            writefln("❌ Worker %d crashed: %s", id, t.msg);
        }
    }
    
    private void handleConnection(StreamSocketFD sock, Reactor reactor, BufferPool pool) @trusted
    {
        auto conn = new Connection();
        auto connConfig = config.connection;
        conn.initialize(sock, &pool, reactor, &connConfig);
        
        runTask({
            try
            {
                connectionLoop(conn);
            }
            catch (Throwable t)
            {
                // Connection error
            }
            finally
            {
                conn.close();
            }
        });
    }
    
    private void connectionLoop(Connection* conn)
    {
        while (!conn.isClosed && atomicLoad(running))
        {
            // 1. Read request
            conn.transition(AuroraConnectionState.READING_HEADERS);
            
            while (!conn.request.isComplete() && !conn.isClosed)
            {
                if (conn.readBuffer.length == 0)
                {
                    conn.readBuffer = conn.bufferPool.acquire(BufferSize.SMALL);
                }
                
                auto res = conn.reactor.socketRead(conn.socket, conn.readBuffer[conn.readPos .. $]);
                
                if (res.bytesRead > 0)
                {
                    conn.readPos += res.bytesRead;
                    conn.request = HTTPRequest.parse(conn.readBuffer[0 .. conn.readPos]);
                    
                    if (conn.request.isComplete())
                        break;
                }
                else if (res.status == IOStatus.wouldBlock)
                {
                    yield();
                }
                else
                {
                    conn.close();
                    return;
                }
            }
            
            if (conn.isClosed)
                return;
            
            // 2. Process request
            conn.transition(AuroraConnectionState.PROCESSING);
            
            // Create context
            Context ctx;
            ctx.request = &conn.request;
            ctx.response = &conn.response;
            
            // Match route
            auto match = router.match(conn.request.method, conn.request.path);
            
            if (match.found)
            {
                ctx.params = match.params;
                
                // Execute middleware pipeline + handler
                pipeline.execute(ctx, match.handler);
            }
            else
            {
                // 404 Not Found
                ctx.status(404);
                ctx.send(`{"error":"Not Found","path":"` ~ conn.request.path ~ `"}`);
            }
            
            // 3. Write response
            conn.transition(AuroraConnectionState.WRITING_RESPONSE);
            
            auto responseData = cast(ubyte[])conn.response.build();
            size_t written = 0;
            
            while (written < responseData.length && !conn.isClosed)
            {
                auto res = conn.reactor.socketWrite(conn.socket, responseData[written .. $]);
                
                if (res.bytesWritten > 0)
                {
                    written += res.bytesWritten;
                }
                else if (res.status == IOStatus.wouldBlock)
                {
                    yield();
                }
                else
                {
                    conn.close();
                    return;
                }
            }
            
            // 4. Check keep-alive
            if (!conn.request.shouldKeepAlive())
            {
                conn.close();
                return;
            }
            
            // Reset for next request
            conn.resetConnection();
        }
    }
}

// ========================================
// CONVENIENCE FUNCTIONS
// ========================================

/**
 * Create new Aurora application with default settings
 */
App createApp()
{
    return new App();
}

/**
 * Create new Aurora application with custom config
 */
App createApp(ServerConfig config)
{
    return new App(config);
}
