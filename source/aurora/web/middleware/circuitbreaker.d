/**
 * Circuit Breaker Middleware — Failure Isolation & Cascading Prevention
 *
 * Package: aurora.web.middleware.circuitbreaker
 *
 * Implements the Circuit Breaker pattern to prevent cascading failures
 * when downstream services or handlers are failing. The circuit has three states:
 *
 * - CLOSED: Normal operation, requests pass through
 * - OPEN: Failure threshold exceeded, requests fast-fail with 503
 * - HALF_OPEN: Testing recovery, limited requests allowed through
 *
 * State Transitions:
 * ---
 *   CLOSED --[failures >= threshold]--> OPEN
 *   OPEN --[timeout elapsed]--> HALF_OPEN
 *   HALF_OPEN --[success]--> CLOSED
 *   HALF_OPEN --[failure]--> OPEN
 * ---
 *
 * Features:
 * - Configurable failure/success thresholds
 * - Configurable reset timeout
 * - Bypass paths for critical endpoints (health, metrics)
 * - Failure detection by HTTP status codes (configurable)
 * - Statistics tracking for monitoring
 * - Thread-safe state transitions
 *
 * Example:
 * ---
 * auto cbConfig = CircuitBreakerConfig();
 * cbConfig.failureThreshold = 5;       // Open after 5 failures
 * cbConfig.successThreshold = 3;       // Close after 3 successes in half-open
 * cbConfig.resetTimeout = 30.seconds;  // Try half-open after 30s
 * cbConfig.bypassPaths = ["/health/*", "/metrics"];
 * 
 * app.use(circuitBreakerMiddleware(cbConfig));
 * ---
 *
 * Kubernetes Integration:
 * ---yaml
 * # The circuit breaker returns 503 when open, which signals
 * # load balancers to route traffic elsewhere
 * ---
 */
module aurora.web.middleware.circuitbreaker;

import aurora.web.context;
import core.time : Duration, seconds, MonoTime;
import core.atomic : atomicLoad, atomicStore, cas, MemoryOrder;
import core.sync.mutex : Mutex;

// Import middleware types without causing circular dependency
alias NextFunction = void delegate();
alias Middleware = void delegate(ref Context ctx, NextFunction next);

// ============================================================================
// CONFIGURATION & TYPES
// ============================================================================

/**
 * Circuit State Enumeration
 *
 * The circuit breaker operates as a finite state machine with these states:
 */
enum CircuitState
{
    /// Normal operation - requests pass through to handlers
    CLOSED,
    
    /// Circuit tripped - requests are rejected immediately with 503
    OPEN,
    
    /// Testing recovery - limited requests pass through to test if service recovered
    HALF_OPEN
}

/**
 * Circuit Breaker Configuration
 *
 * Controls thresholds, timeouts, and behavior of the circuit breaker.
 */
struct CircuitBreakerConfig
{
    // === Failure Detection ===
    
    /// Number of consecutive failures before opening the circuit
    uint failureThreshold = 5;
    
    /// HTTP status codes considered as failures (default: 5xx errors)
    /// Empty array means only exceptions count as failures
    int[] failureStatusCodes = [500, 502, 503, 504];
    
    // === Recovery ===
    
    /// Duration to wait before transitioning from OPEN to HALF_OPEN
    Duration resetTimeout = 30.seconds;
    
    /// Number of consecutive successes in HALF_OPEN before closing circuit
    uint successThreshold = 3;
    
    /// Number of requests to allow through in HALF_OPEN state (per reset period)
    uint halfOpenMaxRequests = 3;
    
    // === Bypass Configuration ===
    
    /// Paths that bypass circuit breaker (supports trailing * glob)
    /// Example: ["/health/*", "/metrics"]
    string[] bypassPaths = ["/health/*"];
    
    // === Response Configuration ===
    
    /// Retry-After header value in seconds when circuit is open
    uint retryAfterSeconds = 30;
    
    /// Custom error message when circuit is open
    string openCircuitMessage = "Service temporarily unavailable";
    
    /// Create default configuration
    static CircuitBreakerConfig defaults() @safe nothrow
    {
        return CircuitBreakerConfig.init;
    }
}

/**
 * Circuit Breaker Statistics
 *
 * Provides metrics for monitoring and alerting.
 */
struct CircuitBreakerStats
{
    /// Total requests processed (all states)
    ulong totalRequests;
    
    /// Total successful requests
    ulong successfulRequests;
    
    /// Total failed requests (status code or exception)
    ulong failedRequests;
    
