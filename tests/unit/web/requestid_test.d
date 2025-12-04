/**
 * Request ID Middleware Tests
 *
 * Tests for Aurora's Request ID middleware:
 * - UUID generation
 * - Preserving existing IDs
 * - Header handling
 * - Context storage
 */
module tests.unit.web.requestid_test;

import unit_threaded;
import aurora.web.middleware;
import aurora.web.middleware.requestid;
import aurora.web.context;
import aurora.http;
import std.uuid : parseUUID, UUID;

// ========================================
// TEST CONTEXT HELPER
// ========================================

/// Test context struct to hold request/response for testing
struct TestContext
{
    Context ctx;
    HTTPResponse response;
    HTTPRequest request;

    /// Create test context with optional method, path, and headers
    static TestContext create(string method = "GET", string path = "/", string extraHeaders = "")
    {
        TestContext tc;
        
        string rawRequest =
            method ~ " " ~ path ~ " HTTP/1.1\r\n" ~
            "Host: localhost\r\n" ~
            extraHeaders ~
            "\r\n";
        tc.request = HTTPRequest.parse(cast(ubyte[]) rawRequest);
        tc.response = HTTPResponse(200, "OK");
        tc.ctx.request = &tc.request;
        tc.ctx.response = &tc.response;
        return tc;
    }
}

// ============================================================================
// BASIC FUNCTIONALITY TESTS
// ============================================================================

// Test 1: RequestIdMiddleware can be created
@("RequestIdMiddleware can be created")
unittest
{
    auto mw = new RequestIdMiddleware();
    mw.shouldNotBeNull;
}

// Test 2: RequestIdMiddleware with config
@("RequestIdMiddleware with config")
unittest
{
    auto config = RequestIdConfig();
    config.headerName = "X-Correlation-ID";
    
    auto mw = new RequestIdMiddleware(config);
    mw.shouldNotBeNull;
}

// Test 3: Middleware generates request ID
@("middleware generates request ID")
unittest
{
    auto tc = TestContext.create();
    auto mw = requestIdMiddleware();
    
    bool nextCalled = false;
    mw(tc.ctx, { nextCalled = true; });
    
    nextCalled.shouldBeTrue;
    
    // Should have set response header
    auto headers = tc.response.getHeaders();
    auto requestId = "X-Request-ID" in headers;
    requestId.shouldNotBeNull;
    (*requestId).length.shouldBeGreaterThan(0);
}

// Test 4: Generated ID is valid UUID
@("generated ID is valid UUID")
unittest
{
    auto tc = TestContext.create();
    auto mw = requestIdMiddleware();
    
    mw(tc.ctx, {});
    
    auto headers = tc.response.getHeaders();
    auto requestId = headers.get("X-Request-ID", "");
    
    // Try to parse as UUID - if it throws, the test fails naturally
    auto uuid = parseUUID(requestId);
    // If we get here, it's a valid UUID
    true.shouldBeTrue;
}

// Test 5: ID stored in context
@("ID stored in context")
unittest
{
    auto tc = TestContext.create();
    auto mw = requestIdMiddleware();
    
    mw(tc.ctx, {});
    
    // Get ID from context
    auto id = getRequestId(tc.ctx);
    id.length.shouldBeGreaterThan(0);
}

// ============================================================================
// PRESERVE EXISTING ID TESTS
// ============================================================================

// Test 6: Preserves existing X-Request-ID header
@("preserves existing X-Request-ID header")
unittest
{
    auto tc = TestContext.create("GET", "/test", "X-Request-ID: existing-id-12345678\r\n");
    auto mw = requestIdMiddleware();
    
    mw(tc.ctx, {});
    
    // Should use existing ID
    auto headers = tc.response.getHeaders();
    auto requestId = headers.get("X-Request-ID", "");
    requestId.shouldEqual("existing-id-12345678");
}

// Test 7: Context also has preserved ID
@("context has preserved ID")
unittest
{
    auto tc = TestContext.create("GET", "/test", "X-Request-ID: preserved-abc123\r\n");
    auto mw = requestIdMiddleware();
    
    mw(tc.ctx, {});
    
    auto id = getRequestId(tc.ctx);
    id.shouldEqual("preserved-abc123");
}

