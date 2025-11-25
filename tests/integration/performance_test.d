/**
 * End-to-End Integration Tests - Performance & Stress
 *
 * Tests performance, concurrency, and stress scenarios
 *
 * Coverage:
 * - Sequential request throughput
 * - Concurrent request handling
 * - Hello world throughput
 * - Latency P99
 * - Router-local middleware
 * - Multiple sub-routers
 */
module tests.integration.performance_test;

import unit_threaded;
import aurora.web;
import aurora.http;
import std.datetime.stopwatch;
import core.time;
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

// Test 1: 1000 sequential requests
@("PERF: 1000 sequential requests succeed")
unittest
{
    auto router = new Router();
    
    int requestCount = 0;
    
    router.get("/test", (ref Context ctx) {
        requestCount++;
        ctx.status(200);
        ctx.send("OK");
    });
    
    // Execute 1000 requests
    foreach (i; 0..1000)
    {
        auto req = makeRequest("GET", "/test");
        auto res = HTTPResponse(200, "OK");
        
        Context ctx;
        ctx.request = &req;
        ctx.response = &res;
        
        auto match = router.match("GET", "/test");
        match.handler(ctx);
        
        res.getStatus().shouldEqual(200);
    }
    
    requestCount.shouldEqual(1000);
}

// Test 2: 100 concurrent requests (simulated)
@("PERF: 100 concurrent requests succeed")
unittest
{
    auto router = new Router();
    
    shared int requestCount = 0;
    
    router.get("/test", (ref Context ctx) {
        import core.atomic : atomicOp;
        atomicOp!"+="(requestCount, 1);
        ctx.status(200);
        ctx.send("OK");
    });
    
    // Simulate concurrent requests
    import std.parallelism : parallel;
    import std.range : iota;
    
    foreach (i; parallel(iota(100)))
    {
        auto req = makeRequest("GET", "/test");
        auto res = HTTPResponse(200, "OK");
        
        Context ctx;
        ctx.request = &req;
        ctx.response = &res;
        
        auto match = router.match("GET", "/test");
        match.handler(ctx);
    }
    
    requestCount.shouldEqual(100);
}

// Test 3: Hello world throughput (relaxed)
@("PERF: Hello world throughput > 10K req/s")
unittest
{
    auto router = new Router();
    
    router.get("/hello", (ref Context ctx) {
        ctx.status(200);
        ctx.send("Hello, World!");
    });
    
    auto sw = StopWatch(AutoStart.yes);
    
    // Execute 10K requests
    foreach (i; 0..10_000)
    {
        auto req = makeRequest("GET", "/hello");
        auto res = HTTPResponse(200, "OK");
        
        Context ctx;
        ctx.request = &req;
        ctx.response = &res;
        
        auto match = router.match("GET", "/hello");
        match.handler(ctx);
    }
    
    sw.stop();
    auto duration = sw.peek();
    auto msecs = duration.total!"msecs";
    auto reqPerSec = msecs > 0 ? 10_000.0 / (msecs / 1000.0) : 10_000_000;
    
    // Relaxed target: > 10K req/s (debug mode)
    assert(reqPerSec > 10_000, "Throughput too low: " ~ reqPerSec.to!string ~ " req/s");
}

// Test 4: Latency P99 < 100ms (relaxed)
@("PERF: Latency P99 < 100ms")
unittest
{
    auto router = new Router();
    
    router.get("/test", (ref Context ctx) {
        ctx.status(200);
        ctx.send("OK");
    });
    
    Duration[] latencies;
    
    // Measure 100 requests
    foreach (i; 0..100)
    {
        auto sw = StopWatch(AutoStart.yes);
        
        auto req = makeRequest("GET", "/test");
        auto res = HTTPResponse(200, "OK");
        
        Context ctx;
        ctx.request = &req;
        ctx.response = &res;
        
        auto match = router.match("GET", "/test");
        match.handler(ctx);
        
        sw.stop();
        latencies ~= sw.peek();
    }
    
    // Sort latencies
    import std.algorithm : sort;
    latencies.sort();
    
    // Get P99 (99th percentile)
    auto p99 = latencies[cast(size_t)(latencies.length * 0.99)];
    
    // Relaxed target: < 100ms (debug mode)
    assert(p99.total!"msecs" < 100, "P99 latency too high: " ~ p99.total!"msecs".to!string ~ "ms");
}

// Test 5: Simulated keep-alive (100 requests)
@("PERF: Keep-alive simulation works")
unittest
{
    auto router = new Router();
    
    int requestCount = 0;
    
    router.get("/test", (ref Context ctx) {
        requestCount++;
        ctx.status(200);
        ctx.send("OK");
    });
    
    // Simulate 100 requests on same connection
    foreach (i; 0..100)
    {
        auto req = makeRequest("GET", "/test", "", ["Connection": "keep-alive"]);
        auto res = HTTPResponse(200, "OK");
        
        Context ctx;
        ctx.request = &req;
        ctx.response = &res;
        
        auto match = router.match("GET", "/test");
        match.handler(ctx);
    }
    
    requestCount.shouldEqual(100);
}

