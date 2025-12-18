/**
 * Aurora HTTP Server - Fiber-based Architecture
 *
 * Architecture: vibe-core fiber pool with async I/O
 * 
 * Platform-specific optimizations:
 * - Linux/FreeBSD: SO_REUSEPORT with N worker threads (kernel load balancing)
 * - macOS/Windows: Single event loop with fiber pool
 *
 * All platforms use non-blocking I/O with fiber scheduling for high concurrency.
 * This provides 10-100x better performance under load compared to blocking I/O.
 */
module aurora.runtime.server;

// ============================================================================
// IMPORTS
// ============================================================================

// vibe-core networking
import vibe.core.net : listenTCP, TCPListener, TCPConnection, TCPListenOptions;
import vibe.core.core : runTask, runEventLoop, exitEventLoop, yield, sleep;
import vibe.core.log : logInfo, logWarn, logError, logDebug;

// Aurora modules
import aurora.http : HTTPRequest, HTTPResponse;
import aurora.web.router : Router, Match, PathParams;
import aurora.web.context : Context;
import aurora.web.middleware : MiddlewarePipeline;
import aurora.http.util : getStatusText, getStatusLine, buildResponseInto;
import aurora.mem.pool : BufferPool, BufferSize;
import aurora.runtime.hooks : ServerHooks, TypeErasedHandler, StartHook, StopHook, 
                               ErrorHook, RequestHook, ResponseHook, ExceptionHandler;

// Wire
import wire.types : isWhitespace, trimWhitespace, findHeaderEnd, StringView;

// Worker pool for multi-threaded mode (Linux/FreeBSD only)
version(linux)
{
    import aurora.runtime.worker : WorkerPool;
    private enum USE_WORKER_POOL = true;
}
else version(FreeBSD)
{
    import aurora.runtime.worker : WorkerPool;
    private enum USE_WORKER_POOL = true;
}
else
{
    private enum USE_WORKER_POOL = false;
}

// Standard library
import core.atomic;
import core.thread : Fiber;
import core.time;
import core.stdc.string : memcpy, memchr;
import std.stdio : stderr, writeln, writefln;
import std.conv : to;
import std.format : format;

// ============================================================================
// PLATFORM DETECTION
// ============================================================================

version(linux) {
    private enum PLATFORM = "linux";
    private enum SUPPORT_REUSEPORT = true;
} else version(FreeBSD) {
    private enum PLATFORM = "freebsd";
    private enum SUPPORT_REUSEPORT = true;
} else version(OSX) {
    private enum PLATFORM = "macos";
    private enum SUPPORT_REUSEPORT = false;  // macOS reuseport doesn't load balance
} else version(Windows) {
    private enum PLATFORM = "windows";
    private enum SUPPORT_REUSEPORT = false;
} else {
    private enum PLATFORM = "other";
    private enum SUPPORT_REUSEPORT = false;
}

// ============================================================================
// COMPILE-TIME UTILITIES
// ============================================================================

/// Fast unsigned integer to decimal string into buffer (no GC)
/// Returns slice of buffer containing the result
pragma(inline, true)
private char[] uintToStr(char[] buf, ulong val) @nogc nothrow pure @safe
{
    if (val == 0)
    {
        buf[$ - 1] = '0';
        return buf[$ - 1 .. $];
    }
    
    size_t pos = buf.length;
    while (val > 0)
    {
        buf[--pos] = cast(char)('0' + val % 10);
        val /= 10;
    }
    return buf[pos .. $];
}

/// Fast min without branching ambiguity
pragma(inline, true)
private T fastMin(T)(T a, T b) @nogc nothrow pure @safe
{
    return a < b ? a : b;
}

pragma(inline, true)
private ulong fnv1a64(const(ubyte)[] data) @nogc nothrow @safe
{
    ulong h = 1469598103934665603UL;
    foreach (b; data)
    {
        h ^= b;
        h *= 1099511628211UL;
    }
    return h;
}

// ============================================================================
// PRE-COMPUTED RESPONSE TEMPLATES (Zero-GC)
// ============================================================================

/// Static 503 response prefix (before Retry-After value)
private immutable ubyte[] RESPONSE_503_PREFIX = cast(immutable ubyte[])
    ("HTTP/1.1 503 Service Unavailable\r\n" ~
    "Content-Type: application/json\r\n" ~
    "Retry-After: ");

/// Static 503 response middle (after Retry-After, before Content-Length)
private immutable ubyte[] RESPONSE_503_MIDDLE = cast(immutable ubyte[])
    ("\r\nConnection: close\r\n" ~
    "Content-Length: ");

/// Static 503 body
private immutable string BODY_503 = `{"error":"Service temporarily unavailable","reason":"server_overloaded"}`;

/// Static 503 body length as string (compile-time computed)
private immutable string BODY_503_LEN_STR = "69";  // BODY_503.length

/// Static error response template components
private immutable ubyte[] ERROR_PREFIX = cast(immutable ubyte[])"HTTP/1.1 ";
private immutable ubyte[] ERROR_MIDDLE = cast(immutable ubyte[])
    ("\r\nContent-Type: application/json\r\n" ~
    "Content-Length: ");
private immutable ubyte[] ERROR_SERVER = cast(immutable ubyte[])
    "\r\nServer: Aurora/0.1\r\n\r\n";
private immutable ubyte[] ERROR_BODY_PREFIX = cast(immutable ubyte[])`{"error":"`;
private immutable ubyte[] ERROR_BODY_SUFFIX = cast(immutable ubyte[])`"}`;

/// Connection header values
private immutable ubyte[] CONN_KEEPALIVE = cast(immutable ubyte[])"\r\nConnection: keep-alive";
private immutable ubyte[] CONN_CLOSE = cast(immutable ubyte[])"\r\nConnection: close";

// ============================================================================
// SERVER CONFIGURATION
// ============================================================================

/// Behavior when server is overloaded
enum OverloadBehavior
{
    /// Return HTTP 503 Service Unavailable with Retry-After header
    reject503,
    
    /// Close connection immediately without response (faster but less graceful)
    closeConnection,
    
    /// Queue request if possible (bounded, may still reject)
    queueRequest
}

/// Server configuration (unchanged API from blocking version)
struct ServerConfig
{
    string host = "0.0.0.0";
    ushort port = 8080;
    uint numWorkers = 0;  // 0 = auto-detect (used for reusePort mode)
    uint connectionQueueSize = 4096;  // Not directly used in fiber mode
    uint listenBacklog = 1024;
    bool debugMode = false;
    
    // === Security Limits (Production Ready) ===
    
    /// Maximum header size in bytes (default 64KB, prevents header DoS)
    uint maxHeaderSize = 64 * 1024;
    
    /// Maximum body size in bytes (default 10MB, prevents memory exhaustion)
    size_t maxBodySize = 10 * 1024 * 1024;
    
    /// Read timeout - max time to wait for client data (prevents slowloris)
    Duration readTimeout = 30.seconds;
    
    /// Write timeout - max time to send response
    Duration writeTimeout = 30.seconds;
    
    /// Keep-alive timeout - max idle time before closing connection
    Duration keepAliveTimeout = 120.seconds;
    
    /// Maximum requests per connection (0 = unlimited)
    uint maxRequestsPerConnection = 1000;
    
    // === Connection Limits & Backpressure (Enterprise) ===
    
    /// Maximum concurrent connections (0 = unlimited, NOT recommended for production)
    uint maxConnections = 10_000;
    
    /// High water mark - start rejecting new connections when this % of maxConnections is reached
    float connectionHighWater = 0.8;
    
    /// Low water mark - resume accepting connections when below this % of maxConnections
    float connectionLowWater = 0.6;
    
    /// Maximum in-flight requests per worker (0 = unlimited)
    uint maxInFlightRequests = 1000;
    
    /// Behavior when server is overloaded
    OverloadBehavior overloadBehavior = OverloadBehavior.reject503;
    
    /// Retry-After header value in seconds (for 503 responses)
    uint retryAfterSeconds = 5;
    
    // Pre-computed thresholds (computed once at config time)
    private uint _highWaterMark;
    private uint _lowWaterMark;
    
    static ServerConfig defaults() @safe nothrow
    {
        return ServerConfig.init;
    }
    
    uint effectiveWorkers() const @safe nothrow
    {
        if (numWorkers > 0) return numWorkers;
        try
        {
            import std.parallelism : totalCPUs;
            return totalCPUs > 0 ? totalCPUs : 4;
        }
        catch (Exception) { return 4; }
    }
    
    /// Pre-compute thresholds for faster runtime checks
    void precomputeThresholds() @safe nothrow
    {
        _highWaterMark = cast(uint)(maxConnections * connectionHighWater);
        _lowWaterMark = cast(uint)(maxConnections * connectionLowWater);
    }
    
    /// Get pre-computed high water mark
    pragma(inline, true)
    uint highWaterMark() const @safe nothrow pure
    {
        return _highWaterMark;
    }
    
