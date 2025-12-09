/**
 * End-to-End Integration Tests - Basic Request Flow
 *
 * Tests full request cycle: HTTP → Router → Middleware → Handler → Response
 *
 * Coverage:
 * - GET request → 200 OK
 * - POST with JSON → 201 Created
 * - GET nonexistent → 404 Not Found
 * - PUT with params → 200 OK
 * - DELETE request → 204 No Content
 * - Middleware chain execution
 * - Nested routers
 */
module tests.integration.basic_flow_test;

import unit_threaded;
import aurora.web;
import aurora.http;

// Helper to create a mock request via parsing
private HTTPRequest makeRequest(string method, string path, string body_ = "", string[string] headers = null)
{
    import std.array : appender;
    import std.conv : to;
    
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

// Test 1: Simple GET request → 200 OK
@("E2E: GET request returns 200")
unittest
{
    auto router = new Router();
    
    router.get("/hello", (ref Context ctx) {
        ctx.status(200);
        ctx.send("Hello, World!");
    });
    
    // Simulate HTTP request
    auto req = makeRequest("GET", "/hello");
    auto res = HTTPResponse(200, "OK");
    
    Context ctx;
    ctx.request = &req;
    ctx.response = &res;
    
    // Match route
    auto match = router.match("GET", "/hello");
    match.found.shouldBeTrue;
    
    // Execute handler
    match.handler(ctx);
    
    // Validate response
    res.getStatus().shouldEqual(200);
    res.getBody().shouldEqual("Hello, World!");
}

// Test 2: POST with JSON → 201 Created
@("E2E: POST with JSON returns 201")
unittest
{
    auto router = new Router();
    
    router.post("/users", (ref Context ctx) {
        // Parse JSON body
        import std.json : parseJSON;
        auto bodyStr = ctx.request.body;
        auto json = parseJSON(bodyStr);
        
        // Create user
        auto name = json["name"].str;
        auto age = cast(int)json["age"].integer;
        
        // Return 201
        ctx.status(201);
        import std.format : format;
        ctx.send(format(`{"id":1,"name":"%s","age":%d}`, name, age));
    });
    
    // Simulate POST request
    auto req = makeRequest("POST", "/users", `{"name":"Alice","age":30}`, 
        ["Content-Type": "application/json"]);
    auto res = HTTPResponse(200, "OK");
    
    Context ctx;
    ctx.request = &req;
    ctx.response = &res;
    
    // Match and execute
    auto match = router.match("POST", "/users");
    match.found.shouldBeTrue;
    match.handler(ctx);
    
    // Validate response
    res.getStatus().shouldEqual(201);
    assert(res.getBody().length > 0, "Response body empty");
}

// Test 3: GET nonexistent route → 404 Not Found
@("E2E: GET nonexistent returns 404")
unittest
{
    auto router = new Router();
    
    router.get("/hello", (ref Context ctx) {
        ctx.status(200);
        ctx.send("Hello");
    });
    
    // Request nonexistent route
    auto req = makeRequest("GET", "/nonexistent");
    auto res = HTTPResponse(200, "OK");
    
    Context ctx;
    ctx.request = &req;
    ctx.response = &res;
    
    // Match route
    auto match = router.match("GET", "/nonexistent");
    match.found.shouldBeFalse;
    
    // Simulate error middleware
    if (!match.found) {
        ctx.status(404);
        ctx.send(`{"error":"Not Found","status":404}`);
    }
    
    // Validate response
    res.getStatus().shouldEqual(404);
}

// Test 4: PUT with parameters → 200 OK
@("E2E: PUT with params returns 200")
unittest
{
    auto router = new Router();
    
    router.put("/users/:id", (ref Context ctx) {
        // Get params from context
        auto userId = ctx.params["id"];
        
        // Parse body
        import std.json : parseJSON;
        auto bodyStr = ctx.request.body;
        auto json = parseJSON(bodyStr);
        
        // Update user
        ctx.status(200);
        import std.format : format;
        ctx.send(format(`{"id":"%s","name":"%s"}`, userId, json["name"].str));
    });
    
    // Simulate PUT request
    auto req = makeRequest("PUT", "/users/123", `{"name":"Bob"}`,
        ["Content-Type": "application/json"]);
    auto res = HTTPResponse(200, "OK");
    
    Context ctx;
    ctx.request = &req;
    ctx.response = &res;
    
    // Match route and extract params
    auto match = router.match("PUT", "/users/123");
    match.found.shouldBeTrue;
    match.params["id"].shouldEqual("123");
    
    // Set params in context
    ctx.params = match.params;
    
    // Execute handler
    match.handler(ctx);
    
    // Validate response
    res.getStatus().shouldEqual(200);
}

// Test 5: DELETE request → 204 No Content
@("E2E: DELETE returns 204")
unittest
{
    auto router = new Router();
    
    router.delete_("/users/:id", (ref Context ctx) {
        auto userId = ctx.params["id"];
        
        // Delete user (simulated)
        ctx.status(204);
        // No body for 204
    });
    
    // Simulate DELETE request
    auto req = makeRequest("DELETE", "/users/123");
    auto res = HTTPResponse(200, "OK");
    
    Context ctx;
    ctx.request = &req;
    ctx.response = &res;
    
    // Match and execute
    auto match = router.match("DELETE", "/users/123");
    match.found.shouldBeTrue;
    ctx.params = match.params;
    match.handler(ctx);
    
    // Validate response
    res.getStatus().shouldEqual(204);
}

// Test 6: Middleware chain execution
@("E2E: Middleware chain executes in order")
unittest
{
    auto pipeline = new MiddlewarePipeline();
    
    int[] executionOrder;
    
    pipeline.use((ref Context ctx, NextFunction next) {
        executionOrder ~= 1;
        next();
    });
    
    pipeline.use((ref Context ctx, NextFunction next) {
        executionOrder ~= 2;
        next();
    });
    
    auto req = makeRequest("GET", "/test");
    auto res = HTTPResponse(200, "OK");
    
    Context ctx;
    ctx.request = &req;
    ctx.response = &res;
    
    pipeline.execute(ctx, (ref Context c) {
        executionOrder ~= 3;
        c.status(200);
        c.send("OK");
    });
    
    executionOrder.shouldEqual([1, 2, 3]);
    res.getStatus().shouldEqual(200);
}

// Test 7: Auth middleware short-circuit
@("E2E: Auth middleware fails returns 401")
unittest
{
    auto pipeline = new MiddlewarePipeline();
    
    bool handlerCalled = false;
    
    pipeline.use((ref Context ctx, NextFunction next) {
        // Check auth header
        if (!ctx.request.hasHeader("Authorization")) {
            ctx.status(401);
            ctx.send(`{"error":"Unauthorized"}`);
            return;  // Don't call next
        }
        next();
    });
    
    auto req = makeRequest("GET", "/protected");
    // No Authorization header
    auto res = HTTPResponse(200, "OK");
    
    Context ctx;
    ctx.request = &req;
    ctx.response = &res;
    
    pipeline.execute(ctx, (ref Context c) {
        handlerCalled = true;
        c.status(200);
    });
    
    handlerCalled.shouldBeFalse;
    res.getStatus().shouldEqual(401);
}

// Test 8: Multiple middleware integration  
@("E2E: CORS + Security + Logger work together")
unittest
{
    import aurora.web.middleware.cors;
    import aurora.web.middleware.security;
    import aurora.web.middleware.logger;
    
    auto pipeline = new MiddlewarePipeline();
    
    auto corsConfig = CORSConfig();
    corsConfig.allowedOrigins = ["*"];  // Explicitly set for test (default is now [] for security)
    auto cors = new CORSMiddleware(corsConfig);
    
    auto securityConfig = SecurityConfig();
    auto security = new SecurityMiddleware(securityConfig);
    
    auto logger = new LoggerMiddleware();
    
    pipeline.use((ref Context ctx, NextFunction next) { cors.handle(ctx, next); });
    pipeline.use((ref Context ctx, NextFunction next) { security.handle(ctx, next); });
    pipeline.use((ref Context ctx, NextFunction next) { logger.handle(ctx, next); });
    
    auto req = makeRequest("GET", "/test");
    auto res = HTTPResponse(200, "OK");
    
    Context ctx;
    ctx.request = &req;
    ctx.response = &res;
    
    pipeline.execute(ctx, (ref Context c) {
        c.status(200);
        c.send("OK");
    });
    
    // Validate headers from all middleware
    auto headers = res.getHeaders();
    assert("Access-Control-Allow-Origin" in headers, "CORS header missing");
    assert("X-Content-Type-Options" in headers, "Security header missing");
    res.getStatus().shouldEqual(200);
}

// Test 9: Nested routers
@("E2E: Nested routers resolve correct path")
unittest
{
    auto app = new Router();
    auto api = new Router("/api");
    auto v1 = new Router("/v1");
    
    v1.get("/users", (ref Context ctx) {
        ctx.status(200);
        ctx.send("Users API v1");
    });
    
    api.includeRouter(v1);
    app.includeRouter(api);
    
    // Match full path
    auto match = app.match("GET", "/api/v1/users");
    match.found.shouldBeTrue;
    
    auto req = makeRequest("GET", "/api/v1/users");
    auto res = HTTPResponse(200, "OK");
    
    Context ctx;
    ctx.request = &req;
    ctx.response = &res;
    
    match.handler(ctx);
    
    res.getStatus().shouldEqual(200);
    res.getBody().shouldEqual("Users API v1");
}

// Test 10: Root path matching
@("E2E: Root path matches correctly")
unittest
{
    auto router = new Router();
    
    router.get("/", (ref Context ctx) {
        ctx.status(200);
        ctx.send("Home");
    });
    
    auto match = router.match("GET", "/");
    match.found.shouldBeTrue;
    
    auto req = makeRequest("GET", "/");
    auto res = HTTPResponse(200, "OK");
    
    Context ctx;
    ctx.request = &req;
    ctx.response = &res;
    
    match.handler(ctx);
    
    res.getStatus().shouldEqual(200);
    res.getBody().shouldEqual("Home");
}
