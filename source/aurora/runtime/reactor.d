/**
 * Reactor - Event Loop Wrapper
 *
 * Wraps eventcore for async I/O and timers. This is the low-level I/O abstraction
 * layer that provides platform-independent event handling.
 *
 * Features:
 * - Socket I/O via public API (encapsulates eventcore)
 * - Timer support (create, cancel, fire)
 * - Event loop lifecycle (run, runOnce, stop)
 * - Socket registration for event-driven patterns
 *
 * Design Principles:
 * - Per-thread event driver (one reactor per worker)
 * - Private EventDriver (no direct access - encapsulation)
 * - All I/O through public socketRead/socketWrite API
 * - Platform backends: epoll (Linux), kqueue (macOS), IOCP (Windows)
 *
 * Usage:
 * ---
 * auto reactor = new Reactor();
 * 
 * // Read from socket (returns ReadResult with IOStatus)
 * auto result = reactor.socketRead(socket, buffer);
 * if (result.status == IOStatus.ok) {
 *     // Process result.bytesRead bytes
 * }
 * 
 * // Create timer
 * auto timer = reactor.createTimer(100.msecs, () { ... });
 * 
 * // Run event loop
 * reactor.run();
 * ---
 */
module aurora.runtime.reactor;

import eventcore.driver;
import core.time;
import core.atomic;
import std.typecons : Tuple, tuple;

/// Timer ID type
alias TimerID = eventcore.driver.TimerID;

/// Socket file descriptor type (from eventcore)
alias SocketFD = StreamSocketFD;

/// Socket event types
enum SocketEvent
{
    READ,   /// Socket is readable
    WRITE   /// Socket is writable
}

/**
 * Result of a socket read operation.
 * 
 * Provides explicit status handling for robust I/O.
 */
struct ReadResult
{
    IOStatus status;   /// Operation status (ok, wouldBlock, eof, error)
    size_t bytesRead;  /// Number of bytes actually read
}

/**
 * Result of a socket write operation.
 * 
 * Provides explicit status handling for robust I/O.
 */
struct WriteResult
{
    IOStatus status;      /// Operation status (ok, wouldBlock, eof, error)
    size_t bytesWritten;  /// Number of bytes actually written
}

/**
 * Reactor - Event Loop Wrapper
 *
 * Wraps eventcore.driver for timer and event loop support.
 * Provides the only approved way to perform socket I/O.
 */
class Reactor
{
    private EventDriver driver;
    private shared bool _running;

    /**
     * Create reactor
     *
     * Initializes per-thread event driver
     */
    this() @trusted
    {
        driver = getThreadEventDriver();
        atomicStore(_running, false);
    }

    /**
     * Shutdown reactor
     *
     * Phase 3: Explicit shutdown instead of destructor
     *
     * Cleans up event driver resources before GC collection.
     * Called explicitly from Worker.cleanup().
     */
    void shutdown() @trusted nothrow
    {
        try
        {
            atomicStore(_running, false);
            
            // Cancel all pending timers
            // eventcore driver cleanup happens in its own destructor
            // We just ensure running flag is cleared
        }
        catch (Throwable e)
        {
            // Shutdown must not throw
        }
    }

    // ========================================
    // SOCKET I/O API (Phase 5: Fix illegal driver access)
    // ========================================

    /**
     * Read from socket using eventcore
     *
     * This is the ONLY way Connection should access eventcore I/O.
     * Direct access to driver is illegal (driver is private).
     *
     * Uses IOMode.immediate to avoid callback conflicts:
     * - Returns immediately with available data or wouldBlock
     * - Caller should yield() and retry on wouldBlock
     *
     * Returns: ReadResult with IOStatus and bytes read
     */
    ReadResult socketRead(SocketFD socket, ubyte[] buffer) @trusted nothrow
    {
        import eventcore.driver : IOMode, IOStatus;
        
        ReadResult result;
        result.status = IOStatus.error;
        result.bytesRead = 0;
        
        try
        {
            // Use IOMode.immediate to avoid "overwriting callback" errors
            // This returns immediately - caller should yield() and retry on wouldBlock
            driver.sockets.read(socket, buffer, IOMode.immediate, 
                (sock, st, bytes) @safe nothrow {
                    result.status = st;
                    result.bytesRead = cast(size_t)bytes;
                });
        }
        catch (Exception e)
        {
            result.status = IOStatus.error;
            result.bytesRead = 0;
        }
        
        return result;
    }

    /**
     * Write to socket using eventcore
     *
     * This is the ONLY way Connection should access eventcore I/O.
     * Direct access to driver is illegal (driver is private).
     *
     * Uses IOMode.immediate to avoid callback conflicts:
     * - Returns immediately with bytes written or wouldBlock
     * - Caller should yield() and retry on wouldBlock
     *
     * Returns: WriteResult with IOStatus and bytes written
     */
    WriteResult socketWrite(SocketFD socket, const(ubyte)[] data) @trusted nothrow
    {
        import eventcore.driver : IOMode, IOStatus;
        
        WriteResult result;
        result.status = IOStatus.error;
        result.bytesWritten = 0;
        
        try
        {
            // Use IOMode.immediate to avoid "overwriting callback" errors
            driver.sockets.write(socket, data, IOMode.immediate,
                (sock, st, bytes) @safe nothrow {
                    result.status = st;
                    result.bytesWritten = cast(size_t)bytes;
                });
        }
        catch (Exception e)
        {
            result.status = IOStatus.error;
            result.bytesWritten = 0;
        }
        
        return result;
    }