// Test 8: Can disable preserve existing
@("can disable preserve existing")
unittest
{
    auto tc = TestContext.create("GET", "/test", "X-Request-ID: should-be-ignored\r\n");
    
    auto config = RequestIdConfig();
    config.preserveExisting = false;
    auto mw = requestIdMiddleware(config);
    
    mw(tc.ctx, {});
    
    // Should generate new UUID, not use existing
    auto headers = tc.response.getHeaders();
    auto requestId = headers.get("X-Request-ID", "");
    requestId.shouldNotEqual("should-be-ignored");
    requestId.length.shouldEqual(36);  // UUID length with dashes
}

// Test 9: Invalid request ID is rejected
@("invalid request ID is rejected")
unittest
{
    // Too short ID
    auto tc = TestContext.create("GET", "/test", "X-Request-ID: short\r\n");
    auto mw = requestIdMiddleware();
    
    mw(tc.ctx, {});
    
    // Should generate new UUID since "short" is invalid
    auto headers = tc.response.getHeaders();
    auto requestId = headers.get("X-Request-ID", "");
    requestId.shouldNotEqual("short");
    requestId.length.shouldBeGreaterThan(8);
}

// Test 10: Request ID with special chars rejected
@("request ID with special chars rejected")
unittest
{
    // ID with invalid characters
    auto tc = TestContext.create("GET", "/test", "X-Request-ID: invalid<script>id\r\n");
    auto mw = requestIdMiddleware();
    
    mw(tc.ctx, {});
    
    // Should generate new UUID since ID has invalid chars
    auto id = getRequestId(tc.ctx);
    id.shouldNotEqual("invalid<script>id");
}

// ============================================================================
// CUSTOM CONFIGURATION TESTS
// ============================================================================

// Test 11: Custom header name
@("custom header name")
unittest
{
    auto tc = TestContext.create();
    
    auto config = RequestIdConfig();
    config.headerName = "X-Correlation-ID";
    auto mw = requestIdMiddleware(config);
    
    mw(tc.ctx, {});
    
    auto headers = tc.response.getHeaders();
    ("X-Correlation-ID" in headers).shouldNotBeNull;
    ("X-Request-ID" in headers).shouldBeNull;
}

// Test 12: Custom storage key
@("custom storage key")
unittest
{
    auto tc = TestContext.create();
    
    auto config = RequestIdConfig();
    config.storageKey = "correlationId";
    auto mw = requestIdMiddleware(config);
    
    mw(tc.ctx, {});
    
    // Default key should be empty
    getRequestId(tc.ctx).shouldEqual("");
    
    // Custom key should have the ID
    getRequestId(tc.ctx, "correlationId").length.shouldBeGreaterThan(0);
}

// Test 13: Custom ID generator
@("custom ID generator")
unittest
{
    auto tc = TestContext.create();
    
    auto config = RequestIdConfig();
    config.generator = () => "custom-generated-id-123";
    auto mw = requestIdMiddleware(config);
    
    mw(tc.ctx, {});
    
    auto id = getRequestId(tc.ctx);
    id.shouldEqual("custom-generated-id-123");
}

// Test 14: Disable response header
@("disable response header")
unittest
{
    auto tc = TestContext.create();
    
    auto config = RequestIdConfig();
    config.setResponseHeader = false;
    auto mw = requestIdMiddleware(config);
    
    mw(tc.ctx, {});
    
    // Response header should not be set
    auto headers = tc.response.getHeaders();
    ("X-Request-ID" in headers).shouldBeNull;
    
    // But context should still have the ID
    getRequestId(tc.ctx).length.shouldBeGreaterThan(0);
}

// ============================================================================
// VALIDATION TESTS
// ============================================================================

// Test 15: Valid UUID format accepted
@("valid UUID format accepted")
unittest
{
    auto tc = TestContext.create("GET", "/test", "X-Request-ID: 550e8400-e29b-41d4-a716-446655440000\r\n");
    auto mw = requestIdMiddleware();
    
    mw(tc.ctx, {});
    
    auto id = getRequestId(tc.ctx);
    id.shouldEqual("550e8400-e29b-41d4-a716-446655440000");
}

// Test 16: UUID without dashes accepted
@("UUID without dashes accepted")
unittest
{
    auto tc = TestContext.create("GET", "/test", "X-Request-ID: 550e8400e29b41d4a716446655440000\r\n");
    auto mw = requestIdMiddleware();
    
    mw(tc.ctx, {});
    
    auto id = getRequestId(tc.ctx);
    id.shouldEqual("550e8400e29b41d4a716446655440000");
}

