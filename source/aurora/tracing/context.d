/**
 * Trace Context — W3C Trace Context Propagation
 *
 * Package: aurora.tracing.context
 *
 * Implements W3C Trace Context Level 1 specification for distributed tracing.
 * Handles parsing and generation of traceparent and tracestate headers.
 *
 * traceparent format:
 * ---
 * version-traceid-parentid-flags
 * 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
 * ---
 *
 * Components:
 * - version: 2 hex digits (always "00" for current spec)
 * - trace-id: 32 hex digits (16 bytes) - unique trace identifier
 * - parent-id: 16 hex digits (8 bytes) - span identifier
 * - flags: 2 hex digits - sampling flags (01 = sampled)
 *
 * Standards: https://www.w3.org/TR/trace-context/
 */
module aurora.tracing.context;

import core.time : MonoTime;

// ============================================================================
// TRACE FLAGS
// ============================================================================

/**
 * Trace Flags (W3C Trace Context)
 *
 * Bit flags that control tracing behavior.
 */
enum TraceFlags : ubyte
{
    /// No flags set (default)
    NONE = 0x00,
    
    /// Trace is sampled (should be recorded)
    SAMPLED = 0x01
}

// ============================================================================
// TRACE CONTEXT
// ============================================================================

/**
 * W3C Trace Context
 *
 * Represents the distributed tracing context propagated through requests.
 * Contains trace-id, span-id (parent-id), and sampling flags.
 */
struct TraceContext
{
    /// Version of the traceparent format (always 0 for current spec)
    ubyte _version = 0;
    
    /// Unique identifier for the entire trace (16 bytes, 32 hex chars)
    ubyte[16] traceId;
    
    /// Identifier for the current span (8 bytes, 16 hex chars)
    /// In traceparent header, this is called "parent-id"
    ubyte[8] spanId;
    
    /// Trace flags (sampling decision)
    TraceFlags flags = TraceFlags.NONE;
    
    /// Whether this context is valid (successfully parsed or generated)
    bool valid = false;
    
    /// Optional tracestate header value (vendor-specific key-value pairs)
    string traceState;
    
    // ========================================================================
    // CONSTRUCTORS & FACTORY METHODS
    // ========================================================================
    
    /**
     * Create an invalid/empty trace context.
     */
    static TraceContext invalid() @safe nothrow
    {
        return TraceContext.init;
    }
    
    /**
     * Generate a new trace context with random IDs.
     *
     * Params:
     *   sampled = Whether the trace should be sampled (recorded)
     */
    static TraceContext generate(bool sampled = true) @trusted nothrow
    {
        TraceContext ctx;
        ctx._version = 0;
        ctx.traceId = generateRandomBytes!16();
        ctx.spanId = generateRandomBytes!8();
        ctx.flags = sampled ? TraceFlags.SAMPLED : TraceFlags.NONE;
        ctx.valid = true;
        return ctx;
    }
    
    /**
     * Generate a child span context (same trace-id, new span-id).
     *
     * Params:
     *   parent = Parent trace context
     */
    static TraceContext child(const ref TraceContext parent) @trusted nothrow
    {
        if (!parent.valid)
            return TraceContext.invalid();
        
        TraceContext ctx;
        ctx._version = parent._version;
        ctx.traceId = parent.traceId;
        ctx.spanId = generateRandomBytes!8();
        ctx.flags = parent.flags;
        ctx.traceState = parent.traceState;
        ctx.valid = true;
        return ctx;
    }
    
    /**
     * Parse a traceparent header value.
     *
     * Format: version-traceid-parentid-flags
     * Example: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
     *
     * Returns: TraceContext (check .valid for success)
     */
    static TraceContext parse(string traceparent) @trusted nothrow
    {
        TraceContext ctx;
        
        // Validate length: 2 + 1 + 32 + 1 + 16 + 1 + 2 = 55
        if (traceparent.length < 55)
            return ctx;
        
        // Validate format (dashes in correct positions)
        if (traceparent[2] != '-' || traceparent[35] != '-' || traceparent[52] != '-')
            return ctx;
        
        // Parse version
        auto versionParsed = parseHexByte(traceparent[0 .. 2]);
        if (!versionParsed.valid)
            return ctx;
        ctx._version = versionParsed.value;
        
        // Version 255 (0xff) is invalid
        if (ctx._version == 255)
            return ctx;
        
        // Parse trace-id (32 hex chars = 16 bytes)
        if (!parseHexBytes(traceparent[3 .. 35], ctx.traceId[]))
            return ctx;
        
        // Trace-id all zeros is invalid
        if (isAllZeros(ctx.traceId[]))
            return ctx;
        
        // Parse parent-id/span-id (16 hex chars = 8 bytes)
        if (!parseHexBytes(traceparent[36 .. 52], ctx.spanId[]))
            return ctx;
        
        // Parent-id all zeros is invalid
        if (isAllZeros(ctx.spanId[]))
            return ctx;
        
        // Parse flags
        auto flagsParsed = parseHexByte(traceparent[53 .. 55]);
        if (!flagsParsed.valid)
            return ctx;
        ctx.flags = cast(TraceFlags)flagsParsed.value;
        
        ctx.valid = true;
        return ctx;
    }
    
