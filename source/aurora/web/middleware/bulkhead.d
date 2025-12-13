/**
 * Bulkhead Middleware — Resource Isolation Pattern
 *
 * Package: aurora.web.middleware.bulkhead
 *
 * Implements the Bulkhead pattern (from "Release It!" by Michael Nygard) to
 * isolate failures between endpoint groups. Like ship bulkheads that prevent
 * sinking, this middleware partitions concurrency pools so overload in one
 * area doesn't cascade to others.
 *
 * Features:
 * - Configurable max concurrent requests per bulkhead
 * - Optional queue with timeout for waiting requests
 * - Statistics tracking for monitoring
 * - Thread-safe with minimal lock contention
 * - Graceful rejection with 503 + Retry-After
 *
 * Example:
 * ---
 * // Create isolated bulkheads for different endpoint groups
 * auto apiBulkhead = createBulkheadMiddleware(BulkheadConfig(
 *     100,  // maxConcurrent
 *     50,   // maxQueue
 *     5.seconds,  // timeout
 *     "api"
 * ));
 *
 * auto adminBulkhead = createBulkheadMiddleware(BulkheadConfig(
 *     10,   // maxConcurrent (admin is low-volume)
 *     5,    // maxQueue
 *     2.seconds,
 *     "admin"
 * ));
 *
 * // Apply to route groups
 * app.group("/api", r => r.use(apiBulkhead.middleware));
 * app.group("/admin", r => r.use(adminBulkhead.middleware));
 *
 * // Monitor stats
 * auto stats = apiBulkhead.getStats();
 * if (stats.state == BulkheadState.OVERLOADED) {
 *     log.warn("API bulkhead overloaded!");
 * }
 * ---
 *
 * Kubernetes Integration:
 * ---yaml
 * # The bulkhead returns 503 when full, which signals
 * # load balancers to reduce traffic to this pod
 * ---
 */
module aurora.web.middleware.bulkhead;

import aurora.web.context;
import core.time : Duration, MonoTime, seconds, msecs;
import core.atomic : atomicLoad, atomicStore, atomicOp, MemoryOrder;
import core.sync.mutex : Mutex;
import core.sync.condition : Condition;

// Import middleware types
alias NextFunction = void delegate();
alias Middleware = void delegate(ref Context ctx, NextFunction next);

// ============================================================================
// CONFIGURATION & TYPES
// ============================================================================

/**
 * Bulkhead State
 *
 * Represents the current health state of the bulkhead.
 */
enum BulkheadState : ubyte
{
    /// Normal operation - capacity available
    NORMAL = 0,
    
    /// Queue is filling up - approaching limits
    FILLING = 1,
    
    /// At or near capacity - requests may be rejected
    OVERLOADED = 2
}

/**
 * Bulkhead Configuration
 *
 * Configures the resource isolation behavior.
 */
struct BulkheadConfig
{
    /// Maximum concurrent requests allowed (semaphore size)
    /// Default: 100. Set based on downstream capacity.
    uint maxConcurrent = 100;
    
    /// Maximum requests that can wait in queue
    /// Default: 50. Set to 0 to disable queueing (fail-fast).
    uint maxQueue = 50;
    
    /// Maximum time a request can wait in queue
    /// Default: 5 seconds. Should be less than client timeout.
    Duration timeout = 5.seconds;
    
    /// Identifier for this bulkhead (used in logs and metrics)
    string name = "default";
    
    /// Retry-After header value when bulkhead is full
    uint retryAfterSeconds = 5;
    
    /// Custom error message when bulkhead rejects request
    string fullMessage = "Service temporarily at capacity";
    
    /// Constructor for quick configuration
    this(uint maxConcurrent, uint maxQueue = 50, 
         Duration timeout = 5.seconds, string name = "default") @safe nothrow
    {
        this.maxConcurrent = maxConcurrent;
        this.maxQueue = maxQueue;
        this.timeout = timeout;
        this.name = name;
    }
    
    /// Create default configuration
    static BulkheadConfig defaults() @safe nothrow
    {
        return BulkheadConfig.init;
    }
}