// Test 17: Alphanumeric ID accepted
@("alphanumeric ID accepted")
unittest
{
    auto tc = TestContext.create("GET", "/test", "X-Request-ID: req_abc123xyz789\r\n");
    auto mw = requestIdMiddleware();
    
    mw(tc.ctx, {});
    
    auto id = getRequestId(tc.ctx);
    id.shouldEqual("req_abc123xyz789");
}

// Test 18: ID with underscores accepted
@("ID with underscores accepted")
unittest
{
    auto tc = TestContext.create("GET", "/test", "X-Request-ID: request_12345_abc\r\n");
    auto mw = requestIdMiddleware();
    
    mw(tc.ctx, {});
    
    auto id = getRequestId(tc.ctx);
    id.shouldEqual("request_12345_abc");
}

// Test 19: Empty ID generates new one
@("empty ID generates new one")
unittest
{
    auto tc = TestContext.create("GET", "/test", "X-Request-ID: \r\n");
    auto mw = requestIdMiddleware();
    
    mw(tc.ctx, {});
    
    auto id = getRequestId(tc.ctx);
    id.length.shouldBeGreaterThan(0);
}

// Test 20: Too long ID rejected
@("too long ID rejected")
unittest
{
    import std.array : replicate;
    
    auto longId = replicate("a", 150);  // 150 chars, limit is 128
    auto tc = TestContext.create("GET", "/test", "X-Request-ID: " ~ longId ~ "\r\n");
    auto mw = requestIdMiddleware();
    
    mw(tc.ctx, {});
    
    // Should generate new ID
    auto id = getRequestId(tc.ctx);
    id.shouldNotEqual(longId);
    assert(id.length < 50, "ID should be less than 50 chars");
}

// ============================================================================
// PIPELINE INTEGRATION TESTS
// ============================================================================

// Test 21: Works in middleware pipeline
@("works in middleware pipeline")
unittest
{
    auto tc = TestContext.create();
    auto pipeline = new MiddlewarePipeline();
    
    pipeline.use(requestIdMiddleware());
    
    string capturedId;
    pipeline.use((ref Context ctx, NextFunction next) {
        capturedId = getRequestId(ctx);
        next();
    });
    
    pipeline.execute(tc.ctx, (ref Context ctx) {});
    
    capturedId.length.shouldBeGreaterThan(0);
}

// Test 22: ID available throughout pipeline
@("ID available throughout pipeline")
unittest
{
    auto tc = TestContext.create();
    auto pipeline = new MiddlewarePipeline();
    
    string[] collectedIds;
    
    pipeline.use(requestIdMiddleware());
    
    pipeline.use((ref Context ctx, NextFunction next) {
        collectedIds ~= getRequestId(ctx);
        next();
    });
    
    pipeline.use((ref Context ctx, NextFunction next) {
        collectedIds ~= getRequestId(ctx);
        next();
    });
    
    pipeline.execute(tc.ctx, (ref Context ctx) {
        collectedIds ~= getRequestId(ctx);
    });
    
    // All should have the same ID
    collectedIds.length.shouldEqual(3);
    collectedIds[0].shouldEqual(collectedIds[1]);
    collectedIds[1].shouldEqual(collectedIds[2]);
}

// Test 23: Multiple requests get different IDs
@("multiple requests get different IDs")
unittest
{
    string[] ids;
    
    foreach (i; 0 .. 5)
    {
        auto tc = TestContext.create();
        auto mw = requestIdMiddleware();
        
        mw(tc.ctx, {});
        ids ~= getRequestId(tc.ctx);
    }
    
    // All IDs should be unique
    import std.algorithm : sort, uniq;
    import std.array : array;
    
    auto uniqueIds = ids.sort.uniq.array;
    uniqueIds.length.shouldEqual(5);
}

// ============================================================================
// FACTORY FUNCTION TESTS
// ============================================================================

// Test 24: requestIdMiddleware() factory works
@("requestIdMiddleware factory works")
unittest
{
    auto mw = requestIdMiddleware();
    mw.shouldNotBeNull;
}

// Test 25: requestIdMiddleware(config) factory works
@("requestIdMiddleware config factory works")
unittest
{
    auto config = RequestIdConfig();
    config.headerName = "X-Trace-ID";
    
    auto mw = requestIdMiddleware(config);
    mw.shouldNotBeNull;
}
