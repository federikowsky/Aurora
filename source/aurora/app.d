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
import aurora.runtime.hooks;
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
    
    // Hooks storage (applied to Server in listen())
    private StartHook[] _startHooks;
    private StopHook[] _stopHooks;
    private ErrorHook[] _errorHooks;
    private RequestHook[] _requestHooks;
    private ResponseHook[] _responseHooks;
    
    // Exception handlers storage (applied to Server in listen())
    private TypeErasedHandler[TypeInfo_Class] _exceptionHandlers;
    
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
    
    /// Add Gin-style request logger (convenience method)
    App useLogger(bool colored = true)
    {
        import aurora.web.middleware.logger;
        auto logger = new LoggerMiddleware();
        logger.format = LogFormat.COLORED;
        logger.useColors = colored;
        return this.use(logger);
    }
    
    // ========================================
    // HOOKS API (V0.4 Extensibility)
    // ========================================
    
    /// Register callback for server start event
    App onStart(StartHook hook)
    {
        if (hook !is null)
            _startHooks ~= hook;
        return this;
    }
    
    /// Register callback for server stop event
    App onStop(StopHook hook)
    {
        if (hook !is null)
            _stopHooks ~= hook;
        return this;
    }
    
    /// Register callback for request errors (for logging/metrics)
    App onError(ErrorHook hook)
    {
        if (hook !is null)
            _errorHooks ~= hook;
        return this;
    }
    
    /// Register callback before routing each request
    App onRequest(RequestHook hook)
    {
        if (hook !is null)
            _requestHooks ~= hook;
        return this;
    }
    
    /// Register callback after handler completion
    App onResponse(ResponseHook hook)
    {
        if (hook !is null)
            _responseHooks ~= hook;
        return this;
    }
    
    // ========================================
    // EXCEPTION HANDLERS API (V0.4 Extensibility)
    // ========================================
    
    /**
     * Register a typed exception handler (FastAPI-style)
     * 
     * Example:
     * ---
     * app.addExceptionHandler!ValidationError((ref ctx, e) {
     *     ctx.status(400).json(`{"error":"` ~ e.msg ~ `"}`);
     * });
     * ---
     */
    App addExceptionHandler(E : Exception)(ExceptionHandler!E handler)
    {
        if (handler is null)
            throw new Exception("Exception handler cannot be null");
        
        // Wrap typed handler in type-erased form
        TypeErasedHandler wrapped = (ref Context ctx, Exception e) @trusted {
            if (auto typed = cast(E) e)
                handler(ctx, typed);
        };
        
        _exceptionHandlers[typeid(E)] = wrapped;
        return this;
    }
    
    /// Check if an exception handler is registered for a type
    bool hasExceptionHandler(E : Exception)() const
    {
        return (typeid(E) in _exceptionHandlers) !is null;
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
        
        // Apply registered hooks to the server
        foreach (hook; _startHooks)
            server.hooks.onStart(hook);
        foreach (hook; _stopHooks)
            server.hooks.onStop(hook);
        foreach (hook; _errorHooks)
            server.hooks.onError(hook);
        foreach (hook; _requestHooks)
            server.hooks.onRequest(hook);
        foreach (hook; _responseHooks)
            server.hooks.onResponse(hook);
        
        // Apply registered exception handlers to the server
        foreach (typeInfo, handler; _exceptionHandlers)
            server.addExceptionHandlerDirect(typeInfo, handler);
        
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
