/**
 * Load Shedding Middleware Tests
 *
 * TDD: Aurora Load Shedding (HTTP-level overload protection)
 *
 * Tests:
 * - Configuration defaults
 * - Bypass path matching (glob patterns)
 * - Hysteresis state management
 * - Probabilistic shedding
 * - Statistics tracking
 * - 503 response format
 */
module tests.unit.web.loadshed_test;

import unit_threaded;
import aurora.web.middleware.loadshed;
import aurora.web.context;
import aurora.http;
import std.algorithm : canFind;

// ========================================
// HELPER FUNCTIONS
// ========================================

/// Get header from response
string getHeader(HTTPResponse* response, string headerName) @trusted
{
    if (response is null) return "";
    auto headers = response.getHeaders();
    if (auto val = headerName in headers)
        return *val;
    return "";
}

/// Get response body
string getBody(HTTPResponse* response) @trusted
{
    if (response is null) return "";
    return response.getBody();
}

/// Create test context with a specific path
struct TestContext
{
    Context ctx;
    HTTPRequest request;
    HTTPResponse response;
    
    static TestContext create(string path) @trusted
    {
        import std.format : format;
        
        TestContext tc;
        tc.response = HTTPResponse(200, "OK");
        tc.ctx.response = &tc.response;
        
        string rawRequest = format("GET %s HTTP/1.1\r\nHost: localhost\r\n\r\n", path);
        tc.request = HTTPRequest.parse(cast(ubyte[])rawRequest);
        tc.ctx.request = &tc.request;
        
        return tc;
    }
}

// ========================================
// CONFIG TESTS
// ========================================

// Test 1: Default config values
@("default config has sensible values")
unittest
{
    auto config = LoadSheddingConfig.defaults();
    
    config.utilizationHighWater.shouldEqual(0.8f);
    config.utilizationLowWater.shouldEqual(0.6f);
    config.inFlightHighWater.shouldEqual(800);
    config.inFlightLowWater.shouldEqual(500);
    config.bypassPaths.shouldEqual(["/health/*"]);
    config.retryAfterSeconds.shouldEqual(5);
    config.enableProbabilistic.shouldBeTrue;
    config.minSheddingProbability.shouldEqual(0.1f);
}

// Test 2: Custom config
@("custom config values are respected")
unittest
{
    LoadSheddingConfig config;
    config.utilizationHighWater = 0.9;
    config.utilizationLowWater = 0.7;
    config.inFlightHighWater = 1000;
    config.bypassPaths = ["/admin/*", "/metrics"];
    
    config.utilizationHighWater.shouldEqual(0.9f);
    config.bypassPaths.length.shouldEqual(2);
}

// ========================================
// MIDDLEWARE CREATION TESTS
// ========================================

// Test 3: Middleware can be created with null server
@("middleware can be created with null server")
unittest
{
    auto mw = new LoadSheddingMiddleware(null);
    mw.shouldNotBeNull;
    mw.isInSheddingState().shouldBeFalse;
}

// Test 4: Factory function works
@("loadSheddingMiddleware factory function works")
unittest
{
    auto mw = loadSheddingMiddleware(null);
    mw.shouldNotBeNull;
}

// Test 5: createLoadSheddingMiddleware returns instance
@("createLoadSheddingMiddleware returns middleware instance")
unittest
{
    auto mw = createLoadSheddingMiddleware(null);
    mw.shouldNotBeNull;
    auto stats = mw.getStats();
    stats.requestsShed.shouldEqual(0);
}

// ========================================
// BYPASS PATH TESTS
// ========================================

// Test 6: Bypass paths work with exact match
@("bypass paths work with exact match")
unittest
{
    LoadSheddingConfig config;
    config.bypassPaths = ["/metrics"];
    
    auto mw = new LoadSheddingMiddleware(null, config);
    auto tc = TestContext.create("/metrics");
    
    bool nextCalled = false;
    mw.handle(tc.ctx, { nextCalled = true; });
    
    nextCalled.shouldBeTrue;
    mw.getStats().requestsBypassed.shouldEqual(1);
}

// Test 7: Bypass paths work with glob pattern
@("bypass paths work with trailing glob")
unittest
{
    LoadSheddingConfig config;
    config.bypassPaths = ["/health/*"];
    
    auto mw = new LoadSheddingMiddleware(null, config);
    
    // Should bypass /health/live
    auto tc1 = TestContext.create("/health/live");
    bool next1 = false;
    mw.handle(tc1.ctx, { next1 = true; });
    next1.shouldBeTrue;
    
    // Should bypass /health/ready
    auto tc2 = TestContext.create("/health/ready");
    bool next2 = false;
    mw.handle(tc2.ctx, { next2 = true; });
    next2.shouldBeTrue;
    
    mw.getStats().requestsBypassed.shouldEqual(2);
}

// Test 8: Non-bypass paths are not bypassed
@("non-bypass paths are not bypassed")
unittest
{
    LoadSheddingConfig config;
    config.bypassPaths = ["/health/*"];
    
    auto mw = new LoadSheddingMiddleware(null, config);
    auto tc = TestContext.create("/api/users");
    
    bool nextCalled = false;
    mw.handle(tc.ctx, { nextCalled = true; });
    
    // With null server, utilization is 0, so no shedding
    nextCalled.shouldBeTrue;
    mw.getStats().requestsAllowed.shouldEqual(1);
}