/**
 * Bulkhead Statistics
 *
 * Provides metrics for monitoring and alerting.
 */
struct BulkheadStats
{
    /// Bulkhead name
    string name;
    
    /// Currently executing requests
    uint activeCalls;
    
    /// Currently waiting in queue
    uint queuedCalls;
    
    /// Maximum concurrent capacity
    uint maxConcurrent;
    
    /// Maximum queue capacity
    uint maxQueue;
    
    /// Current state
    BulkheadState state;
    
    /// Total successful calls (acquired slot and completed)
    ulong completedCalls;
    
    /// Total rejected calls (bulkhead full)
    ulong rejectedCalls;
    
    /// Total calls that timed out waiting in queue
    ulong timedOutCalls;
    
    /// Total calls that acquired a slot (completed + in-progress)
    ulong acquiredCalls;
    
    /// Utilization ratio (0.0 to 1.0)
    @property double utilization() const @safe pure nothrow
    {
        if (maxConcurrent == 0) return 0.0;
        return cast(double)activeCalls / cast(double)maxConcurrent;
    }
    
    /// Queue utilization ratio (0.0 to 1.0)
    @property double queueUtilization() const @safe pure nothrow
    {
        if (maxQueue == 0) return 0.0;
        return cast(double)queuedCalls / cast(double)maxQueue;
    }
    
    /// Check if bulkhead has capacity
    @property bool hasCapacity() const @safe pure nothrow
    {
        return activeCalls < maxConcurrent || queuedCalls < maxQueue;
    }
}

// ============================================================================
// BULKHEAD MIDDLEWARE
// ============================================================================

/**
 * Bulkhead Middleware
 *
 * Implements resource isolation with configurable concurrency and queue limits.
 * Thread-safe for concurrent request handling.
 */
class BulkheadMiddleware
{
    private
    {
        BulkheadConfig config;
        
        // Concurrency control
        shared uint activeCount = 0;
        shared uint queuedCount = 0;
        
        // Queue synchronization
        Mutex mutex;
        Condition condition;
        
        // Statistics (use atomic operations)
        shared ulong completedCalls = 0;
        shared ulong rejectedCalls = 0;
        shared ulong timedOutCalls = 0;
        shared ulong acquiredCalls = 0;
    }
    
    /**
     * Constructor
     *
     * Params:
     *   config = Bulkhead configuration
     */
    this(BulkheadConfig config = BulkheadConfig.defaults()) @trusted
    {
        this.config = config;
        this.mutex = new Mutex();
        this.condition = new Condition(this.mutex);
    }
    