    /// Total requests rejected due to open circuit
    ulong rejectedRequests;
    
    /// Total requests bypassed (priority paths)
    ulong bypassedRequests;
    
    /// Number of times circuit transitioned to OPEN
    ulong timesOpened;
    
    /// Number of times circuit transitioned to CLOSED (recovered)
    ulong timesClosed;
    
    /// Current circuit state
    CircuitState currentState;
    
    /// Consecutive failure count
    uint consecutiveFailures;
    
    /// Consecutive success count (in HALF_OPEN)
    uint consecutiveSuccesses;
    
    /// Time when circuit opened (MonoTime.zero if never opened)
    MonoTime lastOpenedAt;
    
    /// Time when circuit last closed (recovered)
    MonoTime lastClosedAt;
}

// ============================================================================
// CIRCUIT BREAKER MIDDLEWARE
// ============================================================================

/**
 * Circuit Breaker Middleware
 *
 * Implements the circuit breaker pattern to prevent cascading failures.
 * Thread-safe for concurrent request handling.
 */
class CircuitBreakerMiddleware
{
    private
    {
        CircuitBreakerConfig config;
        
        // State machine (needs thread-safe access)
        shared CircuitState state = CircuitState.CLOSED;
        shared MonoTime openedAt;
        
        // Counters (protected by mutex for compound operations)
        Mutex stateMutex;
        uint consecutiveFailures = 0;
        uint consecutiveSuccesses = 0;
        uint halfOpenRequestCount = 0;
        
        // Statistics
        shared ulong totalRequests = 0;
        shared ulong successfulRequests = 0;
        shared ulong failedRequests = 0;
        shared ulong rejectedRequests = 0;
        shared ulong bypassedRequests = 0;
        shared ulong timesOpened = 0;
        shared ulong timesClosed = 0;
        shared MonoTime lastOpenedAt;
        shared MonoTime lastClosedAt;
    }
    
    /**
     * Constructor
     *
     * Params:
     *   config = Circuit breaker configuration
     */
    this(CircuitBreakerConfig config = CircuitBreakerConfig.defaults())
    {
        this.config = config;
        this.stateMutex = new Mutex();
    }
    
