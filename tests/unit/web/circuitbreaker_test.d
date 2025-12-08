/**
 * Circuit Breaker Middleware Tests
 *
 * TDD: Aurora Circuit Breaker (Failure Isolation)
 *
 * Tests:
 * - Configuration defaults
 * - State transitions (CLOSED → OPEN → HALF_OPEN → CLOSED)
 * - Failure threshold detection
 * - Success threshold recovery
 * - Reset timeout behavior
 * - Bypass path matching
 * - Statistics tracking
 * - 503 response format
 * - Manual reset
 */
module tests.unit.web.circuitbreaker_test;

import unit_threaded;
import aurora.web.middleware.circuitbreaker;
import aurora.web.context;
import aurora.http;
import core.time : seconds, msecs;
import core.thread : Thread;

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
    auto config = CircuitBreakerConfig.defaults();
    
    config.failureThreshold.shouldEqual(5);
    config.successThreshold.shouldEqual(3);
    config.resetTimeout.shouldEqual(30.seconds);
    config.halfOpenMaxRequests.shouldEqual(3);
    config.bypassPaths.shouldEqual(["/health/*"]);
    config.retryAfterSeconds.shouldEqual(30);
    config.failureStatusCodes.shouldEqual([500, 502, 503, 504]);
}

// Test 2: Custom config
@("custom config values are respected")
unittest
{
    CircuitBreakerConfig config;
    config.failureThreshold = 10;
    config.successThreshold = 5;
    config.resetTimeout = 60.seconds;
    config.bypassPaths = ["/admin/*", "/metrics"];
    
    config.failureThreshold.shouldEqual(10);
    config.successThreshold.shouldEqual(5);
    config.resetTimeout.shouldEqual(60.seconds);
    config.bypassPaths.length.shouldEqual(2);
}

// ========================================
// MIDDLEWARE CREATION TESTS
// ========================================

// Test 3: Middleware can be created
@("middleware can be created")
unittest
{
    auto mw = new CircuitBreakerMiddleware();
    mw.shouldNotBeNull;
    mw.isClosed().shouldBeTrue;
    mw.isOpen().shouldBeFalse;
}

// Test 4: Factory function works
@("circuitBreakerMiddleware factory function works")
unittest
{
    auto mw = circuitBreakerMiddleware();
    mw.shouldNotBeNull;
}

// Test 5: createCircuitBreakerMiddleware returns instance
@("createCircuitBreakerMiddleware returns middleware instance")
unittest
{
    auto mw = createCircuitBreakerMiddleware();
    mw.shouldNotBeNull;
    auto stats = mw.getStats();
    stats.totalRequests.shouldEqual(0);
    stats.currentState.shouldEqual(CircuitState.CLOSED);
}

// ========================================
// STATE TESTS
// ========================================

// Test 6: Initial state is CLOSED
@("initial state is CLOSED")
unittest
{
    auto mw = new CircuitBreakerMiddleware();
    mw.getCurrentState().shouldEqual(CircuitState.CLOSED);
    mw.isClosed().shouldBeTrue;
}

// Test 7: CircuitState enum values
@("CircuitState enum has correct values")
unittest
{
    auto closed = CircuitState.CLOSED;
    auto open = CircuitState.OPEN;
    auto halfOpen = CircuitState.HALF_OPEN;
    
    closed.shouldEqual(CircuitState.CLOSED);
    open.shouldEqual(CircuitState.OPEN);
    halfOpen.shouldEqual(CircuitState.HALF_OPEN);
}

// ========================================
// BYPASS PATH TESTS
// ========================================

// Test 8: Bypass paths work with exact match
@("bypass paths work with exact match")
unittest
{
    CircuitBreakerConfig config;
    config.bypassPaths = ["/metrics"];
    
    auto mw = new CircuitBreakerMiddleware(config);
    auto tc = TestContext.create("/metrics");
    
    bool nextCalled = false;
    mw.handle(tc.ctx, { nextCalled = true; });
    
    nextCalled.shouldBeTrue;
    mw.getStats().bypassedRequests.shouldEqual(1);
    mw.getStats().totalRequests.shouldEqual(0); // Bypassed don't count
}

// Test 9: Bypass paths work with glob pattern
@("bypass paths work with trailing glob")
unittest
{
    CircuitBreakerConfig config;
    config.bypassPaths = ["/health/*"];
    
    auto mw = new CircuitBreakerMiddleware(config);
    
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
    
    mw.getStats().bypassedRequests.shouldEqual(2);
}

// Test 10: Non-bypass paths are not bypassed
@("non-bypass paths are not bypassed")
unittest
{
    CircuitBreakerConfig config;
    config.bypassPaths = ["/health/*"];
    
    auto mw = new CircuitBreakerMiddleware(config);
    auto tc = TestContext.create("/api/users");
    
    bool nextCalled = false;
    mw.handle(tc.ctx, { nextCalled = true; });
    
    nextCalled.shouldBeTrue;
    mw.getStats().totalRequests.shouldEqual(1);
}

