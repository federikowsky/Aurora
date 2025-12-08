/+ dub.sdl:
name "vibed_benchmark"
dependency "vibe-d" version="~>0.10.0"
+/
/**
 * vibe.d HTTP Benchmark Server
 *
 * Simple benchmark server for comparison with Aurora.
 * Uses same endpoints: /, /json
 *
 * Build & Run:
 *   dub run --single benchmarks/comparison/vibed_server.d --build=release
 *
 * Test:
 *   wrk -t4 -c100 -d30s http://localhost:8081/
 *   wrk -t4 -c100 -d30s http://localhost:8081/json
 */
module benchmarks.comparison.vibed_server;

import vibe.vibe;

void main()
{
    auto settings = new HTTPServerSettings;
    settings.port = 8081;  // Different port from Aurora (8080)
    settings.bindAddresses = ["0.0.0.0"];
    
    auto router = new URLRouter;
    
    // Endpoint 1: Plain text
    router.get("/", (req, res) {
        res.contentType = "text/plain";
        res.writeBody("Hello, World!");
    });
    
    // Endpoint 2: JSON
    router.get("/json", (req, res) {
        res.contentType = "application/json";
        res.writeBody(`{"message":"Hello, World!"}`);
    });
    
    listenHTTP(settings, router);
    
    logInfo("vibe.d benchmark server running on http://localhost:8081");
    runApplication();
}
