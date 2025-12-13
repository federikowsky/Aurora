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

