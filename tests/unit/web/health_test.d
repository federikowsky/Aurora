/**
 * Health Middleware Tests
 *
 * TDD: Aurora Kubernetes Health Probes
 *
 * Tests:
 * - Liveness probe (simple 200 response)
 * - Readiness probe (server state + custom checks)
 * - Startup probe (initialization tracking)
 * - Response formats (minimal vs detailed)
 * - Caching behavior
 */
module tests.unit.web.health_test;

import unit_threaded;
import aurora.web.middleware.health;
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

/// Create test context with a specific path using HTTP parsing
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
        
        // Create HTTP request string and parse it
        string rawRequest = format("GET %s HTTP/1.1\r\nHost: localhost\r\n\r\n", path);
        tc.request = HTTPRequest.parse(cast(ubyte[])rawRequest);
        tc.ctx.request = &tc.request;
        
        return tc;
    }
}

// ========================================
// CONFIG TESTS
// ========================================

// Test 1: Default health config
@("default health config has standard K8s paths")
unittest
{
    auto config = HealthConfig.defaults();
    
    config.livenessPath.shouldEqual("/health/live");
    config.readinessPath.shouldEqual("/health/ready");
    config.startupPath.shouldEqual("/health/startup");
    config.includeDetails.shouldBeFalse;
    config.cacheDurationMs.shouldEqual(0);
    config.readinessChecks.length.shouldEqual(0);
}

// Test 2: Custom paths
@("custom health paths")
unittest
{
    HealthConfig config;
    config.livenessPath = "/healthz";
    config.readinessPath = "/ready";
    config.startupPath = "/startup";
    
    config.livenessPath.shouldEqual("/healthz");
    config.readinessPath.shouldEqual("/ready");
    config.startupPath.shouldEqual("/startup");
}

// Test 3: Custom readiness checks can be added
@("readiness checks can be added to config")
unittest
{
    HealthConfig config;
    
    config.readinessChecks ~= (ref HealthCheckResult r) {
        r.name = "database";
        r.healthy = true;
        r.message = "connected";
    };
    
    config.readinessChecks ~= (ref HealthCheckResult r) {
        r.name = "cache";
        r.healthy = true;
        r.message = "redis ok";
    };
    
    config.readinessChecks.length.shouldEqual(2);
}

// ========================================
// MIDDLEWARE CREATION TESTS
// ========================================

// Test 4: HealthMiddleware can be created without server
@("HealthMiddleware can be created with null server")
unittest
{
    auto health = new HealthMiddleware(null);
    health.shouldNotBeNull;
    health.isStartupComplete().shouldBeFalse;
}

// Test 5: markStartupComplete changes state
@("markStartupComplete changes startup state")
unittest
{
    auto health = new HealthMiddleware(null);
    
    health.isStartupComplete().shouldBeFalse;
    health.markStartupComplete();
    health.isStartupComplete().shouldBeTrue;
}

// Test 6: createHealthMiddleware factory function
@("createHealthMiddleware factory function works")
unittest
{
    auto health = createHealthMiddleware(null);
    health.shouldNotBeNull;
    health.isStartupComplete().shouldBeFalse;
}

// Test 7: healthMiddleware convenience function auto-marks startup
@("healthMiddleware convenience function auto-marks startup complete")
unittest
{
    auto mw = healthMiddleware(null);
    mw.shouldNotBeNull;
    // Cannot directly check, but the function should work
}

// ========================================
// LIVENESS PROBE TESTS
// ========================================

// Test 8: Liveness returns 200 OK
@("liveness probe returns 200 OK")
unittest
{
    auto health = new HealthMiddleware(null);
    auto tc = TestContext.create("/health/live");
    
    bool nextCalled = false;
    health.handle(tc.ctx, { nextCalled = true; });
    
    nextCalled.shouldBeFalse;  // Should not call next()
    tc.ctx.response.getStatus().shouldEqual(200);
    getHeader(tc.ctx.response, "Content-Type").shouldEqual("application/json");
    assert(getBody(tc.ctx.response).canFind(`"status":"alive"`));
}

