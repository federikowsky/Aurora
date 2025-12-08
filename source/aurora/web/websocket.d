/**
 * WebSocket Integration - High-Level WebSocket API for Aurora
 *
 * Module: aurora.web.websocket
 *
 * This module provides a clean, user-friendly API for WebSocket support in Aurora,
 * wrapping the Aurora-WebSocket library. It hides the complexity of connection
 * hijacking, handshake validation, and protocol details.
 *
 * Design Philosophy:
 * - Simple API: upgradeWebSocket() + WebSocket class
 * - Returns null on failure (let handler decide response - Aurora pattern)
 * - Destructor as safety net, but explicit close() recommended
 * - WebSocketConfig for advanced options (subprotocols, origin validation, etc.)
 *
 * Example (Echo Server):
 * ---
 * import aurora;
 * import aurora.web.websocket;
 *
 * app.get("/ws", (ref ctx) {
 *     auto ws = upgradeWebSocket(ctx);
 *     if (ws is null) {
 *         ctx.status(400).send("WebSocket upgrade failed");
 *         return;
 *     }
 *     scope(exit) ws.close();
 *
 *     while (ws.connected) {
 *         auto msg = ws.receive();
 *         if (msg.isNull) break;
 *         ws.send(msg.get.text);
 *     }
 * });
 * ---
 *
 * Example (Chat with Subprotocols):
 * ---
 * WebSocketConfig config;
 * config.subprotocols = ["chat.v1", "chat.v2"];
 * config.validateOrigin = (origin) => origin == "https://mysite.com";
 *
 * auto ws = upgradeWebSocket(ctx, config);
 * if (ws is null) {
 *     ctx.status(400).send("WebSocket upgrade failed");
 *     return;
 * }
 *
 * if (ws.protocol == "chat.v2") {
 *     // Use v2 protocol
 * }
 * ---
 *
 * Authors: Aurora Framework Contributors
 * License: MIT
 */
module aurora.web.websocket;

import aurora.web.context : Context;
import aurora.web.upgrade : HijackedConnection;

// Re-export commonly used types from Aurora-WebSocket
public import aurora_websocket : 
    MessageType, 
    CloseCode, 
    Message,
    WebSocketException,
    WebSocketClosedException;

// ============================================================================
// CONFIGURATION
// ============================================================================

/**
 * Configuration for WebSocket upgrade and connection.
 *
 * All fields are optional. Default values provide sensible behavior
 * for most use cases.
 */
struct WebSocketConfig {
    /// Subprotocols supported by the server (in order of preference).
    /// If client requests a matching protocol, it will be selected.
    /// Example: ["graphql-ws", "json"]
    string[] subprotocols;

    /// Origin validation callback. Return true to accept, false to reject.
    /// If null, all origins are accepted.
    /// Example: (origin) => origin == "https://trusted.com"
    bool delegate(string origin) @safe validateOrigin;

    /// Maximum frame size (default: 64KB)
    size_t maxFrameSize = 64 * 1024;

    /// Maximum message size after reassembly (default: 16MB)
    size_t maxMessageSize = 16 * 1024 * 1024;

    /// Internal read buffer size (default: 16KB)
    size_t bufferSize = 16 * 1024;

    /// Automatically respond to ping frames with pong (default: true)
    bool autoReplyPing = true;
}

// ============================================================================
// WEBSOCKET CLASS
// ============================================================================

/**
 * High-level WebSocket connection.
 *
 * Provides a simple, clean API for WebSocket communication:
 * - receive() - Get next message
 * - send() - Send text/binary data
 * - close() - Graceful close with optional code/reason
 * - connected - Check connection state
 *
 * Resource Management:
 * - Always call close() when done (use scope(exit) ws.close())
 * - Destructor will close if forgotten, but explicit close is better
 * - D's GC doesn't guarantee destructor timing
 *
 * Thread Safety:
 * - NOT thread-safe. Use one WebSocket per thread/fiber.
 */
class WebSocket {
    import aurora_websocket : WebSocketConnection;
    import std.typecons : Nullable;

