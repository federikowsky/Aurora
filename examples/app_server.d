// filepath: /Users/federicofilippi/Desktop/MyProj/D/Aurora/examples/app_server.d
/**
 * Aurora App Server Example
 * 
 * A simple "Hello World" example demonstrating the Aurora App API.
 * Shows basic routing, path parameters, JSON responses, and Gin-style logging.
 * 
 * Build:
 *   ldc2 -O2 -I../source -I../lib/wire/source app_server.d \
 *       $(find ../source -name '*.d') ../lib/wire/build/libwire.a -of=app_server
 * 
 * Or with libaurora.a:
 *   ldc2 -O2 -I../source -I../lib/wire/source app_server.d \
 *       ../build/libaurora.a ../lib/wire/build/libwire.a -of=app_server
 * 
 * Run:
 *   ./app_server
 * 
 * Test:
 *   curl http://localhost:8080/
 *   curl http://localhost:8080/hello/YourName
 *   curl http://localhost:8080/json
 */
module examples.app_server;

import aurora;
import std.json;
import std.conv : to;

void main()
{
    // Create Aurora app with default configuration
    auto app = new App();
    
    // ========================================================================
    // Gin-style Logger Middleware (one line!)
    // ========================================================================
    app.useLogger();  // Colored Gin-style logging
    
    // ========================================================================
    // Routes
    // ========================================================================
    
    // GET / - Home page
    app.get("/", (ref Context ctx) {
        ctx.send("Hello, Aurora! 🌟");
    });
    
    // GET /hello/:name - Greeting with path parameter
    app.get("/hello/:name", (ref Context ctx) {
        string name = ctx.params.get("name", "World");
        ctx.send("Hello, " ~ name ~ "!");
    });
    
    // GET /json - JSON response
    app.get("/json", (ref Context ctx) {
        JSONValue response = JSONValue([
            "message": JSONValue("Welcome to Aurora"),
            "version": JSONValue("1.0.0"),
            "status": JSONValue("running")
        ]);
        ctx.header("Content-Type", "application/json")
           .send(response.toString());
    });
     // POST /data - Accept POST data
    app.post("/data", (ref Context ctx) {
        string body = ctx.request.body;
        ctx.header("Content-Type", "application/json")
           .send(`{"received": true, "length": ` ~ body.length.to!string ~ `}`);
    });

    // GET /health - Health check endpoint
    app.get("/health", (ref Context ctx) {
        ctx.header("Content-Type", "application/json")
           .send(`{"status": "healthy"}`);
    });
    
    // Test endpoints for different status codes
    app.get("/error", (ref Context ctx) {
        ctx.status(500).send("Internal Server Error");
    });
    
    app.get("/notfound", (ref Context ctx) {
        ctx.status(404).send("Not Found");
    });

    // ========================================================================
    // Start Server
    // ========================================================================

    import std.stdio : writeln;
    writeln("🚀 Aurora App Server starting on http://localhost:8080");
    writeln("");
    writeln("   Gin-style logging enabled! Try:");
    writeln("   curl http://localhost:8080/");
    writeln("   curl http://localhost:8080/hello/World");
    writeln("   curl http://localhost:8080/json");
    writeln("   curl -X POST http://localhost:8080/data -d '{\"test\":true}'");
    writeln("   curl http://localhost:8080/error     (500)");
    writeln("   curl http://localhost:8080/notfound  (404)");
    writeln("");

    app.listen(8080);
}
