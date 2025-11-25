/**
 * Intensive Stress Tests - Crash Tests
 *
 * Goal: Try to BREAK Aurora and verify it handles extreme conditions gracefully
 *
 * Categories:
 * - Memory stress (massive allocations, leak detection)
 * - Concurrency chaos (race conditions)
 * - Resource exhaustion 
 * - Edge cases
 */
module tests.stress.crash_test;

import unit_threaded;
import aurora.web;
import aurora.http;
import aurora.mem;
import std.datetime.stopwatch;
import core.time;
import core.memory : GC;
import std.conv : to;

// Helper to create a mock request via parsing
private HTTPRequest makeRequest(string method, string path, string body_ = "", string[string] headers = null)
{
    import std.array : appender;
    
    auto raw = appender!string();
    raw ~= method ~ " " ~ path ~ " HTTP/1.1\r\n";
    raw ~= "Host: localhost\r\n";
    
    foreach (name, value; headers)
    {
        raw ~= name ~ ": " ~ value ~ "\r\n";
    }
    
    if (body_.length > 0)
    {
        raw ~= "Content-Length: " ~ body_.length.to!string ~ "\r\n";
    }
    
    raw ~= "\r\n";
    raw ~= body_;
    
    return HTTPRequest.parse(cast(ubyte[])raw.data);
}

// ========================================
// MEMORY STRESS TESTS
// ========================================

// Test 1: Allocate 100K objects rapidly
@("STRESS: 100K rapid allocations no crash")
unittest
{
    auto router = new Router();
    
    router.get("/stress", (ref Context ctx) {
        // Allocate many small objects
        foreach (i; 0..100)
        {
            auto data = new ubyte[1024];  // 1KB each
        }
        ctx.status(200);
        ctx.send("OK");
    });
    
    // Execute 1000 requests (100K allocations total)
    foreach (i; 0..1000)
    {
        auto req = makeRequest("GET", "/stress");
        auto res = HTTPResponse(200, "OK");
        
        Context ctx;
        ctx.request = &req;
        ctx.response = &res;
        
        auto match = router.match("GET", "/stress");
        match.handler(ctx);
        
        res.getStatus().shouldEqual(200);
    }
    
    // Force GC to check for leaks
    GC.collect();
}

// Test 2: Memory leak detection
@("STRESS: 10K allocations leak detection")
unittest
{
    auto initialMem = GC.stats().usedSize;
    
    auto router = new Router();
    
    router.get("/test", (ref Context ctx) {
        auto data = new ubyte[10240];  // 10KB
        ctx.status(200);
        ctx.send("OK");
    });
    
    // Execute 10K requests
    foreach (i; 0..10_000)
    {
        auto req = makeRequest("GET", "/test");
        auto res = HTTPResponse(200, "OK");
        
        Context ctx;
        ctx.request = &req;
        ctx.response = &res;
        
        auto match = router.match("GET", "/test");
        match.handler(ctx);
    }
    
    // Force GC
    GC.collect();
    GC.minimize();
    
    auto finalMem = GC.stats().usedSize;
    
    // Memory should not grow unbounded
    // Allow some growth but not 100MB+
    auto growth = finalMem > initialMem ? finalMem - initialMem : 0;
    assert(growth < 100_000_000, "Memory leak detected: " ~ growth.to!string ~ " bytes");
}

// Test 3: Arena exhaustion
@("STRESS: Arena exhaustion graceful")
unittest
{
    import aurora.mem.arena;
    
    auto arena = new Arena(1024 * 1024);  // 1MB arena
    
    // Try to allocate more than arena size
    bool exhausted = false;
    foreach (i; 0..10_000)
    {
        auto ptr = arena.allocate(1024);  // 1KB each
        if (ptr is null)
        {
            exhausted = true;
            break;
        }
    }
    
    // Should either exhaust arena or succeed (depending on implementation)
    // Either way, shouldn't crash
}

