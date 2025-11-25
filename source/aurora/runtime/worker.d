/**
 * Worker - Worker thread for handling connections
 *
 * M2 Simplified:
 * - Clean thread lifecycle (start, stop)
 * - Thread-local resources (BufferPool, Arena)
 * - Reactor integration (runOnce per iteration)
 *
 * Phase 2: vibe-core Fiber Integration
 * - vibe-core event loop (runEventLoop)
 * - Connection handling in Tasks (runTask)
 */
module aurora.runtime.worker;

import aurora.runtime.reactor;
import aurora.runtime.config;
import aurora.mem.pool;
import aurora.mem.arena;
import core.thread;
import core.time;
import core.atomic;
import std.format : format;

// Phase 2: vibe-core fiber runtime integration
import vibe.core.core : runEventLoop, exitEventLoop, runTask;
import vibe.core.core : yield;
import vibe.core.task : Task;

/**
 * Worker Thread
 *
 * Cache-line aligned to avoid false sharing
 */
align(64) struct Worker
{
    // Hot data (first cache line)
    uint id;                        /// Worker ID (0..N-1)
    Thread thread;                  /// OS thread handle
    Reactor reactor;                /// Event loop instance

    // Thread-local memory
    BufferPool memoryPool;         /// Thread-local buffer pool
    Arena arena;          /// Thread-local arena

    // NUMA affinity (structure ready for Linux)
    uint numaNode;  // TODO M4: NUMA binding (Fix 7 deferral)
                    // Currently: Placeholder, no CPU affinity set
                    // Future: Use core.thread.setAffinity() for NUMA binding
                    // Requires: OS-specific setup (numactl, taskset)
                    // Rationale: Performance optimization for high-throughput scenarios
    
    // Stats (separate cache line to avoid false sharing)
    align(64) struct Stats
    {
        shared ulong tasksProcessed;    /// Tasks processed counter
    }
    Stats stats;

    // Cold data
    string name;                    /// Worker name: "Worker-0", "Worker-1", ...
    shared bool running;            /// Shutdown flag (atomic)

    /**
     * Initialize worker
     *
     * Params:
     *   workerId = Worker ID (0..N-1)
     *   numa = NUMA node ID
     */
    this(uint workerId, uint numa) @safe
    {
        this.id = workerId;
        this.numaNode = numa;
        this.name = format("Worker-%d", workerId);
        this.running = false;
        this.stats.tasksProcessed = 0;
    }

    /**
     * Start worker thread
     *
     * Spawns OS thread and begins workerMain loop
     */
    void start() @trusted
    {
        atomicStore(running, true);
        thread = new Thread(&workerMain);
        thread.start();
    }

    /**
     * Stop worker thread
     *
     * Sets running flag to false and signals vibe-core event loop to exit.
     * Phase 3: Proper shutdown coordination with exitEventLoop()
     */
    void stopAll() @trusted nothrow
    {
        import vibe.core.core : exitEventLoop;
        
        atomicStore(running, false);
        
        try
        {
            // Signal vibe-core to stop event loop
            // This causes runEventLoop() to return
            exitEventLoop();
        }
        catch (Exception e)
        {
            // Ignore - stop must be nothrow
        }
    }

    /**
     * Join worker thread
     *
     * Waits for worker thread to exit cleanly
     */
    void join() @trusted
    {
        if (thread !is null)
        {
            thread.join();
        }
    }

    /**
     * Worker main loop
     *
     * Phase 2: Uses vibe-core event loop (fiber-based)
     * Phase 3: Proper cleanup with scope(exit)
     *
     * This function runs in a dedicated OS thread.
     * vibe-core manages fibers cooperatively within this thread.
     */
    private void workerMain() @trusted
    {
        // Phase 3: Always cleanup, even on exception or early exit
        scope(exit) cleanup();
        
        try
        {
            // Setup thread-local resources
            setupResources();

            // Phase 2: Run vibe-core event loop
            // This blocks until exitEventLoop() is called (from stop())
            runEventLoop();
        }
        catch (Exception e)
        {
            // Critical error in worker
            // TODO: Log to error handler
        }
        
        // cleanup() called automatically by scope(exit)
    }

    /**
     * Setup thread-local resources
     *
     * Phase 3: Separated from workerMain for clarity
     */
    private void setupResources() @trusted
    {
        // Initialize thread-local memory
        memoryPool = new BufferPool();
        arena = new Arena(1024 * 1024); // 1MB arena

        // Initialize reactor (eventcore driver is thread-local)
        reactor = new Reactor();
    }

    /**
     * Stop the event loop
     *
     * Phase 2: Signals vibe-core to exit
     */
    void stopEventLoop() @safe nothrow
    {
        try
        {
            exitEventLoop();
        }
        catch (Exception e)
        {
            // Ignore errors
        }
    }

    /**
     * Cleanup worker resources
     *
     * Phase 3: Proper shutdown coordination
     */
    private void cleanup() @trusted nothrow
    {
        try
        {
            if (memoryPool !is null)
            {
                memoryPool.cleanup();
                memoryPool = null;
            }

            if (arena !is null)
            {
                arena.reset();
                arena = null;
            }

            // Phase 3: Call shutdown() instead of destroy()
            if (reactor !is null)
            {
                reactor.shutdown();  // ✅ Explicit shutdown
                reactor = null;       // ✅ Let GC collect
                
                // ❌ NOT: destroy(reactor) - we use shutdown() + GC
            }
        }
        catch (Exception e)
        {
            // Ignore cleanup errors
        }
    }
}

/**
 * Create multiple workers
 *
 * Params:
 *   count = Number of workers to create
 *   numaNodes = Number of NUMA nodes (0 = auto-detect)
 *
 * Returns:
 *   Array of initialized workers
 */
Worker[] createWorkers(uint count, uint numaNodes = 1) @safe
{
    Worker[] workers;
    workers.length = count;

    foreach (i; 0..count)
    {
        uint numa = numaNodes > 0 ? (i % numaNodes) : 0;
        workers[i] = Worker(cast(uint)i, numa);
    }

    return workers;
}

/**
 * Start all workers
 *
 * Params:
 *   workers = Array of workers to start
 */
void startAll(Worker[] workers) @trusted
{
    foreach (ref worker; workers)
    {
        worker.start();
    }
}

/**
 * Stop all workers
 *
 * Params:
 *   workers = Array of workers to stop
 */
void stopAll(Worker[] workers) @safe nothrow
{
    foreach (ref worker; workers)
    {
        worker.stopAll();
    }
}

/**
 * Join all workers
 *
 * Params:
 *   workers = Array of workers to join
 */
void joinAll(Worker[] workers) @trusted
{
    foreach (ref worker; workers)
    {
        worker.join();
    }
}
