/**
 * Aurora Multi-threaded Server
 * 
 * Demonstrates multi-worker configuration for high concurrency.
 * Shows how to configure worker count and monitor performance.
 */
module examples.multithread_server;

import aurora;
import core.cpuid : threadsPerCPU;
import std.conv : to;

void main()
{
    // Auto-detect CPU cores
    uint workers = threadsPerCPU();
    if (workers == 0) workers = 4;
    
    auto config = ServerConfig.defaults();
    config.numWorkers = workers;
    
    auto app = new App(config);
    
    // Health endpoint with worker info
    app.get("/", (ref Context ctx) {
        ctx.header("Content-Type", "application/json")
           .send(`{"workers":` ~ workers.to!string ~ `,"status":"running"}`);
    });
    
    // CPU-bound work simulation
    app.get("/compute/:n", (ref Context ctx) {
        import std.conv : to;
        int n = 1000;
        try {
            n = ctx.params.get("n", "1000").to!int;
        } catch (Exception) {}
        
        // Simulate computation
        long sum = 0;
        foreach (i; 0..n) sum += i;
        
        ctx.header("Content-Type", "application/json")
           .send(`{"n":` ~ n.to!string ~ `,"sum":` ~ sum.to!string ~ `}`);
    });
    
    // Stats endpoint
    app.get("/stats", (ref Context ctx) {
        ctx.header("Content-Type", "application/json")
           .send(`{"requests":` ~ app.totalRequests().to!string ~ `}`);
    });
    
    import std.stdio : writefln;
    writefln("Multi-threaded server on http://localhost:8080");
    writefln("  Workers: %d", workers);
    
    app.listen(8080);
}
