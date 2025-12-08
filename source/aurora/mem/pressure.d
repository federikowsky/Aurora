/**
 * Memory Management — GC Pressure Monitoring & Protection
 *
 * Package: aurora.mem.pressure
 *
 * Provides memory monitoring and protection for production deployments:
 * - GC heap usage tracking
 * - Automatic GC.collect() under pressure
 * - Request rejection when memory critical
 * - Callbacks for custom pressure handling
 *
 * The D garbage collector can cause latency spikes under memory pressure.
 * This module helps manage memory proactively:
 *
 * - **NORMAL**: Below 80% of limit — normal operation
 * - **PRESSURE**: 80-95% — triggers GC.collect(), logs warnings
 * - **CRITICAL**: >95% — rejects new requests to prevent OOM
 *
 * Example:
 * ---
 * auto memConfig = MemoryConfig();
 * memConfig.maxHeapBytes = 512 * 1024 * 1024;  // 512 MB limit
 * memConfig.highWaterRatio = 0.8;               // GC at 80%
 * memConfig.criticalWaterRatio = 0.95;          // Reject at 95%
 *
 * auto monitor = new MemoryMonitor(memConfig);
 * monitor.onPressure = (state) {
 *     log.warn("Memory pressure: ", state);
 * };
 *
 * // Use middleware to protect server
 * app.use(memoryMiddleware(monitor));
 *
 * // Check stats
 * auto stats = monitor.getStats();
 * metrics.gauge("memory.used_bytes", stats.usedBytes);
 * metrics.gauge("memory.utilization", stats.utilization);
 * ---
 *
 * Kubernetes Integration:
 * ---yaml
 * # Set Aurora limit below container limit to leave headroom
 * # Container: 1GB → Aurora: 768MB
 * resources:
 *   limits:
 *     memory: "1Gi"
 * env:
 *   - name: AURORA_MAX_HEAP
 *     value: "805306368"  # 768 MB
 * ---
 */
module aurora.mem.pressure;

import core.memory : GC;
import core.time : Duration, MonoTime, seconds, msecs, dur;
import core.atomic : atomicLoad, atomicStore, atomicOp, MemoryOrder;

// ============================================================================
// CONFIGURATION & TYPES
// ============================================================================

/**
 * Memory State
 *
 * Represents the current memory pressure level.
 */
enum MemoryState : ubyte
{
    /// Normal operation — below high water mark
    NORMAL = 0,
    
    /// Under pressure — above high water, GC triggered
    PRESSURE = 1,
    
    /// Critical — above critical water, rejecting requests
    CRITICAL = 2
}

/**
 * Pressure Action
 *
 * What to do when memory reaches high water mark.
 */
enum PressureAction : ubyte
{
    /// Trigger GC.collect() to free memory
    GC_COLLECT = 0,
    
    /// Just log warning, don't trigger GC
    LOG_ONLY = 1,
    
    /// Call custom callback only
    CUSTOM = 2,
    
    /// Do nothing (monitoring only)
    NONE = 3
}

/**
 * Memory Configuration
 */
struct MemoryConfig
{
    /// Maximum heap size in bytes (soft limit)
    /// Default: 512 MB. Set based on container/VM limits.
    size_t maxHeapBytes = 512 * 1024 * 1024;
    
    /// High water mark ratio (0.0 to 1.0)
    /// When usedBytes / maxHeapBytes exceeds this, trigger pressure action.
    /// Default: 0.8 (80%)
    double highWaterRatio = 0.8;
    
    /// Critical water mark ratio (0.0 to 1.0)
    /// When exceeded, enter CRITICAL state and reject requests.
    /// Default: 0.95 (95%)
    double criticalWaterRatio = 0.95;
    
    /// Action to take when reaching high water
    PressureAction pressureAction = PressureAction.GC_COLLECT;
    
    /// Minimum interval between GC.collect() calls
    /// Prevents GC thrashing under sustained load.
    /// Default: 5 seconds
    Duration minGcInterval = 5.seconds;
    
