/**
 * Aurora Worker Thread Management
 *
 * Implements multi-worker architecture for Linux/FreeBSD using SO_REUSEPORT.
 * Each worker runs in its own OS thread with its own event loop.
 * The kernel distributes incoming connections across workers.
 *
 * Architecture:
 * ```
 *         ┌──────────────────────────────────────┐
 *         │             OS Kernel                │
 *         │    (SO_REUSEPORT load balancing)     │
 *         │         Port 8080                    │
 *         └──────────────────────────────────────┘
 *                    ↑ ↑ ↑ ↑ ↑
 *                    │ │ │ │ │  Kernel distributes connections
 *         ┌──────────┴─┴─┴─┴─┴──────────┐
 *         ▼          ▼     ▼            ▼
 *     ┌────────┐ ┌────────┐  ...  ┌────────┐
 *     │Worker 0│ │Worker 1│       │Worker N│
 *     │        │ │        │       │        │
 *     │listener│ │listener│       │listener│
 *     │evtLoop │ │evtLoop │       │evtLoop │
 *     │Thread 0│ │Thread 1│       │Thread N│
 *     └────────┘ └────────┘       └────────┘
 * ```
 */
module aurora.runtime.worker;

// Only compile worker support on platforms that support reusePort
version(linux)
{
    version = HasReusePort;
}
version(FreeBSD)
{
    version = HasReusePort;
}

version(HasReusePort):

import vibe.core.net : listenTCP, TCPListener, TCPConnection, TCPListenOptions;
import vibe.core.core : runEventLoop, exitEventLoop, runWorkerTaskH, runWorkerTaskDist, yield;
import vibe.core.task : Task;

import core.atomic;
import core.thread : Thread;
import core.sync.mutex : Mutex;
import core.time : Duration;

import std.parallelism : totalCPUs;

/// Worker thread state
struct WorkerState
{
    uint id;
    shared bool running;
    shared bool shouldStop;
    
    // Stats (atomic for thread-safety)
    shared ulong connections;
    shared ulong requests;
    shared ulong errors;
    shared ulong rejectedHeader;
    shared ulong rejectedBody;
    shared ulong rejectedTimeout;
    shared ulong activeConnections;
}

/// Worker thread handle
struct WorkerHandle
{
    uint id;
    Task task;
    shared(WorkerState)* state;
}

/// Multi-worker coordinator
final class WorkerPool
{
    private
    {
        WorkerHandle[] workers;
        shared(WorkerState)[] workerStates;
        shared bool poolRunning;
        shared bool poolShuttingDown;
        
        // Config copied from server
        ushort port;
        string host;
        Duration readTimeout;
        Duration keepAliveTimeout;
        uint maxHeaderSize;
        size_t maxBodySize;
        uint maxRequestsPerConnection;
        bool debugMode;
        
        // Connection handler delegate
        void delegate(TCPConnection) @safe nothrow connectionHandler;
    }
    
    /// Create worker pool
    this(uint numWorkers, ushort port, string host,
         void delegate(TCPConnection) @safe nothrow handler) @safe
    {
        this.port = port;
        this.host = host;
        this.connectionHandler = handler;
        
        // Allocate worker states
        workerStates.length = numWorkers;
        foreach (i, ref state; workerStates)
        {
            state.id = cast(uint)i;
            atomicStore(state.running, false);
            atomicStore(state.shouldStop, false);
            atomicStore(state.connections, 0UL);
            atomicStore(state.requests, 0UL);
            atomicStore(state.errors, 0UL);
            atomicStore(state.rejectedHeader, 0UL);
            atomicStore(state.rejectedBody, 0UL);
            atomicStore(state.rejectedTimeout, 0UL);
            atomicStore(state.activeConnections, 0UL);
        }
        
        atomicStore(poolRunning, false);
        atomicStore(poolShuttingDown, false);
    }
    
    /// Start all workers
    void start() @trusted
    {
        import std.stdio : writefln;
        
        atomicStore(poolRunning, true);
        atomicStore(poolShuttingDown, false);
        
        // Launch worker tasks (each will run in its own thread via vibe-core)
        foreach (i, ref state; workerStates)
        {
            auto handle = WorkerHandle();
            handle.id = cast(uint)i;
            handle.state = &state;
            
            // runWorkerTaskH launches task in a worker thread
            handle.task = runWorkerTaskH(&workerEntryPoint,
                                         cast(shared(WorkerPool))this,
                                         handle.state);
            
            workers ~= handle;
            
            if (debugMode)
                writefln("  Started worker %d", i);
        }
    }
    
