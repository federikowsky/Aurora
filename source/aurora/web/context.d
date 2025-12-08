/**
 * Context - Request-scoped context object
 *
 * Package: aurora.web.context
 *
 * Features:
 * - Request/response pointers
 * - Helper methods (json, send, status)
 * - ContextStorage (small object optimization)
 * - Route parameters
 * - Protocol upgrade support (WebSocket/SSE)
 */
module aurora.web.context;

import aurora.http;
import aurora.web.router : PathParams;
import aurora.web.upgrade : HijackedConnection, StreamResponse;
import vibe.core.net : TCPConnection;

/**
 * ContextStorage - Key-value storage for middleware data sharing
 *
 * Uses small object optimization:
 * - First 4 entries stored inline (no allocation)
 * - Overflow to heap for > 4 entries
 */
struct ContextStorage
{
    enum MAX_INLINE_VALUES = 4;
    
    struct Entry
    {
        string key;
        void* value;
    }
    
    Entry[MAX_INLINE_VALUES] inlineEntries;
    Entry[] overflowEntries;
    uint count;
    
    /**
     * Get value by key
     * Returns T.init if key not found
     * 
     * Note: Only supports types that can be safely cast to/from void*:
     * - Integers (int, uint, size_t, etc.)
     * - Pointers
     * - Class references
     */
    T get(T)(string key) if (is(T : void*) || is(T == class) || __traits(isIntegral, T))
    {
        // Search inline entries first
        for (uint i = 0; i < count && i < MAX_INLINE_VALUES; i++)
        {
            if (inlineEntries[i].key == key)
            {
                static if (__traits(isIntegral, T))
                    return cast(T) cast(size_t) inlineEntries[i].value;
                else
                    return cast(T) inlineEntries[i].value;
            }
        }
        
        // Search overflow entries
        foreach (entry; overflowEntries)
        {
            if (entry.key == key)
            {
                static if (__traits(isIntegral, T))
                    return cast(T) cast(size_t) entry.value;
                else
                    return cast(T) entry.value;
            }
        }
        
        return T.init;
    }
    
    /**
     * Set value by key
     * Inline storage for first 4 entries, heap for overflow
     * 
     * Note: Only supports types that can be safely cast to/from void*
     */
    void set(T)(string key, T value) if (is(T : void*) || is(T == class) || __traits(isIntegral, T))
    {
        static if (__traits(isIntegral, T))
            auto storedValue = cast(void*) cast(size_t) value;
        else
            auto storedValue = cast(void*) value;
            
        if (count < MAX_INLINE_VALUES)
        {
            inlineEntries[count] = Entry(key, storedValue);
        }
        else
        {
            overflowEntries ~= Entry(key, storedValue);
        }
        count++;
    }
    
