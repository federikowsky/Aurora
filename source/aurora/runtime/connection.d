/**
 * Connection Management
 *
 * Phase 1: Socket I/O Foundation ✅
 * Phase 2: vibe-core Fiber Integration ✅
 *
 * Provides:
 * - Connection state machine (6 states)
 * - Socket I/O with eventcore (no POSIX)
 * - Buffer management (BufferPool integration)
 * - HTTP request parsing integration
 * - HTTP response sending
 * - Fiber-based cooperative multitasking
 *
 * Phase 3 (partial):
 * - Keep-alive logic (code ready, tests needed)
 */
module aurora.runtime.connection;

import aurora.http;
import aurora.mem.pool;
import aurora.runtime.reactor;
import aurora.runtime.config;
import core.time;

// Phase 2: vibe-core fiber integration
import vibe.core.core : yield;

/**
 * Connection State Machine
 */
enum ConnectionState
{
    NEW,              /// Just accepted
    READING_HEADERS,  /// Reading HTTP request
    PROCESSING,       /// Handler executing
    WRITING_RESPONSE, /// Sending HTTP response
    KEEP_ALIVE,       /// Waiting for next request
    CLOSED            /// Connection closed
}

/**
 * Result of eventcore read operation
 *
 * Includes both bytes read and IOStatus to handle all cases:
 * - ok: Normal read with data
 * - wouldBlock: Socket not ready (NOT an error!)
 * - eof: Clean connection close
 * - error: I/O error
 */
struct ReadResult
{
    import eventcore.driver : IOStatus;
    
    size_t bytesRead;  /// Number of bytes read
    IOStatus status;   /// I/O operation status
}

/**
 * Result of eventcore write operation
 *
 * Includes both bytes written and IOStatus
 */
struct WriteResult
{
    import eventcore.driver : IOStatus;
    
    size_t bytesWritten;  /// Number of bytes written
    IOStatus status;      /// I/O operation status
}

// BUG #2 FIX: Maximum header size before rejecting request
private enum size_t MAX_HEADER_SIZE = 64 * 1024;  // 64KB

/**
 * Connection - HTTP connection handler
 *
 * Phase 1+2: Socket I/O with timeout infrastructure
 *
 * CRITICAL: Connection is non-copyable to prevent delegate capture bugs.
 * Delegates capture 'this' by reference. If Connection is copied,
 * delegates point to old copy location → use-after-free.
 */
struct Connection
{
    @disable this(this);  // Prevent accidental copies
    // State machine
    ConnectionState state;
    HTTPRequest request;
    HTTPResponse response;

    // Socket I/O (Phase 1)
    SocketFD socket;           /// Socket file descriptor
    ubyte[] readBuffer;        /// Read buffer (from BufferPool)
    size_t readPos;            /// Current read position
    ubyte[] writeBuffer;       /// Write buffer (response data - SLICED)
    ubyte[] rawWriteBuffer;    /// Original write buffer (for release)
    size_t writePos;           /// Current write position

    // References to Worker resources
    BufferPool* bufferPool;    /// For buffer acquire/release
    Reactor reactor;           /// Event loop (class reference, not pointer!)

    // Configuration (Phase 2)
    ConnectionConfig* config;  /// Connection timeout configuration

    // Timers (Phase 2)
    TimerID readTimer;         /// Read timeout timer
    TimerID writeTimer;        /// Write timeout timer
    TimerID keepAliveTimer;    /// Keep-alive timeout timer

    // Keep-alive (Phase 3)
    bool keepAlive;            /// Whether to keep connection alive after response
    ulong requestsServed;      /// Number of requests served on this connection