// ========================================
// FAILURE DETECTION TESTS
// ========================================

// Test 11: 500 status is counted as failure
@("500 status is counted as failure")
unittest
{
    CircuitBreakerConfig config;
    config.failureThreshold = 10; // High threshold so we don't trip
    
    auto mw = new CircuitBreakerMiddleware(config);
    auto tc = TestContext.create("/api/users");
    
    mw.handle(tc.ctx, { 
        tc.ctx.status(500);
    });
    
    mw.getStats().failedRequests.shouldEqual(1);
    mw.getStats().successfulRequests.shouldEqual(0);
}

// Test 12: 200 status is counted as success
@("200 status is counted as success")
unittest
{
    auto mw = new CircuitBreakerMiddleware();
    auto tc = TestContext.create("/api/users");
    
    mw.handle(tc.ctx, { 
        tc.ctx.status(200);
    });
    
    mw.getStats().successfulRequests.shouldEqual(1);
    mw.getStats().failedRequests.shouldEqual(0);
}

// Test 13: Custom failure status codes
@("custom failure status codes are respected")
unittest
{
    CircuitBreakerConfig config;
    config.failureStatusCodes = [429]; // Rate limited
    config.failureThreshold = 10;
    
    auto mw = new CircuitBreakerMiddleware(config);
    
    // 429 should be failure
    auto tc1 = TestContext.create("/api/users");
    mw.handle(tc1.ctx, { tc1.ctx.status(429); });
    
    // 500 should NOT be failure (not in our list)
    auto tc2 = TestContext.create("/api/users");
    mw.handle(tc2.ctx, { tc2.ctx.status(500); });
    
    mw.getStats().failedRequests.shouldEqual(1);
    mw.getStats().successfulRequests.shouldEqual(1);
}

// ========================================
// STATE TRANSITION TESTS
// ========================================

// Test 14: Circuit opens after failure threshold
@("circuit opens after failure threshold")
unittest
{
    CircuitBreakerConfig config;
    config.failureThreshold = 3;
    
    auto mw = new CircuitBreakerMiddleware(config);
    
    // Initial state
    mw.isClosed().shouldBeTrue;
    
    // Generate failures
    foreach (i; 0 .. 3)
    {
        auto tc = TestContext.create("/api/users");
        mw.handle(tc.ctx, { tc.ctx.status(500); });
    }
    
    // Circuit should be open now
    mw.isOpen().shouldBeTrue;
    mw.getStats().timesOpened.shouldEqual(1);
}

// Test 15: Open circuit rejects requests
@("open circuit rejects requests with 503")
unittest
{
    CircuitBreakerConfig config;
    config.failureThreshold = 2;
    
    auto mw = new CircuitBreakerMiddleware(config);
    
    // Trip the circuit
    foreach (i; 0 .. 2)
    {
        auto tc = TestContext.create("/api/users");
        mw.handle(tc.ctx, { tc.ctx.status(500); });
    }
    
    mw.isOpen().shouldBeTrue;
    
    // Next request should be rejected
    auto tc = TestContext.create("/api/users");
    bool nextCalled = false;
    mw.handle(tc.ctx, { nextCalled = true; });
    
    nextCalled.shouldBeFalse;
    tc.ctx.response.getStatus().shouldEqual(503);
    mw.getStats().rejectedRequests.shouldEqual(1);
}

// Test 16: Consecutive failures are tracked
@("consecutive failures are tracked correctly")
unittest
{
    CircuitBreakerConfig config;
    config.failureThreshold = 10;
    
    auto mw = new CircuitBreakerMiddleware(config);
    
    // 3 failures
    foreach (i; 0 .. 3)
    {
        auto tc = TestContext.create("/api/users");
        mw.handle(tc.ctx, { tc.ctx.status(500); });
    }
    
    mw.getStats().consecutiveFailures.shouldEqual(3);
    
    // 1 success resets consecutive failures
    auto tcSuccess = TestContext.create("/api/users");
    mw.handle(tcSuccess.ctx, { tcSuccess.ctx.status(200); });
    
    mw.getStats().consecutiveFailures.shouldEqual(0);
}

// ========================================
// STATISTICS TESTS
// ========================================

