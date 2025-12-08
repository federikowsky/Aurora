/**
 * Span — Distributed Tracing Span
 *
 * Package: aurora.tracing.span
 *
 * A Span represents a single unit of work in a distributed trace.
 * Contains timing information, attributes, status, and relationships.
 *
 * Follows OpenTelemetry semantic conventions (subset).
 */
module aurora.tracing.span;

import aurora.tracing.context;
import core.time : MonoTime, Duration;

// ============================================================================
// SPAN KIND
// ============================================================================

/**
 * Span Kind (OpenTelemetry)
 *
 * Describes the relationship between the span and its parent/children.
 */
enum SpanKind
{
    /// Default. Internal operation within an application.
    INTERNAL,
    
    /// Incoming request (server processing a client request)
    SERVER,
    
    /// Outgoing request (client making a request)
    CLIENT,
    
    /// Producer sending a message to a broker
    PRODUCER,
    
    /// Consumer receiving a message from a broker
    CONSUMER
}

// ============================================================================
// SPAN STATUS
// ============================================================================

/**
 * Span Status Code
 *
 * Represents the status of a span.
 */
enum SpanStatusCode
{
    /// Status not set (default)
    UNSET,
    
    /// Operation completed successfully
    OK,
    
    /// Operation failed with an error
    ERROR
}

/**
 * Span Status
 *
 * Contains status code and optional description.
 */
struct SpanStatus
{
    SpanStatusCode code = SpanStatusCode.UNSET;
    string description;
    
    static SpanStatus ok() @safe nothrow
    {
        return SpanStatus(SpanStatusCode.OK, "");
    }
    
    static SpanStatus error(string description = "") @safe nothrow
    {
        return SpanStatus(SpanStatusCode.ERROR, description);
    }
    
    static SpanStatus unset() @safe nothrow
    {
        return SpanStatus(SpanStatusCode.UNSET, "");
    }
}

// ============================================================================
// SPAN ATTRIBUTE
// ============================================================================

/**
 * Span Attribute Value
 *
 * Supports string, int, bool, and double values.
 */
struct AttributeValue
{
    enum Type { STRING, INT, BOOL, DOUBLE }
    
    Type type;
    
    union
    {
        string stringValue;
        long intValue;
        bool boolValue;
        double doubleValue;
    }
    
    static AttributeValue fromString(string v) @trusted nothrow
    {
        AttributeValue av;
        av.type = Type.STRING;
        av.stringValue = v;
        return av;
    }
    
    static AttributeValue fromInt(long v) @trusted nothrow
    {
        AttributeValue av;
        av.type = Type.INT;
        av.intValue = v;
        return av;
    }
    
    static AttributeValue fromBool(bool v) @trusted nothrow
    {
        AttributeValue av;
        av.type = Type.BOOL;
        av.boolValue = v;
        return av;
    }
    
    static AttributeValue fromDouble(double v) @trusted nothrow
    {
        AttributeValue av;
        av.type = Type.DOUBLE;
        av.doubleValue = v;
        return av;
    }
    
    string toString() const @trusted
    {
        import std.conv : to;
        final switch (type)
        {
            case Type.STRING: return stringValue;
            case Type.INT: return intValue.to!string;
            case Type.BOOL: return boolValue ? "true" : "false";
            case Type.DOUBLE: return doubleValue.to!string;
        }
    }
}

// ============================================================================
// SPAN EVENT
// ============================================================================

/**
 * Span Event
 *
 * A timestamped annotation within a span.
 */
struct SpanEvent
{
    /// Event name
    string name;
    
    /// Event timestamp
    MonoTime timestamp;
    
    /// Event attributes
    AttributeValue[string] attributes;
}

// ============================================================================
// SPAN
// ============================================================================

/**
 * Span
 *
 * Represents a unit of work in a distributed trace.
 * Contains timing, attributes, status, and events.
 */
struct Span
{
    // === Identity ===
    
    /// Trace context (trace-id, span-id)
    TraceContext context;
    
    /// Parent span ID (empty if root span)
    ubyte[8] parentSpanId;
    
    /// Human-readable span name
    string name;
    
    /// Kind of span (SERVER, CLIENT, etc.)
    SpanKind kind = SpanKind.INTERNAL;
    
    // === Timing ===
    
    /// Start time
    MonoTime startTime;
    
    /// End time (zero if not ended)
    MonoTime endTime;
    
    // === Data ===
    
    /// Span attributes
    AttributeValue[string] attributes;
    
    /// Span events (timestamped annotations)
    SpanEvent[] events;
    
    /// Span status
    SpanStatus status;
    
    /// Service name
    string serviceName;
    
    // ========================================================================
    // FACTORY METHODS
    // ========================================================================
    
    /**
     * Create a new root span (no parent).
     */
    static Span create(string name, string serviceName, SpanKind kind = SpanKind.INTERNAL) @safe nothrow
    {
        Span span;
        span.context = TraceContext.generate(true);
        span.name = name;
        span.serviceName = serviceName;
        span.kind = kind;
        span.startTime = MonoTime.currTime;
        span.status = SpanStatus.unset();
        return span;
    }
    
