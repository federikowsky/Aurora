/**
 * Server Hooks and Exception Handlers Tests
 *
 * Tests for Aurora V0.4 extensibility features:
 * - ServerHooks (onStart, onStop, onError, onRequest, onResponse)
 * - Exception handlers (FastAPI-style typed handlers)
 *
 * Coverage:
 * - Hook registration and execution
 * - Hook execution order (FIFO)
 * - Null hook rejection
 * - Exception handler type resolution
 * - Exception handler hierarchy
 */
module tests.unit.runtime.hooks_test;

import unit_threaded;
import aurora.runtime.hooks;
import aurora.web.context : Context;

// ============================================================================
// SERVERHOOKS TESTS
// ============================================================================

// ----------------------------------------
// Hook Registration Tests
// ----------------------------------------

@("onStart hook registration")
unittest
{
    ServerHooks hooks;
    int callCount = 0;

    hooks.onStart(() { callCount++; });

    hooks.startHooks.length.shouldEqual(1);
    hooks.hasHooks.shouldBeTrue();
}

@("multiple onStart hooks register in order")
unittest
{
    ServerHooks hooks;
    int[] order;

    hooks.onStart(() { order ~= 1; });
    hooks.onStart(() { order ~= 2; });
    hooks.onStart(() { order ~= 3; });

    hooks.startHooks.length.shouldEqual(3);

    // Execute and verify order
    foreach (hook; hooks.startHooks)
        hook();

    order.shouldEqual([1, 2, 3]);
}

@("onStop hook registration")
unittest
{
    ServerHooks hooks;

    hooks.onStop(() {});

    hooks.stopHooks.length.shouldEqual(1);
}

@("onError hook registration")
unittest
{
    ServerHooks hooks;

    hooks.onError((Exception e, ref Context ctx) {});

    hooks.errorHooks.length.shouldEqual(1);
}

@("onRequest hook registration")
unittest
{
    ServerHooks hooks;

    hooks.onRequest((ref Context ctx) {});

    hooks.requestHooks.length.shouldEqual(1);
}

@("onResponse hook registration")
unittest
{
    ServerHooks hooks;

    hooks.onResponse((ref Context ctx) {});

    hooks.responseHooks.length.shouldEqual(1);
}

// ----------------------------------------
// Null Hook Rejection Tests
// ----------------------------------------

@("null onStart hook is rejected")
unittest
{
    ServerHooks hooks;

    hooks.onStart(null);

    hooks.startHooks.length.shouldEqual(0);
    hooks.hasHooks.shouldBeFalse();
}

@("null onStop hook is rejected")
unittest
{
    ServerHooks hooks;

    hooks.onStop(null);

    hooks.stopHooks.length.shouldEqual(0);
}

@("null onError hook is rejected")
unittest
{
    ServerHooks hooks;

    hooks.onError(null);

    hooks.errorHooks.length.shouldEqual(0);
}

@("null onRequest hook is rejected")
unittest
{
    ServerHooks hooks;

    hooks.onRequest(null);

    hooks.requestHooks.length.shouldEqual(0);
}

@("null onResponse hook is rejected")
unittest
{
    ServerHooks hooks;

    hooks.onResponse(null);

    hooks.responseHooks.length.shouldEqual(0);
}

// ----------------------------------------
// Utility Method Tests
// ----------------------------------------

@("hasHooks returns false when no hooks registered")
unittest
{
    ServerHooks hooks;

    hooks.hasHooks.shouldBeFalse();
}

@("hasHooks returns true when any hook registered")
unittest
{
    ServerHooks hooks;

    hooks.onStart(() {});

    hooks.hasHooks.shouldBeTrue();
}

@("totalHooks counts all hooks")
unittest
{
    ServerHooks hooks;

    hooks.onStart(() {});
    hooks.onStart(() {});
    hooks.onStop(() {});
    hooks.onError((Exception e, ref Context ctx) {});
    hooks.onRequest((ref Context ctx) {});
    hooks.onResponse((ref Context ctx) {});

    hooks.totalHooks.shouldEqual(6);
}