    /**
     * Handle request (middleware interface)
     *
     * Attempts to acquire a slot in the bulkhead:
     * 1. If concurrent capacity available: execute immediately
     * 2. If queue capacity available: wait with timeout
     * 3. If both full: reject with 503
     */
    void handle(ref Context ctx, NextFunction next) @trusted
    {
        // Try to acquire a slot
        auto result = acquire();
        
        if (result == AcquireResult.REJECTED)
        {
            // Bulkhead is full - reject request
            sendFullResponse(ctx, "full");
            return;
        }
        
        if (result == AcquireResult.TIMEOUT)
        {
            // Timed out waiting in queue
            sendFullResponse(ctx, "timeout");
            return;
        }
        
        // Slot acquired - execute downstream
        scope(exit) release();
        
        next();
        
        // Count successful completion
        atomicOp!"+="(completedCalls, 1);
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
    BulkheadStats getStats() @safe nothrow
    {
        BulkheadStats stats;
        stats.name = config.name;
        stats.activeCalls = atomicLoad(activeCount);
        stats.queuedCalls = atomicLoad(queuedCount);
        stats.maxConcurrent = config.maxConcurrent;
        stats.maxQueue = config.maxQueue;
        stats.completedCalls = atomicLoad(completedCalls);
        stats.rejectedCalls = atomicLoad(rejectedCalls);
        stats.timedOutCalls = atomicLoad(timedOutCalls);
        stats.acquiredCalls = atomicLoad(acquiredCalls);
        stats.state = calculateState(stats.activeCalls, stats.queuedCalls);
        return stats;
    }
    
    /**
     * Get current state
     */
    BulkheadState getState() @safe nothrow
    {
        auto active = atomicLoad(activeCount);
        auto queued = atomicLoad(queuedCount);
        return calculateState(active, queued);
    }
    
    /**
     * Check if bulkhead is overloaded
     */
    bool isOverloaded() @safe nothrow
    {
        return getState() == BulkheadState.OVERLOADED;
    }
    
    /**
     * Check if bulkhead has available capacity
     */
    bool hasCapacity() @safe nothrow
    {
        auto active = atomicLoad(activeCount);
        auto queued = atomicLoad(queuedCount);
        return active < config.maxConcurrent || queued < config.maxQueue;
    }
    
    /**
     * Get bulkhead name
     */
    @property string name() const @safe nothrow
    {
        return config.name;
    }
    
    /**
     * Reset statistics (for testing)
     */
    void resetStats() @safe nothrow
    {
        atomicStore(completedCalls, cast(ulong)0);
        atomicStore(rejectedCalls, cast(ulong)0);
        atomicStore(timedOutCalls, cast(ulong)0);
        atomicStore(acquiredCalls, cast(ulong)0);
    }
    
    // ========================================================================
    // PRIVATE METHODS
    // ========================================================================
    
    private enum AcquireResult
    {
        ACQUIRED,
        REJECTED,
        TIMEOUT
    }
    
    /**
     * Attempt to acquire a slot in the bulkhead.
     */
    private AcquireResult acquire() @trusted nothrow
    {
        // Fast path: try to acquire without waiting
        if (tryAcquireImmediate())
        {
            atomicOp!"+="(acquiredCalls, 1);
            return AcquireResult.ACQUIRED;
        }
        
        // Check if queueing is enabled
        if (config.maxQueue == 0)
        {
            atomicOp!"+="(rejectedCalls, 1);
            return AcquireResult.REJECTED;
        }
        
        // Check if queue has capacity
        auto queued = atomicLoad(queuedCount);
        if (queued >= config.maxQueue)
        {
            atomicOp!"+="(rejectedCalls, 1);
            return AcquireResult.REJECTED;
        }
        
        // Wait in queue with timeout
        return waitInQueue();
    }
    
    /**
     * Try to acquire a slot immediately (no waiting).
     */
    private bool tryAcquireImmediate() @trusted nothrow
    {
        // Atomic compare-and-swap loop
        while (true)
        {
            auto current = atomicLoad(activeCount);
            if (current >= config.maxConcurrent)
                return false;
            
            // Try to increment
            if (cas(&activeCount, current, current + 1))
                return true;
        }
    }
    
    /**
     * Wait in queue with timeout.
     */
    private AcquireResult waitInQueue() @trusted nothrow
    {
        // Increment queued count
        atomicOp!"+="(queuedCount, 1);
        scope(exit) atomicOp!"-="(queuedCount, 1);
        
        auto deadline = MonoTime.currTime + config.timeout;
        
        try
        {
            mutex.lock_nothrow();
            scope(exit) mutex.unlock_nothrow();
            
            while (true)
            {
                // Check if slot available
                if (tryAcquireImmediate())
                {
                    atomicOp!"+="(acquiredCalls, 1);
                    return AcquireResult.ACQUIRED;
                }
                
                // Check timeout
                auto now = MonoTime.currTime;
                if (now >= deadline)
                {
                    atomicOp!"+="(timedOutCalls, 1);
                    return AcquireResult.TIMEOUT;
                }
                
                // Wait for signal with remaining timeout
                auto remaining = deadline - now;
                bool notified = condition.wait(remaining);
                
                if (!notified)
                {
                    // Timeout occurred during wait
                    // Check one more time
                    if (tryAcquireImmediate())
                    {
                        atomicOp!"+="(acquiredCalls, 1);
                        return AcquireResult.ACQUIRED;
                    }
                    atomicOp!"+="(timedOutCalls, 1);
                    return AcquireResult.TIMEOUT;
                }
            }
        }
        catch (Exception)
        {
            atomicOp!"+="(rejectedCalls, 1);
            return AcquireResult.REJECTED;
        }
    }
    
    /**
     * Release a slot back to the bulkhead.
     */
    private void release() @trusted nothrow
    {
        atomicOp!"-="(activeCount, 1);
        
        // Signal waiting threads if any
        auto queued = atomicLoad(queuedCount);
        if (queued > 0)
        {
            try
            {
                mutex.lock_nothrow();
                condition.notify();
                mutex.unlock_nothrow();
            }
            catch (Exception) {}
        }
    }
    
    /**
     * Calculate bulkhead state based on current load.
     */
    private BulkheadState calculateState(uint active, uint queued) const @safe nothrow
    {
        // Overloaded: concurrent at max AND queue at or above 50%
        if (active >= config.maxConcurrent)
        {
            if (config.maxQueue == 0 || queued >= config.maxQueue / 2)
                return BulkheadState.OVERLOADED;
            return BulkheadState.FILLING;
        }
        
        // Filling: above 75% concurrent capacity
        if (active >= (config.maxConcurrent * 3) / 4)
            return BulkheadState.FILLING;
        
        return BulkheadState.NORMAL;
    }
    
    /**
     * Send 503 response when bulkhead is full.
     */
    private void sendFullResponse(ref Context ctx, string reason) @trusted
    {
        import std.conv : to;
        
        atomicOp!"+="(rejectedCalls, 1);
        
        ctx.status(503)
           .header("Content-Type", "application/json")
           .header("Retry-After", config.retryAfterSeconds.to!string)
           .header("X-Bulkhead-Name", config.name)
           .header("X-Bulkhead-Reason", reason)
           .header("Cache-Control", "no-cache, no-store")
           .send(`{"error":"` ~ config.fullMessage ~ 
                 `","bulkhead":"` ~ config.name ~
                 `","reason":"` ~ reason ~ `"}`);
    }
    
    /**
     * CAS helper for @trusted context
     */
    private static bool cas(shared(uint)* here, uint ifThis, uint writeThis) @trusted nothrow
    {
        import core.atomic : cas;
        return cas(here, ifThis, writeThis);
    }
}

// ============================================================================
// FACTORY FUNCTIONS
// ============================================================================

/**
 * Factory function to create bulkhead middleware.
 *
 * Example:
 * ---
 * app.use(bulkheadMiddleware(100, 50, 5.seconds, "api"));
 * ---
 */
Middleware bulkheadMiddleware(uint maxConcurrent, uint maxQueue = 50,
                               Duration timeout = 5.seconds, string name = "default")
{
    auto mw = new BulkheadMiddleware(BulkheadConfig(maxConcurrent, maxQueue, timeout, name));
    return mw.middleware;
}

/**
 * Factory function with config struct.
 */
Middleware bulkheadMiddleware(BulkheadConfig config)
{
    auto mw = new BulkheadMiddleware(config);
    return mw.middleware;
}

/**
 * Factory function returning the middleware instance (for stats access).
 *
 * Example:
 * ---
 * auto bh = createBulkheadMiddleware(BulkheadConfig(100, 50, 5.seconds, "api"));
 * app.use(bh.middleware);
 *
 * // Later - check stats
 * auto stats = bh.getStats();
 * if (stats.state == BulkheadState.OVERLOADED) {
 *     log.warn("Bulkhead ", stats.name, " overloaded!");
 * }
 * ---
 */
BulkheadMiddleware createBulkheadMiddleware(BulkheadConfig config = BulkheadConfig.defaults())
{
    return new BulkheadMiddleware(config);
}

/**
 * Convenience factory with positional args.
 */
BulkheadMiddleware createBulkheadMiddleware(uint maxConcurrent, uint maxQueue = 50,
                                             Duration timeout = 5.seconds, string name = "default")
{
    return new BulkheadMiddleware(BulkheadConfig(maxConcurrent, maxQueue, timeout, name));
}