    private WebSocketConnection _conn;
    private WebSocketAdapter _adapter;
    private string _protocol;
    private bool _closed = false;

    // Package constructor - use upgradeWebSocket() to create
    package this(
        WebSocketAdapter adapter,
        WebSocketConnection conn,
        string protocol
    ) @safe {
        _adapter = adapter;
        _conn = conn;
        _protocol = protocol;
    }

    ~this() {
        // Safety net: close if user forgot
        // Note: D destructors run at GC time (non-deterministic)
        // Always prefer explicit scope(exit) ws.close()
        if (!_closed) {
            closeInternal();
        }
    }

    // Internal close for destructor (non-@safe)
    private void closeInternal() nothrow {
        if (_closed) return;
        _closed = true;

        try {
            _conn.close(CloseCode.Normal, "");
        } catch (Exception) {
            // Ignore errors during close
        }

        if (_adapter !is null) {
            _adapter.close();
        }
    }

    /**
     * Receive the next message.
     *
     * Blocks until a message is received or connection closes.
     * Returns Nullable!Message.init (null) on connection close.
     *
     * Example:
     * ---
     * while (ws.connected) {
     *     auto msg = ws.receive();
     *     if (msg.isNull) break;
     *     
     *     if (msg.get.type == MessageType.Text) {
     *         writeln("Got: ", msg.get.text);
     *     }
     * }
     * ---
     */
    Nullable!Message receive() @safe {
        if (_closed) {
            return Nullable!Message.init;
        }

        try {
            auto msg = _conn.receive();
            return Nullable!Message(msg);
        } catch (WebSocketClosedException) {
            _closed = true;
            return Nullable!Message.init;
        } catch (WebSocketException) {
            _closed = true;
            return Nullable!Message.init;
        }
    }

    /**
     * Send a text message.
     *
     * Example:
     * ---
     * ws.send("Hello, WebSocket!");
     * ws.send(`{"type":"greeting","msg":"hi"}`);
     * ---
     */
    void send(string text) @safe {
        if (_closed) return;
        _conn.send(text);
    }

    /**
     * Send a binary message.
     *
     * Example:
     * ---
     * ubyte[] data = [0x01, 0x02, 0x03];
     * ws.sendBinary(data);
     * ---
     */
    void sendBinary(const(ubyte)[] data) @safe {
        if (_closed) return;
        _conn.send(data);  // WebSocketConnection.send() is overloaded for binary
    }

    /**
     * Send a ping frame (keepalive).
     *
     * The remote endpoint should respond with a pong.
     * Pong handling is automatic (autoReplyPing config).
     */
    void ping(const(ubyte)[] data = null) @safe {
        if (_closed) return;
        _conn.ping(data);
    }

    /**
     * Close the WebSocket connection gracefully.
     *
     * Sends a close frame with optional status code and reason.
     * Always call this when done with the WebSocket.
     *
     * Params:
     *   code = Close status code (default: Normal)
     *   reason = Human-readable close reason
     *
     * Example:
     * ---
     * ws.close();  // Normal close
     * ws.close(CloseCode.GoingAway, "Server shutting down");
     * ---
     */
    void close(CloseCode code = CloseCode.Normal, string reason = null) @safe nothrow {
        if (_closed) return;
        _closed = true;

        try {
            string reasonStr = reason is null ? "" : reason;
            _conn.close(code, reasonStr);
        } catch (Exception) {
            // Ignore errors during close
        }

        // Close underlying adapter
        if (_adapter !is null) {
            _adapter.close();
        }
    }

    /**
     * Check if the connection is still open.
     *
     * Returns false if:
     * - close() was called
     * - Remote endpoint closed connection
     * - Network error occurred
     */
    @property bool connected() @safe nothrow {
        if (_closed) return false;
        return _conn.connected;
    }

    /**
     * Get the negotiated subprotocol (if any).
     *
     * Returns null if no subprotocol was negotiated.
     *
     * Example:
     * ---
     * if (ws.protocol == "graphql-ws") {
     *     // Handle GraphQL over WebSocket
     * }
     * ---
     */
    @property string protocol() const @safe pure nothrow {
        return _protocol;
    }
}