    /**
     * Process request and generate response
     *
     * Now uses @nogc buildInto() for zero-allocation response building
     */
    void processRequest() @trusted
    {
        import aurora.mem.pool : BufferSize;

        // Estimate required buffer size
        size_t estimatedSize = response.estimateSize();

        // Choose appropriate buffer size
        BufferSize bufSize;
        if (estimatedSize <= 1024)
            bufSize = BufferSize.TINY;
        else if (estimatedSize <= 4096)
            bufSize = BufferSize.SMALL;
        else if (estimatedSize <= 16384)
            bufSize = BufferSize.MEDIUM;
        else if (estimatedSize <= 65536)
            bufSize = BufferSize.LARGE;
        else
            bufSize = BufferSize.HUGE;

        // Acquire buffer from pool
        rawWriteBuffer = bufferPool.acquire(bufSize);
        writeBuffer = rawWriteBuffer;

        // Build response directly into buffer (@nogc hot-path)
        size_t bytesWritten = response.buildInto(writeBuffer);

        // Handle buffer overflow (rare - only if estimate was wrong)
        if (bytesWritten == 0)
        {
            // Try MEDIUM
            if (bufSize == BufferSize.TINY || bufSize == BufferSize.SMALL)
            {
                bufferPool.release(rawWriteBuffer);
                rawWriteBuffer = bufferPool.acquire(BufferSize.MEDIUM);
                writeBuffer = rawWriteBuffer;
                bytesWritten = response.buildInto(writeBuffer);
            }

            // Try LARGE
            if (bytesWritten == 0 && bufSize != BufferSize.LARGE && bufSize != BufferSize.HUGE)
            {
                bufferPool.release(rawWriteBuffer);
                rawWriteBuffer = bufferPool.acquire(BufferSize.LARGE);
                writeBuffer = rawWriteBuffer;
                bytesWritten = response.buildInto(writeBuffer);
            }

            // Try HUGE
            if (bytesWritten == 0 && bufSize != BufferSize.HUGE)
            {
                bufferPool.release(rawWriteBuffer);
                rawWriteBuffer = bufferPool.acquire(BufferSize.HUGE);
                writeBuffer = rawWriteBuffer;
                bytesWritten = response.buildInto(writeBuffer);
            }

            // Still failed - response too large (> 256KB)
            if (bytesWritten == 0)
            {
                import aurora.http : HTTPResponse;
                bufferPool.release(rawWriteBuffer);
                response = HTTPResponse(500, "Internal Server Error");
                response.setBody("Response exceeds maximum size (256KB)");
                rawWriteBuffer = bufferPool.acquire(BufferSize.SMALL);
                writeBuffer = rawWriteBuffer;
                bytesWritten = response.buildInto(writeBuffer);
            }
        }

        // Trim buffer to actual size written
        writeBuffer = writeBuffer[0 .. bytesWritten];
        writePos = 0;
    }
    
    /// Initialize new connection with socket and resources
    void initialize(SocketFD sock, BufferPool* pool, Reactor react,
                   ConnectionConfig* cfg = null) @trusted
    {
        // BUG #3 FIX: Clean up existing state if re-initializing
        if (state != ConnectionState.NEW && state != ConnectionState.CLOSED)
        {
            close();  // Release all resources (socket, buffers, timers)
        }

        socket = sock;
        bufferPool = pool;
        reactor = react;
        config = cfg;
        state = ConnectionState.NEW;
        readPos = 0;
        writePos = 0;

        // Initialize timer IDs to invalid
        readTimer = TimerID.invalid;
        writeTimer = TimerID.invalid;
        keepAliveTimer = TimerID.invalid;

        // Initialize keep-alive state (Phase 3)
        keepAlive = false;
        requestsServed = 0;

        // Acquire read buffer
        if (bufferPool !is null)
        {
            readBuffer = bufferPool.acquire(BufferSize.SMALL);  // 4KB
        }
    }

    /// Transition to new state
    void transition(ConnectionState newState) @safe nothrow @nogc
    {
        state = newState;
    }

    /// Check if connection is closed
    @property bool isClosed() @safe nothrow @nogc const
    {
        return state == ConnectionState.CLOSED;
    }

