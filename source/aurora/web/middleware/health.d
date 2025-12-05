/**
 * Health Middleware — Kubernetes Health Probes
 *
 * Package: aurora.web.middleware.health
 *
 * Provides standardized health check endpoints for Kubernetes:
 * - Liveness probe: Is the process alive and responsive?
 * - Readiness probe: Is the service ready to accept traffic?
 * - Startup probe: Has the service completed initialization?
 *
 * Features:
 * - Configurable endpoint paths
 * - Custom readiness checks (database, cache, external services)
 * - Integration with server overload/shutdown state
 * - Optional detailed responses for debugging
 * - RFC 7231 compliant HTTP responses
 *
 * Example:
 * ---
 * auto healthConfig = HealthConfig();
 * healthConfig.readinessChecks ~= (ref HealthCheckResult r) {
 *     r.name = "database";
 *     r.healthy = checkDatabaseConnection();
 *     r.message = r.healthy ? "connected" : "connection failed";
 * };
 * 
 * app.use(healthMiddleware(app.server, healthConfig));
 * ---
 *
 * Kubernetes Configuration Example:
 * ---yaml
 * livenessProbe:
 *   httpGet:
 *     path: /health/live
 *     port: 8080
 *   initialDelaySeconds: 5
 *   periodSeconds: 10
 * 
 * readinessProbe:
 *   httpGet:
 *     path: /health/ready
 *     port: 8080
 *   initialDelaySeconds: 10
 *   periodSeconds: 5
 * 
 * startupProbe:
 *   httpGet:
 *     path: /health/startup
 *     port: 8080
 *   failureThreshold: 30
 *   periodSeconds: 10
 * ---
 */
module aurora.web.middleware.health;

import aurora.web.context;
import aurora.runtime.server : Server;

// Import middleware types without causing circular dependency
alias NextFunction = void delegate();
alias Middleware = void delegate(ref Context ctx, NextFunction next);

/**
 * Result of a single health check.
 * Used for custom readiness checks.
 */
struct HealthCheckResult
{
    /// Name of the component being checked
    string name;
    
    /// Whether the check passed
    bool healthy = true;
    
    /// Optional message (error details, status info)
    string message;
    
    /// Optional duration of the check in microseconds
    long durationUs = 0;
}

/// Delegate type for custom readiness checks
alias ReadinessCheck = void delegate(ref HealthCheckResult result);

/**
 * Health Check Configuration
 *
 * Controls endpoint paths, response detail level, and custom checks.
 */
struct HealthConfig
{
    // === Endpoint Paths ===
    
    /// Path for liveness probe (default: /health/live)
    string livenessPath = "/health/live";
    
    /// Path for readiness probe (default: /health/ready)
    string readinessPath = "/health/ready";
    
    /// Path for startup probe (default: /health/startup)
    string startupPath = "/health/startup";
    
    // === Response Options ===
    
    /// Include detailed check results in response body.
    /// WARNING: Disable in production for security (may expose internal state)
    bool includeDetails = false;
    
    /// Cache health check results for this duration (0 = no caching)
    /// Useful for expensive checks to avoid hammering dependencies
    uint cacheDurationMs = 0;
    
    // === Custom Checks ===
    
    /// Custom readiness checks (database, cache, external services)
    /// All checks must pass for readiness probe to succeed
    ReadinessCheck[] readinessChecks;
    
    /// Create default configuration
    static HealthConfig defaults() @safe nothrow
    {
        return HealthConfig.init;
    }
}

/**
 * Health Status enumeration
 */
enum HealthStatus
{
    HEALTHY,
    UNHEALTHY,
    DEGRADED,      // Some checks failed but service can operate
    STARTING,      // Still initializing
    SHUTTING_DOWN  // Graceful shutdown in progress
}

/**
 * Health Middleware Class
 *
 * Intercepts requests to health probe paths and returns appropriate
 * HTTP responses based on server state and custom checks.
 */
class HealthMiddleware
{
    private
    {
        Server server;
        HealthConfig config;
        
        // Startup state tracking
        bool startupComplete = false;
        
        // Cache state
        long lastCheckTimeUs = 0;
        bool cachedReadinessResult = false;
        HealthCheckResult[] cachedCheckResults;
    }
    
    /**
     * Constructor
     *
     * Params:
     *   server = Server instance for checking overload/shutdown state
     *   config = Health check configuration (optional)
     */
    this(Server server, HealthConfig config = HealthConfig.defaults())
    {
        this.server = server;
        this.config = config;
    }
    
    /**
     * Mark startup as complete.
     * Call this after your application has finished initialization.
     *
     * Example:
     * ---
     * auto health = new HealthMiddleware(app.server);
     * app.use(health.middleware);
     * 
     * // After loading config, connecting to DB, etc.
     * health.markStartupComplete();
     * ---
     */
    void markStartupComplete() @safe nothrow
    {
        startupComplete = true;
    }
    
