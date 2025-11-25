/**
 * Multi-Core HTTP Server for Stress Testing
 * 
 * This server uses multiple worker threads to handle requests.
 * Used as target for stress tests to measure throughput and latency.
 */
module tests.realworld.multicore_server;

import aurora;

import core.stdc.signal;
import core.stdc.stdlib : exit;
import std.stdio;
import std.conv : to;

__gshared App app;

extern(C) void handleSignal(int sig) nothrow @nogc @system
{
    exit(0);
}

void main(string[] args)
{
    // Parse args
    uint numWorkers = 8;
    ushort port = 8080;
    
    foreach (arg; args[1..$])
    {
        import std.algorithm : startsWith;
        if (arg.startsWith("--workers="))
            try { numWorkers = arg[10..$].to!uint; } catch (Exception) {}
        else if (arg.startsWith("--port="))
            try { port = arg[7..$].to!ushort; } catch (Exception) {}
    }
    
    // Signal handling
    signal(SIGINT, &handleSignal);
    version(Posix) signal(SIGTERM, &handleSignal);
    
    // Create app with workers
    auto config = ServerConfig.defaults();
    config.numWorkers = numWorkers;
    config.debugMode = false;  // Quiet mode for benchmarks
    
    app = new App(config);
    
    // === TEST ENDPOINTS ===
    
    // Minimal response (test raw throughput)
    app.get("/", (ref Context ctx) {
        ctx.send("OK");
    });
    
    // Small response (1KB)
    app.get("/small", (ref Context ctx) {
        // Pre-allocated 1KB response
        static immutable smallPayload = () {
            char[1024] buf = 'x';
            return cast(string)buf.idup;
        }();
        ctx.send(smallPayload);
    });
    
    // Medium response (64KB)
    app.get("/medium", (ref Context ctx) {
        static immutable mediumPayload = () {
            char[65536] buf = 'M';
            return cast(string)buf.idup;
        }();
        ctx.send(mediumPayload);
    });
    
    // Large response (512KB)
    app.get("/large", (ref Context ctx) {
        static immutable largePayload = () {
            char[512 * 1024] buf = 'L';
            return cast(string)buf.idup;
        }();
        ctx.send(largePayload);
    });
    
    // JSON response
    app.get("/json", (ref Context ctx) {
        ctx.json(["status": "ok", "workers": numWorkers.to!string, "mode": "multi-core"]);
    });
    
    // Echo parameter (tests routing)
    app.get("/echo/:message", (ref Context ctx) {
        ctx.send("Echo: " ~ ctx.params.get("message", ""));
    });
    
    // CPU-bound endpoint (simulate computation)
    app.get("/compute", (ref Context ctx) {
        int sum = 0;
        for (int i = 0; i < 10_000; i++) sum += i;
        ctx.send("Computed: " ~ sum.to!string);
    });
    
    // Health check
    app.get("/health", (ref Context ctx) {
        ctx.json(`{"status":"healthy","workers":` ~ numWorkers.to!string ~ `}`);
    });
    
    // Stats endpoint
    app.get("/stats", (ref Context ctx) {
        auto reqs = app.totalRequests();
        ctx.json(`{"requests":` ~ reqs.to!string ~ `,"workers":` ~ numWorkers.to!string ~ `}`);
    });
    
    writefln("[Multi-Core Server] Starting on port %d with %d workers...", port, numWorkers);
    app.listen(port);
}