    /// Get pre-computed low water mark
    pragma(inline, true)
    uint lowWaterMark() const @safe nothrow pure
    {
        return _lowWaterMark;
    }
}

// ============================================================================
// RESPONSE WRITER (Fiber-compatible)
// ============================================================================

/// Response writer that writes directly to TCPConnection
struct ResponseWriter
{
    private TCPConnection conn;
    private bool headersSent;
    private shared(bool)* shutdownFlag;  // Reference to server shutdown flag
    
    @disable this();
    
    pragma(inline, true)
    this(TCPConnection c, shared(bool)* shutdown = null) @safe nothrow
    {
        conn = c;
        headersSent = false;
        shutdownFlag = shutdown;
    }
    
    /// Write a complete HTTP response
    void write(int statusCode, string contentType, const(ubyte)[] body_, bool keepAlive = true) @trusted
    {
        if (headersSent) return;
        if (shutdownFlag !is null && atomicLoad(*shutdownFlag)) return;
        headersSent = true;
        
        // Stack buffer for small responses
        enum STACK_SIZE = 4096;
        if (body_.length + 256 <= STACK_SIZE)
        {
            ubyte[STACK_SIZE] stackBuf = void;
            auto len = buildResponseInto(stackBuf[], statusCode, contentType,
                                         cast(string)body_, keepAlive);
            if (len > 0)
            {
                conn.write(stackBuf[0..len]);
                return;
            }
        }
        
        // Heap fallback for large responses
        auto heapBuf = new ubyte[body_.length + 512];
        auto len = buildResponseInto(heapBuf, statusCode, contentType,
                                     cast(string)body_, keepAlive);
        if (len > 0)
            conn.write(heapBuf[0..len]);
    }
    
    /// Write a complete HTTP response (string version)
    pragma(inline, true)
    void write(int statusCode, string contentType, string body_, bool keepAlive = true) @safe
    {
        write(statusCode, contentType, cast(const(ubyte)[])body_, keepAlive);
    }
    
    /// Write JSON response
    pragma(inline, true)
    void writeJson(int statusCode, string json) @safe
    {
        write(statusCode, "application/json", json);
    }
    
    /// Write error response (zero-GC path)
    void writeError(int statusCode, string message, bool keepAlive = false) @trusted nothrow
    {
        if (headersSent) return;
        try
        {
            headersSent = true;
            ubyte[512] buf = void;
            auto len = buildErrorResponseInto(buf[], statusCode, message, keepAlive);
            if (len > 0)
                conn.write(buf[0..len]);
        }
        catch (Exception) {}
    }
    
    pragma(inline, true)
    @property bool wasSent() const @safe nothrow pure { return headersSent; }
}

/// Build error response into buffer (zero-GC)
private size_t buildErrorResponseInto(ubyte[] buf, int statusCode, string message, bool keepAlive) @nogc nothrow @trusted
{
    if (buf.length < 256) return 0;
    
    size_t pos = 0;
    
    // "HTTP/1.1 "
    buf[pos..pos+9] = ERROR_PREFIX[0..9];
    pos += 9;
    
    // Status code (3 digits)
    buf[pos++] = cast(ubyte)('0' + statusCode / 100);
    buf[pos++] = cast(ubyte)('0' + (statusCode / 10) % 10);
    buf[pos++] = cast(ubyte)('0' + statusCode % 10);
    buf[pos++] = ' ';
    
    // Status text
    auto statusText = getStatusText(statusCode);
    if (pos + statusText.length >= buf.length) return 0;
    buf[pos..pos+statusText.length] = cast(const(ubyte)[])statusText[];
    pos += statusText.length;
    
    // Headers middle section
    if (pos + ERROR_MIDDLE.length >= buf.length) return 0;
    buf[pos..pos+ERROR_MIDDLE.length] = ERROR_MIDDLE[];
    pos += ERROR_MIDDLE.length;
    
    // Content-Length value: body is {"error":"<message>"}
    auto bodyLen = ERROR_BODY_PREFIX.length + message.length + ERROR_BODY_SUFFIX.length;
    char[20] lenBuf;
    auto lenStr = uintToStr(lenBuf[], bodyLen);
    if (pos + lenStr.length >= buf.length) return 0;
    buf[pos..pos+lenStr.length] = cast(const(ubyte)[])lenStr[];
    pos += lenStr.length;
    
    // Connection header
    auto connHdr = keepAlive ? CONN_KEEPALIVE : CONN_CLOSE;
    if (pos + connHdr.length >= buf.length) return 0;
    buf[pos..pos+connHdr.length] = connHdr[];
    pos += connHdr.length;
    
    // Server header and blank line
    if (pos + ERROR_SERVER.length >= buf.length) return 0;
    buf[pos..pos+ERROR_SERVER.length] = ERROR_SERVER[];
    pos += ERROR_SERVER.length;
    
    // Body
    if (pos + bodyLen >= buf.length) return 0;
    buf[pos..pos+ERROR_BODY_PREFIX.length] = ERROR_BODY_PREFIX[];
    pos += ERROR_BODY_PREFIX.length;
    buf[pos..pos+message.length] = cast(const(ubyte)[])message[];
    pos += message.length;
    buf[pos..pos+ERROR_BODY_SUFFIX.length] = ERROR_BODY_SUFFIX[];
    pos += ERROR_BODY_SUFFIX.length;
    
    return pos;
}

// ============================================================================
// LEGACY RESPONSE BUFFER (for simple handler mode compatibility)
// ============================================================================

/// Response buffer for simple handler mode (legacy API compatibility)
struct ResponseBuffer
{
    private ubyte[] data;
    private bool built;
    private bool keepAlive_ = true;  // Default: keep-alive
    
    /// Set keep-alive flag before calling handler
    pragma(inline, true)
    void setKeepAlive(bool value) @safe nothrow pure
    {
        keepAlive_ = value;
    }
    
    void write(int statusCode, string contentType, const(ubyte)[] body_) @trusted
    {
        if (built) return;
        built = true;
        
        auto bufSize = body_.length + 512;
        data = new ubyte[bufSize];
        
        auto len = buildResponseInto(data, statusCode, contentType, cast(string)body_, keepAlive_);
        
        if (len > 0)
            data = data[0..len];
        else
            data = null;
    }
    
    pragma(inline, true)
    void write(int statusCode, string contentType, string body_) @trusted
    {
        write(statusCode, contentType, cast(const(ubyte)[])body_);
    }
    
    pragma(inline, true)
    void writeJson(int statusCode, string json) @safe
    {
        write(statusCode, "application/json", json);
    }
    
    pragma(inline, true)
    ubyte[] getData() @safe nothrow pure
    {
        return data;
    }
}

// ============================================================================
// REQUEST HANDLER TYPES
// ============================================================================

/// Request handler delegate type (legacy compatibility)
alias RequestHandler = void delegate(scope HTTPRequest* request, scope ResponseBuffer writer) @safe;

// ============================================================================
// FAST HEADER END SEARCH
// ============================================================================

// ============================================================================
// SMALL HTTP PARSING HELPERS (no allocations)
// ============================================================================

// Returns true iff Transfer-Encoding consists only of "chunked" tokens (case-insensitive).
private bool isChunkedOnly(const(char)[] te) @nogc nothrow pure @safe
{
    bool sawChunked = false;
    size_t i = 0;
    while (i < te.length)
    {
        // Skip separators/whitespace
        while (i < te.length && (te[i] == ',' || isWhitespace(te[i])))
            i++;
        if (i >= te.length) break;

        auto start = i;
        while (i < te.length && te[i] != ',')
            i++;
        auto token = trimWhitespace(te[start .. i]);
        if (token.length == 0)
            continue;
        // Use StringView.equalsIgnoreCase() for comparison
        auto tokenView = StringView(token);
        if (!tokenView.equalsIgnoreCase("chunked"))
            return false;
        sawChunked = true;
    }
    return sawChunked;
}

private void drainReadableNow(TCPConnection conn, size_t maxBytes = 256 * 1024) @trusted nothrow
{
    size_t drained = 0;
    while (drained < maxBytes)
    {
        ubyte[] chunk;
        try { chunk = cast(ubyte[])conn.peek(); }
        catch (Exception) { return; }

        if (chunk.length == 0)
            return;

        auto toSkip = chunk.length;
        if (drained + toSkip > maxBytes)
            toSkip = maxBytes - drained;

        try { conn.skip(toSkip); }
        catch (Exception) { return; }

        drained += toSkip;
    }
}