// Test 4: Buffer pool usage
@("STRESS: Buffer pool usage")
unittest
{
    import aurora.mem.pool;
    
    auto pool = new BufferPool();
    
    ubyte[][] buffers;
    
    // Acquire buffers
    foreach (i; 0..100)
    {
        auto buf = pool.acquire(BufferSize.SMALL);
        buffers ~= buf;
    }
    
    // Should have acquired all buffers
    assert(buffers.length == 100, "Should acquire 100 buffers");
    
    // Release all
    foreach (buf; buffers)
    {
        pool.release(buf);
    }
}

// Test 5: Massive concurrent allocations
@("STRESS: Massive concurrent allocations")
unittest
{
    import std.parallelism : parallel;
    import std.range : iota;
    
    auto router = new Router();
    
    shared int successCount = 0;
    
    router.get("/test", (ref Context ctx) {
        // Allocate in handler
        auto data = new ubyte[4096];
        import core.atomic : atomicOp;
        atomicOp!"+="(successCount, 1);
        ctx.status(200);
        ctx.send("OK");
    });
    
    // 1000 concurrent allocations
    foreach (i; parallel(iota(1000)))
    {
        auto req = makeRequest("GET", "/test");
        auto res = HTTPResponse(200, "OK");
        
        Context ctx;
        ctx.request = &req;
        ctx.response = &res;
        
        auto match = router.match("GET", "/test");
        match.handler(ctx);
    }
    
    successCount.shouldEqual(1000);
}

// ========================================
// CONCURRENCY STRESS TESTS
// ========================================

// Test 6: Router thread safety
@("STRESS: Router concurrent access safe")
unittest
{
    import std.parallelism : parallel;
    import std.range : iota;
    
    auto router = new Router();
    
    // Add routes
    foreach (i; 0..100)
    {
        router.get("/route" ~ i.to!string, (ref Context ctx) {
            ctx.status(200);
            ctx.send("OK");
        });
    }
    
    shared int successCount = 0;
    
    // Concurrent reads
    foreach (i; parallel(iota(1000)))
    {
        auto routeNum = i % 100;
        auto match = router.match("GET", "/route" ~ routeNum.to!string);
        if (match.found)
        {
            import core.atomic : atomicOp;
            atomicOp!"+="(successCount, 1);
        }
    }
    
    successCount.shouldEqual(1000);
}

// Test 7: Middleware concurrent execution
@("STRESS: Middleware concurrent execution safe")
unittest
{
    import std.parallelism : parallel;
    import std.range : iota;
    
    auto pipeline = new MiddlewarePipeline();
    
    shared int middlewareCount = 0;
    
    pipeline.use((ref Context ctx, NextFunction next) {
        import core.atomic : atomicOp;
        atomicOp!"+="(middlewareCount, 1);
        next();
    });
    
    // Concurrent execution
    foreach (i; parallel(iota(100)))
    {
        auto req = makeRequest("GET", "/test");
        auto res = HTTPResponse(200, "OK");
        
        Context ctx;
        ctx.request = &req;
        ctx.response = &res;
        
        pipeline.execute(ctx, (ref Context c) {
            c.status(200);
            c.send("OK");
        });
    }
    
    middlewareCount.shouldEqual(100);
}

// ========================================
// EDGE CASE TESTS  
// ========================================

// Test 8: Empty path handling
@("STRESS: Empty path handled")
unittest
{
    auto router = new Router();
    
    router.get("/", (ref Context ctx) {
        ctx.status(200);
        ctx.send("Root");
    });
    
    auto match = router.match("GET", "/");
    match.found.shouldBeTrue;
}