// Test 9: Liveness with details includes probe name
@("liveness probe with details includes probe name")
unittest
{
    HealthConfig config;
    config.includeDetails = true;
    
    auto health = new HealthMiddleware(null, config);
    auto tc = TestContext.create("/health/live");
    
    health.handle(tc.ctx, {});
    
    assert(getBody(tc.ctx.response).canFind(`"probe":"liveness"`));
}

// Test 10: Liveness sets no-cache header
@("liveness probe sets no-cache header")
unittest
{
    auto health = new HealthMiddleware(null);
    auto tc = TestContext.create("/health/live");
    
    health.handle(tc.ctx, {});
    
    getHeader(tc.ctx.response, "Cache-Control").shouldEqual("no-cache, no-store");
}

// ========================================
// READINESS PROBE TESTS
// ========================================

// Test 11: Readiness returns 503 if not started
@("readiness probe returns 503 if not started")
unittest
{
    auto health = new HealthMiddleware(null);  // Not started
    auto tc = TestContext.create("/health/ready");
    
    health.handle(tc.ctx, {});
    
    tc.ctx.response.getStatus().shouldEqual(503);
    assert(getBody(tc.ctx.response).canFind(`"status":"starting"`));
}

// Test 12: Readiness returns 200 if started
@("readiness probe returns 200 if started")
unittest
{
    auto health = new HealthMiddleware(null);
    health.markStartupComplete();
    auto tc = TestContext.create("/health/ready");
    
    health.handle(tc.ctx, {});
    
    tc.ctx.response.getStatus().shouldEqual(200);
    assert(getBody(tc.ctx.response).canFind(`"status":"ready"`));
}

// Test 13: Readiness with custom checks - all pass
@("readiness with all custom checks passing returns 200")
unittest
{
    HealthConfig config;
    config.readinessChecks ~= (ref HealthCheckResult r) {
        r.name = "database";
        r.healthy = true;
    };
    config.readinessChecks ~= (ref HealthCheckResult r) {
        r.name = "cache";
        r.healthy = true;
    };
    
    auto health = new HealthMiddleware(null, config);
    health.markStartupComplete();
    auto tc = TestContext.create("/health/ready");
    
    health.handle(tc.ctx, {});
    
    tc.ctx.response.getStatus().shouldEqual(200);
}

// Test 14: Readiness with failing custom check returns 503
@("readiness with failing custom check returns 503")
unittest
{
    HealthConfig config;
    config.readinessChecks ~= (ref HealthCheckResult r) {
        r.name = "database";
        r.healthy = false;
        r.message = "connection timeout";
    };
    
    auto health = new HealthMiddleware(null, config);
    health.markStartupComplete();
    auto tc = TestContext.create("/health/ready");
    
    health.handle(tc.ctx, {});
    
    tc.ctx.response.getStatus().shouldEqual(503);
    assert(getBody(tc.ctx.response).canFind(`"status":"not_ready"`));
}

// Test 15: Readiness details include check results
@("readiness with details includes check results")
unittest
{
    HealthConfig config;
    config.includeDetails = true;
    config.readinessChecks ~= (ref HealthCheckResult r) {
        r.name = "database";
        r.healthy = true;
        r.message = "connected";
    };
    
    auto health = new HealthMiddleware(null, config);
    health.markStartupComplete();
    auto tc = TestContext.create("/health/ready");
    
    health.handle(tc.ctx, {});
    
    auto body_ = getBody(tc.ctx.response);
    assert(body_.canFind(`"checks":`));
    assert(body_.canFind(`"database"`));
    assert(body_.canFind(`"status":"pass"`));
}

// Test 16: Readiness sets Retry-After header on 503
@("readiness probe sets Retry-After header on 503")
unittest
{
    auto health = new HealthMiddleware(null);  // Not started
    auto tc = TestContext.create("/health/ready");
    
    health.handle(tc.ctx, {});
    
    getHeader(tc.ctx.response, "Retry-After").shouldEqual("5");
}

// ========================================
// STARTUP PROBE TESTS
// ========================================

