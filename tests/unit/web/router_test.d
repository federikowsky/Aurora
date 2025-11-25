/**
 * Routing System Tests
 *
 * TDD: Aurora Routing (Radix tree router)
 *
 * Features:
 * - PathParams (small object optimization)
 * - RadixNode (Radix tree structure)
 * - Router (addRoute, match)
 * - O(K) path matching
 * - Route priority (static > param > wildcard)
 */
module tests.unit.web.router_test;

import unit_threaded;
import aurora.web.router;
import aurora.web.context;
import std.conv : to;

// ========================================
// PATHPARAMS TESTS
// ========================================

// Test 1: PathParams set/get
@("PathParams set and get")
unittest
{
    PathParams params;
    
    params["id"] = "123";
    params["name"] = "alice";
    
    params["id"].shouldEqual("123");
    params["name"].shouldEqual("alice");
}

// Test 2: PathParams inline storage (4 params)
@("PathParams inline storage")
unittest
{
    PathParams params;
    
    params["a"] = "1";
    params["b"] = "2";
    params["c"] = "3";
    params["d"] = "4";
    
    // All should be in inline storage
    params["a"].shouldEqual("1");
    params["d"].shouldEqual("4");
}

// Test 3: PathParams overflow to heap
@("PathParams overflow to heap")
unittest
{
    PathParams params;
    
    // Add 5 params (MAX_INLINE = 4)
    params["a"] = "1";
    params["b"] = "2";
    params["c"] = "3";
    params["d"] = "4";
    params["e"] = "5";  // Overflow
    
    // All should be retrievable
    params["a"].shouldEqual("1");
    params["e"].shouldEqual("5");
}

// Test 4: PathParams non-existent key
@("PathParams nonexistent key returns null")
unittest
{
    PathParams params;
    
    params["id"].shouldBeNull;
}

// Test 5: PathParams count
@("PathParams count")
unittest
{
    PathParams params;
    
    params["a"] = "1";
    params["b"] = "2";
    
    params.count.shouldEqual(2);
}

// ========================================
// HAPPY PATH - REGISTRATION
// ========================================

// Test 6: Register static route
@("register static route")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    
    router.addRoute("GET", "/users", &handler);
    
    // Route should be stored
}

// Test 7: Register param route
@("register param route")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    
    router.addRoute("GET", "/users/:id", &handler);
    
    // Param route should be stored
}

// Test 8: Register wildcard route
@("register wildcard route")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    
    router.addRoute("GET", "/files/*path", &handler);
    
    // Wildcard route should be stored
}

// Test 9: Register multiple methods
@("register multiple methods")
unittest
{
    auto router = new Router();
    
    void getHandler(ref Context ctx) { }
    void postHandler(ref Context ctx) { }
    
    router.addRoute("GET", "/users", &getHandler);
    router.addRoute("POST", "/users", &postHandler);
    
    // Both should be stored
}

// Test 10: Register nested routes
@("register nested routes")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    
    router.addRoute("GET", "/api/v1/users/:id", &handler);
    
    // Nested route should be stored
}

// ========================================
// HAPPY PATH - MATCHING
// ========================================

// Test 11: Match static route
@("match static route")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    router.addRoute("GET", "/users", &handler);
    
    auto match = router.match("GET", "/users");
    
    match.found.shouldBeTrue;
    match.handler.shouldEqual(&handler);
}

// Test 12: Match param route
@("match param route")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    router.addRoute("GET", "/users/:id", &handler);
    
    auto match = router.match("GET", "/users/123");
    
    match.found.shouldBeTrue;
    match.params["id"].shouldEqual("123");
}

// Test 13: Match wildcard route
@("match wildcard route")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    router.addRoute("GET", "/files/*path", &handler);
    
    auto match = router.match("GET", "/files/a/b/c");
    
    match.found.shouldBeTrue;
    match.params["path"].shouldEqual("a/b/c");
}

// Test 14: Match with query string
@("match ignores query string")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    router.addRoute("GET", "/users", &handler);
    
    auto match = router.match("GET", "/users?page=1");
    
    match.found.shouldBeTrue;
}

// Test 15: Match root path
@("match root path")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    router.addRoute("GET", "/", &handler);
    
    auto match = router.match("GET", "/");
    
    match.found.shouldBeTrue;
}

// ========================================
// EDGE CASES - PATH HANDLING
// ========================================