    /// Close connection and cleanup resources
    void close() @trusted nothrow
    {
        // Cancel all active timers (Phase 2)
        if (reactor !is null)
        {
            if (readTimer != TimerID.invalid)
            {
                reactor.cancelTimer(readTimer);
                readTimer = TimerID.invalid;
            }
            if (writeTimer != TimerID.invalid)
            {
                reactor.cancelTimer(writeTimer);
                writeTimer = TimerID.invalid;
            }
            if (keepAliveTimer != TimerID.invalid)
            {
                reactor.cancelTimer(keepAliveTimer);
                keepAliveTimer = TimerID.invalid;
            }
        }

        // Release buffers
        if (readBuffer !is null && bufferPool !is null)
        {
            try
            {
                bufferPool.release(readBuffer);
                readBuffer = null;
            }
            catch (Exception e)
            {
                // Ignore errors on cleanup
            }
        }

        // Release write buffer back to pool (pool-allocated via buildInto)
        if (rawWriteBuffer !is null && bufferPool !is null)
        {
            try
            {
                bufferPool.release(rawWriteBuffer);
                rawWriteBuffer = null;
                writeBuffer = null;
            }
            catch (Exception e)
            {
                // Ignore errors on cleanup
            }
        }

        // Unregister and close socket (BUG #1, #4 fix)
        if (reactor !is null && socket != SocketFD.invalid)
        {
            reactor.unregisterSocket(socket);
            reactor.closeSocket(socket);  // BUG #1 FIX: Actually close the FD
            socket = SocketFD.invalid;    // BUG #4 FIX: Prevent double unregister
        }

        state = ConnectionState.CLOSED;
    }


    // ========================================
    // PHASE 2: TIMEOUT CALLBACKS
    // ========================================

    /// Callback when read timeout expires
    private void onReadTimeout() @safe nothrow
    {
        // Read timeout → close connection
        close();
    }

    /// Callback when write timeout expires (Phase 2)
    private void onWriteTimeout() @safe nothrow
    {
        // Write timeout → close connection
        close();
    }

    /// Callback when keep-alive timeout expires (Phase 2)
    private void onKeepAliveTimeout() @safe nothrow
    {
        // Keep-alive timeout → close connection
        close();
    }

    /// Read from socket using eventcore (IOMode.immediate + IOStatus)
    private ReadResult eventcoreRead(ubyte[] buffer) @trusted nothrow
    {
        import eventcore.driver : IOStatus;
        import std.typecons : Tuple;

        // ISSUE #6 FIX: Verify tuple order at compile-time
        // static assert(is(typeof(reactor.socketRead(socket, buffer)) ==
        //                 Tuple!(IOStatus, size_t)),
        //              "Reactor.socketRead must return Tuple!(IOStatus, size_t)");

        // Return zero result if invalid params
        if (reactor is null || socket == SocketFD.invalid || buffer.length == 0)
            return ReadResult(0, IOStatus.error);

        try
        {
            // Use Reactor public API (NOT direct driver access!)
            // Phase 5 fix: reactor.driver is private, use socketRead instead
            auto result = reactor.socketRead(socket, buffer);

            // Return both status and bytes (ReadResult from Reactor)
            return ReadResult(result.bytesRead, result.status);
        }
        catch (Exception e)
        {
            // Exception during read = error
            return ReadResult(0, IOStatus.error);
        }
    }

    /// Write to socket using eventcore (IOMode.immediate + IOStatus)
    private WriteResult eventcoreWrite(const(ubyte)[] data) @trusted nothrow
    {
        import eventcore.driver : IOStatus;
        import std.typecons : Tuple;

        // ISSUE #6 FIX: Verify tuple order at compile-time
        // static assert(is(typeof(reactor.socketWrite(socket, data)) ==
        //                 Tuple!(IOStatus, size_t)),
        //              "Reactor.socketWrite must return Tuple!(IOStatus, size_t)");

        // Return zero result if invalid params
        if (reactor is null || socket == SocketFD.invalid || data.length == 0)
            return WriteResult(0, IOStatus.error);

        try
        {
            // Use Reactor public API (NOT direct driver access!)
            // Phase 5 fix: reactor.driver is private, use socketWrite instead
            auto result = reactor.socketWrite(socket, data);

            // Return both status and bytes (WriteResult from Reactor)
            return WriteResult(result.bytesWritten, result.status);
        }
        catch (Exception e)
        {
            // Exception during write = error
            return WriteResult(0, IOStatus.error);
        }
    }

    // ========================================
    // PHASE 4: KEEP-ALIVE LOGIC
    // ========================================