    /// Stop all workers
    void stop() @trusted nothrow
    {
        atomicStore(poolShuttingDown, true);
        
        // Signal all workers to stop
        foreach (ref state; workerStates)
        {
            atomicStore(state.shouldStop, true);
        }
        
        atomicStore(poolRunning, false);
    }
    
    /// Wait for all workers to finish (with timeout)
    void join(Duration timeout) @trusted
    {
        import core.time : MonoTime;
        
        auto deadline = MonoTime.currTime + timeout;
        
        while (MonoTime.currTime < deadline)
        {
            bool allStopped = true;
            foreach (ref state; workerStates)
            {
                if (atomicLoad(state.running))
                {
                    allStopped = false;
                    break;
                }
            }
            
            if (allStopped)
                break;
            
            try { yield(); }
            catch (Exception) {}
        }
    }
    
    /// Get aggregated stats
    ulong getTotalConnections() @safe nothrow
    {
        ulong total = 0;
        foreach (ref state; workerStates)
            total += atomicLoad(state.connections);
        return total;
    }
    
    ulong getTotalRequests() @safe nothrow
    {
        ulong total = 0;
        foreach (ref state; workerStates)
            total += atomicLoad(state.requests);
        return total;
    }
    
    ulong getTotalErrors() @safe nothrow
    {
        ulong total = 0;
        foreach (ref state; workerStates)
            total += atomicLoad(state.errors);
        return total;
    }
    
    ulong getActiveConnections() @safe nothrow
    {
        ulong total = 0;
        foreach (ref state; workerStates)
            total += atomicLoad(state.activeConnections);
        return total;
    }
    
    ulong getRejectedHeadersTooLarge() @safe nothrow
    {
        ulong total = 0;
        foreach (ref state; workerStates)
            total += atomicLoad(state.rejectedHeader);
        return total;
    }
    
    ulong getRejectedBodyTooLarge() @safe nothrow
    {
        ulong total = 0;
        foreach (ref state; workerStates)
            total += atomicLoad(state.rejectedBody);
        return total;
    }
    
    ulong getRejectedTimeout() @safe nothrow
    {
        ulong total = 0;
        foreach (ref state; workerStates)
            total += atomicLoad(state.rejectedTimeout);
        return total;
    }
    
    @property uint numWorkers() const @safe nothrow
    {
        return cast(uint)workerStates.length;
    }
    
    @property bool isRunning() @safe nothrow
    {
        return atomicLoad(poolRunning);
    }
    
    @property bool isShuttingDown() @safe nothrow
    {
        return atomicLoad(poolShuttingDown);
    }
    
    // Worker entry point (runs in worker thread)
    private static void workerEntryPoint(shared(WorkerPool) poolRef,
                                          shared(WorkerState)* state) nothrow
    {
        auto pool = cast(WorkerPool)poolRef;
        
        atomicStore(state.running, true);
        
        TCPListener listener;
        
        try
        {
            // Each worker creates its own listener with reusePort
            // The kernel will load-balance connections across all listeners
            listener = listenTCP(
                pool.port,
                (conn) nothrow {
                    // Track stats in worker-local state
                    atomicOp!"+="(state.connections, 1);
                    atomicOp!"+="(state.activeConnections, 1);
                    
                    scope(exit)
                        atomicOp!"-="(state.activeConnections, 1);
                    
                    // Delegate to actual handler
                    if (pool.connectionHandler !is null)
                    {
                        try
                        {
                            pool.connectionHandler(conn);
                        }
                        catch (Exception)
                        {
                            atomicOp!"+="(state.errors, 1);
                        }
                    }
                },
                pool.host,
                TCPListenOptions.reusePort | TCPListenOptions.reuseAddress
            );
            
            // Store listener reference for cleanup
            // Note: The worker thread's event loop is already running 
            // (managed by vibe-core). We just need to keep the listener alive.
            // The listener will receive connections via the worker thread's event loop.
            
            // Wait for shutdown signal by polling
            while (!atomicLoad(state.shouldStop) && !atomicLoad(pool.poolShuttingDown))
            {
                try 
                {
                    yield();  // Give control back to the event loop
                }
                catch (Exception) 
                {
                    break;
                }
            }
        }
        catch (Exception e)
        {
            // Failed to start listener
            atomicOp!"+="(state.errors, 1);
        }
        
        // Cleanup
        if (listener !is TCPListener.init)
        {
            try { listener.stopListening(); }
            catch (Exception) {}
        }
        
        atomicStore(state.running, false);
    }
}