    /**
     * Handle request (middleware interface)
     *
     * Flow:
     * 1. Check bypass paths
     * 2. Check circuit state
     * 3. If OPEN, reject request
     * 4. If CLOSED/HALF_OPEN, execute and evaluate result
     */
    void handle(ref Context ctx, NextFunction next)
    {
        import core.atomic : atomicOp;
        
        if (ctx.request is null)
        {
            next();
            return;
        }
        
        string path = ctx.request.path;
        
        // Check bypass paths first
        if (matchesBypassPath(path))
        {
            atomicOp!"+="(bypassedRequests, 1);
            next();
            return;
        }
        
        atomicOp!"+="(totalRequests, 1);
        
        // Check circuit state
        auto currentState = getEffectiveState();
        
        if (currentState == CircuitState.OPEN)
        {
            // Circuit is open - fast fail
            atomicOp!"+="(rejectedRequests, 1);
            sendOpenCircuitResponse(ctx);
            return;
        }
        
        // Circuit is CLOSED or HALF_OPEN - allow request
        bool isHalfOpen = (currentState == CircuitState.HALF_OPEN);
        
        if (isHalfOpen)
        {
            // Limit requests in half-open state
            if (!tryAcquireHalfOpenSlot())
            {
                atomicOp!"+="(rejectedRequests, 1);
                sendOpenCircuitResponse(ctx);
                return;
            }
        }
        
        // Execute the downstream handler
        bool success = false;
        bool exceptionOccurred = false;
        
        try
        {
            next();
            
            // Check response status code
            success = !isFailureStatusCode(ctx.response.getStatus());
        }
        catch (Exception e)
        {
            exceptionOccurred = true;
            success = false;
            // Re-throw after recording failure
            recordResult(success, isHalfOpen);
            throw e;
        }
        
        // Record the result
        recordResult(success, isHalfOpen);
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
    CircuitBreakerStats getStats() @safe nothrow
    {
        CircuitBreakerStats stats;
        
        stats.totalRequests = atomicLoad(totalRequests);
        stats.successfulRequests = atomicLoad(successfulRequests);
        stats.failedRequests = atomicLoad(failedRequests);
        stats.rejectedRequests = atomicLoad(rejectedRequests);
        stats.bypassedRequests = atomicLoad(bypassedRequests);
        stats.timesOpened = atomicLoad(timesOpened);
        stats.timesClosed = atomicLoad(timesClosed);
        stats.currentState = getEffectiveState();
        stats.lastOpenedAt = atomicLoad(lastOpenedAt);
        stats.lastClosedAt = atomicLoad(lastClosedAt);
        
        // Get counters under lock
        stateMutex.lock_nothrow();
        scope(exit) stateMutex.unlock_nothrow();
        
        stats.consecutiveFailures = consecutiveFailures;
        stats.consecutiveSuccesses = consecutiveSuccesses;
        
        return stats;
    }
    
    /**
     * Get current circuit state
     *
     * Note: This returns the raw state. Use getEffectiveState() to account
     * for automatic OPEN → HALF_OPEN transitions.
     */
    CircuitState getCurrentState() const @safe nothrow
    {
        return atomicLoad(state);
    }
    
    /**
     * Check if circuit is open (requests will be rejected)
     */
    bool isOpen() @safe nothrow
    {
        return getEffectiveState() == CircuitState.OPEN;
    }
    
    /**
     * Check if circuit is closed (normal operation)
     */
    bool isClosed() @safe nothrow
    {
        return getEffectiveState() == CircuitState.CLOSED;
    }
    
    /**
     * Manually reset the circuit to CLOSED state.
     * Use with caution - bypasses normal recovery logic.
     */
    void reset() @safe nothrow
    {
        stateMutex.lock_nothrow();
        scope(exit) stateMutex.unlock_nothrow();
        
        atomicStore(state, CircuitState.CLOSED);
        consecutiveFailures = 0;
        consecutiveSuccesses = 0;
        halfOpenRequestCount = 0;
    }
    
    /**
     * Reset statistics (for testing)
     */
    void resetStats() @safe nothrow
    {
        atomicStore(totalRequests, cast(ulong)0);
        atomicStore(successfulRequests, cast(ulong)0);
        atomicStore(failedRequests, cast(ulong)0);
        atomicStore(rejectedRequests, cast(ulong)0);
        atomicStore(bypassedRequests, cast(ulong)0);
        atomicStore(timesOpened, cast(ulong)0);
        atomicStore(timesClosed, cast(ulong)0);
    }
    
    // ========================================================================
    // PRIVATE METHODS
    // ========================================================================
    
    /**
     * Get effective state, checking for automatic transitions.
     *
     * OPEN → HALF_OPEN transition happens automatically when resetTimeout elapses.
     */
    private CircuitState getEffectiveState() @safe nothrow
    {
        auto currentState = atomicLoad(state);
        
        if (currentState == CircuitState.OPEN)
        {
            // Check if reset timeout has elapsed
            auto opened = atomicLoad(openedAt);
            auto elapsed = MonoTime.currTime - opened;
            
            if (elapsed >= config.resetTimeout)
            {
                // Transition to HALF_OPEN (try to recover)
                tryTransitionToHalfOpen();
                return atomicLoad(state);
            }
        }
        
        return currentState;
    }
    
    /**
     * Try to transition from OPEN to HALF_OPEN.
     * Uses CAS to ensure only one thread performs the transition.
     */
    private void tryTransitionToHalfOpen() @trusted nothrow
    {
        stateMutex.lock_nothrow();
        scope(exit) stateMutex.unlock_nothrow();
        
        // Double-check state under lock
        if (atomicLoad(state) == CircuitState.OPEN)
        {
            auto opened = atomicLoad(openedAt);
            auto elapsed = MonoTime.currTime - opened;
            
            if (elapsed >= config.resetTimeout)
            {
                atomicStore(state, CircuitState.HALF_OPEN);
                consecutiveSuccesses = 0;
                halfOpenRequestCount = 0;
            }
        }
    }
    
    /**
     * Try to acquire a request slot in HALF_OPEN state.
     * Returns false if max requests already in flight.
     */
    private bool tryAcquireHalfOpenSlot() @trusted nothrow
    {
        stateMutex.lock_nothrow();
        scope(exit) stateMutex.unlock_nothrow();
        
        if (halfOpenRequestCount < config.halfOpenMaxRequests)
        {
            halfOpenRequestCount++;
            return true;
        }
        return false;
    }
    
    /**
     * Record the result of a request and update state machine.
     */
    private void recordResult(bool success, bool wasHalfOpen) @trusted nothrow
    {
        import core.atomic : atomicOp;
        
        stateMutex.lock_nothrow();
        scope(exit) stateMutex.unlock_nothrow();
        
        if (success)
        {
            atomicOp!"+="(successfulRequests, 1);
            consecutiveFailures = 0;
            
            if (wasHalfOpen || atomicLoad(state) == CircuitState.HALF_OPEN)
            {
                consecutiveSuccesses++;
                
                // Check if we should close the circuit
                if (consecutiveSuccesses >= config.successThreshold)
                {
                    transitionToClosed();
                }
            }
        }
        else
        {
            atomicOp!"+="(failedRequests, 1);
            consecutiveSuccesses = 0;
            consecutiveFailures++;
            
            auto currentState = atomicLoad(state);
            
            if (currentState == CircuitState.HALF_OPEN)
            {
                // Any failure in HALF_OPEN reopens the circuit
                transitionToOpen();
            }
            else if (currentState == CircuitState.CLOSED)
            {
                // Check if we should open the circuit
                if (consecutiveFailures >= config.failureThreshold)
                {
                    transitionToOpen();
                }
            }
        }
    }
    
    /**
     * Transition to OPEN state.
     * Called when failure threshold is exceeded.
     */
    private void transitionToOpen() @trusted nothrow
    {
        import core.atomic : atomicOp;
        
        atomicStore(state, CircuitState.OPEN);
        atomicStore(openedAt, MonoTime.currTime);
        atomicStore(lastOpenedAt, MonoTime.currTime);
        atomicOp!"+="(timesOpened, 1);
        consecutiveSuccesses = 0;
        halfOpenRequestCount = 0;
    }
    
    /**
     * Transition to CLOSED state.
     * Called when service has recovered (success threshold met in HALF_OPEN).
     */
    private void transitionToClosed() @trusted nothrow
    {
        import core.atomic : atomicOp;
        
        atomicStore(state, CircuitState.CLOSED);
        atomicStore(lastClosedAt, MonoTime.currTime);
        atomicOp!"+="(timesClosed, 1);
        consecutiveFailures = 0;
        consecutiveSuccesses = 0;
        halfOpenRequestCount = 0;
    }
    
    /**
     * Check if status code is considered a failure.
     */
    private bool isFailureStatusCode(int statusCode) const @safe nothrow
    {
        if (config.failureStatusCodes.length == 0)
            return false;
        
        foreach (failureCode; config.failureStatusCodes)
        {
            if (statusCode == failureCode)
                return true;
        }
        return false;
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
     * Send 503 Service Unavailable response when circuit is open.
     */
    private void sendOpenCircuitResponse(ref Context ctx) @trusted
    {
        import std.conv : to;
        
        // Calculate retry-after based on remaining time until HALF_OPEN
        uint retryAfter = config.retryAfterSeconds;
        
        auto opened = atomicLoad(openedAt);
        if (opened != MonoTime.init)
        {
            auto elapsed = MonoTime.currTime - opened;
            auto remaining = config.resetTimeout - elapsed;
            if (remaining.total!"seconds" > 0)
            {
                retryAfter = cast(uint)remaining.total!"seconds";
            }
        }
        
        ctx.status(503)
           .header("Content-Type", "application/json")
           .header("Retry-After", retryAfter.to!string)
           .header("X-Circuit-State", "open")
           .header("Cache-Control", "no-cache, no-store")
           .send(`{"error":"` ~ config.openCircuitMessage ~ `","reason":"circuit_open"}`);
    }
}

// ============================================================================
// FACTORY FUNCTIONS
// ============================================================================

/**
 * Factory function to create circuit breaker middleware.
 *
 * Example:
 * ---
 * app.use(circuitBreakerMiddleware());
 * 
 * // With custom config
 * auto config = CircuitBreakerConfig();
 * config.failureThreshold = 10;
 * app.use(circuitBreakerMiddleware(config));
 * ---
 */
Middleware circuitBreakerMiddleware(CircuitBreakerConfig config = CircuitBreakerConfig.defaults())
{
    auto mw = new CircuitBreakerMiddleware(config);
    return mw.middleware;
}

/**
 * Factory function returning the middleware instance (for stats access).
 *
 * Example:
 * ---
 * auto cb = createCircuitBreakerMiddleware();
 * app.use(cb.middleware);
 * 
 * // Later - check stats
 * auto stats = cb.getStats();
 * if (stats.currentState == CircuitState.OPEN) {
 *     log("Circuit is open! ", stats.consecutiveFailures, " failures");
 * }
 * 
 * // Manual reset if needed
 * cb.reset();
 * ---
 */
CircuitBreakerMiddleware createCircuitBreakerMiddleware(CircuitBreakerConfig config = CircuitBreakerConfig.defaults())
{
    return new CircuitBreakerMiddleware(config);
}
