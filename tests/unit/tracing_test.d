/**
 * Tracing Module Tests
 *
 * TDD: Aurora Distributed Tracing (W3C Trace Context)
 *
 * Tests:
 * - TraceContext parsing and generation
 * - Span creation and lifecycle
 * - SpanExporter interface
 * - TracingMiddleware functionality
 */
module tests.unit.tracing_test;

import unit_threaded;
import aurora.tracing;
import aurora.web.context;
import aurora.http;
import core.time : seconds, msecs;
import core.thread : Thread;

// ========================================
// HELPER FUNCTIONS
// ========================================

/// Create test context with a specific path and headers
struct TestContext
{
    Context ctx;
    HTTPRequest request;
    HTTPResponse response;
    
    static TestContext create(string path, string[string] headers = null) @trusted
    {
        import std.format : format;
        
        TestContext tc;
        tc.response = HTTPResponse(200, "OK");
        tc.ctx.response = &tc.response;
        
        // Build raw request with headers
        string headerStr = "";
        if (headers !is null)
        {
            foreach (name, value; headers)
            {
                headerStr ~= format!"%s: %s\r\n"(name, value);
            }
        }
        
        string rawRequest = format!"GET %s HTTP/1.1\r\nHost: localhost\r\n%s\r\n"(path, headerStr);
        tc.request = HTTPRequest.parse(cast(ubyte[])rawRequest);
        tc.ctx.request = &tc.request;
        
        return tc;
    }
}

// ========================================
// TRACE CONTEXT TESTS
// ========================================

// Test 1: Generate new trace context
@("generate creates valid trace context")
unittest
{
    auto ctx = TraceContext.generate(true);
    
    ctx.valid.shouldBeTrue;
    ctx.isSampled().shouldBeTrue;
    ctx._version.shouldEqual(0);
}

// Test 2: Generate unsampled trace
@("generate with sampled=false creates unsampled context")
unittest
{
    auto ctx = TraceContext.generate(false);
    
    ctx.valid.shouldBeTrue;
    ctx.isSampled().shouldBeFalse;
}

// Test 3: Parse valid traceparent
@("parse valid traceparent header")
unittest
{
    auto ctx = TraceContext.parse("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01");
    
    ctx.valid.shouldBeTrue;
    ctx._version.shouldEqual(0);
    ctx.isSampled().shouldBeTrue;
    ctx.traceIdHex().shouldEqual("0af7651916cd43dd8448eb211c80319c");
    ctx.spanIdHex().shouldEqual("b7ad6b7169203331");
}

// Test 4: Parse unsampled traceparent
@("parse unsampled traceparent (flags=00)")
unittest
{
    auto ctx = TraceContext.parse("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-00");
    
    ctx.valid.shouldBeTrue;
    ctx.isSampled().shouldBeFalse;
}

// Test 5: Parse invalid traceparent - too short
@("parse invalid traceparent - too short")
unittest
{
    auto ctx = TraceContext.parse("00-abc");
    ctx.valid.shouldBeFalse;
}

// Test 6: Parse invalid traceparent - missing dashes
@("parse invalid traceparent - missing dashes")
unittest
{
    auto ctx = TraceContext.parse("000af7651916cd43dd8448eb211c80319cb7ad6b716920333101");
    ctx.valid.shouldBeFalse;
}

// Test 7: Parse invalid traceparent - all zeros trace-id
@("parse invalid traceparent - all zeros trace-id")
unittest
{
    auto ctx = TraceContext.parse("00-00000000000000000000000000000000-b7ad6b7169203331-01");
    ctx.valid.shouldBeFalse;
}

// Test 8: Parse invalid traceparent - all zeros span-id
@("parse invalid traceparent - all zeros span-id")
unittest
{
    auto ctx = TraceContext.parse("00-0af7651916cd43dd8448eb211c80319c-0000000000000000-01");
    ctx.valid.shouldBeFalse;
}

// Test 9: Round-trip serialization
@("traceparent round-trip serialization")
unittest
{
    auto original = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01";
    auto ctx = TraceContext.parse(original);
    
    ctx.valid.shouldBeTrue;
    ctx.toTraceparent().shouldEqual(original);
}

// Test 10: Generate child context
@("child context preserves trace-id")
unittest
{
    auto parent = TraceContext.generate(true);
    auto child = TraceContext.child(parent);
    
    child.valid.shouldBeTrue;
    child.traceIdHex().shouldEqual(parent.traceIdHex());
    child.spanIdHex().shouldNotEqual(parent.spanIdHex());
    child.isSampled().shouldEqual(parent.isSampled());
}