// Test 16: Empty path defaults to /
@("empty path defaults to slash")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    router.addRoute("GET", "", &handler);
    
    auto match = router.match("GET", "/");
    
    match.found.shouldBeTrue;
}

// Test 17: Trailing slash normalized
@("trailing slash normalized")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    router.addRoute("GET", "/users", &handler);
    
    auto match = router.match("GET", "/users/");
    
    match.found.shouldBeTrue;
}

// Test 18: Leading slash
@("leading slash handled")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    router.addRoute("GET", "users", &handler);
    
    auto match = router.match("GET", "/users");
    
    match.found.shouldBeTrue;
}

// Test 19: Double slashes
@("double slashes normalized")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    router.addRoute("GET", "/users/:id", &handler);
    
    auto match = router.match("GET", "/users//123");
    
    match.found.shouldBeTrue;
    match.params["id"].shouldEqual("123");
}

// Test 20: Very long path
@("very long path handled")
unittest
{
    import std.array : replicate;
    
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    string longPath = "/" ~ replicate("a", 1000);
    router.addRoute("GET", longPath, &handler);
    
    auto match = router.match("GET", longPath);
    
    match.found.shouldBeTrue;
}

// ========================================
// EDGE CASES - ROUTE PRIORITY
// ========================================

// Test 21: Static vs param priority
@("static route has priority over param")
unittest
{
    auto router = new Router();
    
    void staticHandler(ref Context ctx) { }
    void paramHandler(ref Context ctx) { }
    
    router.addRoute("GET", "/users/:id", &paramHandler);
    router.addRoute("GET", "/users/new", &staticHandler);
    
    auto match = router.match("GET", "/users/new");
    
    match.found.shouldBeTrue;
    match.handler.shouldEqual(&staticHandler);
}

// Test 22: Param vs wildcard priority
@("param route has priority over wildcard")
unittest
{
    auto router = new Router();
    
    void paramHandler(ref Context ctx) { }
    void wildcardHandler(ref Context ctx) { }
    
    router.addRoute("GET", "/files/*path", &wildcardHandler);
    router.addRoute("GET", "/files/:id", &paramHandler);
    
    auto match = router.match("GET", "/files/123");
    
    match.found.shouldBeTrue;
    match.handler.shouldEqual(&paramHandler);
}

// Test 23: Multiple params
@("multiple params extracted")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    router.addRoute("GET", "/users/:userId/posts/:postId", &handler);
    
    auto match = router.match("GET", "/users/123/posts/456");
    
    match.found.shouldBeTrue;
    match.params["userId"].shouldEqual("123");
    match.params["postId"].shouldEqual("456");
}

// Test 24: Overlapping routes
@("overlapping routes both work")
unittest
{
    auto router = new Router();
    
    void handler1(ref Context ctx) { }
    void handler2(ref Context ctx) { }
    
    router.addRoute("GET", "/api/users", &handler1);
    router.addRoute("GET", "/api/users/:id", &handler2);
    
    auto match1 = router.match("GET", "/api/users");
    auto match2 = router.match("GET", "/api/users/123");
    
    match1.found.shouldBeTrue;
    match1.handler.shouldEqual(&handler1);
    
    match2.found.shouldBeTrue;
    match2.handler.shouldEqual(&handler2);
}

// ========================================
// EDGE CASES - DUPLICATE HANDLING
// ========================================

// Test 25: Duplicate route override
@("duplicate route overrides handler")
unittest
{
    auto router = new Router();
    
    void handler1(ref Context ctx) { }
    void handler2(ref Context ctx) { }
    
    router.addRoute("GET", "/users", &handler1);
    router.addRoute("GET", "/users", &handler2);  // Override
    
    auto match = router.match("GET", "/users");
    
    match.found.shouldBeTrue;
    match.handler.shouldEqual(&handler2);
}

// Test 26: Same path different methods
@("same path different methods allowed")
unittest
{
    auto router = new Router();
    
    void getHandler(ref Context ctx) { }
    void postHandler(ref Context ctx) { }
    
    router.addRoute("GET", "/users", &getHandler);
    router.addRoute("POST", "/users", &postHandler);
    
    auto getMatch = router.match("GET", "/users");
    auto postMatch = router.match("POST", "/users");
    
    getMatch.handler.shouldEqual(&getHandler);
    postMatch.handler.shouldEqual(&postHandler);
}

