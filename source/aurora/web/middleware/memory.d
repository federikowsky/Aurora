/**
 * Memory Pressure Middleware — GC Pressure Protection
 *
 * Package: aurora.web.middleware.memory
 *
 * Rejects HTTP requests when server memory is in CRITICAL state.
 * Protects against OOM by gracefully shedding load.
 *
 * Features:
 * - Automatic request rejection at critical memory threshold
 * - Bypass paths for health probes
 * - Configurable Retry-After header
 * - Integration with MemoryMonitor for stats
 */
module aurora.web.middleware.memory;

import aurora.web.context : Context;
import aurora.web.middleware : NextFunction, Middleware;
import aurora.mem.pressure : MemoryMonitor, MemoryConfig, MemoryState;

/**
 * Memory Middleware
 *
 * Rejects requests when memory is in CRITICAL state.
 * Bypass paths allow health probes to continue working.
 */
class MemoryMiddleware
{
    private
    {
        MemoryMonitor monitor;
        string[] bypassPaths;
        uint retryAfterSeconds;
        bool checkOnRequest;
    }
    
    /**
     * Constructor
     *
     * Params:
     *   monitor = Memory monitor instance
     *   checkOnRequest = Whether to call monitor.check() on each request
     */
    this(MemoryMonitor monitor, bool checkOnRequest = false) @safe
    {
        this.monitor = monitor;
        this.bypassPaths = monitor.configuration.bypassPaths.dup;
        this.retryAfterSeconds = monitor.configuration.retryAfterSeconds;
        this.checkOnRequest = checkOnRequest;
    }
    
    /**
     * Handle request
     */
    void handle(ref Context ctx, NextFunction next) @trusted
    {
        if (ctx.request is null)
        {
            next();
            return;
        }
        
        string path = ctx.request.path;
        
        // Check bypass paths
        if (matchesBypassPath(path))
        {
            next();
            return;
        }
        
        // Optionally check memory on each request
        if (checkOnRequest)
        {
            monitor.check();
        }
        
        // Check current state
        if (monitor.isCritical())
        {
            monitor.recordRejection();
            sendCriticalResponse(ctx);
            return;
        }
        
        // Memory OK - proceed
        next();
    }
    
    /**
     * Get as middleware delegate
     */
    Middleware middleware() @safe
    {
        return &this.handle;
    }
    
    /**
     * Get the underlying monitor for stats access
     */
    @property MemoryMonitor getMonitor() @safe nothrow
    {
        return monitor;
    }
    
    // ========================================================================
    // PRIVATE METHODS
    // ========================================================================
    
    private bool matchesBypassPath(string path) const @safe nothrow
    {
        foreach (pattern; bypassPaths)
        {
            if (globMatch(path, pattern))
                return true;
        }
        return false;
    }
    
    private static bool globMatch(string path, string pattern) @safe nothrow
    {
        if (pattern.length == 0)
            return false;
        
        if (pattern[$ - 1] == '*')
        {
            string prefix = pattern[0 .. $ - 1];
            return path.length >= prefix.length && path[0 .. prefix.length] == prefix;
        }
        else
        {
            return path == pattern;
        }
    }
    
    private void sendCriticalResponse(ref Context ctx) @trusted
    {
        import std.conv : to;
        
        ctx.status(503)
           .header("Content-Type", "application/json")
           .header("Retry-After", retryAfterSeconds.to!string)
           .header("X-Memory-State", "critical")
           .header("Cache-Control", "no-cache, no-store")
           .send(`{"error":"Server under memory pressure","reason":"memory_critical"}`);
    }
}

// ============================================================================
// FACTORY FUNCTIONS
// ============================================================================

/**
 * Create memory middleware with new monitor.
 *
 * Example:
 * ---
 * app.use(memoryMiddleware(512 * 1024 * 1024));  // 512 MB limit
 * ---
 */
Middleware memoryMiddleware(size_t maxHeapBytes)
{
    auto config = MemoryConfig();
    config.maxHeapBytes = maxHeapBytes;
    auto monitor = new MemoryMonitor(config);
    auto mw = new MemoryMiddleware(monitor);
    return mw.middleware;
}

/**
 * Create memory middleware with config.
 */
Middleware memoryMiddleware(MemoryConfig config)
{
    auto monitor = new MemoryMonitor(config);
    auto mw = new MemoryMiddleware(monitor);
    return mw.middleware;
}

/**
 * Create memory middleware with existing monitor.
 *
 * Example:
 * ---
 * auto monitor = new MemoryMonitor(config);
 * monitor.onPressure = (state) { ... };
 * app.use(memoryMiddleware(monitor));
 * ---
 */
Middleware memoryMiddleware(MemoryMonitor monitor, bool checkOnRequest = false)
{
    auto mw = new MemoryMiddleware(monitor, checkOnRequest);
    return mw.middleware;
}

/**
 * Create memory middleware with instance access.
 */
MemoryMiddleware createMemoryMiddleware(MemoryMonitor monitor, bool checkOnRequest = false)
{
    return new MemoryMiddleware(monitor, checkOnRequest);
}