// Test 17: Stats are tracked correctly
@("statistics are tracked correctly")
unittest
{
    CircuitBreakerConfig config;
    config.bypassPaths = ["/health/*"];
    config.failureThreshold = 10;
    
    auto mw = new CircuitBreakerMiddleware(config);
    
    // Bypassed request
    auto tc1 = TestContext.create("/health/live");
    mw.handle(tc1.ctx, {});
    
    // Successful request
    auto tc2 = TestContext.create("/api/users");
    mw.handle(tc2.ctx, { tc2.ctx.status(200); });
    
    // Failed request
    auto tc3 = TestContext.create("/api/users");
    mw.handle(tc3.ctx, { tc3.ctx.status(500); });
    
    auto stats = mw.getStats();
    stats.bypassedRequests.shouldEqual(1);
    stats.totalRequests.shouldEqual(2);
    stats.successfulRequests.shouldEqual(1);
    stats.failedRequests.shouldEqual(1);
}

// Test 18: Stats can be reset
@("statistics can be reset")
unittest
{
    auto mw = new CircuitBreakerMiddleware();
    
    auto tc = TestContext.create("/api/users");
    mw.handle(tc.ctx, {});
    
    mw.getStats().totalRequests.shouldEqual(1);
    
    mw.resetStats();
    
    mw.getStats().totalRequests.shouldEqual(0);
}

// Test 19: CircuitBreakerStats struct works
@("CircuitBreakerStats struct has correct fields")
unittest
{
    CircuitBreakerStats stats;
    stats.totalRequests = 100;
    stats.successfulRequests = 80;
    stats.failedRequests = 20;
    stats.rejectedRequests = 5;
    stats.timesOpened = 2;
    stats.currentState = CircuitState.OPEN;
    
    stats.totalRequests.shouldEqual(100);
    stats.successfulRequests.shouldEqual(80);
    stats.failedRequests.shouldEqual(20);
    stats.rejectedRequests.shouldEqual(5);
    stats.timesOpened.shouldEqual(2);
    stats.currentState.shouldEqual(CircuitState.OPEN);
}

// ========================================
// MANUAL RESET TESTS
// ========================================

// Test 20: Manual reset closes circuit
@("manual reset closes circuit")
unittest
{
    CircuitBreakerConfig config;
    config.failureThreshold = 2;
    
    auto mw = new CircuitBreakerMiddleware(config);
    
    // Trip the circuit
    foreach (i; 0 .. 2)
    {
        auto tc = TestContext.create("/api/users");
        mw.handle(tc.ctx, { tc.ctx.status(500); });
    }
    
    mw.isOpen().shouldBeTrue;
    
    // Manual reset
    mw.reset();
    
    mw.isClosed().shouldBeTrue;
    mw.getStats().consecutiveFailures.shouldEqual(0);
}

// ========================================
// 503 RESPONSE FORMAT TESTS
// ========================================

// Test 21: 503 response has correct headers
@("503 response includes correct headers")
unittest
{
    CircuitBreakerConfig config;
    config.failureThreshold = 1;
    config.retryAfterSeconds = 60;
    
    auto mw = new CircuitBreakerMiddleware(config);
    
    // Trip the circuit
    auto tc1 = TestContext.create("/api/users");
    mw.handle(tc1.ctx, { tc1.ctx.status(500); });
    
    // Get rejected response
    auto tc2 = TestContext.create("/api/users");
    mw.handle(tc2.ctx, {});
    
    tc2.ctx.response.getStatus().shouldEqual(503);
    
    auto contentType = getHeader(tc2.ctx.response, "Content-Type");
    contentType.shouldEqual("application/json");
    
    auto circuitState = getHeader(tc2.ctx.response, "X-Circuit-State");
    circuitState.shouldEqual("open");
    
    auto cacheControl = getHeader(tc2.ctx.response, "Cache-Control");
    cacheControl.shouldEqual("no-cache, no-store");
}

// Test 22: 503 response body is valid JSON
@("503 response body is valid JSON")
unittest
{
    CircuitBreakerConfig config;
    config.failureThreshold = 1;
    
    auto mw = new CircuitBreakerMiddleware(config);
    
    // Trip the circuit
    auto tc1 = TestContext.create("/api/users");
    mw.handle(tc1.ctx, { tc1.ctx.status(500); });
    
    // Get rejected response
    auto tc2 = TestContext.create("/api/users");
    mw.handle(tc2.ctx, {});
    
    auto body = getBody(tc2.ctx.response);
    body.shouldNotBeNull;
    // Should contain error and reason
    import std.algorithm : canFind;
    body.canFind("error").shouldBeTrue;
    body.canFind("circuit_open").shouldBeTrue;
}

// ========================================
// NULL REQUEST HANDLING
// ========================================

// Test 23: Null request calls next
@("null request calls next without crashing")
unittest
{
    auto mw = new CircuitBreakerMiddleware();
    
    Context ctx;
    ctx.request = null;
    HTTPResponse response;
    ctx.response = &response;
    
    bool nextCalled = false;
    mw.handle(ctx, { nextCalled = true; });
    
    nextCalled.shouldBeTrue;
}

