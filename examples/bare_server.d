/**
 * Aurora Bare Server
 * 
 * Low-level server example using Server directly instead of App.
 * Useful for understanding Aurora's internals.
 */
module examples.bare_server;

import aurora.runtime.server;
import aurora.web.router;
import aurora.web.context;
import aurora.web.middleware;

void main()
{
    // Create router directly
    auto router = new Router();
    
    router.get("/", (ref Context ctx) {
        ctx.send("Bare metal Aurora!");
    });
    
    router.get("/info", (ref Context ctx) {
        ctx.header("Content-Type", "application/json")
           .send(`{"server":"Aurora","mode":"bare"}`);
    });
    
    // Create middleware pipeline
    auto pipeline = new MiddlewarePipeline();
    
    // Configure server
    auto config = ServerConfig.defaults();
    config.port = 8080;
    config.numWorkers = 2;
    
    // Create and run server directly
    auto server = new Server(router, pipeline, config);
    
    import std.stdio : writeln;
    writeln("Bare server on http://localhost:8080");
    server.run();
}