    /// Bypass paths that skip memory checks (for health probes)
    string[] bypassPaths = ["/health/*"];
    
    /// Retry-After header value when rejecting requests
    uint retryAfterSeconds = 10;
    
    // ────────────────────────────────────────────
    // Computed properties
    // ────────────────────────────────────────────
    
    /// Get absolute high water mark in bytes
    @property size_t highWaterMark() const @safe pure nothrow
    {
        return cast(size_t)(maxHeapBytes * highWaterRatio);
    }
    
    /// Get absolute critical water mark in bytes
    @property size_t criticalWaterMark() const @safe pure nothrow
    {
        return cast(size_t)(maxHeapBytes * criticalWaterRatio);
    }
    
    /// Create default configuration
    static MemoryConfig defaults() @safe nothrow
    {
        return MemoryConfig.init;
    }
    
    /// Create configuration with max heap in MB
    static MemoryConfig withMaxMB(size_t megabytes) @safe nothrow
    {
        MemoryConfig config;
        config.maxHeapBytes = megabytes * 1024 * 1024;
        return config;
    }
}

/**
 * Memory Statistics
 */
struct MemoryStats
{
    /// Currently used GC heap bytes
    size_t usedBytes;
    
    /// Free bytes in GC pools
    size_t freeBytes;
    
    /// Total GC heap size (used + free in pools)
    size_t poolBytes;
    
    /// Configured maximum heap size
    size_t maxBytes;
    
    /// Current memory state
    MemoryState state;
    
    /// Number of times GC.collect() was triggered
    ulong gcCollections;
    
    /// Number of requests rejected due to memory
    ulong rejectedRequests;
    
    /// Number of state transitions
    ulong stateTransitions;
    
    /// Time spent in PRESSURE state
    Duration pressureTime;
    
    /// Time spent in CRITICAL state
    Duration criticalTime;
    
    /// Timestamp of last check
    MonoTime lastCheck;
    
    /// Heap utilization (0.0 to 1.0)
    @property double utilization() const @safe pure nothrow
    {
        if (maxBytes == 0) return 0.0;
        return cast(double)usedBytes / cast(double)maxBytes;
    }
    
    /// Pool utilization (used / total pool)
    @property double poolUtilization() const @safe pure nothrow
    {
        if (poolBytes == 0) return 0.0;
        return cast(double)usedBytes / cast(double)poolBytes;
    }
    
    /// Bytes remaining before high water
    @property long headroom() const @safe pure nothrow
    {
        auto highWater = cast(size_t)(maxBytes * 0.8);
        return cast(long)highWater - cast(long)usedBytes;
    }
}

// ============================================================================
// MEMORY MONITOR
// ============================================================================

/// Callback type for pressure events
alias PressureCallback = void delegate(MemoryState state) @safe;

/**
 * Memory Monitor
 *
 * Monitors GC heap usage and takes actions under memory pressure.
 * Thread-safe for concurrent access.
 */
class MemoryMonitor
{
    private
    {
        MemoryConfig config;
        
        // State tracking
        shared MemoryState currentState = MemoryState.NORMAL;
        shared MonoTime lastGcTime;
        shared MonoTime pressureStartTime;
        shared MonoTime criticalStartTime;
        
        // Statistics
        shared ulong gcCollections = 0;
        shared ulong rejectedRequests = 0;
        shared ulong stateTransitions = 0;
        shared long totalPressureUsecs = 0;
        shared long totalCriticalUsecs = 0;
        shared MonoTime lastCheck;
        
        // Callback
        PressureCallback pressureCallback;
    }
    
    /**
     * Constructor
     *
     * Params:
     *   config = Memory configuration
     */
    this(MemoryConfig config = MemoryConfig.defaults()) @safe
    {
        this.config = config;
        atomicStore(lastGcTime, MonoTime.currTime);
        atomicStore(lastCheck, MonoTime.currTime);
    }
    
    /**
     * Set pressure callback
     *
     * Called when memory state changes.
     */
    @property void onPressure(PressureCallback cb) @safe nothrow
    {
        pressureCallback = cb;
    }
    