// ========================================
// HALF_OPEN STATE TESTS
// ========================================

// Test 24: Half-open allows limited requests
@("half-open state allows limited requests")
unittest
{
    CircuitBreakerConfig config;
    config.failureThreshold = 1;
    config.resetTimeout = 1.msecs; // Very short for testing
    config.halfOpenMaxRequests = 2;
    config.successThreshold = 2;
    
    auto mw = new CircuitBreakerMiddleware(config);
    
    // Trip the circuit
    auto tc1 = TestContext.create("/api/users");
    mw.handle(tc1.ctx, { tc1.ctx.status(500); });
    
    mw.isOpen().shouldBeTrue;
    
    // Wait for reset timeout
    Thread.sleep(5.msecs);
    
    // First request in half-open - should go through
    auto tc2 = TestContext.create("/api/users");
    bool next2 = false;
    mw.handle(tc2.ctx, { next2 = true; tc2.ctx.status(200); });
    next2.shouldBeTrue;
}

// Test 25: Success in half-open can close circuit
@("success in half-open closes circuit after threshold")
unittest
{
    CircuitBreakerConfig config;
    config.failureThreshold = 1;
    config.resetTimeout = 1.msecs;
    config.halfOpenMaxRequests = 5;
    config.successThreshold = 2;
    
    auto mw = new CircuitBreakerMiddleware(config);
    
    // Trip the circuit
    auto tc1 = TestContext.create("/api/users");
    mw.handle(tc1.ctx, { tc1.ctx.status(500); });
    
    Thread.sleep(5.msecs);
    
    // Two successes in half-open should close circuit
    foreach (i; 0 .. 2)
    {
        auto tc = TestContext.create("/api/users");
        mw.handle(tc.ctx, { tc.ctx.status(200); });
    }
    
    mw.isClosed().shouldBeTrue;
    mw.getStats().timesClosed.shouldEqual(1);
}

// Test 26: Failure in half-open reopens circuit
@("failure in half-open reopens circuit")
unittest
{
    CircuitBreakerConfig config;
    config.failureThreshold = 1;
    config.resetTimeout = 1.msecs;
    config.halfOpenMaxRequests = 5;
    
    auto mw = new CircuitBreakerMiddleware(config);
    
    // Trip the circuit
    auto tc1 = TestContext.create("/api/users");
    mw.handle(tc1.ctx, { tc1.ctx.status(500); });
    
    Thread.sleep(5.msecs);
    
    // Failure in half-open should reopen
    auto tc2 = TestContext.create("/api/users");
    mw.handle(tc2.ctx, { tc2.ctx.status(500); });
    
    mw.isOpen().shouldBeTrue;
    mw.getStats().timesOpened.shouldEqual(2);
}

// ========================================
// GLOB MATCHING TESTS
// ========================================

// Test 27: Root wildcard matches everything
@("root wildcard matches everything")
unittest
{
    CircuitBreakerConfig config;
    config.bypassPaths = ["/*"];
    
    auto mw = new CircuitBreakerMiddleware(config);
    
    auto tc1 = TestContext.create("/anything");
    mw.handle(tc1.ctx, {});
    
    auto tc2 = TestContext.create("/foo/bar/baz");
    mw.handle(tc2.ctx, {});
    
    mw.getStats().bypassedRequests.shouldEqual(2);
}

// Test 28: Empty bypass list means no bypasses
@("empty bypass list means no bypasses")
unittest
{
    CircuitBreakerConfig config;
    config.bypassPaths = [];
    
    auto mw = new CircuitBreakerMiddleware(config);
    
    auto tc = TestContext.create("/health/live");
    mw.handle(tc.ctx, {});
    
    mw.getStats().bypassedRequests.shouldEqual(0);
    mw.getStats().totalRequests.shouldEqual(1);
}

// ========================================
// CONCURRENT ACCESS TESTS
// ========================================

// Test 29: Middleware delegate is safe
@("middleware delegate can be obtained")
unittest
{
    auto cb = createCircuitBreakerMiddleware();
    auto mw = cb.middleware();
    mw.shouldNotBeNull;
}

// Test 30: Empty failure status codes means only exceptions count
@("empty failure status codes means only exceptions count as failures")
unittest
{
    CircuitBreakerConfig config;
    config.failureStatusCodes = []; // Empty = no status codes are failures
    config.failureThreshold = 10;
    
    auto mw = new CircuitBreakerMiddleware(config);
    
    // 500 should NOT be failure
    auto tc = TestContext.create("/api/users");
    mw.handle(tc.ctx, { tc.ctx.status(500); });
    
    mw.getStats().failedRequests.shouldEqual(0);
    mw.getStats().successfulRequests.shouldEqual(1);
}