    /**
     * Reset connection state for next request (keep-alive)
     *
     * Phase 4: Proper keep-alive implementation
     */
    void resetConnection() @trusted nothrow
    {
        // BUG #5 FIX: Increment counter when resetting for next request
        requestsServed++;

        // Cancel keep-alive timer if still running
        if (keepAliveTimer != TimerID.invalid && reactor !is null)
        {
            try
            {
                reactor.cancelTimer(keepAliveTimer);
                keepAliveTimer = TimerID.invalid;
            }
            catch (Exception e)
            {
                // Ignore
            }
        }

        // Reset state to read next request
        state = ConnectionState.READING_HEADERS;
        readPos = 0;
        writePos = 0;

        // Release write buffer back to pool (pool-allocated via buildInto)
        if (rawWriteBuffer !is null && bufferPool !is null)
        {
            try
            {
                bufferPool.release(rawWriteBuffer);
                rawWriteBuffer = null;
                writeBuffer = null;
            }
            catch (Exception e)
            {
                // Ignore errors during reset
            }
        }

        // Reset request/response for next cycle
        // HTTPRequest is a struct, assignment resets it
        request = HTTPRequest.init;
        response = HTTPResponse.init;
    }

    // ========================================
    // PHASE 2: FIBER-DRIVEN CONNECTION LOOP
    // ========================================