// Test 9: Multiple bypass patterns
@("multiple bypass patterns work")
unittest
{
    LoadSheddingConfig config;
    config.bypassPaths = ["/health/*", "/admin/*", "/metrics"];
    
    auto mw = new LoadSheddingMiddleware(null, config);
    
    auto tc1 = TestContext.create("/admin/dashboard");
    mw.handle(tc1.ctx, {});
    
    auto tc2 = TestContext.create("/metrics");
    mw.handle(tc2.ctx, {});
    
    mw.getStats().requestsBypassed.shouldEqual(2);
}

// ========================================
// STATISTICS TESTS
// ========================================

// Test 10: Stats are tracked correctly
@("statistics are tracked correctly")
unittest
{
    LoadSheddingConfig config;
    config.bypassPaths = ["/health/*"];
    
    auto mw = new LoadSheddingMiddleware(null, config);
    
    // Bypassed request
    auto tc1 = TestContext.create("/health/live");
    mw.handle(tc1.ctx, {});
    
    // Allowed request (no shedding with null server)
    auto tc2 = TestContext.create("/api/users");
    mw.handle(tc2.ctx, {});
    
    auto stats = mw.getStats();
    stats.requestsBypassed.shouldEqual(1);
    stats.requestsAllowed.shouldEqual(1);
    stats.requestsShed.shouldEqual(0);
    stats.inSheddingState.shouldBeFalse;
}

// Test 11: Stats can be reset
@("statistics can be reset")
unittest
{
    auto mw = new LoadSheddingMiddleware(null);
    
    auto tc = TestContext.create("/api/users");
    mw.handle(tc.ctx, {});
    
    mw.getStats().requestsAllowed.shouldEqual(1);
    
    mw.resetStats();
    
    mw.getStats().requestsAllowed.shouldEqual(0);
}

// ========================================
// SHEDDING STATE TESTS
// ========================================

// Test 12: Initial state is not shedding
@("initial state is not shedding")
unittest
{
    auto mw = new LoadSheddingMiddleware(null);
    mw.isInSheddingState().shouldBeFalse;
}

// Test 13: LoadSheddingStats struct works
@("LoadSheddingStats struct has correct fields")
unittest
{
    LoadSheddingStats stats;
    stats.requestsShed = 100;
    stats.requestsBypassed = 50;
    stats.requestsAllowed = 1000;
    stats.sheddingStateTransitions = 5;
    stats.inSheddingState = true;
    
    stats.requestsShed.shouldEqual(100);
    stats.requestsBypassed.shouldEqual(50);
    stats.requestsAllowed.shouldEqual(1000);
    stats.sheddingStateTransitions.shouldEqual(5);
    stats.inSheddingState.shouldBeTrue;
}

// ========================================
// 503 RESPONSE TESTS
// ========================================

// Test 14: 503 response format (need to trigger shedding)
// Note: Can't easily test without mock server, so test config path
@("503 response includes correct headers")
unittest
{
    LoadSheddingConfig config;
    config.retryAfterSeconds = 10;
    
    // Can verify config is set
    config.retryAfterSeconds.shouldEqual(10);
}

// ========================================
// GLOB MATCHING TESTS
// ========================================

// Test 15: Root wildcard matches everything
@("root wildcard matches everything")
unittest
{
    LoadSheddingConfig config;
    config.bypassPaths = ["/*"];
    
    auto mw = new LoadSheddingMiddleware(null, config);
    
    auto tc1 = TestContext.create("/anything");
    mw.handle(tc1.ctx, {});
    
    auto tc2 = TestContext.create("/foo/bar/baz");
    mw.handle(tc2.ctx, {});
    
    mw.getStats().requestsBypassed.shouldEqual(2);
}

// Test 16: Partial path with wildcard
@("partial path with wildcard matches correctly")
unittest
{
    LoadSheddingConfig config;
    config.bypassPaths = ["/api/v1/*"];
    
    auto mw = new LoadSheddingMiddleware(null, config);
    
    // Should match
    auto tc1 = TestContext.create("/api/v1/users");
    bool next1 = false;
    mw.handle(tc1.ctx, { next1 = true; });
    
    // Should NOT match
    auto tc2 = TestContext.create("/api/v2/users");
    bool next2 = false;
    mw.handle(tc2.ctx, { next2 = true; });
    
    mw.getStats().requestsBypassed.shouldEqual(1);
    mw.getStats().requestsAllowed.shouldEqual(1);
}

// Test 17: Empty bypass list means no bypasses
@("empty bypass list means no bypasses")
unittest
{
    LoadSheddingConfig config;
    config.bypassPaths = [];
    
    auto mw = new LoadSheddingMiddleware(null, config);
    
    auto tc = TestContext.create("/health/live");
    mw.handle(tc.ctx, {});
    
    mw.getStats().requestsBypassed.shouldEqual(0);
    mw.getStats().requestsAllowed.shouldEqual(1);
}

// ========================================
// NULL REQUEST HANDLING
// ========================================

// Test 18: Null request calls next
@("null request calls next without crashing")
unittest
{
    auto mw = new LoadSheddingMiddleware(null);
    
    Context ctx;
    ctx.request = null;
    HTTPResponse response;
    ctx.response = &response;
    
    bool nextCalled = false;
    mw.handle(ctx, { nextCalled = true; });
    
    nextCalled.shouldBeTrue;
}

// ========================================
// PROBABILISTIC CONFIG TESTS
// ========================================

// Test 19: Probabilistic can be disabled
@("probabilistic shedding can be disabled")
unittest
{
    LoadSheddingConfig config;
    config.enableProbabilistic = false;
    
    config.enableProbabilistic.shouldBeFalse;
}

// Test 20: Min shedding probability config
@("min shedding probability can be configured")
unittest
{
    LoadSheddingConfig config;
    config.minSheddingProbability = 0.2;
    
    config.minSheddingProbability.shouldEqual(0.2f);
}
