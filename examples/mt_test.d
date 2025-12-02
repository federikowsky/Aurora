/**
 * Aurora MT (Multi-Threading) Test
 * 
 * Stress test for multi-threaded server.
 * Tests thread safety and concurrent request handling.
 */
module examples.mt_test;

import aurora;
import core.atomic;
import std.conv : to;

// Thread-safe counters
shared long totalRequests = 0;
shared long[8] workerRequests;  // Per-worker counter

void main()
{
    auto config = ServerConfig.defaults();
    config.numWorkers = 4;
    
    auto app = new App(config);
    
    // Increment counter on every request
    app.use((ref Context ctx, NextFunction next) {
        atomicOp!"+="(totalRequests, 1);
        next();
    });
    
    app.get("/", (ref Context ctx) {
        ctx.send("MT Test Server");
    });
    
    app.get("/stress", (ref Context ctx) {
        // Quick response for load testing
        ctx.send("OK");
    });
    
    app.get("/stats", (ref Context ctx) {
        auto total = atomicLoad(totalRequests);
        ctx.header("Content-Type", "application/json")
           .send(`{"total_requests":` ~ total.to!string ~ `}`);
    });
    
    // Shared state test
    app.post("/increment", (ref Context ctx) {
        auto newVal = atomicOp!"+="(totalRequests, 1);
        ctx.header("Content-Type", "application/json")
           .send(`{"count":` ~ newVal.to!string ~ `}`);
    });
    
    import std.stdio : writeln;
    writeln("MT Test Server on http://localhost:8080");
    writeln("  /        - home");
    writeln("  /stress  - load test endpoint");
    writeln("  /stats   - request count");
    
    app.listen(8080);
}