    /**
     * Check if startup is complete.
     */
    bool isStartupComplete() const @safe nothrow
    {
        return startupComplete;
    }
    
    /**
     * Handle request (middleware interface)
     *
     * Intercepts health probe paths and returns appropriate responses.
     * Non-health requests are passed to the next middleware.
     */
    void handle(ref Context ctx, NextFunction next)
    {
        if (ctx.request is null)
        {
            next();
            return;
        }
        
        string path = ctx.request.path;
        
        // Check liveness endpoint
        if (path == config.livenessPath)
        {
            handleLiveness(ctx);
            return;
        }
        
        // Check readiness endpoint
        if (path == config.readinessPath)
        {
            handleReadiness(ctx);
            return;
        }
        
        // Check startup endpoint
        if (path == config.startupPath)
        {
            handleStartup(ctx);
            return;
        }
        
        // Not a health endpoint, continue to next middleware
        next();
    }
    
    /**
     * Get as middleware delegate for app.use()
     */
    Middleware middleware() @safe
    {
        return &this.handle;
    }
    
    // ========================================================================
    // PROBE HANDLERS
    // ========================================================================
    
    private void handleLiveness(ref Context ctx) @trusted
    {
        // Liveness is simple: if we can respond, we're alive
        // This should NEVER fail unless the process is truly dead
        
        if (config.includeDetails)
        {
            ctx.status(200)
               .header("Content-Type", "application/json")
               .header("Cache-Control", "no-cache, no-store")
               .send(`{"status":"alive","probe":"liveness"}`);
        }
        else
        {
            ctx.status(200)
               .header("Content-Type", "application/json")
               .header("Cache-Control", "no-cache, no-store")
               .send(`{"status":"alive"}`);
        }
    }
    
    private void handleReadiness(ref Context ctx) @trusted
    {
        import std.format : format;
        import std.datetime.stopwatch : StopWatch, AutoStart;
        
        // Check 1: Server shutting down?
        if (server !is null && server.isShuttingDown())
        {
            sendUnhealthyResponse(ctx, HealthStatus.SHUTTING_DOWN, 
                "Server is shutting down", null);
            return;
        }
        
        // Check 2: Server overloaded?
        if (server !is null && server.isInOverload())
        {
            sendUnhealthyResponse(ctx, HealthStatus.UNHEALTHY,
                "Server is overloaded", null);
            return;
        }
        
        // Check 3: Startup complete?
        if (!startupComplete)
        {
            sendUnhealthyResponse(ctx, HealthStatus.STARTING,
                "Service still starting", null);
            return;
        }
        
        // Check 4: Custom readiness checks
        HealthCheckResult[] results;
        bool allHealthy = true;
        
        if (config.readinessChecks.length > 0)
        {
            // Check cache validity
            if (config.cacheDurationMs > 0 && isCacheValid())
            {
                results = cachedCheckResults;
                allHealthy = cachedReadinessResult;
            }
            else
            {
                // Run all checks
                foreach (check; config.readinessChecks)
                {
                    HealthCheckResult result;
                    
                    auto sw = StopWatch(AutoStart.yes);
                    try
                    {
                        check(result);
                    }
                    catch (Exception e)
                    {
                        result.healthy = false;
                        result.message = e.msg;
                    }
                    sw.stop();
                    result.durationUs = sw.peek.total!"usecs";
                    
                    results ~= result;
                    if (!result.healthy)
                        allHealthy = false;
                }
                
                // Update cache
                if (config.cacheDurationMs > 0)
                {
                    updateCache(allHealthy, results);
                }
            }
        }
        
        if (allHealthy)
        {
            sendHealthyResponse(ctx, HealthStatus.HEALTHY, results);
        }
        else
        {
            sendUnhealthyResponse(ctx, HealthStatus.UNHEALTHY,
                "One or more checks failed", results);
        }
    }
    
    private void handleStartup(ref Context ctx) @trusted
    {
        if (startupComplete)
        {
            if (config.includeDetails)
            {
                ctx.status(200)
                   .header("Content-Type", "application/json")
                   .header("Cache-Control", "no-cache, no-store")
                   .send(`{"status":"started","probe":"startup"}`);
            }
            else
            {
                ctx.status(200)
                   .header("Content-Type", "application/json")
                   .header("Cache-Control", "no-cache, no-store")
                   .send(`{"status":"started"}`);
            }
        }
        else
        {
            if (config.includeDetails)
            {
                ctx.status(503)
                   .header("Content-Type", "application/json")
                   .header("Cache-Control", "no-cache, no-store")
                   .header("Retry-After", "5")
                   .send(`{"status":"starting","probe":"startup"}`);
            }
            else
            {
                ctx.status(503)
                   .header("Content-Type", "application/json")
                   .header("Cache-Control", "no-cache, no-store")
                   .header("Retry-After", "5")
                   .send(`{"status":"starting"}`);
            }
        }
    }
    