@("clear removes all hooks")
unittest
{
    ServerHooks hooks;

    hooks.onStart(() {});
    hooks.onStop(() {});
    hooks.onError((Exception e, ref Context ctx) {});

    hooks.hasHooks.shouldBeTrue();

    hooks.clear();

    hooks.hasHooks.shouldBeFalse();
    hooks.totalHooks.shouldEqual(0);
    hooks.startHooks.length.shouldEqual(0);
    hooks.stopHooks.length.shouldEqual(0);
    hooks.errorHooks.length.shouldEqual(0);
}

// ----------------------------------------
// Hook Execution Tests
// ----------------------------------------

@("onStart hooks execute in registration order (FIFO)")
unittest
{
    ServerHooks hooks;
    string result;

    hooks.onStart(() { result ~= "A"; });
    hooks.onStart(() { result ~= "B"; });
    hooks.onStart(() { result ~= "C"; });

    foreach (hook; hooks.startHooks)
        hook();

    result.shouldEqual("ABC");
}

@("onStop hooks execute in registration order")
unittest
{
    ServerHooks hooks;
    string result;

    hooks.onStop(() { result ~= "1"; });
    hooks.onStop(() { result ~= "2"; });
    hooks.onStop(() { result ~= "3"; });

    foreach (hook; hooks.stopHooks)
        hook();

    result.shouldEqual("123");
}

// ============================================================================
// EXCEPTION HANDLER TESTS (Server Integration)
// ============================================================================

// Custom exception types for testing
class ValidationException : Exception
{
    this(string msg) { super(msg); }
}

class PermissionException : Exception
{
    this(string msg) { super(msg); }
}

class DetailedValidationException : ValidationException
{
    this(string msg) { super(msg); }
}

@("ExceptionHandler alias compiles")
unittest
{
    // Test that the template alias compiles correctly
    alias ValidationHandler = ExceptionHandler!Exception;

    // Should compile without error
    ValidationHandler handler = (ref Context ctx, Exception e) {};
    handler.shouldNotBeNull();
}

@("TypeErasedHandler alias compiles")
unittest
{
    TypeErasedHandler handler = (ref Context ctx, Exception e) {};
    handler.shouldNotBeNull();
}

// ============================================================================
// EXECUTION METHOD TESTS
// ============================================================================

@("executeOnStart runs all start hooks")
unittest
{
    ServerHooks hooks;
    int count = 0;
    
    hooks.onStart(() { count++; });
    hooks.onStart(() { count++; });
    hooks.onStart(() { count++; });
    
    hooks.executeOnStart();
    
    count.shouldEqual(3);
}

@("executeOnStop runs all stop hooks")
unittest
{
    ServerHooks hooks;
    int count = 0;
    
    hooks.onStop(() { count++; });
    hooks.onStop(() { count++; });
    
    hooks.executeOnStop();
    
    count.shouldEqual(2);
}

@("executeOnRequest runs with context")
unittest
{
    ServerHooks hooks;
    bool wasExecuted = false;
    
    hooks.onRequest((ref Context ctx) { 
        wasExecuted = true;
    });
    
    Context ctx;
    hooks.executeOnRequest(ctx);
    
    wasExecuted.shouldBeTrue();
}

@("executeOnResponse runs with context")
unittest
{
    ServerHooks hooks;
    bool wasExecuted = false;
    
    hooks.onResponse((ref Context ctx) { 
        wasExecuted = true;
    });
    
    Context ctx;
    hooks.executeOnResponse(ctx);
    
    wasExecuted.shouldBeTrue();
}

@("executeOnError runs with exception and context")
unittest
{
    ServerHooks hooks;
    bool wasExecuted = false;
    Exception caughtException;
    
    hooks.onError((Exception e, ref Context ctx) { 
        wasExecuted = true;
        caughtException = e;
    });
    
    Context ctx;
    auto testException = new Exception("test error");
    hooks.executeOnError(testException, ctx);
    
    wasExecuted.shouldBeTrue();
    assert(caughtException is testException, "Should receive same exception instance");
}