// Test 11: Invalid context produces empty traceparent
@("invalid context produces empty traceparent")
unittest
{
    auto ctx = TraceContext.invalid();
    ctx.valid.shouldBeFalse;
    ctx.toTraceparent().shouldEqual("");
}

// ========================================
// SPAN TESTS
// ========================================

// Test 12: Create root span
@("create root span")
unittest
{
    auto span = Span.create("test-operation", "test-service", SpanKind.INTERNAL);
    
    span.name.shouldEqual("test-operation");
    span.serviceName.shouldEqual("test-service");
    span.kind.shouldEqual(SpanKind.INTERNAL);
    span.context.valid.shouldBeTrue;
    span.isRoot().shouldBeTrue;
}

// Test 13: Create child span
@("create child span from parent context")
unittest
{
    auto parent = TraceContext.generate(true);
    auto span = Span.createChild(parent, "child-op", "test-service");
    
    span.traceId().shouldEqual(parent.traceIdHex());
    span.isRoot().shouldBeFalse;
    span.parentId().shouldEqual(parent.spanIdHex());
}

// Test 14: Span timing
@("span records timing correctly")
unittest
{
    auto span = Span.create("test", "service");
    
    Thread.sleep(5.msecs);
    span.end();
    
    span.hasEnded().shouldBeTrue;
    span.duration().total!"msecs".shouldBeGreaterThan(0);
}

// Test 15: Span attributes
@("span attributes can be set")
unittest
{
    auto span = Span.create("test", "service");
    
    span.setAttribute("http.method", "GET");
    span.setAttribute("http.status_code", 200L);
    span.setAttribute("error", false);
    span.setAttribute("latency", 1.5);
    
    span.attributes.length.shouldEqual(4);
    span.attributes["http.method"].toString().shouldEqual("GET");
    span.attributes["http.status_code"].toString().shouldEqual("200");
    span.attributes["error"].toString().shouldEqual("false");
}

// Test 16: Span status
@("span status can be set")
unittest
{
    auto span = Span.create("test", "service");
    
    span.status.code.shouldEqual(SpanStatusCode.UNSET);
    
    span.setOk();
    span.status.code.shouldEqual(SpanStatusCode.OK);
    
    span.setError("something went wrong");
    span.status.code.shouldEqual(SpanStatusCode.ERROR);
    span.status.description.shouldEqual("something went wrong");
}

// Test 17: Span events
@("span events can be added")
unittest
{
    auto span = Span.create("test", "service");
    
    span.addEvent("started");
    span.addEvent("completed");
    
    span.events.length.shouldEqual(2);
    span.events[0].name.shouldEqual("started");
    span.events[1].name.shouldEqual("completed");
}

// ========================================
// EXPORTER TESTS
// ========================================

// Test 18: NoopSpanExporter
@("NoopSpanExporter always succeeds")
unittest
{
    auto exporter = new NoopSpanExporter();
    
    auto span = Span.create("test", "service");
    span.end();
    
    exporter.exportSpan(span).shouldBeTrue;
    exporter.forceFlush().shouldBeTrue;
}

// Test 19: ConsoleSpanExporter can be created
@("ConsoleSpanExporter can be created")
unittest
{
    import std.stdio : stdout;
    
    auto exporter = new ConsoleSpanExporter(stdout, false, false);
    exporter.shouldNotBeNull;
}

// Test 20: BatchingSpanExporter batches spans
@("BatchingSpanExporter batches spans correctly")
unittest
{
    auto noop = new NoopSpanExporter();
    auto batching = new BatchingSpanExporter(noop, 10);
    
    auto span = Span.create("test", "service");
    span.end();
    
    batching.exportSpan(span).shouldBeTrue;
    batching.forceFlush().shouldBeTrue;
}

// Test 21: MultiSpanExporter exports to multiple
@("MultiSpanExporter exports to all exporters")
unittest
{
    auto noop1 = new NoopSpanExporter();
    auto noop2 = new NoopSpanExporter();
    auto multi = new MultiSpanExporter(noop1, noop2);
    
    auto span = Span.create("test", "service");
    span.end();
    
    multi.exportSpan(span).shouldBeTrue;
}

// ========================================
// TRACING CONFIG TESTS
// ========================================

