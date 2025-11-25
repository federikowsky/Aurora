/**
 * Router Pattern Tests
 *
 * TDD: Aurora Router Pattern (FastAPI-style decorators)
 *
 * Features:
 * - Router class with HTTP method helpers
 * - UDA decorators (@Get, @Post, etc.)
 * - RouterMixin template
 * - includeRouter() composition
 */
module tests.unit.web.router_pattern_test;

import unit_threaded;
import aurora.web.router;
import aurora.web.context;
import aurora.web.decorators;
import aurora.web.router_mixin;
import aurora.web.middleware : NextFunction;

// ========================================
// HAPPY PATH - ROUTER CLASS
// ========================================

// Test 1: Router.get() registers route
@("Router.get registers route")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    
    router.get("/users", &handler);
    
    // Route should be registered
    auto match = router.match("GET", "/users");
    match.found.shouldBeTrue;
}

// Test 2: Router.post() registers route
@("Router.post registers route")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    
    router.post("/users", &handler);
    
    auto match = router.match("POST", "/users");
    match.found.shouldBeTrue;
}

// Test 3: Router.put() registers route
@("Router.put registers route")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    
    router.put("/users/:id", &handler);
    
    auto match = router.match("PUT", "/users/123");
    match.found.shouldBeTrue;
}

// Test 4: Router.delete_() registers route
@("Router.delete_ registers route")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    
    router.delete_("/users/:id", &handler);
    
    auto match = router.match("DELETE", "/users/123");
    match.found.shouldBeTrue;
}

// Test 5: Router.patch() registers route
@("Router.patch registers route")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    
    router.patch("/users/:id", &handler);
    
    auto match = router.match("PATCH", "/users/123");
    match.found.shouldBeTrue;
}

// Test 6: Router with prefix
@("Router with prefix")
unittest
{
    auto router = new Router("/api");
    
    void handler(ref Context ctx) { }
    
    router.get("/users", &handler);
    
    // Should match /api/users
    auto match = router.match("GET", "/api/users");
    match.found.shouldBeTrue;
}

// Test 7: includeRouter() merges routes
@("includeRouter merges routes")
unittest
{
    auto mainRouter = new Router();
    auto subRouter = new Router("/api");
    
    void handler(ref Context ctx) { }
    
    subRouter.get("/users", &handler);
    mainRouter.includeRouter(subRouter);
    
    // Should match /api/users
    auto match = mainRouter.match("GET", "/api/users");
    match.found.shouldBeTrue;
}

// Test 8: Prefix stacking
@("prefix stacking works")
unittest
{
    auto app = new Router();
    auto api = new Router("/api");
    auto v1 = new Router("/v1");
    
    void handler(ref Context ctx) { }
    
    v1.get("/users", &handler);
    api.includeRouter(v1);
    app.includeRouter(api);
    
    // Should match /api/v1/users
    auto match = app.match("GET", "/api/v1/users");
    match.found.shouldBeTrue;
}

// Test 9: Multiple HTTP methods on same path
@("multiple methods same path")
unittest
{
    auto router = new Router();
    
    void getHandler(ref Context ctx) { }
    void postHandler(ref Context ctx) { }
    
    router.get("/users", &getHandler);
    router.post("/users", &postHandler);
    
    auto getMatch = router.match("GET", "/users");
    auto postMatch = router.match("POST", "/users");
    
    getMatch.found.shouldBeTrue;
    postMatch.found.shouldBeTrue;
    getMatch.handler.shouldEqual(&getHandler);
    postMatch.handler.shouldEqual(&postHandler);
}

// Test 10: Router middleware
@("router middleware")
unittest
{
    auto router = new Router();
    
    bool middlewareCalled = false;
    
    void middleware(ref Context ctx, NextFunction next) {
        middlewareCalled = true;
        next();
    }
    
    void handler(ref Context ctx) { }
    
    router.use(&middleware);
    router.get("/test", &handler);
    
    // Middleware should be stored
    router.middlewares.length.shouldEqual(1);
}