// Best-effort drain to avoid abortive close (RST) when rejecting a request.
// Waits for additional in-flight bytes up to `waitTimeout` before giving up.
private void drainForClose(TCPConnection conn, Duration waitTimeout, size_t maxBytes = 256 * 1024) @trusted
{
    // This is only used on error paths where the connection is about to be closed.
    // Best-effort: shorten timeout while draining; no need to restore.
    try { conn.readTimeout = waitTimeout; }
    catch (Exception) {}

    size_t drained = 0;
    while (drained < maxBytes)
    {
        ubyte[] chunk;
        try { chunk = cast(ubyte[])conn.peek(); }
        catch (Exception) { return; }

        if (chunk.length == 0)
        {
            bool closed;
            try { closed = conn.empty; }
            catch (Exception) { return; }
            if (closed)
                return;

            bool ok = false;
            try { ok = conn.waitForData(); }
            catch (Exception) { return; }
            if (!ok)
                return;
            continue;
        }

        auto toSkip = chunk.length;
        if (drained + toSkip > maxBytes)
            toSkip = maxBytes - drained;

        try { conn.skip(toSkip); }
        catch (Exception) { return; }

        drained += toSkip;
    }
}

// ============================================================================
// CHUNKED BODY READER (streaming decode)
// ============================================================================

private enum ChunkedReadStatus
{
    ok,
    timeout,
    clientClosed,
    tooLarge,
    bad,
}

private bool parseChunkSizeLine(const(ubyte)[] line, out size_t size) @nogc nothrow pure @safe
{
    size_t i = 0;
    while (i < line.length && (line[i] == ' ' || line[i] == '\t'))
        i++;

    if (i >= line.length)
        return false;

    bool any = false;
    size_t v = 0;
    while (i < line.length)
    {
        auto c = line[i];
        uint digit;
        if (c >= '0' && c <= '9') digit = c - '0';
        else if (c >= 'a' && c <= 'f') digit = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') digit = c - 'A' + 10;
        else break;

        any = true;
        auto newV = v * 16 + digit;
        if (newV < v)
            return false;
        v = newV;
        i++;
    }

    if (!any)
        return false;

    while (i < line.length && (line[i] == ' ' || line[i] == '\t'))
        i++;

    // Allow chunk extensions (";..."), reject any other garbage.
    if (i < line.length && line[i] != ';')
        return false;

    size = v;
    return true;
}

private ChunkedReadStatus readExactFromConn(
    TCPConnection conn,
    ubyte[] dest
) @trusted
{
    size_t off = 0;
    while (off < dest.length)
    {
        ubyte[] chunk;
        try { chunk = cast(ubyte[])conn.peek(); }
        catch (Exception) { return ChunkedReadStatus.bad; }

        if (chunk.length == 0)
        {
            bool closed;
            try { closed = conn.empty; }
            catch (Exception) { return ChunkedReadStatus.bad; }
            if (closed)
                return ChunkedReadStatus.clientClosed;

            bool ok = false;
            try { ok = conn.waitForData(); }
            catch (Exception) { return ChunkedReadStatus.bad; }
            if (!ok)
                return ChunkedReadStatus.timeout;
            continue;
        }

        auto toCopy = fastMin(chunk.length, dest.length - off);
        dest[off .. off + toCopy] = chunk[0 .. toCopy];
        try { conn.skip(toCopy); }
        catch (Exception) { return ChunkedReadStatus.bad; }
        off += toCopy;
    }

    return ChunkedReadStatus.ok;
}

// Consume bytes until "\r\n\r\n" is seen, bounded by maxBytes.
private ChunkedReadStatus consumeUntilHeaderEnd(
    TCPConnection conn,
    size_t maxBytes
) @trusted
{
    ubyte[3] tail = void;
    size_t tailLen = 0;
    size_t total = 0;

    while (total < maxBytes)
    {
        ubyte[] chunk;
        try { chunk = cast(ubyte[])conn.peek(); }
        catch (Exception) { return ChunkedReadStatus.bad; }

        if (chunk.length == 0)
        {
            bool closed;
            try { closed = conn.empty; }
            catch (Exception) { return ChunkedReadStatus.bad; }
            if (closed)
                return ChunkedReadStatus.clientClosed;

            if (!conn.waitForData())
                return ChunkedReadStatus.timeout;
            continue;
        }

        auto maxCopy = chunk.length;
        if (total + maxCopy > maxBytes)
            maxCopy = maxBytes - total;
        if (maxCopy == 0)
            break;

        auto need = findHeaderEnd(tail[0 .. tailLen], chunk[0 .. maxCopy]);
        auto toConsume = (need != 0) ? need : maxCopy;

        // Capture last bytes before skip (peek() slice may become invalid after skip()).
        ubyte[3] last = void;
        auto take = (toConsume > 3) ? 3 : toConsume;
        if (take)
            last[0 .. take] = chunk[toConsume - take .. toConsume];

        try { conn.skip(toConsume); }
        catch (Exception) { return ChunkedReadStatus.bad; }

        // Update tail with the last up to 3 bytes of the consumed stream.
        ubyte[6] tmp = void;
        size_t tmpLen = 0;
        if (tailLen)
        {
            tmp[0 .. tailLen] = tail[0 .. tailLen];
            tmpLen = tailLen;
        }
        if (take)
            tmp[tmpLen .. tmpLen + take] = last[0 .. take];
        tmpLen += take;
        if (tmpLen <= 3)
        {
            tail[0 .. tmpLen] = tmp[0 .. tmpLen];
            tailLen = tmpLen;
        }
        else
        {
            tail[0 .. 3] = tmp[tmpLen - 3 .. tmpLen];
            tailLen = 3;
        }

        total += toConsume;
        if (need != 0)
            return ChunkedReadStatus.ok;
    }

    return ChunkedReadStatus.bad;
}

private ChunkedReadStatus readLineCRLF(
    TCPConnection conn,
    ref ubyte[1024] lineBuf,
    out size_t lineLen
) @trusted
{
    lineLen = 0;
    bool pendingLF = false; // we consumed '\r' at the end of an I/O chunk

    while (true)
    {
        ubyte[] chunk;
        try { chunk = cast(ubyte[])conn.peek(); }
        catch (Exception) { return ChunkedReadStatus.bad; }

        if (chunk.length == 0)
        {
            bool closed;
            try { closed = conn.empty; }
            catch (Exception) { return ChunkedReadStatus.bad; }
            if (closed)
                return ChunkedReadStatus.clientClosed;

            bool ok = false;
            try { ok = conn.waitForData(); }
            catch (Exception) { return ChunkedReadStatus.bad; }
            if (!ok)
                return ChunkedReadStatus.timeout;
            continue;
        }

        // If the previous chunk ended with '\r', we must see '\n' next.
        if (pendingLF)
        {
            if (chunk[0] != '\n')
                return ChunkedReadStatus.bad;

            try { conn.skip(1); }
            catch (Exception) { return ChunkedReadStatus.bad; }

            return ChunkedReadStatus.ok;
        }

        // Search for '\r' in the currently available chunk. Chunk-size lines are tiny,
        // but using memchr keeps the fast path branch-predictable and avoids per-byte peeks.
        auto crPtr = cast(ubyte*)memchr(chunk.ptr, '\r', chunk.length);
        if (crPtr is null)
        {
            // No terminator yet: bulk-copy and consume all available bytes.
            immutable toCopy = chunk.length;
            if (lineLen + toCopy > lineBuf.length)
                return ChunkedReadStatus.bad;

            memcpy(lineBuf.ptr + lineLen, chunk.ptr, toCopy);
            try { conn.skip(toCopy); }
            catch (Exception) { return ChunkedReadStatus.bad; }

            lineLen += toCopy;
            continue;
        }

        // Copy bytes before '\r' into lineBuf (CR is NOT part of the line content).
        immutable crIdx = cast(size_t)(crPtr - chunk.ptr);
        if (crIdx)
        {
            if (lineLen + crIdx > lineBuf.length)
                return ChunkedReadStatus.bad;
            memcpy(lineBuf.ptr + lineLen, chunk.ptr, crIdx);
            lineLen += crIdx;
        }

        // We must not consume beyond CRLF: extra bytes belong to the next parse stage.
        // Capture the next byte before skip() (peek() slice may become invalid after skip()).
        if (crIdx + 1 >= chunk.length)
        {
            // '\r' is the last byte in this chunk; consume it and wait for '\n'.
            try { conn.skip(crIdx + 1); }
            catch (Exception) { return ChunkedReadStatus.bad; }

            pendingLF = true;
            continue;
        }

        immutable next = chunk[crIdx + 1];
        if (next != '\n')
            return ChunkedReadStatus.bad;

        // Consume up to and including CRLF in one skip().
        try { conn.skip(crIdx + 2); }
        catch (Exception) { return ChunkedReadStatus.bad; }

        return ChunkedReadStatus.ok;
    }
}

