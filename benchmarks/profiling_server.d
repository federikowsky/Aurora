#!/usr/bin/env dub
/+ dub.sdl:
    name "aurora_profiling_benchmark"
    dependency "aurora" path=".."
+/
/**
 * Aurora Profiling Benchmark Server
 * 
 * Runs with detailed metrics collection and periodic stats output.
 * Use this to identify performance bottlenecks.
 */
module benchmarks.profiling_server;

import aurora;
import aurora.runtime.server : Server, ServerConfig;
import aurora.mem.pool : BufferPool;
import core.time : seconds, msecs;
import core.thread : Thread;
import std.stdio : writeln, writefln;
import std.datetime.stopwatch : StopWatch, AutoStart;

void main()
{
    writeln("╔══════════════════════════════════════════════════════════════╗");
    writeln("║         Aurora Profiling Benchmark Server                    ║");
    writeln("╚══════════════════════════════════════════════════════════════╝");
    writeln();
    
    // Minimal config for profiling
    auto config = ServerConfig.defaults();
    config.port = 8080;
    config.numWorkers = 0;  // Auto-detect
    config.maxConnections = 50_000;
    config.maxInFlightRequests = 10_000;
    config.debugMode = true;
    
    auto app = new App(config);
    
    // Simple plaintext endpoint
    app.get("/", (ref Context ctx) {
        ctx.send("Hello, World!");
    });
    
    // JSON endpoint
    app.get("/json", (ref Context ctx) {
        ctx.json(`{"message":"Hello, World!"}`);
    });
    
    // Stats endpoint
    app.get("/stats", (ref Context ctx) {
        import std.format : format;
        auto stats = format(
            `{"requests":%d,"connections":%d,"active":%d,"errors":%d}`,
            app.totalRequests(),
            app.isRunning ? 1 : 0,  // simplified
            0,
            0
        );
        ctx.json(stats);
    });
    
    // Start stats printer in background
    import vibe.core.core : runTask;
    runTask({
        auto lastRequests = 0UL;
        auto sw = StopWatch(AutoStart.yes);
        
        while (true) {
            Thread.sleep(5.seconds);
            
            auto currentRequests = app.totalRequests();
            auto elapsed = sw.peek.total!"msecs";
            auto rps = elapsed > 0 ? (currentRequests - lastRequests) * 1000 / elapsed : 0;
            
            writeln();
            writeln("═══════════════════════════════════════════════════════");
            writefln("  Requests/sec (5s avg): %,d", rps);
            writefln("  Total requests:        %,d", currentRequests);
            
            // BufferPool metrics
            writeln("───────────────────────────────────────────────────────");
            writefln("  Pool hits (global):    %,d", BufferPool.getGlobalPoolMisses());
            writefln("  Pool fallbacks:        %,d", BufferPool.getGlobalFallbackAllocs());
            writefln("  Pool full drops:       %,d", BufferPool.getGlobalPoolFullDrops());
            
            writeln("═══════════════════════════════════════════════════════");
            
            lastRequests = currentRequests;
            sw.reset();
            sw.start();
        }
    });
    
    writeln();
    writeln("Endpoints:");
    writeln("  GET  /       - Plain text response");
    writeln("  GET  /json   - JSON response");
    writeln("  GET  /stats  - Server statistics");
    writeln();
    writefln("Starting server on http://localhost:%d", config.port);
    writeln("Stats printed every 5 seconds");
    writeln("Use Ctrl+C to stop");
    writeln();
    
    // Run (blocking)
    app.listen();
}