    // ========================================================================
    // RESPONSE HELPERS
    // ========================================================================
    
    private void sendHealthyResponse(ref Context ctx, HealthStatus status, 
                                      HealthCheckResult[] checks) @trusted
    {
        import std.format : format;
        
        if (config.includeDetails && checks.length > 0)
        {
            // Build detailed JSON response
            string checksJson = buildChecksJson(checks);
            string json = format(`{"status":"ready","probe":"readiness","checks":[%s]}`, checksJson);
            
            ctx.status(200)
               .header("Content-Type", "application/json")
               .header("Cache-Control", "no-cache, no-store")
               .send(json);
        }
        else
        {
            ctx.status(200)
               .header("Content-Type", "application/json")
               .header("Cache-Control", "no-cache, no-store")
               .send(`{"status":"ready"}`);
        }
    }
    
    private void sendUnhealthyResponse(ref Context ctx, HealthStatus status,
                                        string reason, HealthCheckResult[] checks) @trusted
    {
        import std.format : format;
        
        string statusStr = healthStatusToString(status);
        
        if (config.includeDetails)
        {
            string checksJson = checks.length > 0 ? buildChecksJson(checks) : "";
            string json;
            
            if (checksJson.length > 0)
            {
                json = format(`{"status":"%s","probe":"readiness","reason":"%s","checks":[%s]}`,
                    statusStr, escapeJson(reason), checksJson);
            }
            else
            {
                json = format(`{"status":"%s","probe":"readiness","reason":"%s"}`,
                    statusStr, escapeJson(reason));
            }
            
            ctx.status(503)
               .header("Content-Type", "application/json")
               .header("Cache-Control", "no-cache, no-store")
               .header("Retry-After", "5")
               .send(json);
        }
        else
        {
            ctx.status(503)
               .header("Content-Type", "application/json")
               .header("Cache-Control", "no-cache, no-store")
               .header("Retry-After", "5")
               .send(format(`{"status":"%s"}`, statusStr));
        }
    }
    
    private string buildChecksJson(HealthCheckResult[] checks) @trusted
    {
        import std.format : format;
        import std.array : join;
        
        string[] parts;
        foreach (check; checks)
        {
            string statusStr = check.healthy ? "pass" : "fail";
            string json;
            
            if (check.message.length > 0)
            {
                json = format(`{"name":"%s","status":"%s","message":"%s","duration_us":%d}`,
                    escapeJson(check.name), statusStr, 
                    escapeJson(check.message), check.durationUs);
            }
            else
            {
                json = format(`{"name":"%s","status":"%s","duration_us":%d}`,
                    escapeJson(check.name), statusStr, check.durationUs);
            }
            parts ~= json;
        }
        
        return parts.join(",");
    }
    
    private static string healthStatusToString(HealthStatus status) @safe nothrow
    {
        final switch (status)
        {
            case HealthStatus.HEALTHY:       return "ready";
            case HealthStatus.UNHEALTHY:     return "not_ready";
            case HealthStatus.DEGRADED:      return "degraded";
            case HealthStatus.STARTING:      return "starting";
            case HealthStatus.SHUTTING_DOWN: return "shutting_down";
        }
    }
    
    private static string escapeJson(string s) @trusted
    {
        import std.array : replace;
        return s.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t");
    }
    
    // ========================================================================
    // CACHING
    // ========================================================================
    
    private bool isCacheValid() @trusted
    {
        if (lastCheckTimeUs == 0)
            return false;
            
        import std.datetime : Clock;
        auto nowUs = Clock.currStdTime / 10;  // hnsecs to usecs
        auto elapsedMs = (nowUs - lastCheckTimeUs) / 1000;
        
        return elapsedMs < config.cacheDurationMs;
    }
    
    private void updateCache(bool result, HealthCheckResult[] checks) @trusted
    {
        import std.datetime : Clock;
        
        cachedReadinessResult = result;
        cachedCheckResults = checks.dup;
        lastCheckTimeUs = Clock.currStdTime / 10;
    }
}

/**
 * Helper function to create health middleware delegate
 *
 * Params:
 *   server = Server instance for state checks
 *   config = Health configuration (optional)
 *
 * Returns: Middleware delegate and HealthMiddleware instance
 *
 * Example:
 * ---
 * auto health = new HealthMiddleware(app.server);
 * app.use(health.middleware);
 * 
 * // Later, after initialization
 * health.markStartupComplete();
 * ---
 */
HealthMiddleware createHealthMiddleware(Server server, HealthConfig config = HealthConfig.defaults())
{
    return new HealthMiddleware(server, config);
}

/**
 * Convenience function for simple usage without startup tracking
 */
Middleware healthMiddleware(Server server, HealthConfig config = HealthConfig.defaults())
{
    auto mw = new HealthMiddleware(server, config);
    mw.markStartupComplete();  // Assume already started for simple cases
    return mw.middleware;
}