private bool ensureBodyCapacity(
    BufferPool pool,
    ref ubyte[] buf,
    size_t used,
    size_t needed
) @trusted nothrow
{
    if (buf.length >= needed)
        return true;

    size_t newCap = buf.length ? (buf.length * 2) : 4096;
    if (newCap < needed)
        newCap = needed;

    auto newBuf = pool.acquire(newCap);
    if (newBuf.ptr is null)
        return false;

    if (used)
        newBuf[0 .. used] = buf[0 .. used];
    if (buf.length)
        pool.release(buf);
    buf = newBuf;
    return true;
}

private ChunkedReadStatus readChunkedBody(
    TCPConnection conn,
    BufferPool pool,
    size_t maxTrailerBytes,
    size_t maxBodyBytes,
    ref ubyte[] outBuf,
    ref size_t outLen
) @trusted
{
    outLen = 0;

    while (true)
    {
        ubyte[1024] lineBuf = void;
        size_t lineLen = 0;
        auto ls = readLineCRLF(conn, lineBuf, lineLen);
        if (ls != ChunkedReadStatus.ok)
            return ls;

        size_t chunkSize = 0;
        if (!parseChunkSizeLine(lineBuf[0 .. lineLen], chunkSize))
            return ChunkedReadStatus.bad;

        if (chunkSize == 0)
        {
            // Trailer-part: header fields terminated by an empty line.
            // Empty trailer is a single CRLF immediately after the "0\r\n" line.
            while (true)
            {
                ubyte[] chunk;
                try { chunk = cast(ubyte[])conn.peek(); }
                catch (Exception) { return ChunkedReadStatus.bad; }

                if (chunk.length >= 2)
                    break;

                bool closed;
                try { closed = conn.empty; }
                catch (Exception) { return ChunkedReadStatus.bad; }
                if (closed)
                    return ChunkedReadStatus.clientClosed;

                if (!conn.waitForData())
                    return ChunkedReadStatus.timeout;
            }

            ubyte[] chunk2;
            try { chunk2 = cast(ubyte[])conn.peek(); }
            catch (Exception) { return ChunkedReadStatus.bad; }
            if (chunk2.length >= 2 && chunk2[0] == '\r' && chunk2[1] == '\n')
            {
                try { conn.skip(2); }
                catch (Exception) { return ChunkedReadStatus.bad; }
                return ChunkedReadStatus.ok;
            }

            // Non-empty trailer: consume until CRLFCRLF.
            return consumeUntilHeaderEnd(conn, maxTrailerBytes);
        }

        if (chunkSize > maxBodyBytes || outLen + chunkSize > maxBodyBytes)
            return ChunkedReadStatus.tooLarge;

        if (!ensureBodyCapacity(pool, outBuf, outLen, outLen + chunkSize))
            return ChunkedReadStatus.bad;

        auto rs = readExactFromConn(conn, outBuf[outLen .. outLen + chunkSize]);
        if (rs != ChunkedReadStatus.ok)
            return rs;
        outLen += chunkSize;

        ubyte[2] crlf = void;
        rs = readExactFromConn(conn, crlf[]);
        if (rs != ChunkedReadStatus.ok)
            return rs;
        if (crlf[0] != '\r' || crlf[1] != '\n')
            return ChunkedReadStatus.bad;
    }
}

// ============================================================================
// MAIN SERVER CLASS
// ============================================================================

/// Fiber-based HTTP Server
final class Server
{
    private
    {
        // === Hot data (frequently accessed together) ===
        // Grouped for cache locality
        shared bool running;
        shared bool shuttingDown;
        shared bool inOverloadState;
        
        // Pre-computed config values (avoid repeated floating point math)
        uint _highWaterMark;
        uint _lowWaterMark;
        uint _maxConnections;
        uint _maxInFlightRequests;
        uint _maxRequestsPerConnection;
        uint _maxHeaderSize;
        size_t _maxBodySize;
        OverloadBehavior _overloadBehavior;
        uint _retryAfterSeconds;
        
        // === Counters (grouped for potential SIMD operations) ===
        shared ulong totalConnections;
        shared ulong activeConnections;
        shared ulong totalRequests;
        shared ulong totalErrors;
        shared ulong rejectedHeadersTooLarge;
        shared ulong rejectedBodyTooLarge;
        shared ulong rejectedTimeout;
        shared ulong rejectedDuringShutdown;
        shared ulong rejectedOverload;
        shared ulong rejectedInFlight;
        shared ulong overloadStateTransitions;
        shared ulong currentInFlightRequests;
        
        // === Cold data (setup/config, rarely accessed in hot path) ===
        ServerConfig config;
        Router router;
        MiddlewarePipeline pipeline;
        RequestHandler handler;
        
        // Server hooks for lifecycle events
        ServerHooks _hooks;
        
        // Exception handlers (type hierarchy based)
        TypeErasedHandler[TypeInfo_Class] _exceptionHandlers;
        
        // Single-listener mode (macOS/Windows)
        TCPListener listener;
        
        // Multi-worker mode (Linux/FreeBSD)
        static if (USE_WORKER_POOL)
        {
            WorkerPool workerPool;
        }
        
        // Thread-local buffer pool reference
        static BufferPool _tlsPool;
    }
    
    // ========================================
    // CONSTRUCTORS (unchanged API)
    // ========================================
    
    /// Create with router
    this(Router r, ServerConfig cfg = ServerConfig.defaults()) @safe
    {
        this.router = r;
        this.pipeline = null;
        this.handler = null;
        this.config = cfg;
        initServer();
    }
    
    /// Create with router and middleware pipeline
    this(Router r, MiddlewarePipeline p, ServerConfig cfg = ServerConfig.defaults()) @safe
    {
        this.router = r;
        this.pipeline = p;
        this.handler = null;
        this.config = cfg;
        initServer();
    }
    
    /// Create with simple handler
    this(RequestHandler h, ServerConfig cfg = ServerConfig.defaults()) @safe
    {
        this.router = null;
        this.pipeline = null;
        this.handler = h;
        this.config = cfg;
        initServer();
    }
    
    /// Initialize server state and pre-compute config values
    private void initServer() @safe nothrow
    {
        // Pre-compute config values to avoid repeated calculations in hot path
        config.precomputeThresholds();
        _highWaterMark = config.highWaterMark();
        _lowWaterMark = config.lowWaterMark();
        _maxConnections = config.maxConnections;
        _maxInFlightRequests = config.maxInFlightRequests;
        _maxRequestsPerConnection = config.maxRequestsPerConnection;
        _maxHeaderSize = config.maxHeaderSize;
        _maxBodySize = config.maxBodySize;
        _overloadBehavior = config.overloadBehavior;
        _retryAfterSeconds = config.retryAfterSeconds;
        
        initStats();
    }
    
    private void initStats() @safe nothrow
    {
        atomicStore(running, false);
        atomicStore(shuttingDown, false);
        atomicStore(totalConnections, 0UL);
        atomicStore(activeConnections, 0UL);
        atomicStore(totalRequests, 0UL);
        atomicStore(totalErrors, 0UL);
        atomicStore(rejectedHeadersTooLarge, 0UL);
        atomicStore(rejectedBodyTooLarge, 0UL);
        atomicStore(rejectedTimeout, 0UL);
        atomicStore(rejectedDuringShutdown, 0UL);
        
        // Backpressure state
        atomicStore(inOverloadState, false);
        atomicStore(rejectedOverload, 0UL);
        atomicStore(rejectedInFlight, 0UL);
        atomicStore(overloadStateTransitions, 0UL);
        atomicStore(currentInFlightRequests, 0UL);
    }
    
    // ========================================
    // HOOKS & EXCEPTION HANDLERS
    // ========================================
    
    /// Access server hooks for lifecycle events
    /// Example: server.hooks.onStart(() => writeln("Server starting!"));
    pragma(inline, true)
    ref ServerHooks hooks() @safe nothrow
    {
        return _hooks;
    }
    
    /// Register a typed exception handler
    /// Example: server.addExceptionHandler!ValidationError((ctx, e) => ctx.response.json(...));
    void addExceptionHandler(E : Exception)(ExceptionHandler!E handler) @trusted
    {
        if (handler is null)
        {
            throw new Exception("Exception handler cannot be null");
        }
        
        // Wrap typed handler in type-erased form
        TypeErasedHandler wrapped = (ref Context ctx, Exception e) @trusted {
            // Safe downcast - we know the type matches when this is called
            if (auto typed = cast(E) e)
            {
                handler(ctx, typed);
            }
        };
        
        _exceptionHandlers[typeid(E)] = wrapped;
    }
    
    /// Check if an exception handler is registered for a type
    pragma(inline, true)
    bool hasExceptionHandler(E : Exception)() const @safe nothrow
    {
        return (typeid(E) in _exceptionHandlers) !is null;
    }
    
    /// Get number of registered exception handlers
    pragma(inline, true)
    size_t exceptionHandlerCount() const @safe nothrow
    {
        return _exceptionHandlers.length;
    }
    
