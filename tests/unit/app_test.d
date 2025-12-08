/**
 * Aurora App API Tests
 *
 * Tests for the high-level App API including:
 * - Hooks registration (onStart, onStop, onError, onRequest, onResponse)
 * - Exception handlers registration
 * - Configuration methods
 */
module tests.unit.app_test;

import unit_threaded;
import aurora.app;
import aurora.runtime.hooks;
import aurora.web.context : Context;

// Custom exception for testing
class TestValidationError : Exception
{
    this(string msg) { super(msg); }
}

// ============================================================================
// HOOKS API TESTS
// ============================================================================

@("App.onStart registers hook")
unittest
{
    auto app = new App();
    bool called = false;
    
    app.onStart(() { called = true; });
    
    // Hook is stored, will be applied when listen() is called
    // We can't easily test execution without starting server
    app.shouldNotBeNull();
}

@("App.onStop registers hook")
unittest
{
    auto app = new App();
    
    auto result = app.onStop(() { });
    
    // Fluent API returns App
    assert(result is app, "onStop should return same App instance");
}

@("App.onError registers hook")
unittest
{
    auto app = new App();
    
    auto result = app.onError((Exception e, ref Context ctx) { });
    
    assert(result is app, "onError should return same App instance");
}

@("App.onRequest registers hook")
unittest
{
    auto app = new App();
    
    auto result = app.onRequest((ref Context ctx) { });
    
    assert(result is app, "onRequest should return same App instance");
}

@("App.onResponse registers hook")
unittest
{
    auto app = new App();
    
    auto result = app.onResponse((ref Context ctx) { });
    
    assert(result is app, "onResponse should return same App instance");
}

@("App hooks support fluent chaining")
unittest
{
    auto app = new App();
    
    app.onStart(() { })
       .onStop(() { })
       .onError((Exception e, ref Context ctx) { })
       .onRequest((ref Context ctx) { })
       .onResponse((ref Context ctx) { });
    
    app.shouldNotBeNull();
}

@("App null hooks are ignored")
unittest
{
    auto app = new App();
    
    // Should not throw
    app.onStart(null)
       .onStop(null)
       .onError(null)
       .onRequest(null)
       .onResponse(null);
    
    app.shouldNotBeNull();
}

// ============================================================================
// EXCEPTION HANDLERS API TESTS
// ============================================================================

@("App.addExceptionHandler registers handler")
unittest
{
    auto app = new App();
    
    app.addExceptionHandler!TestValidationError((ref Context ctx, TestValidationError e) {
        // Handler logic
    });
    
    app.hasExceptionHandler!TestValidationError.shouldBeTrue();
}

@("App.addExceptionHandler returns App for chaining")
unittest
{
    auto app = new App();
    
    auto result = app.addExceptionHandler!Exception((ref Context ctx, Exception e) { });
    
    assert(result is app, "addExceptionHandler should return same App instance");
}

@("App.hasExceptionHandler returns false for unregistered type")
unittest
{
    auto app = new App();
    
    app.hasExceptionHandler!TestValidationError.shouldBeFalse();
}

@("App.addExceptionHandler rejects null handler")
unittest
{
    auto app = new App();
    
    bool threw = false;
    try
    {
        app.addExceptionHandler!Exception(null);
    }
    catch (Exception e)
    {
        threw = true;
    }
    
    threw.shouldBeTrue();
}

@("App supports multiple exception handlers for different types")
unittest
{
    auto app = new App();
    
    app.addExceptionHandler!TestValidationError((ref ctx, e) { })
       .addExceptionHandler!Exception((ref ctx, e) { });
    
    app.hasExceptionHandler!TestValidationError.shouldBeTrue();
    app.hasExceptionHandler!Exception.shouldBeTrue();
}

// ============================================================================
// COMBINED API TESTS
// ============================================================================

@("App supports full fluent configuration")
unittest
{
    auto app = new App();
    
    app.get("/", (ref Context ctx) { ctx.send("OK"); })
       .post("/data", (ref Context ctx) { })
       .onStart(() { })
       .onError((Exception e, ref Context ctx) { })
       .addExceptionHandler!TestValidationError((ref ctx, e) { })
       .workers(4)
       .debug_(true);
    
    app.shouldNotBeNull();
}