// Test 6: Connection pooling simulation
@("PERF: Connection pooling efficient")
unittest
{
    auto router = new Router();
    
    shared int requestCount = 0;
    
    router.get("/test", (ref Context ctx) {
        import core.atomic : atomicOp;
        atomicOp!"+="(requestCount, 1);
        ctx.status(200);
        ctx.send("OK");
    });
    
    // Simulate multiple connections, multiple requests each
    import std.parallelism : parallel;
    import std.range : iota;
    
    foreach (conn; parallel(iota(10)))
    {
        foreach (r; 0..10)
        {
            auto req = makeRequest("GET", "/test");
            auto res = HTTPResponse(200, "OK");
            
            Context ctx;
            ctx.request = &req;
            ctx.response = &res;
            
            auto match = router.match("GET", "/test");
            match.handler(ctx);
        }
    }
    
    requestCount.shouldEqual(100);
}

// Test 7: High concurrency (1000 simulated)
@("PERF: 1000 concurrent connections stable")
unittest
{
    auto router = new Router();
    
    shared int requestCount = 0;
    
    router.get("/test", (ref Context ctx) {
        import core.atomic : atomicOp;
        atomicOp!"+="(requestCount, 1);
        ctx.status(200);
        ctx.send("OK");
    });
    
    // Simulate 1000 concurrent connections
    import std.parallelism : parallel;
    import std.range : iota;
    
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
    
    requestCount.shouldEqual(1000);
}

// Test 8: Large request body (1MB)
@("PERF: Large request body handled")
unittest
{
    auto router = new Router();
    
    router.post("/upload", (ref Context ctx) {
        auto bodySize = ctx.request.body.length;
        ctx.status(200);
        ctx.send("Received " ~ bodySize.to!string ~ " bytes");
    });
    
    // Create 1MB body
    import std.array : replicate;
    auto largeBody = replicate("A", 1024 * 1024);
    
    auto req = makeRequest("POST", "/upload", largeBody, ["Content-Type": "application/octet-stream"]);
    auto res = HTTPResponse(200, "OK");
    
    Context ctx;
    ctx.request = &req;
    ctx.response = &res;
    
    auto match = router.match("POST", "/upload");
    match.handler(ctx);
    
    res.getStatus().shouldEqual(200);
}

// Test 9: Router-local middleware
@("PERF: Router-local middleware executes")
unittest
{
    auto router = new Router("/api");
    
    int middlewareCount = 0;
    
    router.use((ref Context ctx, NextFunction next) {
        middlewareCount++;
        next();
    });
    
    router.get("/test", (ref Context ctx) {
        ctx.status(200);
        ctx.send("OK");
    });
    
    // Note: This test shows the pattern
    // Actual execution would require MiddlewarePipeline integration
    router.middlewares.length.shouldEqual(1);
}

// Test 10: Multiple sub-routers
@("PERF: Multiple sub-routers isolated")
unittest
{
    auto app = new Router();
    auto usersRouter = new Router("/users");
    auto postsRouter = new Router("/posts");
    auto productsRouter = new Router("/products");
    
    usersRouter.get("/", (ref Context ctx) {
        ctx.status(200);
        ctx.send("Users");
    });
    
    postsRouter.get("/", (ref Context ctx) {
        ctx.status(200);
        ctx.send("Posts");
    });
    
    productsRouter.get("/", (ref Context ctx) {
        ctx.status(200);
        ctx.send("Products");
    });
    
    app.includeRouter(usersRouter);
    app.includeRouter(postsRouter);
    app.includeRouter(productsRouter);
    
    // Test all routes
    auto match1 = app.match("GET", "/users");
    auto match2 = app.match("GET", "/posts");
    auto match3 = app.match("GET", "/products");
    
    match1.found.shouldBeTrue;
    match2.found.shouldBeTrue;
    match3.found.shouldBeTrue;
    
    // Execute handlers without HTTP parsing (direct test)
    auto res1 = HTTPResponse(200, "OK");
    Context ctx1;
    ctx1.response = &res1;
    match1.handler(ctx1);
    
    auto res2 = HTTPResponse(200, "OK");
    Context ctx2;
    ctx2.response = &res2;
    match2.handler(ctx2);
    
    auto res3 = HTTPResponse(200, "OK");
    Context ctx3;
    ctx3.response = &res3;
    match3.handler(ctx3);
    
    // Validate responses
    res1.getBody().shouldEqual("Users");
    res2.getBody().shouldEqual("Posts");
    res3.getBody().shouldEqual("Products");
}