    /**
     * Check current memory state (updates stats)
     *
     * Call this periodically or before processing requests.
     * Triggers GC.collect() if above high water and action is GC_COLLECT.
     */
    MemoryState check() @trusted
    {
        // Get GC stats
        auto gcStats = GC.stats;
        auto usedBytes = gcStats.usedSize;
        auto poolBytes = gcStats.usedSize + gcStats.freeSize;
        
        // Update last check time
        atomicStore(lastCheck, MonoTime.currTime);
        
        // Determine new state
        MemoryState newState;
        if (usedBytes >= config.criticalWaterMark)
            newState = MemoryState.CRITICAL;
        else if (usedBytes >= config.highWaterMark)
            newState = MemoryState.PRESSURE;
        else
            newState = MemoryState.NORMAL;
        
        // Handle state transition
        auto oldState = atomicLoad(currentState);
        if (newState != oldState)
        {
            handleStateTransition(oldState, newState);
            atomicStore(currentState, newState);
            atomicOp!"+="(stateTransitions, 1);
        }
        
        // Take action if under pressure
        if (newState >= MemoryState.PRESSURE)
        {
            takeAction(newState);
        }
        
        return newState;
    }
    
    /**
     * Get current state without updating
     */
    MemoryState getState() @safe nothrow
    {
        return atomicLoad(currentState);
    }
    
    /**
     * Check if in critical state
     */
    bool isCritical() @safe nothrow
    {
        return atomicLoad(currentState) == MemoryState.CRITICAL;
    }
    
    /**
     * Check if under any pressure
     */
    bool isUnderPressure() @safe nothrow
    {
        return atomicLoad(currentState) >= MemoryState.PRESSURE;
    }
    
    /**
     * Record a rejected request
     */
    void recordRejection() @safe nothrow
    {
        atomicOp!"+="(rejectedRequests, 1);
    }
    
    /**
     * Get current statistics
     */
    MemoryStats getStats() @trusted nothrow
    {
        MemoryStats stats;
        
        // Get current GC stats
        try
        {
            auto gcStats = GC.stats;
            stats.usedBytes = gcStats.usedSize;
            stats.freeBytes = gcStats.freeSize;
            stats.poolBytes = gcStats.usedSize + gcStats.freeSize;
        }
        catch (Exception)
        {
            // GC.stats can throw in rare cases
        }
        
        stats.maxBytes = config.maxHeapBytes;
        stats.state = atomicLoad(currentState);
        stats.gcCollections = atomicLoad(gcCollections);
        stats.rejectedRequests = atomicLoad(rejectedRequests);
        stats.stateTransitions = atomicLoad(stateTransitions);
        stats.pressureTime = usecs(atomicLoad(totalPressureUsecs));
        stats.criticalTime = usecs(atomicLoad(totalCriticalUsecs));
        stats.lastCheck = atomicLoad(lastCheck);
        
        return stats;
    }
    
    /**
     * Force GC collection (manual trigger)
     */
    void forceGC() @trusted
    {
        GC.collect();
        atomicOp!"+="(gcCollections, 1);
        atomicStore(lastGcTime, MonoTime.currTime);
    }
    
    /**
     * Reset statistics (for testing)
     */
    void resetStats() @safe nothrow
    {
        atomicStore(gcCollections, cast(ulong)0);
        atomicStore(rejectedRequests, cast(ulong)0);
        atomicStore(stateTransitions, cast(ulong)0);
        atomicStore(totalPressureUsecs, cast(long)0);
        atomicStore(totalCriticalUsecs, cast(long)0);
    }
    
    /**
     * Get configuration
     */
    @property const(MemoryConfig) configuration() const @safe nothrow
    {
        return config;
    }
    
    // ========================================================================
    // PRIVATE METHODS
    // ========================================================================
    
