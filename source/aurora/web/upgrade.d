/**
 * Protocol Upgrade Support - WebSocket/SSE/Streaming Hooks
 *
 * Package: aurora.web.upgrade
 *
 * Provides minimal hooks for external protocol libraries to integrate with Aurora:
 * - HijackedConnection: Raw socket access for WebSocket libraries
 * - StreamResponse: SSE and chunked streaming support
 *
 * Design Philosophy:
 * Aurora does NOT implement WebSocket protocol directly.
 * Instead, it provides hooks so external libraries can take over connections.
 * This keeps the core lean and lets users choose their preferred WebSocket library.
 *
 * Pattern inspired by:
 * - Go: net/http.Hijacker
 * - Node/Fastify: req.socket access
 * - Express: res.socket access
 */
module aurora.web.upgrade;

import vibe.core.net : TCPConnection;

// ============================================================================
// HIJACKED CONNECTION (for WebSocket, HTTP/2, etc.)
// ============================================================================

/**
 * A hijacked connection for external protocol handlers.
 *
 * OWNERSHIP SEMANTICS (Go-style):
 * After calling ctx.hijack(), the external handler is FULLY RESPONSIBLE for:
 * - Reading/writing to the connection
 * - Closing the connection when done (call close())
 *
 * Aurora will NOT close the connection automatically after hijack().
 *
 * Example:
 * ---
 * app.get("/ws", (ref ctx) {
 *     auto conn = ctx.hijack();
 *     scope(exit) conn.close();  // MUST close when done
 *
 *     // Use conn.fd() for libraries that need file descriptor
 *     // Or use conn.connection() for vibe-d's TCPConnection API
 *     // Or use conn.read()/conn.write() for direct I/O
 * });
 * ---
 */
struct HijackedConnection {
    private TCPConnection _connection;
    private bool _valid = true;

    @disable this();

    package this(TCPConnection conn) @safe nothrow {
        _connection = conn;
    }

    /**
     * Get the underlying file descriptor for external library integration.
     * Use this to pass the fd to WebSocket libraries, etc.
     *
     * Returns: Raw file descriptor (can be used with external libraries)
     */
    int fd() @trusted {
        if (!_valid)
            throw new ConnectionHijackedException("Connection already closed/released");
        return _connection.fd;
    }

    /**
     * Get the underlying TCPConnection for direct vibe-d usage.
     * Use this for full access to vibe-d's TCPConnection API.
     */
    TCPConnection connection() @safe {
        if (!_valid)
            throw new ConnectionHijackedException("Connection already closed/released");
        return _connection;
    }

    /**
     * Read raw bytes from the connection.
     * Returns: Slice of buffer filled with data, or empty if no data available.
     */
    ubyte[] read(ubyte[] buffer) @trusted {
        if (!_valid)
            throw new ConnectionHijackedException("Connection already closed/released");

        auto available = cast(ubyte[]) _connection.peek();
        if (available.length == 0)
            return null;

        auto toRead = available.length < buffer.length ? available.length : buffer.length;
        buffer[0..toRead] = available[0..toRead];
        _connection.skip(toRead);
        return buffer[0..toRead];
    }

    /**
     * Write raw bytes to the connection.
     */
    void write(const(ubyte)[] data) @trusted {
        if (!_valid)
            throw new ConnectionHijackedException("Connection already closed/released");
        _connection.write(data);
    }

    /**
     * Write raw string to the connection.
     */
    void write(string data) @trusted {
        write(cast(const(ubyte)[]) data);
    }

    /**
     * Check if connection is still valid and open.
     */
    bool isValid() const @safe nothrow {
        if (!_valid)
            return false;
        try {
            return _connection.connected;
        }
        catch (Exception) {
            return false;
        }
    }

    /**
     * Close the connection. MUST be called when done.
     *
     * After hijack(), Aurora does NOT close the connection automatically.
     * The external handler is responsible for closing.
     */
    void close() @trusted nothrow {
        if (_valid) {
            try {
                if (_connection.connected)
                    _connection.close();
            }
            catch (Exception) {
                // Ignore close errors
            }
        }
        _valid = false;
    }

    /**
     * Release without closing (for connection pooling scenarios).
     * Use with caution - connection state is undefined after release.
     */
    void release() @safe nothrow {
        _valid = false;
    }
}

// ============================================================================
// STREAM RESPONSE (for SSE, chunked streaming)
// ============================================================================