    /// Add a type-erased exception handler directly (used by App)
    /// This is an internal API - prefer addExceptionHandler!E() for type safety
    void addExceptionHandlerDirect(TypeInfo_Class typeInfo, TypeErasedHandler handler) @safe
    {
        if (handler is null)
            throw new Exception("Exception handler cannot be null");
        _exceptionHandlers[typeInfo] = handler;
    }
    
    // ========================================
    // SERVER CONTROL (unchanged API)
    // ========================================
    
    /// Start the server (blocking)
    void run() @trusted
    {
        atomicStore(running, true);
        atomicStore(shuttingDown, false);
        
        auto numWorkers = config.effectiveWorkers();
        
        if (config.debugMode)
        {
            writeln("╔════════════════════════════════════════╗");
            writeln("║      Aurora HTTP Server v0.3.0         ║");
            writeln("╠════════════════════════════════════════╣");
            writefln("║  Host:    %-27s ║", config.host);
            writefln("║  Port:    %-27d ║", config.port);
            writefln("║  Workers: %-27d ║", numWorkers);
            static if (USE_WORKER_POOL) {
                writeln("║  Mode:    Multi-worker (reusePort)     ║");
                writefln("║  Threads: %-27d ║", numWorkers);
            } else {
                writeln("║  Mode:    Single-listener (fiber pool) ║");
            }
            writefln("║  Platform: %-26s ║", PLATFORM);
            writeln("║  I/O:     Fiber-based (vibe-core)      ║");
            writeln("╚════════════════════════════════════════╝");
        }
        
        // Execute onStart hooks
        try
        {
            _hooks.executeOnStart();
        }
        catch (Exception e)
        {
            atomicStore(running, false);
            throw new Exception("onStart hook failed: " ~ e.msg);
        }
        
        // Platform-specific startup
        try
        {
            static if (USE_WORKER_POOL)
            {
                // Linux/FreeBSD: Multi-worker mode with SO_REUSEPORT
                // Each worker thread has its own listener and event loop
                // Kernel distributes connections across workers
                runWithWorkerPool(numWorkers);
            }
            else
            {
                // macOS/Windows: Single event loop with fiber pool
                runWithSingleListener();
            }
        }
        catch (Exception e)
        {
            atomicStore(running, false);
            // Execute onStop hooks even on failure
            try { _hooks.executeOnStop(); } catch (Exception) {}
            throw new Exception("Failed to start server: " ~ e.msg);
        }
        
        // Execute onStop hooks
        try
        {
            _hooks.executeOnStop();
        }
        catch (Exception) {}  // Don't fail on stop hook errors
        
        // Cleanup
        atomicStore(running, false);
    }
    
    // Platform-specific run implementations
    static if (USE_WORKER_POOL)
    {
        private void runWithWorkerPool(uint numWorkers) @trusted
        {
            // Create worker pool
            workerPool = new WorkerPool(
                numWorkers,
                config.port,
                config.host,
                &handleConnection
            );
            
            // Start all workers
            workerPool.start();
            
            // Run main thread's event loop (coordinates workers)
            runEventLoop();
            
            // Cleanup
            if (workerPool !is null)
            {
                workerPool.stop();
                workerPool.join(30.seconds);
            }
        }
    }
    
    private void runWithSingleListener() @trusted
    {
        // Create single listener
        listener = listenTCP(
            config.port,
            &handleConnection,
            config.host,
            TCPListenOptions.reuseAddress
        );
        
        // Run the event loop (blocking)
        runEventLoop();
        
        // Cleanup
        if (listener !is TCPListener.init)
        {
            try { listener.stopListening(); }
            catch (Exception) {}
        }
    }
    
    /// Stop the server immediately
    void stop() @trusted nothrow
    {
        atomicStore(shuttingDown, true);
        atomicStore(running, false);
        
        // Stop based on mode
        static if (USE_WORKER_POOL)
        {
            if (workerPool !is null)
            {
                workerPool.stop();
            }
        }
        
        if (listener !is TCPListener.init)
        {
            try { listener.stopListening(); }
            catch (Exception) {}
        }
        
        // Exit the event loop
        try { exitEventLoop(); }
        catch (Exception) {}
    }
    
    /// Graceful shutdown - stop accepting, wait for in-flight requests
    void gracefulStop(Duration timeout = 30.seconds) @trusted
    {
        import core.time : MonoTime;
        
        // Mark as shutting down
        atomicStore(shuttingDown, true);
        
        // Stop accepting new connections
        static if (USE_WORKER_POOL)
        {
            if (workerPool !is null)
            {
                workerPool.stop();
            }
        }
        
        if (listener !is TCPListener.init)
        {
            try { listener.stopListening(); }
            catch (Exception) {}
        }
        
        // Wait for active connections to finish (with timeout)
        auto deadline = MonoTime.currTime + timeout;
        
        while (MonoTime.currTime < deadline)
        {
            auto active = getActiveConnections();
            if (active == 0)
                break;
            
            // Yield to allow other fibers to complete
            try { yield(); }
            catch (Exception) {}
        }
        
        // Now fully stop
        atomicStore(running, false);
        
        try { exitEventLoop(); }
        catch (Exception) {}
    }
    
    // ========================================
    // STATUS (unchanged API)
    // ========================================
    
    /// Check if server is running
    pragma(inline, true)
    bool isRunning() @safe nothrow { return atomicLoad(running); }
    
    /// Check if server is shutting down
    pragma(inline, true)
    bool isShuttingDown() @safe nothrow { return atomicLoad(shuttingDown); }
    
    // ========================================
    // STATS (unchanged API)
    // Stats are aggregated from WorkerPool on Linux, local on macOS
    // ========================================
    
    /// Get total connections accepted
    ulong getConnections() @safe nothrow
    {
        static if (USE_WORKER_POOL)
        {
            if (workerPool !is null)
                return workerPool.getTotalConnections();
        }
        return atomicLoad(totalConnections);
    }
    
    /// Get currently active connections
    ulong getActiveConnections() @safe nothrow
    {
        static if (USE_WORKER_POOL)
        {
            if (workerPool !is null)
                return workerPool.getActiveConnections();
        }
        return atomicLoad(activeConnections);
    }
    
    /// Get total requests processed
    ulong getRequests() @safe nothrow
    {
        static if (USE_WORKER_POOL)
        {
            if (workerPool !is null)
                return workerPool.getTotalRequests();
        }
        return atomicLoad(totalRequests);
    }
    
    /// Get total errors
    ulong getErrors() @safe nothrow
    {
        static if (USE_WORKER_POOL)
        {
            if (workerPool !is null)
                return workerPool.getTotalErrors();
        }
        return atomicLoad(totalErrors);
    }
    
    /// Get rejected requests (header too large)
    ulong getRejectedHeadersTooLarge() @safe nothrow
    {
        static if (USE_WORKER_POOL)
        {
            if (workerPool !is null)
                return workerPool.getRejectedHeadersTooLarge();
        }
        return atomicLoad(rejectedHeadersTooLarge);
    }
    
    /// Get rejected requests (body too large)
    ulong getRejectedBodyTooLarge() @safe nothrow
    {
        static if (USE_WORKER_POOL)
        {
            if (workerPool !is null)
                return workerPool.getRejectedBodyTooLarge();
        }
        return atomicLoad(rejectedBodyTooLarge);
    }
    
    /// Get rejected requests (timeout)
    ulong getRejectedTimeout() @safe nothrow
    {
        static if (USE_WORKER_POOL)
        {
            if (workerPool !is null)
                return workerPool.getRejectedTimeout();
        }
        return atomicLoad(rejectedTimeout);
    }
    
    /// Get rejected during shutdown
    pragma(inline, true)
    ulong getRejectedDuringShutdown() @safe nothrow
    {
        // This is always tracked locally in main thread
        return atomicLoad(rejectedDuringShutdown);
    }
    
    // ========================================
    // BACKPRESSURE METRICS (Enterprise)
    // ========================================
    
    /// Check if server is currently in overload state
    pragma(inline, true)
    bool isInOverload() @safe nothrow
    {
        return atomicLoad(inOverloadState);
    }
    
    /// Get connections rejected due to overload
    pragma(inline, true)
    ulong getRejectedOverload() @safe nothrow
    {
        return atomicLoad(rejectedOverload);
    }
    
    /// Get requests rejected due to in-flight limit
    pragma(inline, true)
    ulong getRejectedInFlight() @safe nothrow
    {
        return atomicLoad(rejectedInFlight);
    }
    
    /// Get number of times server entered overload state
    pragma(inline, true)
    ulong getOverloadTransitions() @safe nothrow
    {
        return atomicLoad(overloadStateTransitions);
    }
    
    /// Get current in-flight requests count
    pragma(inline, true)
    ulong getCurrentInFlightRequests() @safe nothrow
    {
        return atomicLoad(currentInFlightRequests);
    }
    
    /// Get connection utilization ratio (0.0 - 1.0)
    float getConnectionUtilization() @safe nothrow
    {
        if (_maxConnections == 0) return 0.0f;
        auto active = getActiveConnections();
        return cast(float)active / cast(float)_maxConnections;
    }
    