    /**
     * Parse traceparent and tracestate headers together.
     */
    static TraceContext parseWithState(string traceparent, string tracestate) @safe nothrow
    {
        auto ctx = parse(traceparent);
        if (ctx.valid)
            ctx.traceState = tracestate;
        return ctx;
    }
    
    // ========================================================================
    // SERIALIZATION
    // ========================================================================
    
    /**
     * Serialize to traceparent header value.
     *
     * Returns: String like "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
     */
    string toTraceparent() const @safe nothrow
    {
        if (!valid)
            return "";
        
        char[55] buffer;
        
        // Version
        buffer[0 .. 2] = byteToHex(_version);
        buffer[2] = '-';
        
        // Trace ID
        foreach (i, b; traceId)
        {
            auto hex = byteToHex(b);
            buffer[3 + i * 2] = hex[0];
            buffer[4 + i * 2] = hex[1];
        }
        buffer[35] = '-';
        
        // Span ID
        foreach (i, b; spanId)
        {
            auto hex = byteToHex(b);
            buffer[36 + i * 2] = hex[0];
            buffer[37 + i * 2] = hex[1];
        }
        buffer[52] = '-';
        
        // Flags
        buffer[53 .. 55] = byteToHex(cast(ubyte)flags);
        
        return buffer[].idup;
    }
    
    /**
     * Get trace ID as hex string (32 chars).
     */
    string traceIdHex() const @trusted nothrow
    {
        return bytesToHex(traceId[]);
    }
    
    /**
     * Get span ID as hex string (16 chars).
     */
    string spanIdHex() const @trusted nothrow
    {
        return bytesToHex(spanId[]);
    }
    
    // ========================================================================
    // PROPERTIES
    // ========================================================================
    
    /**
     * Check if this trace is sampled (should be recorded).
     */
    bool isSampled() const @safe nothrow
    {
        return (flags & TraceFlags.SAMPLED) != 0;
    }
    
    /**
     * Set sampling flag.
     */
    void setSampled(bool sampled) @safe nothrow
    {
        if (sampled)
            flags = cast(TraceFlags)(flags | TraceFlags.SAMPLED);
        else
            flags = cast(TraceFlags)(flags & ~TraceFlags.SAMPLED);
    }
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

private:

/**
 * Generate random bytes using a simple xorshift PRNG.
 * For production, consider using /dev/urandom or similar.
 */
ubyte[N] generateRandomBytes(size_t N)() @trusted nothrow
{
    // Use monotonically increasing counter combined with time for uniqueness
    static shared ulong counter = 0;
    import core.atomic : atomicOp;
    
    auto cnt = atomicOp!"+="(counter, 1);
    auto now = MonoTime.currTime.ticks;
    
    // Mix both high and low bits of time with counter
    ulong seed = now;
    seed ^= cnt * 2654435761UL; // Knuth's multiplicative hash
    seed ^= (now >> 32);
    seed ^= (cnt << 32);
    
    ubyte[N] result;
    ulong state = seed;
    
    foreach (i; 0 .. N)
    {
        // xorshift64
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        result[i] = cast(ubyte)(state & 0xFF);
        state ^= cnt; // Additional mixing
    }
    
    return result;
}

/**
 * Parse a single hex byte (2 chars).
 */
struct HexByteResult
{
    ubyte value;
    bool valid;
}

HexByteResult parseHexByte(const(char)[] hex) @safe nothrow
{
    if (hex.length < 2)
        return HexByteResult(0, false);
    
    auto high = hexCharToNibble(hex[0]);
    auto low = hexCharToNibble(hex[1]);
    
    if (high < 0 || low < 0)
        return HexByteResult(0, false);
    
    return HexByteResult(cast(ubyte)((high << 4) | low), true);
}

/**
 * Parse hex string into byte array.
 */
bool parseHexBytes(const(char)[] hex, ubyte[] output) @safe nothrow
{
    if (hex.length != output.length * 2)
        return false;
    
    foreach (i; 0 .. output.length)
    {
        auto result = parseHexByte(hex[i * 2 .. i * 2 + 2]);
        if (!result.valid)
            return false;
        output[i] = result.value;
    }
    return true;
}

/**
 * Convert hex char to nibble value.
 */
int hexCharToNibble(char c) @safe nothrow
{
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}

/**
 * Convert byte to hex chars.
 */
char[2] byteToHex(ubyte b) @safe nothrow
{
    static immutable char[] hexChars = "0123456789abcdef";
    return [hexChars[b >> 4], hexChars[b & 0x0F]];
}

/**
 * Convert byte array to hex string.
 */
string bytesToHex(const(ubyte)[] bytes) @trusted nothrow
{
    char[] result;
    result.length = bytes.length * 2;
    
    foreach (i, b; bytes)
    {
        auto hex = byteToHex(b);
        result[i * 2] = hex[0];
        result[i * 2 + 1] = hex[1];
    }
    
    return cast(string)result;
}

/**
 * Check if all bytes are zero.
 */
bool isAllZeros(const(ubyte)[] bytes) @safe nothrow
{
    foreach (b; bytes)
    {
        if (b != 0)
            return false;
    }
    return true;
}