@("multiple error hooks all receive the same exception")
unittest
{
    ServerHooks hooks;
    Exception[] received;
    
    hooks.onError((Exception e, ref Context ctx) { received ~= e; });
    hooks.onError((Exception e, ref Context ctx) { received ~= e; });
    hooks.onError((Exception e, ref Context ctx) { received ~= e; });
    
    Context ctx;
    auto testException = new Exception("shared error");
    hooks.executeOnError(testException, ctx);
    
    received.length.shouldEqual(3);
    // All should be the same exception instance
    assert(received[0] is testException, "First should be same instance");
    assert(received[1] is testException, "Second should be same instance");
    assert(received[2] is testException, "Third should be same instance");
}

@("hooks execute in FIFO order during execution")
unittest
{
    ServerHooks hooks;
    string order;
    
    hooks.onStart(() { order ~= "1"; });
    hooks.onStart(() { order ~= "2"; });
    hooks.onStart(() { order ~= "3"; });
    
    hooks.executeOnStart();
    
    order.shouldEqual("123");
}

@("empty hooks execute without error")
unittest
{
    ServerHooks hooks;
    
    // Should not throw
    hooks.executeOnStart();
    hooks.executeOnStop();
    
    Context ctx;
    hooks.executeOnRequest(ctx);
    hooks.executeOnResponse(ctx);
    hooks.executeOnError(new Exception("test"), ctx);
}

// ============================================================================
// SERVER EXCEPTION HANDLER INTEGRATION TESTS
// ============================================================================

import aurora.runtime.server : Server, ServerConfig;
import aurora.web.router : Router;

@("server can register exception handler")
unittest
{
    auto router = new Router();
    router.get("/test", (ref Context ctx) {
        ctx.response.setBody("OK");
    });
    
    auto server = new Server(router);
    
    // Should not throw
    server.addExceptionHandler!ValidationException((ref Context ctx, ValidationException e) {
        ctx.response.setStatus(400);
        ctx.response.setBody(`{"error":"` ~ e.msg ~ `"}`);
    });
    
    server.exceptionHandlerCount.shouldEqual(1);
}

@("server can register multiple exception handlers")
unittest
{
    auto router = new Router();
    auto server = new Server(router);
    
    server.addExceptionHandler!ValidationException((ref Context ctx, ValidationException e) {
        ctx.response.setStatus(400);
    });
    
    server.addExceptionHandler!PermissionException((ref Context ctx, PermissionException e) {
        ctx.response.setStatus(403);
    });
    
    server.exceptionHandlerCount.shouldEqual(2);
}

@("server hasExceptionHandler returns true for registered type")
unittest
{
    auto router = new Router();
    auto server = new Server(router);
    
    server.hasExceptionHandler!ValidationException.shouldBeFalse();
    
    server.addExceptionHandler!ValidationException((ref Context ctx, ValidationException e) {});
    
    server.hasExceptionHandler!ValidationException.shouldBeTrue();
    server.hasExceptionHandler!PermissionException.shouldBeFalse();
}

@("server rejects null exception handler")
unittest
{
    auto router = new Router();
    auto server = new Server(router);
    
    bool threw = false;
    try
    {
        server.addExceptionHandler!Exception(null);
    }
    catch (Exception e)
    {
        threw = true;
        assert(e.msg == "Exception handler cannot be null");
    }
    
    threw.shouldBeTrue();
}

@("server hooks are accessible via hooks() method")
unittest
{
    auto router = new Router();
    auto server = new Server(router);
    
    bool startCalled = false;
    server.hooks.onStart(() { startCalled = true; });
    
    server.hooks.hasHooks.shouldBeTrue();
    server.hooks.totalHooks.shouldEqual(1);
}

@("server hooks support all event types")
unittest
{
    auto router = new Router();
    auto server = new Server(router);
    
    server.hooks.onStart(() {});
    server.hooks.onStop(() {});
    server.hooks.onError((Exception e, ref Context ctx) {});
    server.hooks.onRequest((ref Context ctx) {});
    server.hooks.onResponse((ref Context ctx) {});
    
    server.hooks.totalHooks.shouldEqual(5);
}