    /// Get the high water mark threshold (absolute number)
    pragma(inline, true)
    uint getConnectionHighWaterMark() const @safe nothrow pure
    {
        return _highWaterMark;
    }
    
    /// Get the low water mark threshold (absolute number)
    pragma(inline, true)
    uint getConnectionLowWaterMark() const @safe nothrow pure
    {
        return _lowWaterMark;
    }
    
    // ========================================
    // CONNECTION HANDLING (internal)
    // ========================================
    
    /// Safe close helper (nothrow)
    pragma(inline, true)
    private static void safeClose(TCPConnection conn) @trusted nothrow
    {
        try { conn.close(); }
        catch (Exception) {}
    }
    
    /**
     * Handle an exception using the registered exception handlers.
     * 
     * Strategy:
     * 1. Execute all onError hooks first (for logging/monitoring)
     * 2. Search for an exact type match handler
     * 3. Walk up the class hierarchy looking for a handler
     * 4. If no handler found, rethrow the exception (like FastAPI/Express)
     *
     * Returns: true if exception was handled, false if it was rethrown
     */
    private bool handleException(ref Context ctx, Exception e) @trusted
    {
        // Step 1: Execute all onError hooks (for logging/monitoring)
        // These run regardless of whether a handler exists
        try
        {
            _hooks.executeOnError(e, ctx);
        }
        catch (Exception hookError)
        {
            // Hook failure should not prevent exception handling
            // But we could log this in debug mode
        }
        
        // Step 2: Find handler by walking up the type hierarchy
        TypeInfo_Class typeInfo = typeid(e);
        
        while (typeInfo !is null)
        {
            if (auto handler = typeInfo in _exceptionHandlers)
            {
                // Found a handler - execute it
                (*handler)(ctx, e);
                return true;
            }
            
            // Walk up to parent class
            typeInfo = typeInfo.base;
        }
        
        // Step 3: No handler found - propagate the exception
        throw e;
    }
    
    private void handleConnection(TCPConnection conn) @safe nothrow
    {
        // Check if shutting down (hot path first check)
        if (atomicLoad(shuttingDown))
        {
            atomicOp!"+="(rejectedDuringShutdown, 1);
            safeClose(conn);
            return;
        }
        
        // === BACKPRESSURE CHECK ===
        if (!checkAndUpdateBackpressure(conn))
        {
            return;  // Connection rejected due to overload
        }
        
        atomicOp!"+="(totalConnections, 1);
        atomicOp!"+="(activeConnections, 1);
        
        scope(exit)
        {
            atomicOp!"-="(activeConnections, 1);
            safeClose(conn);
            
            // Check if we should exit overload state (hysteresis)
            checkOverloadRecovery();
        }
        
        try
        {
            processConnection(conn);
        }
        catch (Exception e)
        {
            atomicOp!"+="(totalErrors, 1);
        }
    }
    
    /// Check backpressure state and decide whether to accept connection
    /// Returns: true if connection should be accepted, false if rejected
    private bool checkAndUpdateBackpressure(TCPConnection conn) @safe nothrow
    {
        // Skip if maxConnections is 0 (unlimited) - fast path
        if (_maxConnections == 0) return true;
        
        auto currentActive = atomicLoad(activeConnections);
        
        // Check if we're already in overload state
        if (atomicLoad(inOverloadState))
        {
            // In overload: only accept if we've recovered below low water mark
            if (currentActive < _lowWaterMark)
            {
                // Recovery! Exit overload state
                atomicStore(inOverloadState, false);
                // Fall through to accept connection
            }
            else
            {
                // Still overloaded - reject
                rejectConnectionOverload(conn);
                return false;
            }
        }
        
        // Check if we should enter overload state
        if (currentActive >= _highWaterMark)
        {
            // Enter overload state
            if (!atomicLoad(inOverloadState))
            {
                atomicStore(inOverloadState, true);
                atomicOp!"+="(overloadStateTransitions, 1);
            }
            
            rejectConnectionOverload(conn);
            return false;
        }
        
        // Check hard limit
        if (currentActive >= _maxConnections)
        {
            rejectConnectionOverload(conn);
            return false;
        }
        
        return true;
    }
    
    /// Check if we should exit overload state (called on connection close)
    pragma(inline, true)
    private void checkOverloadRecovery() @safe nothrow
    {
        if (!atomicLoad(inOverloadState)) return;
        
        auto currentActive = atomicLoad(activeConnections);
        
        if (currentActive < _lowWaterMark)
        {
            atomicStore(inOverloadState, false);
        }
    }
    
    /// Reject connection due to overload
    private void rejectConnectionOverload(TCPConnection conn) @safe nothrow
    {
        atomicOp!"+="(rejectedOverload, 1);
        
        final switch (_overloadBehavior)
        {
            case OverloadBehavior.reject503:
                send503Response(conn);
                safeClose(conn);
                break;
                
            case OverloadBehavior.closeConnection:
                safeClose(conn);
                break;
                
            case OverloadBehavior.queueRequest:
                // TODO: Implement request queuing in future version
                // For now, fall back to 503
                send503Response(conn);
                safeClose(conn);
                break;
        }
    }
    
    /// Send HTTP 503 response with Retry-After header (zero-GC)
    private void send503Response(TCPConnection conn) @trusted nothrow
    {
        try
        {
            // Pre-sized buffer for 503 response
            ubyte[256] buf = void;
            size_t pos = 0;
            
            // Copy prefix
            buf[pos..pos+RESPONSE_503_PREFIX.length] = RESPONSE_503_PREFIX[];
            pos += RESPONSE_503_PREFIX.length;
            
            // Retry-After value
            char[12] retryBuf;
            auto retryStr = uintToStr(retryBuf[], _retryAfterSeconds);
            buf[pos..pos+retryStr.length] = cast(const(ubyte)[])retryStr[];
            pos += retryStr.length;
            
            // Middle section
            buf[pos..pos+RESPONSE_503_MIDDLE.length] = RESPONSE_503_MIDDLE[];
            pos += RESPONSE_503_MIDDLE.length;
            
            // Content-Length
            buf[pos..pos+BODY_503_LEN_STR.length] = cast(const(ubyte)[])BODY_503_LEN_STR[];
            pos += BODY_503_LEN_STR.length;
            
            // End headers
            buf[pos..pos+4] = cast(const(ubyte)[])"\r\n\r\n";
            pos += 4;
            
            // Body
            buf[pos..pos+BODY_503.length] = cast(const(ubyte)[])BODY_503[];
            pos += BODY_503.length;
            
            conn.write(buf[0..pos]);
        }
        catch (Exception) 
        {
            // Ignore write errors on rejection
        }
    }
    