/**
 * A streaming response writer for SSE and chunked transfer.
 * Writes directly to socket without application-level buffering.
 *
 * BUFFERING:
 * For SSE through reverse proxies (nginx, etc.), the X-Accel-Buffering: no
 * header is sent by default to prevent proxy buffering.
 *
 * API LEVELS:
 * - send(data)             → Simplest: just sends "data: <payload>\n\n"
 * - sendEvent(data,evt,id) → Full SSE control with event type and id
 * - sendRaw(bytes)         → Complete control, no framing added
 * - sendComment(text)      → Keep-alive pings (ignored by clients)
 * - setRetry(ms)           → Set reconnection interval for clients
 *
 * Example (SSE - simple):
 * ---
 * app.get("/events", (ref ctx) {
 *     auto stream = ctx.streamResponse();
 *     stream.beginSSE();
 *     
 *     foreach (i; 0..10) {
 *         if (!stream.isOpen()) break;
 *         stream.send(`{"count":` ~ i.to!string ~ `}`);
 *         Thread.sleep(1.seconds);
 *     }
 *     stream.close();
 * });
 * ---
 *
 * Example (SSE - with event types):
 * ---
 * stream.sendEvent(`{"user":"joined"}`, "presence", "evt-1");
 * stream.sendEvent(`{"msg":"hello"}`, "message", "evt-2");
 * ---
 *
 * Example (SSE - raw control):
 * ---
 * stream.beginSSE();
 * stream.sendRaw("event: custom\nid: 123\ndata: raw format\n\n");
 * ---
 */
struct StreamResponse {
    private TCPConnection _connection;
    private bool _headersSent = false;
    private bool _closed = false;

    @disable this();

    package this(TCPConnection conn) @safe nothrow {
        _connection = conn;
    }

    /**
     * Begin SSE response with proper headers.
     * Includes X-Accel-Buffering: no to prevent nginx/proxy buffering.
     *
     * Params:
     *   extraHeaders = Additional headers to include
     */
    void beginSSE(string[string] extraHeaders = null) @trusted {
        if (_headersSent)
            throw new StreamResponseException("Headers already sent");

        string response = "HTTP/1.1 200 OK\r\n";
        response ~= "Content-Type: text/event-stream\r\n";
        response ~= "Cache-Control: no-cache\r\n";
        response ~= "Connection: keep-alive\r\n";
        response ~= "X-Accel-Buffering: no\r\n"; // Prevent nginx buffering

        foreach (name, value; extraHeaders) {
            response ~= name ~ ": " ~ value ~ "\r\n";
        }
        response ~= "\r\n";

        _connection.write(cast(const(ubyte)[]) response);
        _headersSent = true;
    }

    /**
     * Begin a chunked transfer response.
     *
     * Params:
     *   contentType = MIME type for the response
     *   extraHeaders = Additional headers to include
     */
    void beginChunked(string contentType = "application/octet-stream",
                      string[string] extraHeaders = null) @trusted {
        if (_headersSent)
            throw new StreamResponseException("Headers already sent");

        string response = "HTTP/1.1 200 OK\r\n";
        response ~= "Content-Type: " ~ contentType ~ "\r\n";
        response ~= "Transfer-Encoding: chunked\r\n";
        response ~= "Connection: keep-alive\r\n";

        foreach (name, value; extraHeaders) {
            response ~= name ~ ": " ~ value ~ "\r\n";
        }
        response ~= "\r\n";

        _connection.write(cast(const(ubyte)[]) response);
        _headersSent = true;
    }

    /**
     * Send an SSE event with optional event type and id.
     * Auto-calls beginSSE() if headers not yet sent.
     *
     * Full control over SSE format. For simpler usage, see send() variants.
     *
     * Params:
     *   data = Event data (can be multi-line, will be properly formatted)
     *   event = Optional event type name (for client-side addEventListener)
     *   id = Optional event ID (for Last-Event-ID reconnection)
     *
     * Example:
     * ---
     * stream.sendEvent(`{"status":"ok"}`, "update", "msg-123");
     * // Produces: event: update\nid: msg-123\ndata: {"status":"ok"}\n\n
     * ---
     */
    void sendEvent(string data, string event = null, string id = null) @trusted {
        if (!_headersSent)
            beginSSE();

        if (_closed)
            throw new StreamResponseException("Stream closed");

        string message;

        if (id.length)
            message ~= "id: " ~ id ~ "\n";

        if (event.length)
            message ~= "event: " ~ event ~ "\n";

        // Handle multi-line data (SSE spec: each line needs "data: " prefix)
        import std.algorithm : splitter;
        foreach (line; data.splitter('\n')) {
            message ~= "data: " ~ line ~ "\n";
        }
        message ~= "\n"; // End of event

        _connection.write(cast(const(ubyte)[]) message);
    }

    /**
     * Send SSE data field only (simplest form).
     * Auto-calls beginSSE() if headers not yet sent.
     *
     * Equivalent to: "data: <payload>\n\n"
     *
     * Example:
     * ---
     * stream.send(`{"msg":"hello"}`);
     * // Produces: data: {"msg":"hello"}\n\n
     * ---
     */
    void send(string data) @trusted {
        sendEvent(data, null, null);
    }