    /**
     * Check if key exists
     */
    bool has(string key)
    {
        // Search inline entries
        for (uint i = 0; i < count && i < MAX_INLINE_VALUES; i++)
        {
            if (inlineEntries[i].key == key)
            {
                return true;
            }
        }
        
        // Search overflow entries
        foreach (entry; overflowEntries)
        {
            if (entry.key == key)
            {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * Remove entry by key
     */
    void remove(string key)
    {
        // Search inline entries
        for (uint i = 0; i < count && i < MAX_INLINE_VALUES; i++)
        {
            if (inlineEntries[i].key == key)
            {
                // Shift remaining entries
                for (uint j = i; j < count - 1 && j < MAX_INLINE_VALUES - 1; j++)
                {
                    inlineEntries[j] = inlineEntries[j + 1];
                }
                count--;
                return;
            }
        }
        
        // Search overflow entries
        import std.algorithm : remove;
        foreach (idx, entry; overflowEntries)
        {
            if (entry.key == key)
            {
                overflowEntries = overflowEntries.remove(idx);
                count--;
                return;
            }
        }
    }
}

/**
 * Context - Request-scoped context object
 *
 * Holds request/response data and provides helper methods
 * for handlers and middleware.
 *
 * Protocol Upgrade Support:
 * - isUpgradeRequest(), isWebSocketUpgrade(), isSSERequest() for detection
 * - hijack() for WebSocket/protocol takeover
 * - streamResponse() for SSE/chunked streaming
 */
align(64) struct Context
{
    // Request data (read-only after parse)
    HTTPRequest* request;
    
    // Response builder (writable)
    HTTPResponse* response;
    
    // Route parameters (extracted from path)
    PathParams params;
    
    // Middleware storage (key-value)
    ContextStorage storage;
    
    // State
    bool responseSent;
    
    // Connection upgrade support (package access for server.d)
    package TCPConnection _rawConnection;
    private bool _hasRawConnection = false;  // Track if _rawConnection is set
    private bool _hijacked = false;

    // ========================================================================
    // PROTOCOL UPGRADE DETECTION (RFC 7230 compliant)
    // ========================================================================

    /**
     * Check if this is any kind of upgrade request.
     * RFC 7230: Connection header is a comma-separated list of tokens.
     *
     * Example: Connection: keep-alive, upgrade
     */
    bool isUpgradeRequest() const @safe
    {
        if (request is null)
            return false;
            
        auto conn = request.getHeader("connection");
        if (conn.length == 0)
            return false;

        // Parse comma-separated tokens (RFC 7230 compliant)
        import std.algorithm : splitter;
        import std.string : strip;
        import std.uni : toLower;
        
        foreach (token; conn.splitter(','))
        {
            if (token.strip.toLower == "upgrade")
                return true;
        }
        return false;
    }

    /**
     * Check specifically for WebSocket upgrade.
     * Returns true if Connection: upgrade AND Upgrade: websocket.
     */
    bool isWebSocketUpgrade() const @safe
    {
        if (!isUpgradeRequest())
            return false;
            
        auto upgrade = request.getHeader("upgrade");
        if (upgrade.length == 0)
            return false;
            
        import std.uni : toLower;
        return upgrade.toLower == "websocket";
    }

    /**
     * Check for SSE request (Accept: text/event-stream).
     *
     * NOTE: This is just a HINT, not a requirement. Many SSE clients
     * set this header, but you can use streamResponse() regardless.
     */
    bool isSSERequest() const @safe
    {
        if (request is null)
            return false;
            
        auto accept = request.getHeader("accept");
        if (accept.length == 0)
            return false;

        // Check if text/event-stream is in Accept header
        import std.algorithm : splitter, startsWith;
        import std.string : strip;
        import std.uni : toLower;
        
        foreach (mediaType; accept.splitter(','))
        {
            if (mediaType.strip.toLower.startsWith("text/event-stream"))
                return true;
        }
        return false;
    }

    // ========================================================================
    // CONNECTION CONTROL
    // ========================================================================

    /**
     * Hijack the connection for external protocol handling (WebSocket, etc.)
     *
     * OWNERSHIP: After calling hijack(), the external handler is FULLY
     * RESPONSIBLE for the connection, including closing it when done.
     * Aurora will NOT close the connection or send any response.
     *
     * Returns: HijackedConnection wrapper for raw socket access
     * Throws: Exception if already hijacked or connection unavailable
     *
     * Example:
     * ---
     * auto conn = ctx.hijack();
     * scope(exit) conn.close();  // MUST close when done
     * // ... use conn for WebSocket handshake etc.
     * ---
     */
    HijackedConnection hijack() @safe
    {
        if (_hijacked)
            throw new Exception("Connection already hijacked");
        if (!_hasRawConnection)
            throw new Exception("Raw connection not available");
            
        _hijacked = true;
        return HijackedConnection(_rawConnection);
    }

    /**
     * Get a streaming response writer for SSE or long-polling.
     * After calling this, Aurora will not send the normal response.
     *
     * Returns: StreamResponse writer for SSE/chunked streaming
     * Throws: Exception if already hijacked or connection unavailable
     *
     * Example:
     * ---
     * auto stream = ctx.streamResponse();
     * stream.beginSSE();
     * stream.sendEvent(`{"msg":"hello"}`, "message");
     * stream.close();
     * ---
     */
    StreamResponse streamResponse() @safe
    {
        if (_hijacked)
            throw new Exception("Connection already hijacked");
        if (!_hasRawConnection)
            throw new Exception("Raw connection not available");
            
        _hijacked = true; // Prevent normal response
        return StreamResponse(_rawConnection);
    }

    /**
     * Check if connection has been hijacked (by hijack() or streamResponse()).
     * Used by server to skip normal response handling.
     */
    bool isHijacked() const @safe nothrow
    {
        return _hijacked;
    }

    /**
     * Set the raw TCP connection for hijack support.
     * Called by the server runtime when handling a request.
     */
    void setRawConnection(TCPConnection conn) @safe nothrow
    {
        _rawConnection = conn;
        _hasRawConnection = true;
    }

    // ========================================================================
    // RESPONSE HELPERS (with hijack protection)
    // ========================================================================

    /**
     * Set response status code.
     * Throws if connection was hijacked.
     */
    Context status(int code) @trusted
    {
        if (_hijacked)
            throw new Exception("Cannot set status: connection hijacked");
        if (response !is null)
        {
            response.setStatus(code);
        }
        return this; // Enable chaining: ctx.status(200).send("OK")
    }
    
    /**
     * Set response header.
     * Throws if connection was hijacked.
     */
    Context header(string name, string value) @trusted
    {
        if (_hijacked)
            throw new Exception("Cannot set header: connection hijacked");
        if (response !is null)
        {
            response.setHeader(name, value);
        }
        return this; // Enable chaining
    }
    
    /**
     * Send text response.
     * Throws if connection was hijacked.
     */
    void send(string text) @trusted
    {
        if (_hijacked)
            throw new Exception("Cannot send response: connection hijacked");
        if (response !is null)
        {
            response.setBody(text);
        }
    }
    
    /**
     * Send JSON response.
     * Sets Content-Type and serializes data.
     * Throws if connection was hijacked.
     */
    void json(T)(T data) @trusted
    {
        if (_hijacked)
            throw new Exception("Cannot send JSON response: connection hijacked");
        if (response !is null)
        {
            response.setHeader("Content-Type", "application/json");
            
            // Use fastjsond native serialization
            import aurora.schema.json : serialize;
            response.setBody(serialize(data));
        }
    }
}
