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
            `{"requests":%d,"connections":%d,"active":%d,"errors":%d,"pool_misses":%d}`,
            app.totalRequests(),
            app.isRunning ? 1 : 0,
            0,
            0,
            BufferPool.getGlobalPoolMisses()
        );
        ctx.json(stats);
    });

    writeln();
    writeln("Endpoints:");
    writeln("  GET  /       - Plain text response");
    writeln("  GET  /json   - JSON response");
    writeln("  GET  /stats  - Server statistics (JSON)");
    writeln();
    writefln("Starting server on http://localhost:%d", config.port);
    writeln("Monitor with: watch -n1 'curl -s http://localhost:8080/stats | jq'");
    writeln("Use Ctrl+C to stop");
    writeln();
    
    // Run (blocking)
    app.listen();
}
