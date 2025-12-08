/**
 * CORS Middleware Tests
 *
 * TDD: Aurora CORS Middleware
 *
 * Features:
 * - Preflight OPTIONS handling
 * - CORS headers (Origin, Methods, Headers)
 * - Origin validation
 * - Credentials support
 */
module tests.unit.web.cors_test;

import unit_threaded;
import aurora.web.middleware.cors;
import aurora.web.middleware;
import aurora.web.context;
import aurora.http;

// ========================================
// HELPER FUNCTIONS
// ========================================

/// Get header from response
string getHeader(HTTPResponse* response, string headerName)
{
    if (response is null) return "";
    auto headers = response.getHeaders();
    if (auto val = headerName in headers)
        return *val;
    return "";
}

/// Check if header exists in response
bool hasHeader(HTTPResponse* response, string headerName)
{
    if (response is null) return false;
    auto headers = response.getHeaders();
    return (headerName in headers) !is null;
}

/// Create test context with parsed request
struct TestContext
{
    Context ctx;
    HTTPResponse response;
    
    static TestContext createWithOrigin(string origin = "https://example.com")
    {
        TestContext tc;
        tc.response = HTTPResponse(200, "OK");
        tc.ctx.response = &tc.response;
        // Note: Cannot easily set request origin without real HTTP parsing
        // CORS middleware checks ctx.request for headers
        return tc;
    }
    
    static TestContext createSimple()
    {
        TestContext tc;
        tc.response = HTTPResponse(200, "OK");
        tc.ctx.response = &tc.response;
        return tc;
    }
}

// ========================================
// CONFIG TESTS
// ========================================