    /**
     * Create timer
     *
     * Params:
     *   timeout = Duration until timer fires
     *   callback = Callback to invoke when timer fires
     *
     * Returns:
     *   Timer ID (use with cancelTimer)
     */
    TimerID createTimer(Duration timeout, void delegate() @safe nothrow callback) @trusted
    {
        auto timer = driver.timers.create();

        driver.timers.set(timer, timeout, 0.seconds);  // Non-recurring timer

        driver.timers.wait(timer, (tm) {
            if (tm == TimerID.invalid)
                return;  // Timer was cancelled

            try
            {
                callback();
            }
            catch (Exception e)
            {
                // Log error (future: use logging system)
            }
        });

        return timer;
    }

    /**
     * Register socket for events
     *
     * Register a socket to be monitored for read or write events.
     * When the socket becomes ready, the callback will be invoked.
     *
     * Params:
     *   socket = Socket file descriptor to monitor
     *   event = Type of event (READ or WRITE)
     *   callback = Callback to invoke when socket is ready
     *
     * Note:
     *   Callback must be @safe nothrow for reactor safety
     */
    void registerSocket(SocketFD socket, SocketEvent event,
                        void delegate() @safe nothrow callback) @trusted
    {
        if (socket == SocketFD.invalid)
            return;

        final switch (event)
        {
            case SocketEvent.READ:
                // Register for read readiness using eventcore
                driver.sockets.waitForData(socket, (sock, status, nbytes) {
                    if (sock == SocketFD.invalid || status != IOStatus.ok)
                        return;

                    try
                    {
                        callback();
                    }
                    catch (Exception e)
                    {
                        // Log error (future: use logging system)
                    }
                });
                break;

            case SocketEvent.WRITE:
                // Write events: call callback directly
                // The actual write operation with IOMode.once + IOStatus handling
                // happens in Connection.onWritable() → eventcoreWrite()
                // No need for timer hack - the fiber handles synchronous write + status check
                try
                {
                    callback();
                }
                catch (Exception e)
                {
                    // Log error (future: use logging system)
                }
                break;
        }
    }

    void cancelTimer(TimerID timerId) @trusted nothrow
    {
        try
        {
            if (timerId != TimerID.invalid)
            {
                driver.timers.stop(timerId);
                driver.timers.releaseRef(timerId);
            }
        }
        catch (Throwable e)
        {
            // Ignore errors on cancel
        }
    }

// ...

    void unregisterSocket(SocketFD socket) @trusted nothrow
    {
        if (socket == SocketFD.invalid)
            return;

        try
        {
            // Cancel any pending read/write operations
            driver.sockets.cancelRead(socket);
            // Note: eventcore may not have cancelWrite, handled via socket close
        }
        catch (Throwable e)
        {
            // Ignore errors on unregister
        }
    }
    
    /**
     * Close socket
     * 
     * Actually closes the socket file descriptor
     */
    void closeSocket(SocketFD socket) @trusted nothrow
    {
        if (socket == SocketFD.invalid)
            return;
            
        try
        {
            driver.sockets.releaseRef(socket);
        }
        catch (Throwable e)
        {
            // Ignore errors
        }
    }

    /**
     * Run event loop
     *
     * Blocks until stop() is called
     */
    void run() @trusted
    {
        atomicStore(_running, true);

        while (atomicLoad(_running))
        {
            try
            {
                ExitReason reason = driver.core.processEvents(1.seconds);

                if (reason == ExitReason.exited)
                    break;
            }
            catch (Exception e)
            {
                // Log error and continue
            }
        }
    }

    /**
     * Run event loop once
     *
     * Process events for one iteration with timeout
     *
     * Params:
     *   timeout = Maximum time to wait for events
     */
    void runOnce(Duration timeout) @trusted
    {
        try
        {
            driver.core.processEvents(timeout);
        }
        catch (Exception e)
        {
            // Log error
        }
    }

    /**
     * Stop event loop
     *
     * Signals run() to exit
     */
    void stop() @safe nothrow @nogc
    {
        atomicStore(_running, false);
    }

    /**
     * Check if reactor is running
     *
     * Returns:
     *   true if run() is active
     */
    @property bool running() @safe nothrow @nogc
    {
        return atomicLoad(_running);
    }
}

/**
 * Get thread-local event driver
 *
 * Returns:
 *   EventDriver instance for current thread
 */
private EventDriver getThreadEventDriver() @trusted
{
    static EventDriver driver;

    if (driver is null)
    {
        driver = createEventDriver();
    }

    return driver;
}

import eventcore.core;

/**
 * Create event driver
 *
 * Creates platform-specific event driver
 *
 * Returns:
 *   New EventDriver instance
 */
private EventDriver createEventDriver() @trusted
{
    // eventcore will automatically select platform driver
    return eventcore.core.eventDriver;
}