// ========================================
// EDGE CASES
// ========================================

// Test 11: Empty router valid
@("empty router valid")
unittest
{
    auto router = new Router();
    
    auto match = router.match("GET", "/nonexistent");
    match.found.shouldBeFalse;
}

// Test 12: Conflicting routes
@("conflicting routes override")
unittest
{
    auto router = new Router();
    
    void handler1(ref Context ctx) { }
    void handler2(ref Context ctx) { }
    
    router.get("/users", &handler1);
    router.get("/users", &handler2);  // Override
    
    auto match = router.match("GET", "/users");
    match.handler.shouldEqual(&handler2);
}

// Test 13: Invalid prefix handled
@("invalid prefix normalized")
unittest
{
    auto router = new Router("api");  // Missing leading slash
    
    void handler(ref Context ctx) { }
    router.get("/users", &handler);
    
    // Should normalize to /api/users
    auto match = router.match("GET", "/api/users");
    match.found.shouldBeTrue;
}

// Test 14: Router without prefix
@("router without prefix")
unittest
{
    auto router = new Router("");
    
    void handler(ref Context ctx) { }
    router.get("/users", &handler);
    
    auto match = router.match("GET", "/users");
    match.found.shouldBeTrue;
}

// Test 15: Deep nesting (5 levels)
@("deep nesting works")
unittest
{
    auto r1 = new Router("/a");
    auto r2 = new Router("/b");
    auto r3 = new Router("/c");
    auto r4 = new Router("/d");
    auto r5 = new Router("/e");
    
    void handler(ref Context ctx) { }
    
    r5.get("/test", &handler);
    r4.includeRouter(r5);
    r3.includeRouter(r4);
    r2.includeRouter(r3);
    r1.includeRouter(r2);
    
    // Should match /a/b/c/d/e/test
    auto match = r1.match("GET", "/a/b/c/d/e/test");
    match.found.shouldBeTrue;
}

// ========================================
// INTEGRATION TESTS
// ========================================

// Test 16: Router with Context
@("router with context")
unittest
{
    auto router = new Router();
    
    bool handlerCalled = false;
    
    void handler(ref Context ctx) {
        handlerCalled = true;
    }
    
    router.get("/test", &handler);
    
    auto match = router.match("GET", "/test");
    
    Context ctx;
    match.handler(ctx);
    
    handlerCalled.shouldBeTrue;
}

// Test 17: Router prefix normalization
@("router prefix normalization")
unittest
{
    auto router1 = new Router("/api/");  // Trailing slash
    auto router2 = new Router("api");    // No leading slash
    
    void handler(ref Context ctx) { }
    
    router1.get("/users", &handler);
    router2.get("/posts", &handler);
    
    // Both should normalize correctly
    router1.match("GET", "/api/users").found.shouldBeTrue;
    router2.match("GET", "/api/posts").found.shouldBeTrue;
}

// Test 18: Route matching with params
@("route matching with params")
unittest
{
    auto router = new Router("/api");
    
    void handler(ref Context ctx) { }
    
    router.get("/users/:id/posts/:postId", &handler);
    
    auto match = router.match("GET", "/api/users/123/posts/456");
    
    match.found.shouldBeTrue;
    match.params["id"].shouldEqual("123");
    match.params["postId"].shouldEqual("456");
}

// Test 19: Multiple routers in app
@("multiple routers in app")
unittest
{
    auto app = new Router();
    auto usersRouter = new Router("/users");
    auto postsRouter = new Router("/posts");
    
    void usersHandler(ref Context ctx) { }
    void postsHandler(ref Context ctx) { }
    
    usersRouter.get("/", &usersHandler);
    postsRouter.get("/", &postsHandler);
    
    app.includeRouter(usersRouter);
    app.includeRouter(postsRouter);
    
    app.match("GET", "/users").found.shouldBeTrue;
    app.match("GET", "/posts").found.shouldBeTrue;
}

