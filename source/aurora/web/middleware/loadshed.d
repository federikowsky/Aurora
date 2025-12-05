/**
 * Load Shedding Middleware — HTTP-level Overload Protection
 *
 * Package: aurora.web.middleware.loadshed
 *
 * Provides intelligent request rejection to prevent server overload.
 * Works alongside TCP-level backpressure (server.d) for defense in depth.
 *
 * Key differences from TCP backpressure:
 * - TCP backpressure: Rejects NEW connections when limit reached
 * - Load shedding: Rejects REQUESTS on existing connections
 *
 * Why both are needed:
 * - Keep-alive connections can send many requests
 * - Some requests should be prioritized (health probes, admin)
 * - Better to reject early than respond late (tail latency)
 *
 * Features:
 * - Hysteresis-based state (avoids oscillation)
 * - Probabilistic shedding (gradual degradation)
 * - Bypass paths for critical endpoints
 * - Integration with server metrics
 *
 * Example:
 * ---
 * auto config = LoadSheddingConfig();
 * config.bypassPaths = ["/health/*", "/metrics"];
 * config.utilizationHighWater = 0.85;
 * 
 * app.use(loadSheddingMiddleware(app.server, config));
 * ---
 */
module aurora.web.middleware.loadshed;

import aurora.web.context;
import aurora.runtime.server : Server;

// Import middleware types without causing circular dependency
alias NextFunction = void delegate();
alias Middleware = void delegate(ref Context ctx, NextFunction next);

/**
 * Load Shedding Configuration
 */
struct LoadSheddingConfig
{
    // === Utilization Thresholds ===
    
    /// Connection utilization threshold to START shedding (0.0-1.0)
    float utilizationHighWater = 0.8;
    
    /// Connection utilization threshold to STOP shedding (0.0-1.0)
    float utilizationLowWater = 0.6;
    
    // === In-Flight Request Thresholds ===
    
    /// In-flight requests threshold to START shedding
    uint inFlightHighWater = 800;
    
    /// In-flight requests threshold to STOP shedding
    uint inFlightLowWater = 500;
    
    // === Bypass Configuration ===
    
    /// Paths that bypass load shedding (supports trailing * glob)
    /// Example: ["/health/*", "/metrics", "/admin/*"]
    string[] bypassPaths = ["/health/*"];
    
    // === Response Configuration ===
    
    /// Retry-After header value in seconds
    uint retryAfterSeconds = 5;
    
    // === Shedding Strategy ===
    
    /// Enable probabilistic shedding (gradual) vs hard cutoff
    bool enableProbabilistic = true;
    
    /// Minimum probability when in shedding state (0.0-1.0)
    /// Even at threshold, shed this % of requests
    float minSheddingProbability = 0.1;
    
    /// Create default configuration
    static LoadSheddingConfig defaults() @safe nothrow
    {
        return LoadSheddingConfig.init;
    }
}

/**
 * Load Shedding Statistics
 */
struct LoadSheddingStats
{
    /// Total requests shed
    ulong requestsShed;
    
    /// Total requests bypassed (priority paths)
    ulong requestsBypassed;
    
    /// Total requests allowed through
    ulong requestsAllowed;
    
    /// Times entered shedding state
    ulong sheddingStateTransitions;
    
    /// Current shedding state
    bool inSheddingState;
}

/**
 * Load Shedding Middleware
 *
 * Rejects requests when server is under heavy load.
 * Uses hysteresis to prevent oscillation.
 */
class LoadSheddingMiddleware
{
    private
    {
        Server server;
        LoadSheddingConfig config;
        
        // Shedding state (hysteresis)
        bool inSheddingState = false;
        
        // Statistics
        ulong requestsShed = 0;
        ulong requestsBypassed = 0;
        ulong requestsAllowed = 0;
        ulong sheddingStateTransitions = 0;
        
        // Random seed for probabilistic shedding
        uint randomState = 12345;
    }
    
