/**
 * Aurora Unified Test
 * 
 * Comprehensive test covering all major Aurora features.
 */
module examples.unified_test;

import aurora;
import std.json;
import std.conv : to;
import std.stdio : writeln, writefln;

void main()
{
    writeln("═══ Aurora Unified Test Server ═══\n");
    
    auto config = ServerConfig.defaults();
    config.numWorkers = 2;
    
    auto app = new App(config);
    
    // ═══════════════════════════════════════════
    // Middleware Tests
    // ═══════════════════════════════════════════
    
    // Request counter middleware
    shared static long requestCount = 0;
    app.use((ref Context ctx, NextFunction next) {
        import core.atomic : atomicOp;
        atomicOp!"+="(requestCount, 1L);
        next();
    });
    
    // ═══════════════════════════════════════════
    // Basic Routes
    // ═══════════════════════════════════════════
    
    app.get("/", (ref Context ctx) {
        ctx.send("Aurora Unified Test");
    });
    
    // ═══════════════════════════════════════════
    // REST API Tests
    // ═══════════════════════════════════════════
    
    app.get("/api/test", (ref Context ctx) {
        ctx.header("Content-Type", "application/json")
           .send(`{"test":true}`);
    });
    
    app.post("/api/test", (ref Context ctx) {
        string body = ctx.request ? ctx.request.body : "";
        ctx.status(201)
           .header("Content-Type", "application/json")
           .send(`{"created":true,"size":` ~ body.length.to!string ~ `}`);
    });
    
    app.put("/api/test/:id", (ref Context ctx) {
        string id = ctx.params.get("id", "?");
        ctx.header("Content-Type", "application/json")
           .send(`{"updated":"` ~ id ~ `"}`);
    });
    
    app.delete_("/api/test/:id", (ref Context ctx) {
        string id = ctx.params.get("id", "?");
        ctx.status(204).send("");
    });
    
    // ═══════════════════════════════════════════
    // Path Parameters
    // ═══════════════════════════════════════════
    
    app.get("/users/:userId/posts/:postId/comments/:commentId", (ref Context ctx) {
        JSONValue result = JSONValue([
            "userId": JSONValue(ctx.params.get("userId", "")),
            "postId": JSONValue(ctx.params.get("postId", "")),
            "commentId": JSONValue(ctx.params.get("commentId", ""))
        ]);
        ctx.header("Content-Type", "application/json")
           .send(result.toString());
    });
    
    // ═══════════════════════════════════════════
    // Status Codes
    // ═══════════════════════════════════════════
    
    app.get("/error/400", (ref Context ctx) { ctx.status(400).send("Bad Request"); });
    app.get("/error/401", (ref Context ctx) { ctx.status(401).send("Unauthorized"); });
    app.get("/error/403", (ref Context ctx) { ctx.status(403).send("Forbidden"); });
    app.get("/error/404", (ref Context ctx) { ctx.status(404).send("Not Found"); });
    app.get("/error/500", (ref Context ctx) { ctx.status(500).send("Internal Error"); });
    
    // ═══════════════════════════════════════════
    // Stats
    // ═══════════════════════════════════════════
    
    app.get("/stats", (ref Context ctx) {
        import core.atomic : atomicLoad;
        ctx.header("Content-Type", "application/json")
           .send(`{"requests":` ~ atomicLoad(requestCount).to!string ~ `}`);
    });
    
    writeln("Endpoints:");
    writeln("  GET  /              - home");
    writeln("  GET  /api/test      - JSON test");
    writeln("  POST /api/test      - create test");
    writeln("  PUT  /api/test/:id  - update test");
    writeln("  DEL  /api/test/:id  - delete test");
    writeln("  GET  /users/:u/posts/:p/comments/:c");
    writeln("  GET  /error/{400,401,403,404,500}");
    writeln("  GET  /stats         - request count");
    writeln("\nStarting on http://localhost:8080\n");
    
    app.listen(8080);
}
