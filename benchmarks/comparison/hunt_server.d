/+ dub.sdl:
name "hunt_benchmark"
dependency "hunt-http" version="~>0.8.2"
+/
/**
 * hunt-http Benchmark Server
 *
 * Simple benchmark server for comparison with Aurora.
 * Uses same endpoints: /, /json
 *
 * Build & Run:
 *   dub run --single benchmarks/comparison/hunt_server.d --build=release
 *
 * Test:
 *   wrk -t4 -c100 -d30s http://localhost:8082/
 *   wrk -t4 -c100 -d30s http://localhost:8082/json
 */
module benchmarks.comparison.hunt_server;

import hunt.http;
import std.stdio : writeln;

void main()
{
    writeln("hunt-http benchmark server starting on http://localhost:8082");
    
    auto server = HttpServer.builder()
        .setListener(8082, "0.0.0.0")
        .setHandler((RoutingContext ctx) {
            string path = ctx.getRequest().getPath();
            
            if (path == "/json") {
                ctx.getResponse().header("Content-Type", "application/json");
                ctx.write(`{"message":"Hello, World!"}`);
            } else {
                ctx.getResponse().header("Content-Type", "text/plain");
                ctx.write("Hello, World!");
            }
            ctx.end();
        }).build();
    
    server.start();
}
