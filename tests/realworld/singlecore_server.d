/**
 * Single-Core HTTP Server for Stress Testing
 * 
 * This server uses only 1 worker thread.
 * Used to compare performance against multi-core server.
 */
module tests.realworld.singlecore_server;

import aurora;

import core.stdc.signal;
import core.stdc.stdlib : exit;
import std.stdio;
import std.conv : to;

__gshared App app;

// Pre-allocated response payloads (runtime init to avoid CTFE OOM)
private __gshared string smallPayload;   // 1KB
private __gshared string mediumPayload;  // 64KB
private __gshared string largePayload;   // 512KB

shared static this()
{
    char[1024] s = 'x';
    smallPayload = cast(string)s.idup;
    
    char[65536] m = 'M';
    mediumPayload = cast(string)m.idup;
    
    char[512 * 1024] l = 'L';
    largePayload = cast(string)l.idup;
}

extern(C) void handleSignal(int sig) nothrow @nogc @system
{
    exit(0);
}

void main(string[] args)
{
    ushort port = 8081;  // Different port from multi-core
    
    foreach (arg; args[1..$])
    {
        import std.algorithm : startsWith;
        if (arg.startsWith("--port="))
            try { port = arg[7..$].to!ushort; } catch (Exception) {}
    }
    
    // Signal handling
    signal(SIGINT, &handleSignal);
    version(Posix) signal(SIGTERM, &handleSignal);
    
    // Create app with SINGLE worker
    auto config = ServerConfig.defaults();
    config.numWorkers = 1;  // Single core!
    config.debugMode = false;
    
    app = new App(config);
    
    // === SAME ENDPOINTS AS MULTI-CORE ===
    
    app.get("/", (ref Context ctx) {
        ctx.send("OK");
    });
     app.get("/small", (ref Context ctx) {
        ctx.send(smallPayload);
    });

    app.get("/medium", (ref Context ctx) {
        ctx.send(mediumPayload);
    });

    app.get("/large", (ref Context ctx) {
        ctx.send(largePayload);
    });
    
    app.get("/json", (ref Context ctx) {
        ctx.json(["status": "ok", "workers": "1", "mode": "single-core"]);
    });
    
    app.get("/echo/:message", (ref Context ctx) {
        ctx.send("Echo: " ~ ctx.params.get("message", ""));
    });
    
    app.get("/compute", (ref Context ctx) {
        int sum = 0;
        for (int i = 0; i < 10_000; i++) sum += i;
        ctx.send("Computed: " ~ sum.to!string);
    });
    
    app.get("/health", (ref Context ctx) {
        ctx.json(`{"status":"healthy","workers":1}`);
    });
    
    app.get("/stats", (ref Context ctx) {
        auto reqs = app.totalRequests();
        ctx.json(`{"requests":` ~ reqs.to!string ~ `,"workers":1}`);
    });
    
    writefln("[Single-Core Server] Starting on port %d with 1 worker...", port);
    app.listen(port);
}
