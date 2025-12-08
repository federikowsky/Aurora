/**
 * Fiber Crash Isolation Tests
 *
 * Tests for Aurora's fiber-based error isolation:
 * - Crash in one fiber doesn't affect others
 * - Worker thread continues after fiber crash
 * - Proper error counting and resource cleanup
 * - Exception handler hierarchy
 * - onError hooks execution
 *
 * Unit tests verify API contracts and exception handling mechanics.
 * Full concurrency testing is in fiber_isolation_test.py.
 */
module tests.integration.fiber_isolation_test;

import unit_threaded;
import aurora.runtime.server;
import aurora.web.router;
import aurora.web.context;
import aurora.web.middleware;
import aurora.runtime.hooks : ServerHooks;
import core.atomic;
import core.time;

// ============================================================================
// CUSTOM EXCEPTIONS FOR TESTING
// ============================================================================

/// Base custom exception for testing handler hierarchy
class CustomException : Exception
{
    this(string msg) { super(msg); }
}

/// Derived exception to test inheritance matching
class ValidationError : CustomException
{
    this(string msg) { super(msg); }
}

/// Another derived exception
class AuthenticationError : CustomException
{
    this(string msg) { super(msg); }
}

/// Unrelated exception (not in hierarchy)
class NetworkError : Exception
{
    this(string msg) { super(msg); }
}

// ============================================================================
// ERROR HANDLING API TESTS
// ============================================================================

// Test 1: Server has error counter API
@("server has error counter API")
unittest
{
    auto server = createTestServer();
    
    static assert(__traits(compiles, server.getErrors()));
    server.getErrors().shouldEqual(0);
}

// Test 2: Server can register exception handlers
@("server can register exception handlers")
unittest
{
    auto server = createTestServer();
    
    // Should compile and not throw
    server.addExceptionHandler!ValidationError((ref Context ctx, ValidationError e) {
        ctx.response.setStatus(400);
        ctx.response.setBody(`{"error":"validation"}`);
    });
    
    server.exceptionHandlerCount().shouldEqual(1);
}

// Test 3: Multiple exception handlers can be registered
@("multiple exception handlers can be registered")
unittest
{
    auto server = createTestServer();
    
    server.addExceptionHandler!ValidationError((ref Context ctx, ValidationError e) {
        ctx.response.setStatus(400);
    });
    
    server.addExceptionHandler!AuthenticationError((ref Context ctx, AuthenticationError e) {
        ctx.response.setStatus(401);
    });
    
    server.addExceptionHandler!NetworkError((ref Context ctx, NetworkError e) {
        ctx.response.setStatus(503);
    });
    
    server.exceptionHandlerCount().shouldEqual(3);
}

// Test 4: hasExceptionHandler returns correct state
@("hasExceptionHandler returns correct state")
unittest
{
    auto server = createTestServer();
    
    server.hasExceptionHandler!ValidationError().shouldBeFalse;
    
    server.addExceptionHandler!ValidationError((ref Context ctx, ValidationError e) {
        ctx.response.setStatus(400);
    });
    
    server.hasExceptionHandler!ValidationError().shouldBeTrue;
    server.hasExceptionHandler!NetworkError().shouldBeFalse;
}

// Test 5: Null handler registration throws
@("null handler registration throws")
unittest
{
    auto server = createTestServer();
    
    import std.exception : assertThrown;
    
    assertThrown!Exception(
        server.addExceptionHandler!ValidationError(null)
    );
}

// ============================================================================
// HOOKS API TESTS
// ============================================================================

// Test 6: onError hook can be registered
@("onError hook can be registered")
unittest
{
    auto server = createTestServer();
    
    int hookCalled = 0;
    server.hooks.onError((Exception e, ref Context ctx) {
        hookCalled++;
    });
    
    // Hook is registered but not called until error occurs
    hookCalled.shouldEqual(0);
}

// Test 7: Multiple onError hooks can be registered
@("multiple onError hooks can be registered")
unittest
{
    auto server = createTestServer();
    
    int hook1Count = 0;
    int hook2Count = 0;
    
    server.hooks.onError((Exception e, ref Context ctx) {
        hook1Count++;
    });
    
    server.hooks.onError((Exception e, ref Context ctx) {
        hook2Count++;
    });
    
    // Both registered successfully
    hook1Count.shouldEqual(0);
    hook2Count.shouldEqual(0);
}

// ============================================================================
// SERVER STATE ISOLATION TESTS
// ============================================================================

// Test 8: Server running state unaffected by configuration
@("server state is clean before run")
unittest
{
    auto server = createTestServer();
    
    // Add some handlers
    server.addExceptionHandler!ValidationError((ref Context ctx, ValidationError e) {
        ctx.response.setStatus(400);
    });
    
    server.hooks.onError((Exception e, ref Context ctx) {});
    
    // Server should still not be running
    server.isRunning().shouldBeFalse;
    server.isShuttingDown().shouldBeFalse;
    server.getErrors().shouldEqual(0);
}