// Test 22: Default config
@("TracingConfig defaults are sensible")
unittest
{
    auto config = TracingConfig.defaults();
    
    config.serviceName.shouldEqual("aurora-service");
    config.alwaysSample.shouldBeFalse;
    config.samplingProbability.shouldEqual(1.0);
    config.excludePaths.shouldEqual(["/health/*", "/metrics"]);
}

// ========================================
// TRACING MIDDLEWARE TESTS
// ========================================

// Test 23: Middleware can be created
@("TracingMiddleware can be created")
unittest
{
    auto exporter = new NoopSpanExporter();
    auto middleware = new TracingMiddleware("test-service", exporter);
    
    middleware.shouldNotBeNull;
}

// Test 24: Factory function works
@("tracingMiddleware factory function works")
unittest
{
    auto exporter = new NoopSpanExporter();
    auto mw = tracingMiddleware("test-service", exporter);
    
    mw.shouldNotBeNull;
}

// Test 25: Middleware passes through for excluded paths
@("middleware skips excluded paths")
unittest
{
    auto exporter = new NoopSpanExporter();
    TracingConfig config;
    config.excludePaths = ["/health/*"];
    
    auto middleware = new TracingMiddleware("test-service", exporter, config);
    auto tc = TestContext.create("/health/live");
    
    bool nextCalled = false;
    middleware.handle(tc.ctx, { nextCalled = true; });
    
    nextCalled.shouldBeTrue;
    // No tracing data stored for excluded paths (getTracingData returns null)
}

// Test 26: Middleware processes normal requests
@("middleware processes normal requests")
unittest
{
    auto exporter = new NoopSpanExporter();
    auto middleware = new TracingMiddleware("test-service", exporter);
    auto tc = TestContext.create("/api/users");
    
    bool nextCalled = false;
    middleware.handle(tc.ctx, { nextCalled = true; });
    
    nextCalled.shouldBeTrue;
    
    // Check tracing data was stored
    auto tracingData = getTracingData(tc.ctx);
    tracingData.shouldNotBeNull;
    tracingData.traceId.length.shouldEqual(32);
    tracingData.spanId.length.shouldEqual(16);
}

// Test 27: Middleware extracts incoming traceparent
@("middleware extracts incoming traceparent header")
unittest
{
    auto exporter = new NoopSpanExporter();
    auto middleware = new TracingMiddleware("test-service", exporter);
    
    string incomingTraceId = "0af7651916cd43dd8448eb211c80319c";
    auto tc = TestContext.create("/api/users", [
        "traceparent": "00-" ~ incomingTraceId ~ "-b7ad6b7169203331-01"
    ]);
    
    middleware.handle(tc.ctx, {});
    
    auto tracingData = getTracingData(tc.ctx);
    tracingData.shouldNotBeNull;
    // Trace ID should be preserved from parent
    tracingData.traceId.shouldEqual(incomingTraceId);
}

// Test 28: Helper functions work
@("getTraceId helper works")
unittest
{
    auto exporter = new NoopSpanExporter();
    auto middleware = new TracingMiddleware("test-service", exporter);
    auto tc = TestContext.create("/api/users");
    
    middleware.handle(tc.ctx, {});
    
    auto traceId = getTraceId(tc.ctx);
    traceId.length.shouldEqual(32);
    
    auto spanId = getSpanId(tc.ctx);
    spanId.length.shouldEqual(16);
    
    auto traceparent = getTraceparent(tc.ctx);
    traceparent.length.shouldEqual(55);
}

// Test 29: Null request is handled
@("middleware handles null request gracefully")
unittest
{
    auto exporter = new NoopSpanExporter();
    auto middleware = new TracingMiddleware("test-service", exporter);
    
    Context ctx;
    ctx.request = null;
    HTTPResponse response;
    ctx.response = &response;
    
    bool nextCalled = false;
    middleware.handle(ctx, { nextCalled = true; });
    
    nextCalled.shouldBeTrue;
}

// Test 30: TracingData class works
@("TracingData class stores all fields")
unittest
{
    auto data = new TracingData();
    data.traceId = "abc123";
    data.spanId = "def456";
    data.traceparent = "00-abc-def-01";
    data.sampled = true;
    
    data.traceId.shouldEqual("abc123");
    data.spanId.shouldEqual("def456");
    data.traceparent.shouldEqual("00-abc-def-01");
    data.sampled.shouldBeTrue;
}
