/+ dub.sdl:
    name "app_server"
    dependency "aurora" path=".."
    dependency "vibe-core" version="~>2.8.6"
    dependency "eventcore" version="~>0.9.0"
+/
/**
 * Aurora App Server Example
 * 
 * Demonstrates the Express.js-like API for building HTTP servers.
 * 
 * Usage:
 *   dub run --single examples/app_server.d
 * 
 * Test:
 *   curl http://localhost:8080/
 *   curl http://localhost:8080/api/users
 *   curl http://localhost:8080/api/users/123
 *   curl -X POST http://localhost:8080/api/users -d '{"name":"John"}'
 */
module app_server;

import aurora;
import std.stdio : writeln, writefln;

void main()
{
    // Create Aurora application with custom config
    auto config = ServerConfig.defaults();
    config.port = 8080;
    config.workers = 4;
    config.debug_ = true;
    
    auto app = new App(config);
    
    // ========================================
    // MIDDLEWARE
    // ========================================
    
    // Request logging middleware
    app.use((ref Context ctx, NextFunction next) {
        import std.datetime.stopwatch : StopWatch, AutoStart;
        auto sw = StopWatch(AutoStart.yes);
        
        next();
        
        sw.stop();
        writefln("%s %s %d - %dμs", 
            ctx.request.method, 
            ctx.request.path,
            ctx.response.status,
            sw.peek.total!"usecs");
    });
    
    // CORS middleware
    app.use((ref Context ctx, NextFunction next) {
        ctx.header("Access-Control-Allow-Origin", "*");
        ctx.header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
        ctx.header("Access-Control-Allow-Headers", "Content-Type, Authorization");
        
        // Handle preflight
        if (ctx.request.method == "OPTIONS")
        {
            ctx.status(204);
            return;
        }
        
        next();
    });
    
    // ========================================
    // ROOT ROUTES
    // ========================================
    
    // Home page
    app.get("/", (ref Context ctx) {
        ctx.send("🌟 Welcome to Aurora HTTP Framework!");
    });
    
    // Health check
    app.get("/health", (ref Context ctx) {
        ctx.json(`{"status":"healthy","framework":"aurora"}`);
    });
    
    // ========================================
    // API ROUTES (using sub-router)
    // ========================================
    
    auto api = new Router("/api");
    
    // GET /api/users
    api.get("/users", (ref Context ctx) {
        ctx.json(`[{"id":1,"name":"Alice"},{"id":2,"name":"Bob"}]`);
    });
    
    // GET /api/users/:id
    api.get("/users/:id", (ref Context ctx) {
        auto userId = ctx.params.get("id", "unknown");
        ctx.json(`{"id":"` ~ userId ~ `","name":"User ` ~ userId ~ `"}`);
    });
    
    // POST /api/users
    api.post("/users", (ref Context ctx) {
        ctx.status(201);
        ctx.json(`{"message":"User created","body":"` ~ ctx.request.body ~ `"}`);
    });
    
    // PUT /api/users/:id
    api.put("/users/:id", (ref Context ctx) {
        auto userId = ctx.params.get("id", "unknown");
        ctx.json(`{"message":"User ` ~ userId ~ ` updated"}`);
    });
    
    // DELETE /api/users/:id
    api.delete_("/users/:id", (ref Context ctx) {
        auto userId = ctx.params.get("id", "unknown");
        ctx.status(204);  // No Content
    });
    
    // Include API router
    app.includeRouter(api);
    
    // ========================================
    // ERROR HANDLING
    // ========================================
    
    // 404 is handled automatically by the App class
    
    // ========================================
    // START SERVER
    // ========================================
    
    writeln("\n📚 Available routes:");
    writeln("  GET  /           - Home page");
    writeln("  GET  /health     - Health check");
    writeln("  GET  /api/users  - List users");
    writeln("  GET  /api/users/:id - Get user by ID");
    writeln("  POST /api/users  - Create user");
    writeln("  PUT  /api/users/:id - Update user");
    writeln("  DELETE /api/users/:id - Delete user");
    writeln();
    
    // This blocks until server is stopped
    app.listen();
}