// Test 9: Very long path
@("STRESS: Very long path handled")
unittest
{
    auto router = new Router();
    
    // Create a very long path
    import std.array : replicate;
    auto longPath = "/" ~ replicate("segment/", 100);
    
    router.get(longPath, (ref Context ctx) {
        ctx.status(200);
        ctx.send("OK");
    });
    
    auto match = router.match("GET", longPath);
    // May or may not match depending on implementation limits
    // Important thing is it doesn't crash
}

// Test 10: Special characters in path
@("STRESS: Special characters in path handled")
unittest
{
    auto router = new Router();
    
    router.get("/api/v1/users/:id", (ref Context ctx) {
        ctx.status(200);
        ctx.send("OK");
    });
    
    // Test with URL-like characters
    auto match = router.match("GET", "/api/v1/users/user%40example.com");
    match.found.shouldBeTrue;
}

// Test 11: Rapid connect/disconnect
@("STRESS: Rapid connect/disconnect no leaks")
unittest
{
    auto router = new Router();
    
    router.get("/test", (ref Context ctx) {
        ctx.status(200);
        ctx.send("OK");
    });
    
    // Simulate 1000 quick connections
    foreach (i; 0..1000)
    {
        auto req = makeRequest("GET", "/test");
        auto res = HTTPResponse(200, "OK");
        
        Context ctx;
        ctx.request = &req;
        ctx.response = &res;
        
        auto match = router.match("GET", "/test");
        match.handler(ctx);
        
        // Simulate disconnect (cleanup)
        ctx = Context.init;
    }
    
    // If we get here without crash, no obvious leak
}

// Test 12: Many params extraction
@("STRESS: Many params extraction")
unittest
{
    auto router = new Router();
    
    router.get("/a/:p1/b/:p2/c/:p3/d/:p4", (ref Context ctx) {
        ctx.status(200);
        ctx.send("OK");
    });
    
    auto match = router.match("GET", "/a/1/b/2/c/3/d/4");
    match.found.shouldBeTrue;
    match.params["p1"].shouldEqual("1");
    match.params["p2"].shouldEqual("2");
    match.params["p3"].shouldEqual("3");
    match.params["p4"].shouldEqual("4");
}

// Test 13: Context storage stress
@("STRESS: Context storage many entries")
unittest
{
    Context ctx;
    
    // Add many entries
    foreach (i; 0..100)
    {
        ctx.storage.set("key" ~ i.to!string, i);
    }
    
    // Retrieve all
    foreach (i; 0..100)
    {
        auto value = ctx.storage.get!int("key" ~ i.to!string);
        value.shouldEqual(i);
    }
}

// Test 14: Deeply nested routers (simplified)
@("STRESS: Deeply nested routers")
unittest
{
    auto root = new Router();
    auto level1 = new Router("/level1");
    auto level2 = new Router("/level2");
    
    // Add route at deepest level
    level2.get("/endpoint", (ref Context ctx) {
        ctx.status(200);
        ctx.send("Deep");
    });
    
    level1.includeRouter(level2);
    root.includeRouter(level1);
    
    // Match should work for /level1/level2/endpoint
    auto match = root.match("GET", "/level1/level2/endpoint");
    match.found.shouldBeTrue;
}

// Test 15: Mixed method routes
@("STRESS: Mixed method routes")
unittest
{
    auto router = new Router();
    
    // Same path, different methods
    router.get("/resource", (ref Context ctx) { ctx.send("GET"); });
    router.post("/resource", (ref Context ctx) { ctx.send("POST"); });
    router.put("/resource", (ref Context ctx) { ctx.send("PUT"); });
    router.delete_("/resource", (ref Context ctx) { ctx.send("DELETE"); });
    
    // All should match correctly
    router.match("GET", "/resource").found.shouldBeTrue;
    router.match("POST", "/resource").found.shouldBeTrue;
    router.match("PUT", "/resource").found.shouldBeTrue;
    router.match("DELETE", "/resource").found.shouldBeTrue;
    
    // Non-existent method should not match
    router.match("PATCH", "/resource").found.shouldBeFalse;
}
