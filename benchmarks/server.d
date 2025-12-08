/+ dub.sdl:
name "aurora_benchmark"
dependency "aurora" path=".."
+/
/**
 * Aurora HTTP Framework - Performance Benchmark
 * 
 * Simple benchmark server for measuring req/s and latency.
 * Use with wrk, hey, or ab for load testing.
 * 
 * Build & Run (MUST use release mode for accurate benchmarks):
 *   dub run --single benchmarks/server.d --build=release
 * 
 * Build modes explained:
 *   --build=debug          Development (slow, with checks)
 *   --build=release        Production (optimized, no bounds checks)
 *   --build=release-debug  Profiling (optimized + debug symbols)
 * 
 * Test with wrk:
 *   wrk -t4 -c100 -d30s http://localhost:8080/
 *   wrk -t4 -c100 -d30s http://localhost:8080/json
 * 
 * Test with hey:
 *   hey -n 100000 -c 100 http://localhost:8080/
 * 
 * Endpoints:
 *   GET /       - Plain text "Hello, World!"
 *   GET /json   - JSON {"message": "Hello, World!"}
 *   GET /delay  - Simulated 10ms delay (for latency testing)
 */
module benchmarks.server;

import aurora;
import std.stdio : writeln, writefln;
import core.time : Duration, msecs;

void main()
{
    writeln("╔════════════════════════════════════════════════════════════╗");
    writeln("║           Aurora Benchmark Server v1.0.0                   ║");
    writeln("╚════════════════════════════════════════════════════════════╝");
    writeln();
    
    // Minimal config for maximum performance
    auto config = ServerConfig.defaults();
    config.port = 8080;  // Use 9000 to avoid conflicts
    config.numWorkers = 0;  // Auto-detect CPU cores
    config.maxConnections = 50_000;
    config.maxInFlightRequests = 10_000;
    
    auto app = new App(config);
    
    // Endpoint 1: Plain text (minimal overhead)
    app.get("/", (ref Context ctx) {
        ctx.response.setHeader("Content-Type", "text/plain");
        ctx.send("Hello, World!");
    });
    
    // Endpoint 2: JSON response
    app.get("/json", (ref Context ctx) {
        ctx.json(["message": "Hello, World!"]);
    });
    
    // Endpoint 3: Simulated delay (latency testing)
    app.get("/delay", (ref Context ctx) {
        import core.thread : Thread;
        Thread.sleep(10.msecs);
        ctx.send("Delayed response");
    });
    
    // Endpoint 4: Echo body (throughput testing)
    app.post("/echo", (ref Context ctx) {
        ctx.send(ctx.request.body());
    });
    
    writeln("Endpoints:");
    writeln("  GET  /       - Plain text response");
    writeln("  GET  /json   - JSON response");
    writeln("  GET  /delay  - 10ms delayed response");
    writeln("  POST /echo   - Echo request body");
    writeln();
    writefln("Workers: %d", config.effectiveWorkers);
    writefln("Max connections: %d", config.maxConnections);
    writeln();
    writeln("Starting server on http://localhost:8080");
    writeln("Use Ctrl+C to stop");
    writeln();
    
    app.listen();
}
