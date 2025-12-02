/**
 * Aurora Debug Server
 * 
 * Server with verbose logging for debugging and development.
 * Shows request details, timing, and internal state.
 */
module examples.debug_server;

import aurora;
import std.stdio : writefln, writeln;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.array : replicate;

void main()
{
    auto config = ServerConfig.defaults();
    config.numWorkers = 1;  // Single worker for easier debugging
    config.debugMode = true;
    
    auto app = new App(config);
    
    // Debug logging middleware
    app.use((ref Context ctx, NextFunction next) {
        auto sw = StopWatch(AutoStart.yes);
        
        writefln("[DEBUG] → %s %s", 
            ctx.request ? ctx.request.method : "?",
            ctx.request ? ctx.request.path : "?");
        
        next();
        
        sw.stop();
        writefln("[DEBUG] ← responded (%d μs)", sw.peek.total!"usecs");
        writeln(replicate("─", 50));
    });
    
    // Routes
    app.get("/", (ref Context ctx) {
        ctx.send("Debug server running!");
    });
    
    app.get("/echo/:msg", (ref Context ctx) {
        string msg = ctx.params.get("msg", "empty");
        writefln("[DEBUG] Param msg = %s", msg);
        ctx.send("Echo: " ~ msg);
    });
    
    app.post("/debug", (ref Context ctx) {
        string body = ctx.request ? ctx.request.body : "";
        writefln("[DEBUG] Body length: %d", body.length);
        writefln("[DEBUG] Body: %s", body.length > 100 ? body[0..100] ~ "..." : body);
        ctx.header("Content-Type", "application/json")
           .send(`{"received":true}`);
    });
    
    writeln(replicate("═", 50));
    writeln("  DEBUG SERVER - http://localhost:8080");
    writeln("  Single worker, verbose logging enabled");
    writeln(replicate("═", 50));
    
    app.listen(8080);
}
