/**
 * Aurora Application - High-Level API
 *
 * Provides an Express.js-like API for building HTTP servers.
 * This is a thin wrapper around Server that provides a friendlier interface.
 *
 * Usage:
 * ---
 * import aurora;
 *
 * void main() {
 *     auto app = new App();
 *     
 *     app.get("/", (ref Context ctx) {
 *         ctx.send("Hello, Aurora!");
 *     });
 *     
 *     app.get("/users/:id", (ref Context ctx) {
 *         ctx.json(["id": ctx.params["id"]]);
 *     });
 *     
 *     app.listen(8080);
 * }
 * ---
 */
module aurora.app;

import aurora.runtime.server;
import aurora.web.router;
import aurora.web.context;
import aurora.web.middleware;

import std.stdio : writefln;

/**
 * Aurora Application
 *
 * Main entry point for Aurora HTTP servers.
 * Wraps Server with a fluent, user-friendly API.
 */
class App
{
    private Server server;
    private Router router;
    private MiddlewarePipeline pipeline;
    private ServerConfig config;
    
    /**
     * Create new Aurora application
     */
    this(ServerConfig config = ServerConfig.defaults())
    {
        this.config = config;
        this.router = new Router();
        this.pipeline = new MiddlewarePipeline();
    }
    
    // ========================================
    // ROUTING API
    // ========================================
    
    /// Register GET route
    App get(string path, Handler handler)
    {
        router.get(path, handler);
        return this;
    }
    
    /// Register POST route
    App post(string path, Handler handler)
    {
        router.post(path, handler);
        return this;
    }
    
    /// Register PUT route
    App put(string path, Handler handler)
    {
        router.put(path, handler);
        return this;
    }
    
    /// Register DELETE route
    App delete_(string path, Handler handler)
    {
        router.delete_(path, handler);
        return this;
    }
    
    /// Register PATCH route
    App patch(string path, Handler handler)
    {
        router.patch(path, handler);
        return this;
    }
    
    /// Register route for any HTTP method
    App route(string method, string path, Handler handler)
    {
        router.addRoute(method, path, handler);
        return this;
    }
    
    /// Include sub-router
    App includeRouter(Router subRouter)
    {
        router.includeRouter(subRouter);
        return this;
    }
    
    // ========================================
    // MIDDLEWARE API
    // ========================================
    
    /// Add middleware function
    App use(Middleware mw)
    {
        pipeline.use(mw);
        return this;
    }
    
    /// Add middleware class instance
    App use(T)(T middleware) if (__traits(hasMember, T, "handle"))
    {
        pipeline.use((ref Context ctx, NextFunction next) {
            middleware.handle(ctx, next);
        });
        return this;
    }
    
    // ========================================
    // CONFIGURATION
    // ========================================
    
    /// Set number of worker threads
    App workers(uint n)
    {
        config.numWorkers = n;
        return this;
    }
    
    /// Set host address
    App host(string h)
    {
        config.host = h;
        return this;
    }
    
    /// Enable debug mode
    App debug_(bool enabled = true)
    {
        config.debugMode = enabled;
        return this;
    }
    
    // ========================================
    // SERVER LIFECYCLE
    // ========================================
    
    /**
     * Start server and listen on specified port
     * This method blocks until the server is stopped.
     */
    void listen(ushort port)
    {
        config.port = port;
        listen();
    }
    
    /**
     * Start server with configured settings
     * This method blocks until the server is stopped.
     */
    void listen()
    {
        // Create server with our router and pipeline
        server = new Server(router, pipeline, config);
        
        // Run (blocking)
        server.run();
    }
    
    /**
     * Stop server gracefully
     */
    void stop()
    {
        if (server !is null)
            server.stop();
    }
    
    /**
     * Check if server is running
     */
    @property bool isRunning()
    {
        return server !is null && server.isRunning;
    }
    
    /**
     * Get server statistics
     */
    void printStats()
    {
        if (server !is null)
        {
            import std.stdio : writefln;
            writefln("Stats: %d requests, %d connections, %d active, %d errors",
                server.getRequests(), server.getConnections(), 
                server.getActiveConnections(), server.getErrors());
        }
    }
    
    /**
     * Get total requests processed
     */
    ulong totalRequests()
    {
        return server !is null ? server.getRequests() : 0;
    }
}

// ========================================
// CONVENIENCE FUNCTIONS
// ========================================

/// Create new Aurora application with default settings
App createApp()
{
    return new App();
}

/// Create new Aurora application with custom config
App createApp(ServerConfig config)
{
    return new App(config);
}