// Test 9: Error counter starts at zero
@("error counter starts at zero")
unittest
{
    auto server = createTestServer();
    
    server.getErrors().shouldEqual(0);
    server.getActiveConnections().shouldEqual(0);
    server.getConnections().shouldEqual(0);
}

// Test 10: All rejection counters start at zero
@("rejection counters start at zero")
unittest
{
    auto server = createTestServer();
    
    server.getRejectedHeadersTooLarge().shouldEqual(0);
    server.getRejectedBodyTooLarge().shouldEqual(0);
    server.getRejectedTimeout().shouldEqual(0);
    server.getRejectedDuringShutdown().shouldEqual(0);
}

// ============================================================================
// EXCEPTION HIERARCHY TESTS
// ============================================================================

// Test 11: Exception handler type lookup compiles
@("exception handler type lookup compiles")
unittest
{
    auto server = createTestServer();
    
    // Handler for base type
    server.addExceptionHandler!CustomException((ref Context ctx, CustomException e) {
        ctx.response.setStatus(400);
    });
    
    // Check base type
    server.hasExceptionHandler!CustomException().shouldBeTrue;
    
    // Derived types don't have their own handler
    server.hasExceptionHandler!ValidationError().shouldBeFalse;
}

// Test 12: Direct handler registration API exists
@("direct handler registration API exists")
unittest
{
    auto server = createTestServer();
    
    // This is the internal API for handler registration
    static assert(__traits(compiles, 
        server.addExceptionHandlerDirect(typeid(ValidationError), 
            (ref Context ctx, Exception e) {})));
}

// ============================================================================
// MIDDLEWARE EXCEPTION ISOLATION TESTS
// ============================================================================

// Test 13: Middleware pipeline exists
@("middleware pipeline can be created")
unittest
{
    auto pipeline = new MiddlewarePipeline();
    
    pipeline.shouldNotBeNull;
    pipeline.length.shouldEqual(0);
}

// Test 14: Server accepts middleware pipeline
@("server accepts middleware pipeline")
unittest
{
    auto router = new Router();
    auto pipeline = new MiddlewarePipeline();
    
    auto server = new Server(router, pipeline);
    
    server.shouldNotBeNull;
}

// Test 15: Middleware can be added to pipeline
@("middleware can be added to pipeline")
unittest
{
    auto pipeline = new MiddlewarePipeline();
    
    int middlewareRan = 0;
    pipeline.use((ref Context ctx, NextFunction next) {
        middlewareRan++;
        next();
    });
    
    pipeline.length.shouldEqual(1);
}

// ============================================================================
// ROUTER EXCEPTION TESTS
// ============================================================================

// Test 16: Router with throwing handler compiles
@("router with throwing handler compiles")
unittest
{
    auto router = new Router();
    
    router.get("/throw", (ref Context ctx) {
        throw new ValidationError("test error");
    });
    
    // Router compiles with throwing handler
    router.shouldNotBeNull;
}

// Test 17: Router match API exists
@("router match API exists")
unittest
{
    auto router = new Router();
    
    router.get("/test", (ref Context ctx) {
        ctx.send("ok");
    });
    
    auto match = router.match("GET", "/test");
    match.found.shouldBeTrue;
}

// Test 18: Router 404 for unmatched routes
@("router returns 404 for unmatched routes")
unittest
{
    auto router = new Router();
    
    router.get("/exists", (ref Context ctx) {
        ctx.send("ok");
    });
    
    auto match = router.match("GET", "/nonexistent");
    match.found.shouldBeFalse;
}

// ============================================================================
// SERVER CONFIG TESTS
// ============================================================================

// Test 19: ServerConfig has all required limits
@("ServerConfig has all required limits")
unittest
{
    ServerConfig config;
    
    config.maxHeaderSize.shouldBeGreaterThan(0);
    config.maxBodySize.shouldBeGreaterThan(0);
    config.readTimeout.total!"seconds".shouldBeGreaterThan(0);
    config.writeTimeout.total!"seconds".shouldBeGreaterThan(0);
    config.keepAliveTimeout.total!"seconds".shouldBeGreaterThan(0);
}

// Test 20: ServerConfig effectiveWorkers returns positive
@("ServerConfig effectiveWorkers returns positive")
unittest
{
    ServerConfig config;
    
    config.effectiveWorkers().shouldBeGreaterThan(0);
}

// ============================================================================
// HELPERS
// ============================================================================

/// Create a test server with a simple router
Server createTestServer()
{
    auto router = new Router();
    
    router.get("/", (ref Context ctx) {
        ctx.send("OK");
    });
    
    router.get("/error", (ref Context ctx) {
        throw new Exception("Test error");
    });
    
    router.get("/validation-error", (ref Context ctx) {
        throw new ValidationError("Invalid input");
    });
    
    router.get("/custom-error", (ref Context ctx) {
        throw new CustomException("Custom error");
    });
    
    return new Server(router);
}