    private void processConnection(TCPConnection conn) @trusted
    {
        immutable readTimeout = config.readTimeout;
        immutable keepAliveTimeout = config.keepAliveTimeout;

        // Set timeouts
        conn.readTimeout = readTimeout;
        
        // Cache config values locally for hot loop (avoid member access)
        immutable maxHeader = _maxHeaderSize;
        immutable maxBody = _maxBodySize;
        immutable maxRequests = _maxRequestsPerConnection;
        immutable maxInFlight = _maxInFlightRequests;
        
        // Get thread-local buffer pool
        if (_tlsPool is null) _tlsPool = new BufferPool();
        auto pool = _tlsPool;

        // ═══════════════════════════════════════════════════════════════
        // OPTIMIZATION (P1): Unified buffer for request + response
        // Use LARGE (64KB) buffer that will be reused for both:
        // - Request parsing (first 16-32KB typically)
        // - Response building (entire buffer after parsing completes)
        // Benefits: Better cache locality, fewer pool operations
        // ═══════════════════════════════════════════════════════════════
        ubyte[] buffer = pool.acquire(BufferSize.LARGE);  // 64KB from pool
        scope(exit) pool.release(buffer);
        
        uint requestCount = 0;
        
	        // Keep-alive loop
	        while (atomicLoad(running) && !atomicLoad(shuttingDown))
	        {
            // Check max requests per connection
            if (maxRequests > 0 && requestCount >= maxRequests)
                break;
            
            // Wait for data to be available first
            // This properly handles keep-alive: if client closes, we exit cleanly
            try
            {
                if (conn.empty)
                    return;  // Client closed connection - clean exit
            }
            catch (Exception)
            {
                return;  // Connection error
            }
            
            // Now read the request
            size_t totalReceived = 0;
            size_t headerEndPos = 0;
            ubyte[] decodedBodyBuf;
            size_t decodedBodyLen = 0;
            bool restoreReadTimeout = (requestCount > 0);

            scope(exit)
            {
                if (decodedBodyBuf.length)
                    pool.release(decodedBodyBuf);
            }
            
            // Read until we have complete headers, without over-consuming pipelined bytes.
            readLoop: while (headerEndPos == 0)
            {
                // Enforce header size limit independent of current buffer capacity.
                if (totalReceived >= maxHeader)
                {
                    atomicOp!"+="(rejectedHeadersTooLarge, 1);
                    sendErrorResponse(conn, 431, "Request Header Fields Too Large");
                    drainForClose(conn, 50.msecs);
                    return;
                }

                // Grow buffer if needed
                if (totalReceived >= buffer.length)
                {
                    // Grow buffer using pool
                    auto newSize = fastMin(buffer.length * 2, cast(size_t)maxHeader);
                    if (newSize <= buffer.length)
                    {
                        atomicOp!"+="(rejectedHeadersTooLarge, 1);
                        sendErrorResponse(conn, 431, "Request Header Fields Too Large");
                        drainForClose(conn, 50.msecs);
                        return;
                    }
                    auto newBuf = pool.acquire(newSize);
                    newBuf[0..totalReceived] = buffer[0..totalReceived];
                    pool.release(buffer);  // Return old buffer to pool
                    buffer = newBuf;
                }
                
                // Peek at available data
                ubyte[] chunk;
                try
                {
                    chunk = cast(ubyte[])conn.peek();
                    
                    if (chunk.length == 0)
                    {
                        // No data available - check if connection closed
                        if (conn.empty)
                        {
                            if (totalReceived == 0)
                                return;  // Clean close, no partial data
                            // Partial data received but connection closed
                            atomicOp!"+="(totalErrors, 1);
                            return;
                        }
                        
                        // Connection still open, wait for more data
                        // waitForData will yield the fiber
                        if (!conn.waitForData())
                        {
                            // Timeout or error
                            if (totalReceived == 0)
                                return;  // Clean timeout on keep-alive
                            atomicOp!"+="(rejectedTimeout, 1);
                            sendErrorResponse(conn, 408, "Request Timeout");
                            return;
                        }
                        continue readLoop;
                    }
                    
                    // Copy only up to header end, do not eat into body/pipelined requests.
                    auto maxCopy = fastMin(chunk.length, buffer.length - totalReceived);
                    auto headerRemaining = cast(size_t)maxHeader - totalReceived;
                    if (maxCopy > headerRemaining)
                        maxCopy = headerRemaining;

                    auto need = findHeaderEnd(buffer[0..totalReceived], chunk[0..maxCopy]);
                    auto toCopy = (need != 0) ? need : maxCopy;

                    buffer[totalReceived .. totalReceived + toCopy] = chunk[0 .. toCopy];
                    conn.skip(toCopy);
                    totalReceived += toCopy;

                    // Once we've started receiving a request, apply the stricter per-request read timeout.
                    if (restoreReadTimeout)
                    {
                        conn.readTimeout = readTimeout;
                        restoreReadTimeout = false;
                    }

                    if (need != 0)
                        headerEndPos = totalReceived;
                }
                catch (Exception)
                {
                    if (totalReceived == 0)
                        return;  // Clean close
                    atomicOp!"+="(totalErrors, 1);
                    return;
                }
            }
            
            if (headerEndPos == 0)
            {
                atomicOp!"+="(rejectedHeadersTooLarge, 1);
                sendErrorResponse(conn, 431, "Request Header Fields Too Large");
                drainForClose(conn, 50.msecs);
                return;
            }
            
            // Parse HTTP headers (body is handled separately for correct framing).
            HTTPRequest request;
            try
            {
                request = HTTPRequest.parse(buffer[0..headerEndPos]);
            }
            catch (Exception)
            {
                sendErrorResponse(conn, 400, "Bad Request");
                drainForClose(conn, 50.msecs);
                break;
            }

            if (request.hasError())
            {
                sendErrorResponse(conn, 400, "Bad Request");
                drainForClose(conn, 50.msecs);
                break;
            }

            // Read request body (Content-Length or Transfer-Encoding: chunked) before dispatch.
            import aurora.http.util : parseContentLength;

            bool isChunked = false;
            auto te = trimWhitespace(request.getHeaderRaw("transfer-encoding"));
            if (te.length)
            {
                if (isChunkedOnly(te))
                {
                    isChunked = true;
                }
                else
                {
                    sendErrorResponse(conn, 501, "Unsupported Transfer-Encoding");
                    drainForClose(conn, 50.msecs);
                    return;
                }
            }

            size_t contentLength = 0;
            auto clRaw = trimWhitespace(request.getHeaderRaw("content-length"));
            if (!isChunked && clRaw.length)
            {
                auto cl = parseContentLength(clRaw);
                if (cl == size_t.max)
                {
                    sendErrorResponse(conn, 400, "Bad Request");
                    drainForClose(conn, 50.msecs);
                    return;
                }
                contentLength = cl;
                if (contentLength > maxBody)
                {
                    atomicOp!"+="(rejectedBodyTooLarge, 1);
                    sendErrorResponse(conn, 413, "Payload Too Large");
                    drainForClose(conn, 50.msecs);
                    return;
                }
            }

            if (isChunked)
            {
                auto status = readChunkedBody(conn, pool, maxHeader, maxBody,
                    decodedBodyBuf, decodedBodyLen);
                final switch (status)
                {
                    case ChunkedReadStatus.ok:
                        request.setBodyRaw(decodedBodyBuf[0 .. decodedBodyLen]);
                        break;
                    case ChunkedReadStatus.timeout:
                        atomicOp!"+="(rejectedTimeout, 1);
                        sendErrorResponse(conn, 408, "Request Timeout");
                        return;
                    case ChunkedReadStatus.clientClosed:
                        return;
                    case ChunkedReadStatus.tooLarge:
                        atomicOp!"+="(rejectedBodyTooLarge, 1);
                        sendErrorResponse(conn, 413, "Payload Too Large");
                        drainForClose(conn, 50.msecs);
                        return;
                    case ChunkedReadStatus.bad:
                        sendErrorResponse(conn, 400, "Bad Request");
                        drainForClose(conn, 50.msecs);
                        return;
                }
            }
            else if (contentLength > 0)
            {
                // Ensure buffer can hold headers + body contiguously.
                auto needed = headerEndPos + contentLength;
                if (needed > buffer.length)
                {
                    auto newBuf = pool.acquire(needed);
                    newBuf[0 .. headerEndPos] = buffer[0 .. headerEndPos];
                    pool.release(buffer);
                    buffer = newBuf;
                }

                // Read exact Content-Length bytes without consuming pipelined bytes.
                auto rs = readExactFromConn(conn, buffer[totalReceived .. needed]);
                final switch (rs)
                {
                    case ChunkedReadStatus.ok:
                        totalReceived = needed;
                        request.setBodyRaw(buffer[headerEndPos .. needed]);
                        break;
                    case ChunkedReadStatus.timeout:
                        atomicOp!"+="(rejectedTimeout, 1);
                        sendErrorResponse(conn, 408, "Request Timeout");
                        return;
                    case ChunkedReadStatus.clientClosed:
                        return;
                    case ChunkedReadStatus.tooLarge:
                        // Not possible for fixed Content-Length dest slice.
                        return;
                    case ChunkedReadStatus.bad:
                        return;
                }
            }

            requestCount++;
            atomicOp!"+="(totalRequests, 1);
            
            // === IN-FLIGHT REQUEST LIMIT CHECK ===
            if (maxInFlight > 0)
            {
                auto inFlight = atomicOp!"+="(currentInFlightRequests, 1);
                scope(exit) atomicOp!"-="(currentInFlightRequests, 1);

                if (inFlight > maxInFlight)
                {
                    atomicOp!"+="(rejectedInFlight, 1);
                    sendErrorResponse(conn, 503, "Too many requests in flight");
                    return;
                }
            }
            
            // ═══════════════════════════════════════════════════════════════
            // RESPONSE: Stack-local, fiber-safe, reset for each request
            // ═══════════════════════════════════════════════════════════════
            HTTPResponse response = HTTPResponse(200, "OK");

            // Determine keep-alive BEFORE handling (based on request)
            auto connHeader = request.getHeaderRaw("connection");
            auto httpVer = request.httpVersionRaw();
            bool keepAlive = true;
            if (connHeader == "close")
                keepAlive = false;
            else if (httpVer == "HTTP/1.0" && connHeader != "keep-alive")
                keepAlive = false;
            
            // Force close on last allowed request (fixes off-by-one keep-alive bug)
            if (maxRequests > 0 && requestCount >= maxRequests)
                keepAlive = false;

            // Set up Context with pointers to our stack-local data
            Context ctx;
            ctx.request = &request;
            ctx.response = &response;
            ctx.setRawConnection(conn);  // For hijack support

            // Handle request based on mode
            bool wasHijacked = false;

            if (handler !is null)
            {
                // Simple handler mode (legacy API)
                auto respBuffer = ResponseBuffer();
                respBuffer.setKeepAlive(keepAlive);  // Honor keep-alive decision
                try
                {
                    handler(&request, respBuffer);
                    auto data = respBuffer.getData();
                    if (data.length > 0)
                    {
                        try { conn.write(data); }
                        catch (Exception) { atomicOp!"+="(totalErrors, 1); return; }
                    }
                }
                catch (Exception)
                {
                    sendErrorResponse(conn, 500, "Internal Server Error", false);
                    return;
                }
            }
            else if (router !is null)
            {
                // Router mode - uses new unified architecture
                auto result = handleWithRouter(ctx);
                wasHijacked = result.hijacked;

                // If hijacked, external handler owns the connection
                if (wasHijacked)
                    return;

                // Send response through single I/O point
                // OPTIMIZATION (P1): Pass unified buffer for reuse (already hot in cache)
                if (result.hasResponse)
                {
                    if (!sendHttpResponse(conn, result.response, keepAlive, buffer))
                    {
                        atomicOp!"+="(totalErrors, 1);
                        return;
                    }
                }
            }
            else
            {
                // No handler configured
                sendErrorResponse(conn, 500, "Internal Server Error", false);
                return;
            }

            // Check if we should continue keep-alive loop
            if (!keepAlive)
                break;

            // Update timeout for keep-alive
            conn.readTimeout = keepAliveTimeout;
        }
    }
    