    /**
     * Send raw bytes without any SSE framing.
     * Use this for complete control over the wire format.
     * Does NOT auto-call beginSSE() - you must send headers yourself.
     *
     * Example:
     * ---
     * stream.beginSSE();
     * stream.sendRaw("event: custom\ndata: raw\n\n");
     * ---
     */
    void sendRaw(const(ubyte)[] data) @trusted {
        if (_closed)
            throw new StreamResponseException("Stream closed");
        _connection.write(data);
    }

    /// ditto
    void sendRaw(string data) @trusted {
        sendRaw(cast(const(ubyte)[]) data);
    }

    /**
     * Send a comment (for keep-alive pings).
     * SSE comments start with ":" and are ignored by clients.
     * Auto-calls beginSSE() if headers not yet sent.
     *
     * Example:
     * ---
     * stream.sendComment("ping");  // Produces: :ping\n\n
     * stream.sendComment();        // Produces: :\n\n
     * ---
     */
    void sendComment(string comment = "") @trusted {
        if (!_headersSent)
            beginSSE();

        if (_closed)
            throw new StreamResponseException("Stream closed");

        _connection.write(cast(const(ubyte)[])(":" ~ comment ~ "\n\n"));
    }

    /**
     * Set the reconnection time for SSE clients.
     * Tells the browser how many milliseconds to wait before reconnecting
     * if the connection is lost.
     *
     * Auto-calls beginSSE() if headers not yet sent.
     *
     * Example:
     * ---
     * stream.setRetry(3000);  // Reconnect after 3 seconds
     * // Produces: retry: 3000\n\n
     * ---
     */
    void setRetry(uint milliseconds) @trusted {
        if (!_headersSent)
            beginSSE();

        if (_closed)
            throw new StreamResponseException("Stream closed");

        import std.conv : to;
        _connection.write(cast(const(ubyte)[])("retry: " ~ milliseconds.to!string ~ "\n\n"));
    }

    /**
     * Flush the connection buffer to ensure data is sent immediately.
     * Useful for SSE where you want events delivered without delay.
     */
    void flush() @trusted {
        if (_closed)
            throw new StreamResponseException("Stream closed");
        _connection.flush();
    }

    /**
     * Send a chunk (for chunked transfer encoding).
     * Formats data with chunk size header per HTTP/1.1 spec.
     */
    void sendChunk(const(ubyte)[] data) @trusted {
        import std.format : format;

        if (_closed)
            throw new StreamResponseException("Stream closed");

        string header = format("%x\r\n", data.length);
        _connection.write(cast(const(ubyte)[]) header);
        _connection.write(data);
        _connection.write(cast(const(ubyte)[]) "\r\n");
    }

    /**
     * Send a string chunk (for chunked transfer encoding).
     */
    void sendChunk(string data) @trusted {
        sendChunk(cast(const(ubyte)[]) data);
    }

    /**
     * End chunked transfer (sends final 0-length chunk).
     * Call this when done sending chunks.
     */
    void endChunked() @trusted {
        if (_closed)
            return;
        _connection.write(cast(const(ubyte)[]) "0\r\n\r\n");
        _closed = true;
    }

    /**
     * Check if stream is still open.
     * Returns false if closed or connection lost.
     */
    bool isOpen() const @safe nothrow {
        if (_closed)
            return false;
        try {
            return _connection.connected;
        }
        catch (Exception) {
            return false;
        }
    }

    /**
     * Mark stream as closed (does NOT close the socket).
     * Use for graceful end of streaming while keeping connection alive.
     */
    void close() @safe nothrow {
        _closed = true;
    }

    /**
     * Close the stream AND the underlying connection.
     * Use when you want to terminate the connection completely.
     */
    void closeConnection() @trusted nothrow {
        _closed = true;
        try {
            if (_connection.connected)
                _connection.close();
        }
        catch (Exception) {
            // Ignore close errors
        }
    }
}

// ============================================================================
// EXCEPTIONS
// ============================================================================

/**
 * Exception thrown when operations are attempted on an invalid hijacked connection.
 */
class ConnectionHijackedException : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
        super(msg, file, line);
    }
}

/**
 * Exception thrown for stream response errors.
 */
class StreamResponseException : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
        super(msg, file, line);
    }
}

// ============================================================================
// WEBSOCKET INTEGRATION
// ============================================================================
//
// For WebSocket support, use aurora.web.websocket module which provides
// a high-level API:
//
// ---
// import aurora.web.websocket;
//
// app.get("/ws", (ref ctx) {
//     auto ws = upgradeWebSocket(ctx);
//     if (ws is null) {
//         ctx.status(400).send("WebSocket upgrade failed");
//         return;
//     }
//     scope(exit) ws.close();
//
//     while (ws.connected) {
//         auto msg = ws.receive();
//         if (msg.isNull) break;
//         ws.send(msg.get.text);
//     }
// });
// ---
//
// See aurora.web.websocket for the full API documentation.