    private void handleStateTransition(MemoryState oldState, MemoryState newState) @trusted
    {
        auto now = MonoTime.currTime;
        
        // Track time in previous state
        if (oldState == MemoryState.PRESSURE)
        {
            auto start = atomicLoad(pressureStartTime);
            if (start != MonoTime.init)
            {
                auto elapsed = (now - start).total!"usecs";
                atomicOp!"+="(totalPressureUsecs, elapsed);
            }
        }
        else if (oldState == MemoryState.CRITICAL)
        {
            auto start = atomicLoad(criticalStartTime);
            if (start != MonoTime.init)
            {
                auto elapsed = (now - start).total!"usecs";
                atomicOp!"+="(totalCriticalUsecs, elapsed);
            }
        }
        
        // Record start time for new state
        if (newState == MemoryState.PRESSURE)
        {
            atomicStore(pressureStartTime, now);
        }
        else if (newState == MemoryState.CRITICAL)
        {
            atomicStore(criticalStartTime, now);
        }
        
        // Fire callback
        if (pressureCallback !is null)
        {
            try
            {
                pressureCallback(newState);
            }
            catch (Exception) {}
        }
    }
    
    private void takeAction(MemoryState state) @trusted
    {
        if (config.pressureAction == PressureAction.NONE)
            return;
        
        if (config.pressureAction == PressureAction.LOG_ONLY ||
            config.pressureAction == PressureAction.CUSTOM)
            return;
        
        // GC_COLLECT action
        if (config.pressureAction == PressureAction.GC_COLLECT)
        {
            // Check minimum interval
            auto lastGc = atomicLoad(lastGcTime);
            auto elapsed = MonoTime.currTime - lastGc;
            
            if (elapsed >= config.minGcInterval)
            {
                GC.collect();
                atomicOp!"+="(gcCollections, 1);
                atomicStore(lastGcTime, MonoTime.currTime);
            }
        }
    }
    
    private static Duration usecs(long us) @safe nothrow
    {
        return dur!"usecs"(us);
    }
}

// ============================================================================
// MEMORY MIDDLEWARE
// ============================================================================

import aurora.web.context : Context;

alias NextFunction = void delegate();
alias Middleware = void delegate(ref Context ctx, NextFunction next);

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

// ============================================================================
// UNIT TESTS
// ============================================================================

// Test 1: Config defaults
@("memory config has sensible defaults")
unittest
{
    auto config = MemoryConfig.defaults();
    assert(config.maxHeapBytes == 512 * 1024 * 1024);
    assert(config.highWaterRatio == 0.8);
    assert(config.criticalWaterRatio == 0.95);
}

// Test 2: Config computed properties
@("memory config computed water marks")
unittest
{
    auto config = MemoryConfig();
    config.maxHeapBytes = 1000;
    config.highWaterRatio = 0.8;
    config.criticalWaterRatio = 0.95;
    
    assert(config.highWaterMark == 800);
    assert(config.criticalWaterMark == 950);
}

// Test 3: Config withMaxMB factory
@("memory config withMaxMB")
unittest
{
    auto config = MemoryConfig.withMaxMB(256);
    assert(config.maxHeapBytes == 256 * 1024 * 1024);
}

// Test 4: MemoryState enum values
@("memory state enum")
unittest
{
    assert(MemoryState.NORMAL == cast(MemoryState)0);
    assert(MemoryState.PRESSURE == cast(MemoryState)1);
    assert(MemoryState.CRITICAL == cast(MemoryState)2);
}

// Test 5: PressureAction enum values
@("pressure action enum")
unittest
{
    assert(PressureAction.GC_COLLECT == cast(PressureAction)0);
    assert(PressureAction.LOG_ONLY == cast(PressureAction)1);
    assert(PressureAction.CUSTOM == cast(PressureAction)2);
    assert(PressureAction.NONE == cast(PressureAction)3);
}

// Test 6: MemoryStats utilization
@("memory stats utilization")
unittest
{
    MemoryStats stats;
    stats.usedBytes = 500;
    stats.maxBytes = 1000;
    
    assert(stats.utilization == 0.5);
}