// ============================================================================
// UPGRADE HELPER
// ============================================================================

/**
 * Upgrade an HTTP connection to WebSocket.
 *
 * This is the main entry point for WebSocket support. It:
 * 1. Validates the upgrade request (RFC 6455)
 * 2. Validates origin (if configured)
 * 3. Negotiates subprotocol (if configured)
 * 4. Hijacks the connection
 * 5. Sends the upgrade response
 * 6. Returns a ready-to-use WebSocket object
 *
 * Returns null if upgrade fails (invalid request, origin rejected, etc.)
 * The handler can then send an appropriate HTTP error response.
 *
 * Params:
 *   ctx = Aurora request context
 *   config = Optional configuration
 *
 * Returns:
 *   WebSocket object ready for communication, or null on failure
 *
 * Example:
 * ---
 * app.get("/ws", (ref ctx) {
 *     auto ws = upgradeWebSocket(ctx);
 *     if (ws is null) {
 *         ctx.status(400).send("WebSocket upgrade failed");
 *         return;
 *     }
 *     scope(exit) ws.close();
 *
 *     // Echo loop
 *     while (ws.connected) {
 *         auto msg = ws.receive();
 *         if (msg.isNull) break;
 *         ws.send(msg.get.text);
 *     }
 * });
 * ---
 */
WebSocket upgradeWebSocket(ref Context ctx, WebSocketConfig config = WebSocketConfig.init) @safe {
    import aurora_websocket : 
        validateUpgradeRequest, 
        buildUpgradeResponse,
        selectSubprotocol,
        WebSocketConnection;
    import aurora_websocket.connection : ConnectionMode;
    import WsConfigMod = aurora_websocket.connection;

    // Step 1: Check if this is a WebSocket upgrade request
    if (!ctx.isWebSocketUpgrade()) {
        return null;
    }

    // Step 2: Build headers map for validation (lowercase keys)
    string[string] headers;
    if (ctx.request !is null) {
        // Get required headers
        auto host = ctx.request.getHeader("host");
        if (host.length > 0) headers["host"] = host;
        
        auto upgrade = ctx.request.getHeader("upgrade");
        if (upgrade.length > 0) headers["upgrade"] = upgrade;
        
        auto connection = ctx.request.getHeader("connection");
        if (connection.length > 0) headers["connection"] = connection;
        
        auto key = ctx.request.getHeader("sec-websocket-key");
        if (key.length > 0) headers["sec-websocket-key"] = key;
        
        auto version_ = ctx.request.getHeader("sec-websocket-version");
        if (version_.length > 0) headers["sec-websocket-version"] = version_;
        
        auto protocol = ctx.request.getHeader("sec-websocket-protocol");
        if (protocol.length > 0) headers["sec-websocket-protocol"] = protocol;
        
        auto origin = ctx.request.getHeader("origin");
        if (origin.length > 0) headers["origin"] = origin;
    }

    // Step 3: Validate the upgrade request
    auto validation = validateUpgradeRequest("GET", headers);
    if (!validation.valid) {
        return null;
    }

    // Step 4: Validate origin (if configured)
    if (config.validateOrigin !is null) {
        auto origin = "origin" in headers;
        string originValue = origin !is null ? *origin : "";
        if (!config.validateOrigin(originValue)) {
            return null;  // Origin rejected
        }
    }

    // Step 5: Negotiate subprotocol
    string selectedProtocol = null;
    if (config.subprotocols.length > 0 && validation.protocols.length > 0) {
        selectedProtocol = selectSubprotocol(config.subprotocols, validation.protocols);
    }

    // Step 6: Hijack the connection and complete upgrade
    // Note: We return immediately from inner function to avoid default construction issues
    return doUpgrade(ctx, config, validation.clientKey, selectedProtocol);
}

