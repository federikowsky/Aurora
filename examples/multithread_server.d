/+ dub.sdl:
    name "multithread_server"
    dependency "aurora" path=".."
    dependency "vibe-core" version="~>2.8.6"
    dependency "eventcore" version="~>0.9.0"
+/
/**
 * Multi-Threaded Production Server
 * 
 * Demonstrates Aurora's true multi-threaded architecture:
 * - N worker threads (one per CPU core by default)
 * - Main thread accepts connections, workers process them
 * - Thread-local resources (BufferPool, Arena, Reactor)
 * - Connection distribution via thread-safe queue
 *
 * Usage:
 *   dub run --single multithread_server.d
 *
 * Test:
 *   python3 final_benchmark.py
 */
module multithread_server;

import aurora.runtime.server;
import aurora.web.router;
import aurora.web.context;
import aurora.web.middleware;

import core.thread;
import core.time;
import core.atomic;
import std.stdio;
import std.conv : to;
import std.array : appender;
import std.random : uniform, Random, unpredictableSeed;
import core.memory : GC;

// === Global Statistics ===
shared ulong startTime;

// Pre-generate payloads
__gshared string smallPayload;
__gshared string mediumPayload;
__gshared string largePayload;

void initPayloads()
{
    auto small = appender!string();
    foreach (_; 0 .. 1024)
        small ~= 'A';
    smallPayload = small.data;
    
    auto medium = appender!string();
    foreach (_; 0 .. 64 * 1024)
        medium ~= 'B';
    mediumPayload = medium.data;
    
    auto large = appender!string();
    foreach (_; 0 .. 512 * 1024)
        large ~= 'C';
    largePayload = large.data;
    
    stderr.writefln("Payloads: small=%dKB, medium=%dKB, large=%dKB",
                    smallPayload.length/1024, mediumPayload.length/1024, 
                    largePayload.length/1024);
}

void main(string[] args)
{
    ushort port = 8080;
    uint numWorkers = 0;  // 0 = auto-detect
    
    // Parse args
    foreach (i, arg; args)
    {
        if (arg == "-p" && i + 1 < args.length)
            port = args[i + 1].to!ushort;
        else if (arg == "-w" && i + 1 < args.length)
            numWorkers = args[i + 1].to!uint;
    }
    
    initPayloads();
    atomicStore(startTime, cast(ulong)(MonoTime.currTime.ticks / 10_000_000));
    
    // Setup router
    auto router = new Router();
    
    // Root - minimal
    router.get("/", (ref Context ctx) {
        ctx.send("OK");
    });
    
    // Health check
    router.get("/health", (ref Context ctx) {
        ctx.header("Content-Type", "application/json");
        ctx.send(`{"status":"healthy"}`);
    });
    
    // Small payload (1KB)
    router.get("/small", (ref Context ctx) {
        ctx.send(smallPayload);
    });
    
    // Medium payload (64KB)
    router.get("/medium", (ref Context ctx) {
        ctx.send(mediumPayload);
    });
    
    // Large payload (512KB)  
    router.get("/large", (ref Context ctx) {
        ctx.send(largePayload);
    });
    
    // JSON endpoint
    router.get("/json", (ref Context ctx) {
        auto rng = Random(unpredictableSeed);
        auto json = appender!string();
        json ~= `{"items":[`;
        foreach (i; 0 .. 100)
        {
            if (i > 0) json ~= ",";
            json ~= `{"id":` ~ i.to!string ~ 
                    `,"value":` ~ uniform(0, 10000, rng).to!string ~ `}`;
        }
        json ~= `]}`;
        ctx.header("Content-Type", "application/json");
        ctx.send(json.data);
    });
    
    // CPU-intensive
    router.get("/compute", (ref Context ctx) {
        long sum = 0;
        foreach (i; 0 .. 10000)
            sum += i * i;
        ctx.send("Result: " ~ sum.to!string);
    });
    
    // Echo POST body
    router.post("/echo", (ref Context ctx) {
        ctx.send(ctx.request.body());
    });
    
    auto pipeline = new MiddlewarePipeline();
    
    // Configure server
    auto config = ServerConfig.defaults();
    config.port = port;
    config.numWorkers = numWorkers;
    config.connectionConfig.maxRequestsPerConnection = 1000;
    config.connectionConfig.keepAliveTimeout = 30.seconds;
    
    // Create and run server
    auto server = new Server(router, pipeline, config);
    
    // Stats printer
    new Thread({
        while (true)
        {
            Thread.sleep(15.seconds);
            try { server.printStats(); } catch (Exception) {}
        }
    }).start();
    
    // Signal handler for graceful shutdown
    import core.stdc.signal;
    
    extern(C) void handleSigint(int) nothrow @nogc
    {
        import core.stdc.stdio : printf;
        printf("\nShutting down...\n");
    }
    
    signal(SIGINT, &handleSigint);
    
    server.run();
}