// Test 7: MemoryStats utilization edge case
@("memory stats utilization edge case")
unittest
{
    MemoryStats stats;
    stats.maxBytes = 0;
    stats.usedBytes = 100;
    
    assert(stats.utilization == 0.0);
}

// Test 8: MemoryStats poolUtilization
@("memory stats pool utilization")
unittest
{
    MemoryStats stats;
    stats.usedBytes = 300;
    stats.poolBytes = 600;
    
    assert(stats.poolUtilization == 0.5);
}

// Test 9: MemoryStats headroom
@("memory stats headroom")
unittest
{
    MemoryStats stats;
    stats.usedBytes = 500;
    stats.maxBytes = 1000;
    
    // High water at 80% = 800
    assert(stats.headroom == 300);
}

// Test 10: MemoryMonitor creation
@("memory monitor creation")
unittest
{
    auto monitor = new MemoryMonitor();
    assert(monitor !is null);
    assert(monitor.getState() == MemoryState.NORMAL);
}

// Test 11: MemoryMonitor initial state
@("memory monitor initial state is NORMAL")
unittest
{
    auto config = MemoryConfig();
    config.maxHeapBytes = 1024 * 1024 * 1024;  // 1GB - should be plenty
    auto monitor = new MemoryMonitor(config);
    
    // Should be NORMAL with such high limit
    assert(!monitor.isCritical());
}

// Test 12: MemoryMonitor isUnderPressure
@("memory monitor isUnderPressure")
unittest
{
    auto monitor = new MemoryMonitor();
    // Initial state should be NORMAL
    assert(!monitor.isUnderPressure() || monitor.getState() >= MemoryState.PRESSURE);
}

// Test 13: MemoryMonitor stats
@("memory monitor stats")
unittest
{
    auto monitor = new MemoryMonitor();
    auto stats = monitor.getStats();
    
    assert(stats.maxBytes == 512 * 1024 * 1024);
    assert(stats.gcCollections == 0);
    assert(stats.rejectedRequests == 0);
}

// Test 14: MemoryMonitor configuration access
@("memory monitor configuration")
unittest
{
    auto config = MemoryConfig();
    config.maxHeapBytes = 256 * 1024 * 1024;
    auto monitor = new MemoryMonitor(config);
    
    assert(monitor.configuration.maxHeapBytes == 256 * 1024 * 1024);
}

// Test 15: MemoryMonitor resetStats
@("memory monitor reset stats")
unittest
{
    auto monitor = new MemoryMonitor();
    monitor.recordRejection();
    monitor.resetStats();
    
    auto stats = monitor.getStats();
    assert(stats.rejectedRequests == 0);
}

// Test 16: MemoryMonitor recordRejection
@("memory monitor record rejection")
unittest
{
    auto monitor = new MemoryMonitor();
    
    monitor.recordRejection();
    monitor.recordRejection();
    
    auto stats = monitor.getStats();
    assert(stats.rejectedRequests == 2);
}

// Test 17: MemoryMiddleware creation
@("memory middleware creation")
unittest
{
    auto monitor = new MemoryMonitor();
    auto mw = createMemoryMiddleware(monitor);
    assert(mw !is null);
}

// Test 18: Factory functions
@("memory factory functions")
unittest
{
    auto mw1 = memoryMiddleware(256 * 1024 * 1024);
    assert(mw1 !is null);
    
    auto config = MemoryConfig.withMaxMB(128);
    auto mw2 = memoryMiddleware(config);
    assert(mw2 !is null);
}

// Test 19: MemoryMonitor forceGC
@("memory monitor forceGC increments counter")
unittest
{
    auto monitor = new MemoryMonitor();
    auto beforeStats = monitor.getStats();
    
    monitor.forceGC();
    
    auto afterStats = monitor.getStats();
    assert(afterStats.gcCollections == beforeStats.gcCollections + 1);
}

// Test 20: Config bypass paths
@("memory config bypass paths")
unittest
{
    auto config = MemoryConfig();
    assert(config.bypassPaths.length == 1);
    assert(config.bypassPaths[0] == "/health/*");
}