// Internal helper to complete WebSocket upgrade after validation
private WebSocket doUpgrade(
    ref Context ctx, 
    ref WebSocketConfig config,
    string clientKey,
    string selectedProtocol
) @safe {
    import aurora_websocket : buildUpgradeResponse, WebSocketConnection;
    import aurora_websocket.connection : ConnectionMode;
    import WsConfigMod = aurora_websocket.connection;

    // Hijack the connection
    try {
        auto hijacked = ctx.hijack();
        
        // Send upgrade response
        try {
            auto response = buildUpgradeResponse(clientKey, selectedProtocol);
            hijacked.write(response);
        } catch (Exception) {
            hijacked.close();
            return null;
        }

        // Create adapter and WebSocket connection
        auto adapter = new WebSocketAdapter(hijacked, config.bufferSize);
        
        WsConfigMod.WebSocketConfig wsConfig;
        wsConfig.maxFrameSize = config.maxFrameSize;
        wsConfig.maxMessageSize = config.maxMessageSize;
        wsConfig.autoReplyPing = config.autoReplyPing;
        wsConfig.mode = ConnectionMode.server;

        try {
            auto conn = new WebSocketConnection(adapter, wsConfig);
            return new WebSocket(adapter, conn, selectedProtocol);
        } catch (Exception) {
            adapter.close();
            return null;
        }
    } catch (Exception) {
        return null;  // Hijack failed
    }
}

// ============================================================================
// INTERNAL: STREAM ADAPTER
// ============================================================================

/**
 * Internal adapter that bridges Aurora's HijackedConnection to 
 * Aurora-WebSocket's IWebSocketStream interface.
 *
 * This is package-private - users interact with WebSocket class only.
 */
package class WebSocketAdapter : IWebSocketStream {
    import aurora_websocket.stream : IWebSocketStream, WebSocketStreamException;

    private HijackedConnection _hijacked;
    private ubyte[] _readBuffer;
    private size_t _bufferSize;

    this(HijackedConnection hijacked, size_t bufferSize = 16 * 1024) @safe {
        _hijacked = hijacked;
        _bufferSize = bufferSize;
        _readBuffer = new ubyte[bufferSize];
    }

    /// Read available data into buffer (non-blocking)
    override ubyte[] read(ubyte[] buffer) @trusted {
        if (!_hijacked.isValid())
            throw new WebSocketStreamException("Connection closed");
        return _hijacked.read(buffer);
    }

    /// Read exactly n bytes (blocking)
    override ubyte[] readExactly(size_t n) @trusted {
        if (!_hijacked.isValid())
            throw new WebSocketStreamException("Connection closed");

        if (n > _bufferSize) {
            _readBuffer = new ubyte[n];
            _bufferSize = n;
        }

        auto conn = _hijacked.connection();
        size_t totalRead = 0;

        while (totalRead < n) {
            // First check if there's already buffered data
            auto available = cast(ubyte[]) conn.peek();
            if (available.length > 0) {
                auto toRead = (n - totalRead) < available.length
                    ? (n - totalRead)
                    : available.length;
                _readBuffer[totalRead .. totalRead + toRead] = available[0 .. toRead];
                conn.skip(toRead);
                totalRead += toRead;
            } else {
                // No buffered data - use blocking read to wait for data
                if (!conn.connected)
                    throw new WebSocketStreamException("Connection closed while reading");
                
                // Read at least 1 byte, up to remaining needed
                auto remaining = n - totalRead;
                conn.read(_readBuffer[totalRead .. totalRead + remaining]);
                totalRead = n; // read() fills the entire buffer or throws
            }
        }

        return _readBuffer[0 .. n].dup;
    }

    /// Write all data (blocking)
    override void write(const(ubyte)[] data) @trusted {
        if (!_hijacked.isValid())
            throw new WebSocketStreamException("Connection closed");
        _hijacked.write(data);
    }

    /// Flush buffered data
    override void flush() @trusted {
        if (!_hijacked.isValid())
            throw new WebSocketStreamException("Connection closed");
        _hijacked.connection().flush();
    }

    /// Check if connection is still open
    override @property bool connected() @safe nothrow {
        return _hijacked.isValid();
    }

    /// Close the connection
    void close() @safe nothrow {
        _hijacked.close();
    }
}

// Re-import IWebSocketStream for the adapter
private import aurora_websocket.stream : IWebSocketStream;