    /**
     * Handle connection lifecycle in fiber
     *
     * Phase 2: Full fiber-driven model - handles entire request/response lifecycle
     *
     * This is the HEART of the fiber-based connection handling.
     * Runs as a vibe-core Task, uses yield() for cooperative multitasking.
     *
     * Solves 3 critical issues:
     * - 2.2: WRITE stalls (loop handles wouldBlock with yield)
     * - 2.3: READ one-shot (loop handles partial reads)
     * - 2.7: Fiber integration (fiber owns control flow)
     */
    void handleConnectionLoop() @trusted
    {
        // No yield import needed - fiber scheduling handled by vibe-core
        import eventcore.driver : IOStatus;
        
        try
        {
            // ========================================
            // KEEP-ALIVE LOOP: Handle multiple requests
            // ========================================
            while (state != ConnectionState.CLOSED)
            {
                // ========================================
                // READ LOOP: Handle partial HTTP requests
                // ========================================
                state = ConnectionState.READING_HEADERS;
                
                // CRITICAL FIX 2: Start read timer at beginning of read phase
                if (reactor !is null && config !is null)
                {
                    readTimer = reactor.createTimer(config.readTimeout, () @safe nothrow {
                        onReadTimeout();
                    });
                }
                
                while (!request.isComplete() && state != ConnectionState.CLOSED)
                {
                    // BUG #2 FIX: Resize buffer if almost full (> 90%)
                    if (readPos >= readBuffer.length * 9 / 10)
                    {
                        size_t newSize = readBuffer.length * 2;

                        if (newSize > MAX_HEADER_SIZE)
                        {
                            // Request headers too large, reject with 431
                            // TODO: Send proper HTTP 431 response
                            state = ConnectionState.CLOSED;
                            return;
                        }

                        // Determine next buffer size from pool
                        BufferSize nextSize;
                        if (newSize <= 16 * 1024)
                            nextSize = BufferSize.MEDIUM;  // 16KB
                        else if (newSize <= 64 * 1024)
                            nextSize = BufferSize.LARGE;   // 64KB
                        else
                            nextSize = BufferSize.HUGE;    // 256KB

                        // Acquire new buffer and copy data
                        auto newBuffer = bufferPool.acquire(nextSize);
                        newBuffer[0 .. readPos] = readBuffer[0 .. readPos];

                        // Release old buffer
                        bufferPool.release(readBuffer);
                        readBuffer = newBuffer;
                    }

                    auto result = eventcoreRead(readBuffer[readPos .. $]);

                    switch (result.status)
                    {
                        case IOStatus.ok:
                            if (result.bytesRead > 0)
                            {
                                // Got data, advance position
                                readPos += result.bytesRead;
                                
                                // Try to parse what we have so far
                                request = HTTPRequest.parse(readBuffer[0 .. readPos]);
                                
                                if (request.hasError())
                                {
                                    // Parse error → close
                                    state = ConnectionState.CLOSED;
                                    return;
                                }
                                
                                // If complete, exit loop
                                if (request.isComplete())
                                    break;
                            }
                            else
                            {
                                // 0 bytes with ok = no data yet
                                yield();  // Let other fibers run
                            }
                            break;
                            
                        case IOStatus.wouldBlock:
                            // Socket not ready - NORMAL for non-blocking I/O
                            yield();  // Cooperative multitasking
                            break;
                            
                        case IOStatus.disconnected:
                            // Clean close by peer
                            state = ConnectionState.CLOSED;
                            return;
                            
                        case IOStatus.error:
                            // I/O error
                            state = ConnectionState.CLOSED;
                            return;
                        default:
                            // Unknown status - treat as error
                            state = ConnectionState.CLOSED;
                            return;
                    }
                }
                
                // Cancel read timer - request successfully received
                if (reactor !is null && readTimer != TimerID.invalid)
                {
                    reactor.cancelTimer(readTimer);
                    readTimer = TimerID.invalid;
                }
                
                // Request complete, verify no parse error
                if (request.hasError())
                {
                    state = ConnectionState.CLOSED;
                    return;
                }
                
                // ========================================
                // PROCESSING: Call handler
                // ========================================
                state = ConnectionState.PROCESSING;
                processRequest();  // Sets response
                
                // ========================================
                // WRITE LOOP: Handle partial responses
                // ========================================
                state = ConnectionState.WRITING_RESPONSE;
                
                // CRITICAL FIX 2: Start write timer at beginning of write phase
                if (reactor !is null && config !is null)
                {
                    writeTimer = reactor.createTimer(config.writeTimeout, () @safe nothrow {
                        onWriteTimeout();
                    });
                }
                
                while (writePos < writeBuffer.length && state != ConnectionState.CLOSED)
                {
                    auto result = eventcoreWrite(writeBuffer[writePos .. $]);
                    
                    switch (result.status)
                    {
                        case IOStatus.ok:
                            if (result.bytesWritten > 0)
                            {
                                // Wrote some data, advance
                                writePos += result.bytesWritten;
                                
                                // Check if all sent
                                if (writePos >= writeBuffer.length)
                                {
                                    // Success! All data sent
                                    break;  // Exit write loop
                                }
                            }
                            else
                            {
                                // 0 bytes with ok = socket buffer full
                                yield();  // Let other fibers run, try again
                            }
                            break;
                            
                        case IOStatus.wouldBlock:
                            // Socket not ready for write - NORMAL
                            yield();  // Cooperative multitasking
                            break;
                            
                        case IOStatus.disconnected:
                        case IOStatus.error:
                            // Connection closed or error during write
                            state = ConnectionState.CLOSED;
                            return;
                        default:
                            // Unknown status - treat as error
                            state = ConnectionState.CLOSED;
                            return;
                    }
                }
                
                // Cancel write timer - response successfully sent
                if (reactor !is null && writeTimer != TimerID.invalid)
                {
                    reactor.cancelTimer(writeTimer);
                    writeTimer = TimerID.invalid;
                }

                // BUG #5 FIX: Counter increment moved to resetConnection()
                // (No increment here - will happen in resetConnection() for keep-alive,
                //  or connection closes without needing the count)

                // ========================================
                // KEEP-ALIVE DECISION
                // ========================================
                
                // Check if client wants keep-alive
                bool clientWantsKeepAlive = request.shouldKeepAlive();
                
                // Check if we haven't exceeded max requests
                bool belowMaxRequests = (config is null) || 
                                       (requestsServed < config.maxRequestsPerConnection);
                
                if (clientWantsKeepAlive && belowMaxRequests)
                {
                    // ========================================
                    // KEEP-ALIVE: Reset and wait for next request
                    // ========================================
                    state = ConnectionState.KEEP_ALIVE;
                    
                    // Reset connection state for next request FIRST
                    resetConnection();
                    
                    // CRITICAL FIX 2: Start keep-alive timer AFTER reset
                    // Timer monitors idle time DURING keep-alive (waiting for next request)
                    // If created before resetConnection(), it gets cancelled immediately!
                    if (config !is null && reactor !is null)
                    {
                        keepAliveTimer = reactor.createTimer(
                            config.keepAliveTimeout,
                            &onKeepAliveTimeout
                        );
                    }
                    
                    // Loop continues - will read next request
                }
                else
                {
                    // Close connection (client requested close or max requests reached)
                    state = ConnectionState.CLOSED;
                    return;
                }
            }
            
        }
        catch (Exception e)
        {
            // Error during processing
            state = ConnectionState.CLOSED;
        }
        finally
        {
            // Always cleanup
            close();
        }
    }
}