    /// Result from handleWithRouter - includes response pointer and hijack state
    private struct RouterResult
    {
        HTTPResponse* response;  // Points to stack-allocated response in processConnection()
        bool hijacked;           // true if handler took over connection (WebSocket, etc.)

        /// Check if there's a valid response to send
        pragma(inline, true)
        @property bool hasResponse() const @safe nothrow pure
        {
            return response !is null && !hijacked;
        }
    }

    // ========================================
    // SINGLE HTTP RESPONSE OUTPUT POINT
    // ========================================

    /**
     * Send HTTP response to connection - the ONLY place where HTTP responses are written.
     *
     * This function:
     * - Uses HTTPResponse.buildInto() which includes ALL headers (including custom headers)
     * - Sets Connection header based on keepAlive
     * - OPTIMIZATION (P1): Reuses request buffer if provided (better cache locality)
     * - Falls back to pool buffer for large responses (P4: eliminates GC)
     *
     * Params:
     *   conn = TCP connection to write to
     *   response = Response to send (must not be null)
     *   keepAlive = Whether connection should be kept alive
     *   reuseBuffer = Optional pre-allocated buffer to reuse (e.g., from request parsing)
     *
     * Returns: true on success, false on I/O error
     */
    private bool sendHttpResponse(
        TCPConnection conn,
        HTTPResponse* response,
        bool keepAlive,
        ubyte[] reuseBuffer = null
    ) @trusted nothrow
    {
        if (response is null)
            return false;

        try
        {
            // Set Connection header - no hasHeader() check, just set it
            // This is faster than AA lookup and handles the common case
            response.setHeader("Connection", keepAlive ? "keep-alive" : "close");

            // ═══════════════════════════════════════════════════════════════
            // HOT PATH: Use provided reusable buffer (P1 optimization)
            // This buffer is typically the 64KB buffer used for request parsing
            // Already in L2/L3 cache = better performance than fresh stack buffer
            // ═══════════════════════════════════════════════════════════════
            if (reuseBuffer.length > 0)
            {
                auto len = response.buildInto(reuseBuffer);
                if (len > 0)
                {
                    conn.write(reuseBuffer[0..len]);
                    return true;
                }
                // If it doesn't fit in reuse buffer, fall through to pool allocation
            }

            // ═══════════════════════════════════════════════════════════════
            // FALLBACK PATH: Large response - use pool buffer (P4 optimization)
            // Avoids GC allocation for responses >64KB
            // ═══════════════════════════════════════════════════════════════
            auto estimatedSize = response.estimateSize();

            // Choose appropriate pool size
            ubyte[] poolBuf;
            if (estimatedSize < 64 * 1024)
            {
                poolBuf = _tlsPool.acquire(BufferSize.LARGE);  // 64KB
            }
            else if (estimatedSize < 256 * 1024)
            {
                poolBuf = _tlsPool.acquire(BufferSize.HUGE);  // 256KB
            }
            else
            {
                // Very large response - use non-pooled path (malloc/free) to avoid GC.
                poolBuf = _tlsPool.acquire(estimatedSize + 1024);
                if (poolBuf.ptr is null)
                    return false;
            }

            scope(exit) _tlsPool.release(poolBuf);

            auto len = response.buildInto(poolBuf);
            if (len > 0)
            {
                conn.write(poolBuf[0..len]);
                return true;
            }

            // Failed to build response
            return false;
        }
        catch (Exception)
        {
            // I/O error or other exception
            return false;
        }
    }

    /**
     * Send an error response without needing a full HTTPResponse object.
     * Used for early errors before HTTPResponse is set up.
     * Zero-GC implementation using pre-built buffer.
     */
    private bool sendErrorResponse(TCPConnection conn, int statusCode, string message, bool keepAlive = false) @trusted nothrow
    {
        try
        {
            ubyte[512] buf = void;
            auto len = buildErrorResponseInto(buf[], statusCode, message, keepAlive);
            if (len > 0)
            {
                conn.write(buf[0..len]);
                return true;
            }
            return false;
        }
        catch (Exception)
        {
            return false;
        }
    }

    /**
     * Handle request through router - ROUTING ONLY, NO I/O.
     *
     * This function:
     * - Finds matching route
     * - Executes middleware/handler
     * - Populates ctx.response (which points to stack-allocated HTTPResponse in processConnection)
     * - Does NOT do any I/O - that's sendHttpResponse's job
     *
     * Params:
     *   ctx = Context with request pointer and response pointer already set
     *
     * Returns: RouterResult with response pointer and hijacked flag
     */
    private RouterResult handleWithRouter(ref Context ctx) @trusted
    {
        RouterResult result;
        result.response = ctx.response;
        result.hijacked = false;

        try
        {
            // Execute onRequest hooks
            _hooks.executeOnRequest(ctx);

            // PHASE -1 T-1.1: Use methodRaw/pathRaw to avoid string allocations (7-20% gain)
            auto match = router.match(
                cast(string)ctx.request.methodRaw(),
                cast(string)ctx.request.pathRaw()
            );

            if (match.found && match.handler !is null)
            {
                ctx.params = match.params;

                // Execute with middleware pipeline if available
                if (pipeline !is null && pipeline.length > 0)
                {
                    pipeline.execute(ctx, match.handler);
                }
                else
                {
                    match.handler(ctx);
                }
            }
            else
            {
                // 404 Not Found
                ctx.response.setStatus(404);
                ctx.response.setHeader("Content-Type", "application/json");
                ctx.response.setBody(`{"error":"Not Found"}`);
            }

            // Check if connection was hijacked
            if (ctx.isHijacked())
            {
                // Connection is now owned by external handler
                // Do NOT send response, do NOT close connection
                result.hijacked = true;
                result.response = null;
                return result;
            }

            // Execute onResponse hooks
            _hooks.executeOnResponse(ctx);

            return result;
        }
        catch (Exception e)
        {
            // Check if hijacked before trying to send error response
            if (ctx.isHijacked())
            {
                // Cannot send error response on hijacked connection
                try { logError("Exception after hijack: " ~ e.msg); } catch (Exception) {}
                result.hijacked = true;
                result.response = null;
                return result;
            }

            // Try to handle with registered exception handlers
            try
            {
                handleException(ctx, e);
                // Handler executed - return the response it set
                _hooks.executeOnResponse(ctx);
                return result;
            }
            catch (Exception)
            {
                // No handler found or handler failed - set 500 error
                ctx.response.setStatus(500);
                ctx.response.setHeader("Content-Type", "application/json");
                ctx.response.setBody(`{"error":"Internal Server Error"}`);
                return result;
            }
        }
    }
}

// ============================================================================
// CONVENIENCE FUNCTIONS
// ============================================================================

/// Simple server runner (runs with default config)
void runServer(Router router, ushort port = 8080)
{
    auto config = ServerConfig.defaults();
    config.port = port;
    config.precomputeThresholds();
    auto server = new Server(router, config);
    server.run();
}

/// Server runner with config
void runServer(Router router, ServerConfig config)
{
    config.precomputeThresholds();
    auto server = new Server(router, config);
    server.run();
}

/// Server runner with middleware
void runServer(Router router, MiddlewarePipeline pipeline, ushort port = 8080)
{
    auto config = ServerConfig.defaults();
    config.port = port;
    config.precomputeThresholds();
    auto server = new Server(router, pipeline, config);
    server.run();
}

/// Server runner with middleware and config
void runServer(Router router, MiddlewarePipeline pipeline, ServerConfig config)
{
    config.precomputeThresholds();
    auto server = new Server(router, pipeline, config);
    server.run();
}