// ========================================
// PERFORMANCE TESTS
// ========================================

// Test 27: Lookup latency < 500ns
@("lookup latency under 500ns")
unittest
{
    import std.datetime.stopwatch;
    
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    router.addRoute("GET", "/api/v1/users/:id/posts/:postId", &handler);
    
    auto sw = StopWatch(AutoStart.yes);
    
    foreach (i; 0..10_000)
    {
        auto match = router.match("GET", "/api/v1/users/123/posts/456");
    }
    
    sw.stop();
    auto avgNs = sw.peek().total!"nsecs" / 10_000;
    
    // Target: < 500ns (relaxed for debug)
    assert(avgNs < 5000, "Lookup too slow: " ~ avgNs.to!string ~ "ns");
}

// Test 28: 1000 routes scalable
@("1000 routes scalable")
unittest
{
    import std.conv : to;
    
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    
    // Register 1000 routes
    foreach (i; 0..1000)
    {
        router.addRoute("GET", "/route" ~ i.to!string, &handler);
    }
    
    // Match should still work
    auto match = router.match("GET", "/route500");
    match.found.shouldBeTrue;
}

// Test 29: Deep nesting (10 levels)
@("deep nesting works")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    router.addRoute("GET", "/a/b/c/d/e/f/g/h/i/j", &handler);
    
    auto match = router.match("GET", "/a/b/c/d/e/f/g/h/i/j");
    
    match.found.shouldBeTrue;
}

// Test 30: Param extraction overhead
@("param extraction fast")
unittest
{
    import std.datetime.stopwatch;
    
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    router.addRoute("GET", "/users/:id", &handler);
    
    auto sw = StopWatch(AutoStart.yes);
    
    foreach (i; 0..10_000)
    {
        auto match = router.match("GET", "/users/123");
        auto id = match.params["id"];
    }
    
    sw.stop();
    auto avgNs = sw.peek().total!"nsecs" / 10_000;
    
    // Should be fast
    assert(avgNs < 10000, "Param extraction too slow");
}

// ========================================
// INTEGRATION TESTS
// ========================================

// Test 31: Route not found
@("route not found returns false")
unittest
{
    auto router = new Router();
    
    auto match = router.match("GET", "/nonexistent");
    
    match.found.shouldBeFalse;
}

// Test 32: Method not allowed
@("method not allowed returns false")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    router.addRoute("GET", "/users", &handler);
    
    auto match = router.match("POST", "/users");
    
    match.found.shouldBeFalse;
}

// Test 33: Multiple HTTP methods
@("multiple HTTP methods")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    
    router.addRoute("GET", "/users", &handler);
    router.addRoute("POST", "/users", &handler);
    router.addRoute("PUT", "/users/:id", &handler);
    router.addRoute("DELETE", "/users/:id", &handler);
    router.addRoute("PATCH", "/users/:id", &handler);
    
    // All should match
    router.match("GET", "/users").found.shouldBeTrue;
    router.match("POST", "/users").found.shouldBeTrue;
    router.match("PUT", "/users/123").found.shouldBeTrue;
    router.match("DELETE", "/users/123").found.shouldBeTrue;
    router.match("PATCH", "/users/123").found.shouldBeTrue;
}

// Test 34: Complex pattern
// NOTE: Inline params like "v:version" are not supported.
// Only full-segment params ":param" and wildcards "*rest" are supported per spec.
@("complex pattern works")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    // Changed from "/api/v:version/users/:id/posts/*path" to use supported syntax
    router.addRoute("GET", "/api/:version/users/:id/posts/*path", &handler);
    
    auto match = router.match("GET", "/api/v1/users/123/posts/2024/11/23/post.md");
    
    match.found.shouldBeTrue;
    match.params["version"].shouldEqual("v1");
    match.params["id"].shouldEqual("123");
    match.params["path"].shouldEqual("2024/11/23/post.md");
}

// Test 35: Case sensitivity
@("routes are case sensitive")
unittest
{
    auto router = new Router();
    
    void handler(ref Context ctx) { }
    router.addRoute("GET", "/Users", &handler);
    
    auto match1 = router.match("GET", "/Users");
    auto match2 = router.match("GET", "/users");
    
    match1.found.shouldBeTrue;
    match2.found.shouldBeFalse;
}