    /**
     * Create a child span from a parent context.
     */
    static Span createChild(const ref TraceContext parent, string name, string serviceName, 
                            SpanKind kind = SpanKind.INTERNAL) @safe nothrow
    {
        Span span;
        span.context = TraceContext.child(parent);
        span.parentSpanId = parent.spanId;
        span.name = name;
        span.serviceName = serviceName;
        span.kind = kind;
        span.startTime = MonoTime.currTime;
        span.status = SpanStatus.unset();
        return span;
    }
    
    /**
     * Create a span from an incoming trace context (e.g., from traceparent header).
     * The incoming span-id becomes the parent, and a new span-id is generated.
     */
    static Span fromContext(const ref TraceContext incoming, string name, string serviceName,
                            SpanKind kind = SpanKind.SERVER) @safe nothrow
    {
        Span span;
        span.context = TraceContext.child(incoming);
        span.parentSpanId = incoming.spanId;  // The incoming span-id is our parent
        span.name = name;
        span.serviceName = serviceName;
        span.kind = kind;
        span.startTime = MonoTime.currTime;
        span.status = SpanStatus.unset();
        return span;
    }
    
    // ========================================================================
    // MUTATION METHODS
    // ========================================================================
    
    /**
     * Set a string attribute.
     */
    ref Span setAttribute(string key, string value) return @safe nothrow
    {
        attributes[key] = AttributeValue.fromString(value);
        return this;
    }
    
    /**
     * Set an integer attribute.
     */
    ref Span setAttribute(string key, long value) return @safe nothrow
    {
        attributes[key] = AttributeValue.fromInt(value);
        return this;
    }
    
    /**
     * Set a boolean attribute.
     */
    ref Span setAttribute(string key, bool value) return @safe nothrow
    {
        attributes[key] = AttributeValue.fromBool(value);
        return this;
    }
    
    /**
     * Set a double attribute.
     */
    ref Span setAttribute(string key, double value) return @safe nothrow
    {
        attributes[key] = AttributeValue.fromDouble(value);
        return this;
    }
    
    /**
     * Add an event to the span.
     */
    ref Span addEvent(string name, AttributeValue[string] eventAttrs = null) return @safe nothrow
    {
        SpanEvent event;
        event.name = name;
        event.timestamp = MonoTime.currTime;
        event.attributes = eventAttrs;
        events ~= event;
        return this;
    }
    
    /**
     * Set span status to OK.
     */
    ref Span setOk() return @safe nothrow
    {
        status = SpanStatus.ok();
        return this;
    }
    
    /**
     * Set span status to ERROR with description.
     */
    ref Span setError(string description = "") return @safe nothrow
    {
        status = SpanStatus.error(description);
        return this;
    }
    
    /**
     * End the span with current timestamp.
     */
    void end() @safe nothrow
    {
        if (endTime == MonoTime.init)
            endTime = MonoTime.currTime;
    }
    
    /**
     * End the span with a specific timestamp.
     */
    void end(MonoTime timestamp) @safe nothrow
    {
        if (endTime == MonoTime.init)
            endTime = timestamp;
    }
    
    // ========================================================================
    // ACCESSORS
    // ========================================================================
    
    /**
     * Get span duration. Returns zero if span not ended.
     */
    Duration duration() const @safe nothrow
    {
        if (endTime == MonoTime.init)
            return Duration.zero;
        return endTime - startTime;
    }
    
    /**
     * Check if span has ended.
     */
    bool hasEnded() const @safe nothrow
    {
        return endTime != MonoTime.init;
    }
    
    /**
     * Get trace ID as hex string.
     */
    string traceId() const @safe nothrow
    {
        return context.traceIdHex();
    }
    
    /**
     * Get span ID as hex string.
     */
    string spanId() const @safe nothrow
    {
        return context.spanIdHex();
    }
    
    /**
     * Get parent span ID as hex string.
     */
    string parentId() const @trusted nothrow
    {
        return bytesToHexLocal(parentSpanId[]);
    }
    
    /**
     * Check if this is a root span (no parent).
     */
    bool isRoot() const @trusted nothrow
    {
        return isAllZerosLocal(parentSpanId[]);
    }
}

// ============================================================================
// PRIVATE HELPERS
// ============================================================================

private:

string bytesToHexLocal(const(ubyte)[] bytes) @trusted nothrow
{
    static immutable char[] hexChars = "0123456789abcdef";
    char[] result;
    result.length = bytes.length * 2;
    
    foreach (i, b; bytes)
    {
        result[i * 2] = hexChars[b >> 4];
        result[i * 2 + 1] = hexChars[b & 0x0F];
    }
    
    return cast(string)result;
}

bool isAllZerosLocal(const(ubyte)[] bytes) @safe nothrow
{
    foreach (b; bytes)
    {
        if (b != 0)
            return false;
    }
    return true;
}