    /**
     * Constructor
     *
     * Params:
     *   server = Server instance for metrics (can be null for testing)
     *   config = Load shedding configuration
     */
    this(Server server, LoadSheddingConfig config = LoadSheddingConfig.defaults())
    {
        this.server = server;
        this.config = config;
    }
    
    /**
     * Handle request (middleware interface)
     */
    void handle(ref Context ctx, NextFunction next)
    {
        if (ctx.request is null)
        {
            next();
            return;
        }
        
        string path = ctx.request.path;
        
        // Check bypass paths first
        if (matchesBypassPath(path))
        {
            requestsBypassed++;
            next();
            return;
        }
        
        // Check if we should shed this request
        if (shouldShed())
        {
            requestsShed++;
            send503Response(ctx);
            return;
        }
        
        // Allow request through
        requestsAllowed++;
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
     * Get current statistics
     */
    LoadSheddingStats getStats() @safe nothrow
    {
        LoadSheddingStats stats;
        stats.requestsShed = requestsShed;
        stats.requestsBypassed = requestsBypassed;
        stats.requestsAllowed = requestsAllowed;
        stats.sheddingStateTransitions = sheddingStateTransitions;
        stats.inSheddingState = inSheddingState;
        return stats;
    }
    
    /**
     * Check if currently in shedding state
     */
    bool isInSheddingState() const @safe nothrow
    {
        return inSheddingState;
    }
    
    /**
     * Reset statistics (for testing)
     */
    void resetStats() @safe nothrow
    {
        requestsShed = 0;
        requestsBypassed = 0;
        requestsAllowed = 0;
        sheddingStateTransitions = 0;
    }
    
    // ========================================================================
    // PRIVATE METHODS
    // ========================================================================
    
    /**
     * Determine if request should be shed.
     * Uses hysteresis to prevent oscillation.
     */
    private bool shouldShed() @trusted nothrow
    {
        // Get current metrics
        float utilization = 0.0f;
        ulong inFlight = 0;
        
        if (server !is null)
        {
            utilization = server.getConnectionUtilization();
            inFlight = server.getCurrentInFlightRequests();
        }
        
        // Update hysteresis state
        updateSheddingState(utilization, inFlight);
        
        // If not in shedding state, allow request
        if (!inSheddingState)
            return false;
        
        // If probabilistic shedding is disabled, always shed
        if (!config.enableProbabilistic)
            return true;
        
        // Calculate shedding probability
        float probability = calculateSheddingProbability(utilization, inFlight);
        
        // Roll the dice
        return randomFloat() < probability;
    }
    
    /**
     * Update hysteresis shedding state based on metrics.
     */
    private void updateSheddingState(float utilization, ulong inFlight) @safe nothrow
    {
        bool shouldBeInSheddingState = false;
        
        if (inSheddingState)
        {
            // Currently shedding - check if we should exit
            // Exit only when BOTH metrics are below low water marks
            bool utilizationOk = utilization < config.utilizationLowWater;
            bool inFlightOk = inFlight < config.inFlightLowWater;
            
            shouldBeInSheddingState = !(utilizationOk && inFlightOk);
        }
        else
        {
            // Not shedding - check if we should enter
            // Enter when EITHER metric exceeds high water mark
            bool utilizationHigh = utilization >= config.utilizationHighWater;
            bool inFlightHigh = inFlight >= config.inFlightHighWater;
            
            shouldBeInSheddingState = utilizationHigh || inFlightHigh;
        }
        
        // Track state transitions
        if (shouldBeInSheddingState != inSheddingState)
        {
            sheddingStateTransitions++;
            inSheddingState = shouldBeInSheddingState;
        }
    }
    
    /**
     * Calculate shedding probability based on current load.
     * Higher load = higher probability of shedding.
     */
    private float calculateSheddingProbability(float utilization, ulong inFlight) const @safe nothrow
    {
        // Calculate utilization-based probability
        float utilizationProb = 0.0f;
        if (utilization > config.utilizationHighWater)
        {
            float range = 1.0f - config.utilizationHighWater;
            if (range > 0)
                utilizationProb = (utilization - config.utilizationHighWater) / range;
        }
        
        // Calculate in-flight-based probability
        float inFlightProb = 0.0f;
        if (inFlight > config.inFlightHighWater)
        {
            // Assume max in-flight is 2x high water mark
            uint maxInFlight = config.inFlightHighWater * 2;
            if (maxInFlight > config.inFlightHighWater)
            {
                float range = cast(float)(maxInFlight - config.inFlightHighWater);
                inFlightProb = cast(float)(inFlight - config.inFlightHighWater) / range;
            }
        }
        
        // Take maximum of both probabilities
        float prob = utilizationProb > inFlightProb ? utilizationProb : inFlightProb;
        
        // Clamp and apply minimum
        if (prob < config.minSheddingProbability)
            prob = config.minSheddingProbability;
        if (prob > 1.0f)
            prob = 1.0f;
        
        return prob;
    }
    
    /**
     * Check if path matches any bypass pattern.
     * Supports trailing * glob pattern.
     */
    private bool matchesBypassPath(string path) const @safe nothrow
    {
        foreach (pattern; config.bypassPaths)
        {
            if (globMatch(path, pattern))
                return true;
        }
        return false;
    }
    
    /**
     * Simple glob matching - supports trailing * only.
     * Examples:
     *   "/health/*" matches "/health/live", "/health/ready"
     *   "/metrics" matches only "/metrics"
     *   "/*" matches everything
     */
    private static bool globMatch(string path, string pattern) @safe nothrow
    {
        if (pattern.length == 0)
            return false;
        
        // Check for trailing wildcard
        if (pattern.length > 0 && pattern[$ - 1] == '*')
        {
            // Match prefix
            string prefix = pattern[0 .. $ - 1];
            return path.length >= prefix.length && 
                   path[0 .. prefix.length] == prefix;
        }
        else
        {
            // Exact match
            return path == pattern;
        }
    }
    
    /**
     * Send 503 Service Unavailable response.
     */
    private void send503Response(ref Context ctx) @trusted
    {
        import std.conv : to;
        
        ctx.status(503)
           .header("Content-Type", "application/json")
           .header("Retry-After", config.retryAfterSeconds.to!string)
           .header("Cache-Control", "no-cache, no-store")
           .send(`{"error":"Service temporarily unavailable","reason":"load_shedding"}`);
    }
    
    /**
     * Simple pseudo-random number generator (xorshift).
     * Returns float in [0, 1).
     */
    private float randomFloat() @safe nothrow
    {
        // xorshift32
        randomState ^= randomState << 13;
        randomState ^= randomState >> 17;
        randomState ^= randomState << 5;
        
        // Convert to float [0, 1)
        return (randomState & 0x7FFFFFFF) / cast(float)0x80000000;
    }
}

/**
 * Factory function to create load shedding middleware.
 *
 * Example:
 * ---
 * app.use(loadSheddingMiddleware(app.server));
 * ---
 */
Middleware loadSheddingMiddleware(Server server, LoadSheddingConfig config = LoadSheddingConfig.defaults())
{
    auto mw = new LoadSheddingMiddleware(server, config);
    return mw.middleware;
}

/**
 * Factory function returning the middleware instance (for stats access).
 *
 * Example:
 * ---
 * auto shedder = createLoadSheddingMiddleware(app.server);
 * app.use(shedder.middleware);
 * 
 * // Later
 * auto stats = shedder.getStats();
 * ---
 */
LoadSheddingMiddleware createLoadSheddingMiddleware(Server server, LoadSheddingConfig config = LoadSheddingConfig.defaults())
{
    return new LoadSheddingMiddleware(server, config);
}