// Test 1: Default CORS config
@("default CORS config has wildcard origin")
unittest
{
    auto config = CORSConfig();
    
    config.allowedOrigins.shouldEqual(["*"]);
    config.allowedMethods.shouldEqual(["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]);
    config.allowedHeaders.shouldEqual(["*"]);
    config.allowCredentials.shouldBeFalse;
    config.maxAge.shouldEqual(86400);
}

// Test 2: Custom CORS config
@("custom CORS config")
unittest
{
    CORSConfig config;
    config.allowedOrigins = ["https://example.com", "https://app.example.com"];
    config.allowedMethods = ["GET", "POST"];
    config.allowedHeaders = ["Content-Type", "Authorization"];
    config.allowCredentials = true;
    config.maxAge = 3600;
    config.exposedHeaders = ["X-Request-Id"];
    
    config.allowedOrigins.shouldEqual(["https://example.com", "https://app.example.com"]);
    config.allowedMethods.shouldEqual(["GET", "POST"]);
    config.allowedHeaders.shouldEqual(["Content-Type", "Authorization"]);
    config.allowCredentials.shouldBeTrue;
    config.maxAge.shouldEqual(3600);
    config.exposedHeaders.shouldEqual(["X-Request-Id"]);
}

// ========================================
// MIDDLEWARE CREATION TESTS
// ========================================

// Test 3: CORSMiddleware can be created
@("CORSMiddleware can be created")
unittest
{
    auto config = CORSConfig();
    auto cors = new CORSMiddleware(config);
    
    assert(cors !is null, "CORS middleware should be created");
}

// Test 4: corsMiddleware helper creates middleware
@("corsMiddleware helper creates middleware")
unittest
{
    auto middleware = corsMiddleware();
    
    auto tc = TestContext.createSimple();
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    middleware(tc.ctx, &next);
    
    // Should call next for non-OPTIONS requests (without Origin header)
    nextCalled.shouldBeTrue;
}

// Test 5: corsMiddleware with custom config
@("corsMiddleware with custom config")
unittest
{
    CORSConfig config;
    config.allowedOrigins = ["https://trusted.com"];
    config.allowCredentials = true;
    
    auto middleware = corsMiddleware(config);
    
    auto tc = TestContext.createSimple();
    
    void next() { }
    
    middleware(tc.ctx, &next);
    
    // Without Origin header, credentials header not set
    // This tests that middleware doesn't crash
}

// ========================================
// CORS HEADERS TESTS (without real request)
// ========================================

// Test 6: CORS middleware calls next for normal requests
@("CORS middleware calls next for normal requests")
unittest
{
    auto config = CORSConfig();
    auto cors = new CORSMiddleware(config);
    
    auto tc = TestContext.createSimple();
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    cors.handle(tc.ctx, &next);
    
    nextCalled.shouldBeTrue;
}

// Test 7: CORS middleware handles null response
@("CORS middleware handles null response")
unittest
{
    auto config = CORSConfig();
    auto cors = new CORSMiddleware(config);
    
    Context ctx;
    ctx.response = null;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    // Should not crash
    cors.handle(ctx, &next);
    
    nextCalled.shouldBeTrue;
}

// Test 8: CORS middleware handles null request
@("CORS middleware handles null request")
unittest
{
    auto config = CORSConfig();
    auto cors = new CORSMiddleware(config);
    
    auto tc = TestContext.createSimple();
    tc.ctx.request = null;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    // Should not crash
    cors.handle(tc.ctx, &next);
    
    nextCalled.shouldBeTrue;
}

// ========================================
// WILDCARD ORIGIN TESTS
// ========================================

// Test 9: Wildcard origin returns *
@("wildcard origin returns asterisk")
unittest
{
    CORSConfig config;
    config.allowedOrigins = ["*"];
    
    auto cors = new CORSMiddleware(config);
    auto tc = TestContext.createSimple();
    
    void next() { }
    
    cors.handle(tc.ctx, &next);
    
    // Without request Origin header, wildcard behavior applies
    // Headers are set based on config
    getHeader(&tc.response, "Access-Control-Allow-Origin").shouldEqual("*");
}

// ========================================
// CREDENTIALS TESTS
// ========================================

// Test 10: Credentials enabled adds header
@("credentials enabled adds header")
unittest
{
    CORSConfig config;
    config.allowCredentials = true;
    
    auto cors = new CORSMiddleware(config);
    auto tc = TestContext.createSimple();
    
    void next() { }
    
    cors.handle(tc.ctx, &next);
    
    getHeader(&tc.response, "Access-Control-Allow-Credentials").shouldEqual("true");
}

// Test 11: Credentials disabled no header
@("credentials disabled no header")
unittest
{
    CORSConfig config;
    config.allowCredentials = false;
    
    auto cors = new CORSMiddleware(config);
    auto tc = TestContext.createSimple();
    
    void next() { }
    
    cors.handle(tc.ctx, &next);
    
    hasHeader(&tc.response, "Access-Control-Allow-Credentials").shouldBeFalse;
}

// ========================================
// EXPOSED HEADERS TESTS
// ========================================

// Test 12: Exposed headers are set
@("exposed headers are set")
unittest
{
    CORSConfig config;
    config.exposedHeaders = ["X-Request-Id", "X-Response-Time"];
    
    auto cors = new CORSMiddleware(config);
    auto tc = TestContext.createSimple();
    
    void next() { }
    
    cors.handle(tc.ctx, &next);
    
    getHeader(&tc.response, "Access-Control-Expose-Headers").shouldEqual("X-Request-Id,X-Response-Time");
}

// Test 13: No exposed headers when empty
@("no exposed headers when empty")
unittest
{
    CORSConfig config;
    config.exposedHeaders = [];
    
    auto cors = new CORSMiddleware(config);
    auto tc = TestContext.createSimple();
    
    void next() { }
    
    cors.handle(tc.ctx, &next);
    
    hasHeader(&tc.response, "Access-Control-Expose-Headers").shouldBeFalse;
}

// ========================================
// EMPTY ORIGINS TESTS
// ========================================

// Test 14: Empty allowed origins returns empty
@("empty allowed origins returns empty")
unittest
{
    CORSConfig config;
    config.allowedOrigins = [];
    
    auto cors = new CORSMiddleware(config);
    auto tc = TestContext.createSimple();
    
    void next() { }
    
    cors.handle(tc.ctx, &next);
    
    // With no allowed origins, no Allow-Origin header should be set
    hasHeader(&tc.response, "Access-Control-Allow-Origin").shouldBeFalse;
}

// ========================================
// PRODUCTION CONFIGURATIONS
// ========================================

// Test 15: Strict production config
@("strict production config")
unittest
{
    CORSConfig config;
    config.allowedOrigins = ["https://myapp.com"];
    config.allowedMethods = ["GET", "POST"];
    config.allowedHeaders = ["Content-Type", "Authorization"];
    config.allowCredentials = true;
    config.maxAge = 600;  // 10 minutes
    
    auto cors = new CORSMiddleware(config);
    auto tc = TestContext.createSimple();
    
    void next() { }
    
    cors.handle(tc.ctx, &next);
    
    // Should have credentials header
    getHeader(&tc.response, "Access-Control-Allow-Credentials").shouldEqual("true");
}

// Test 16: API Gateway config
@("API gateway config with multiple origins")
unittest
{
    CORSConfig config;
    config.allowedOrigins = [
        "https://web.example.com",
        "https://mobile.example.com",
        "https://admin.example.com"
    ];
    config.allowedMethods = ["GET", "POST", "PUT", "DELETE", "PATCH"];
    config.allowedHeaders = ["*"];
    config.exposedHeaders = ["X-Request-Id", "X-RateLimit-Remaining"];
    config.allowCredentials = false;
    config.maxAge = 86400;
    
    auto cors = new CORSMiddleware(config);
    
    // Should create without error
    assert(cors !is null);
}

// ========================================
// EDGE CASES
// ========================================

// Test 17: Single origin
@("single origin")
unittest
{
    CORSConfig config;
    config.allowedOrigins = ["https://only.example.com"];
    
    auto cors = new CORSMiddleware(config);
    auto tc = TestContext.createSimple();
    
    void next() { }
    
    cors.handle(tc.ctx, &next);
    
    // Without request Origin header, returns first allowed origin
    getHeader(&tc.response, "Access-Control-Allow-Origin").shouldEqual("https://only.example.com");
}

// Test 18: Single method
@("single method")
unittest
{
    CORSConfig config;
    config.allowedMethods = ["GET"];
    
    // Should create without error
    auto cors = new CORSMiddleware(config);
    assert(cors !is null);
}

// Test 19: Zero max age
@("zero max age")
unittest
{
    CORSConfig config;
    config.maxAge = 0;
    
    auto cors = new CORSMiddleware(config);
    assert(cors !is null);
}

// Test 20: Large max age
@("large max age")
unittest
{
    CORSConfig config;
    config.maxAge = 604800;  // 1 week
    
    auto cors = new CORSMiddleware(config);
    assert(cors !is null);
}
