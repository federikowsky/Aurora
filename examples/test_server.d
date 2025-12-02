/**
 * Aurora Test Server
 * 
 * Server with various endpoints for integration testing.
 */
module examples.test_server;

import aurora;
import std.json;
import std.conv : to;

void main()
{
    auto app = new App();
    
    // Basic endpoints
    app.get("/", (ref Context ctx) {
        ctx.send("Test Server OK");
    });
    
    // Status codes
    app.get("/status/:code", (ref Context ctx) {
        int code = 200;
        try {
            code = ctx.params.get("code", "200").to!int;
        } catch (Exception) {}
        ctx.status(code).send("Status: " ~ code.to!string);
    });
    
    // Echo headers back
    app.get("/headers", (ref Context ctx) {
        ctx.header("Content-Type", "application/json")
           .send(`{"note":"headers endpoint"}`);
    });
    
    // Echo body back
    app.post("/echo", (ref Context ctx) {
        string body = ctx.request ? ctx.request.body : "";
        ctx.header("Content-Type", "text/plain")
           .send(body);
    });
    
    // JSON echo
    app.post("/json", (ref Context ctx) {
        string body = ctx.request ? ctx.request.body : "{}";
        ctx.header("Content-Type", "application/json")
           .send(body);
    });
    
    // Path params test
    app.get("/users/:id/posts/:postId", (ref Context ctx) {
        string userId = ctx.params.get("id", "?");
        string postId = ctx.params.get("postId", "?");
        ctx.header("Content-Type", "application/json")
           .send(`{"userId":"` ~ userId ~ `","postId":"` ~ postId ~ `"}`);
    });
    
    // Delay endpoint for timeout testing
    app.get("/delay/:ms", (ref Context ctx) {
        import core.thread : Thread;
        import core.time : dur;
        
        int ms = 100;
        try {
            ms = ctx.params.get("ms", "100").to!int;
            if (ms > 5000) ms = 5000;  // Cap at 5s
        } catch (Exception) {}
        
        Thread.sleep(dur!"msecs"(ms));
        ctx.send("Delayed " ~ ms.to!string ~ "ms");
    });
    
    import std.stdio : writeln;
    writeln("Test server on http://localhost:8080");
    
    app.listen(8080);
}