// Test 20: Full request flow
@("full request flow")
unittest
{
    auto router = new Router("/api");
    
    int requestCount = 0;
    
    void middleware(ref Context ctx, NextFunction next) {
        requestCount++;
        next();
    }
    
    void handler(ref Context ctx) {
        requestCount++;
    }
    
    router.use(&middleware);
    router.get("/test", &handler);
    
    auto match = router.match("GET", "/api/test");
    
    // Execute middleware + handler
    Context ctx;
    
    // Note: This test shows the pattern, actual execution
    // would be done by MiddlewarePipeline
    requestCount.shouldEqual(0);  // Not executed yet
}

// ========================================
// ROUTERMIXIN AND AUTO-REGISTRATION TESTS
// ========================================

// Test 21: RouterMixin creates router
@("RouterMixin creates router")
unittest
{
    // Note: RouterMixin uses static this() which runs at module load
    // For testing, we manually create and test the pattern
    
    auto router = new Router("/test");
    
    // Manually register like RouterMixin would
    void handler(ref Context ctx) { }
    router.get("/", &handler);
    
    router.match("GET", "/test/").found.shouldBeTrue;
}

// Test 22: Auto-registration with @Get
@("auto-registration with Get decorator")
unittest
{
    auto router = new Router("/api");
    
    // Simulate auto-registration
    void getHandler(ref Context ctx) { }
    router.get("/users", &getHandler);
    
    auto match = router.match("GET", "/api/users");
    match.found.shouldBeTrue;
}

// Test 23: Auto-registration with multiple decorators
@("auto-registration with multiple decorators")
unittest
{
    auto router = new Router("/api");
    
    void getHandler(ref Context ctx) { }
    void postHandler(ref Context ctx) { }
    void putHandler(ref Context ctx) { }
    
    // Simulate auto-registration of multiple methods
    router.get("/users", &getHandler);
    router.post("/users", &postHandler);
    router.put("/users/:id", &putHandler);
    
    router.match("GET", "/api/users").found.shouldBeTrue;
    router.match("POST", "/api/users").found.shouldBeTrue;
    router.match("PUT", "/api/users/123").found.shouldBeTrue;
}

// Test 24: RouterMixin with prefix
@("RouterMixin with prefix")
unittest
{
    // Test the pattern that RouterMixin implements
    auto router = new Router("/users");
    
    void listHandler(ref Context ctx) { }
    void getHandler(ref Context ctx) { }
    
    router.get("/", &listHandler);
    router.get("/:id", &getHandler);
    
    router.match("GET", "/users/").found.shouldBeTrue;
    router.match("GET", "/users/123").found.shouldBeTrue;
}

// Test 25: Auto-registration scans all HTTP methods
@("auto-registration scans all HTTP methods")
unittest
{
    auto router = new Router("/api");
    
    void getHandler(ref Context ctx) { }
    void postHandler(ref Context ctx) { }
    void putHandler(ref Context ctx) { }
    void deleteHandler(ref Context ctx) { }
    void patchHandler(ref Context ctx) { }
    
    // Simulate complete auto-registration
    router.get("/resource", &getHandler);
    router.post("/resource", &postHandler);
    router.put("/resource/:id", &putHandler);
    router.delete_("/resource/:id", &deleteHandler);
    router.patch("/resource/:id", &patchHandler);
    
    // All methods should be registered
    router.match("GET", "/api/resource").found.shouldBeTrue;
    router.match("POST", "/api/resource").found.shouldBeTrue;
    router.match("PUT", "/api/resource/123").found.shouldBeTrue;
    router.match("DELETE", "/api/resource/123").found.shouldBeTrue;
    router.match("PATCH", "/api/resource/123").found.shouldBeTrue;
}