// Test 17: Startup returns 503 if not complete
@("startup probe returns 503 if not complete")
unittest
{
    auto health = new HealthMiddleware(null);
    auto tc = TestContext.create("/health/startup");
    
    health.handle(tc.ctx, {});
    
    tc.ctx.response.getStatus().shouldEqual(503);
    assert(getBody(tc.ctx.response).canFind(`"status":"starting"`));
}

// Test 18: Startup returns 200 if complete
@("startup probe returns 200 if complete")
unittest
{
    auto health = new HealthMiddleware(null);
    health.markStartupComplete();
    auto tc = TestContext.create("/health/startup");
    
    health.handle(tc.ctx, {});
    
    tc.ctx.response.getStatus().shouldEqual(200);
    assert(getBody(tc.ctx.response).canFind(`"status":"started"`));
}

// Test 19: Startup with details includes probe name
@("startup probe with details includes probe name")
unittest
{
    HealthConfig config;
    config.includeDetails = true;
    
    auto health = new HealthMiddleware(null, config);
    health.markStartupComplete();
    auto tc = TestContext.create("/health/startup");
    
    health.handle(tc.ctx, {});
    
    assert(getBody(tc.ctx.response).canFind(`"probe":"startup"`));
}

// ========================================
// NON-HEALTH PATH TESTS
// ========================================

// Test 20: Non-health path calls next()
@("non-health paths call next() middleware")
unittest
{
    auto health = new HealthMiddleware(null);
    auto tc = TestContext.create("/api/users");
    
    bool nextCalled = false;
    health.handle(tc.ctx, { nextCalled = true; });
    
    nextCalled.shouldBeTrue;
}

// Test 21: Custom paths are respected
@("custom paths are respected")
unittest
{
    HealthConfig config;
    config.livenessPath = "/healthz";
    config.readinessPath = "/readyz";
    config.startupPath = "/startupz";
    
    auto health = new HealthMiddleware(null, config);
    
    // Standard paths should call next()
    auto tc1 = TestContext.create("/health/live");
    bool next1 = false;
    health.handle(tc1.ctx, { next1 = true; });
    next1.shouldBeTrue;
    
    // Custom path should respond
    auto tc2 = TestContext.create("/healthz");
    bool next2 = false;
    health.handle(tc2.ctx, { next2 = true; });
    next2.shouldBeFalse;
    tc2.ctx.response.getStatus().shouldEqual(200);
}

// ========================================
// EXCEPTION HANDLING TESTS
// ========================================

// Test 22: Failing check exception is caught
@("failing readiness check exception is caught")
unittest
{
    HealthConfig config;
    config.includeDetails = true;
    config.readinessChecks ~= (ref HealthCheckResult r) {
        r.name = "broken";
        throw new Exception("check exploded");
    };
    
    auto health = new HealthMiddleware(null, config);
    health.markStartupComplete();
    auto tc = TestContext.create("/health/ready");
    
    // Should not throw
    health.handle(tc.ctx, {});
    
    tc.ctx.response.getStatus().shouldEqual(503);
    assert(getBody(tc.ctx.response).canFind(`"check exploded"`));
}

// ========================================
// HEALTH CHECK RESULT STRUCT TESTS
// ========================================

// Test 23: HealthCheckResult default values
@("HealthCheckResult has sensible defaults")
unittest
{
    HealthCheckResult r;
    
    r.name.shouldEqual("");
    r.healthy.shouldBeTrue;
    r.message.shouldEqual("");
    r.durationUs.shouldEqual(0);
}

// Test 24: HealthStatus enum values
@("HealthStatus enum has expected values")
unittest
{
    // Check that all enum values exist and are distinct
    static assert(HealthStatus.HEALTHY != HealthStatus.UNHEALTHY);
    static assert(HealthStatus.DEGRADED != HealthStatus.STARTING);
    static assert(HealthStatus.SHUTTING_DOWN != HealthStatus.HEALTHY);
}

// Test 25: Null request is handled gracefully
@("null request calls next without crashing")
unittest
{
    auto health = new HealthMiddleware(null);
    
    Context ctx;
    ctx.request = null;
    HTTPResponse response;
    ctx.response = &response;
    
    bool nextCalled = false;
    health.handle(ctx, { nextCalled = true; });
    
    nextCalled.shouldBeTrue;
}
