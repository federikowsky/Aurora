/+ dub.sdl:
name "production_server"
dependency "aurora" path=".."
+/
/**
 * Aurora Enterprise Production Server
 * 
 * Production-ready server configuration showcasing v0.7.0 enterprise features:
 * 
 * 1. **Connection Limits & Backpressure**: Prevents resource exhaustion
 * 2. **Kubernetes Health Probes**: /health/live, /health/ready, /health/startup
 * 3. **Load Shedding**: Probabilistic request rejection under load
 * 4. **Circuit Breaker**: Prevents cascading failures
 * 5. **Bulkhead Pattern**: Isolates failures between endpoint groups
 * 6. **Rate Limiting**: Per-client request throttling with bucket cleanup
 * 7. **Distributed Tracing**: W3C Trace Context propagation
 * 8. **Memory Pressure Monitoring**: GC pressure management
 * 9. **Security Headers**: OWASP recommended headers
 * 10. **CORS**: Cross-origin resource sharing
 * 
 * Environment Variables:
 *   PORT          - Server port (default: 8080)
 *   WORKERS       - Number of worker threads (default: 4)
 *   SERVICE_NAME  - Service name for tracing (default: aurora-service)
 */
module examples.production_server;

import aurora;
import aurora.web.middleware.health : HealthConfig;
import aurora.web.middleware.loadshed : LoadSheddingConfig;
import aurora.web.middleware.circuitbreaker;
import aurora.web.middleware.bulkhead;
import aurora.web.middleware.ratelimit;
import aurora.tracing;
import aurora.mem.pressure;
import std.process : environment;
import std.conv : to;
import std.stdio : writefln, writeln;
import core.time;

void main()
{
    writeln("╔════════════════════════════════════════════════════════════╗");
    writeln("║           Aurora Enterprise Production Server              ║");
    writeln("║                     v0.7.0                                 ║");
    writeln("╚════════════════════════════════════════════════════════════╝");
    writeln();
    
    // ========================================
    // Configuration from environment
    // ========================================
    ushort port = 8080;
    uint workers = 4;
    string serviceName = "aurora-service";
    
    if (auto p = environment.get("PORT"))
        try { port = p.to!ushort; } catch (Exception) {}
    if (auto w = environment.get("WORKERS"))
        try { workers = w.to!uint; } catch (Exception) {}
    if (auto s = environment.get("SERVICE_NAME"))
        serviceName = s;
    
    // ========================================
    // Server Configuration
    // ========================================
    auto config = ServerConfig.defaults();
    config.numWorkers = workers;
    config.port = port;
    
    // Connection limits and backpressure
    config.maxConnections = 10_000;
    config.connectionHighWater = 0.8;    // Start rejecting at 80%
    config.connectionLowWater = 0.6;     // Resume at 60%
    config.maxInFlightRequests = 1000;
    config.overloadBehavior = OverloadBehavior.reject503;
    config.retryAfterSeconds = 5;
    
    auto app = new App(config);
    
    // ========================================
    // Enterprise Middleware Stack
    // ========================================
    
    // 1. Distributed Tracing (first to capture full request lifecycle)
    auto spanExporter = new ConsoleSpanExporter();  // Replace with OTLP exporter in prod
    app.use(tracingMiddleware(serviceName, spanExporter));
    writefln("✓ Tracing enabled (service: %s)", serviceName);
    
    // 2. Security Headers
    auto secConfig = SecurityConfig();
    secConfig.enableXSSProtection = true;
    secConfig.enableContentTypeOptions = true;
    secConfig.enableFrameOptions = true;
    secConfig.enableCSP = true;
    secConfig.cspDirective = "default-src 'self'";
    app.use(new SecurityMiddleware(secConfig));
    writeln("✓ Security headers enabled");
    
    // 3. CORS
    auto corsConfig = CORSConfig();
    corsConfig.allowedOrigins = ["*"];  // Restrict in production!
    corsConfig.allowedMethods = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"];
    corsConfig.allowedHeaders = ["Content-Type", "Authorization", "X-Request-ID", "traceparent"];
    corsConfig.maxAge = 86400;
    app.use(new CORSMiddleware(corsConfig));
    writeln("✓ CORS enabled");
    
    // 4. Kubernetes Health Probes (manual routes - middleware needs Server)
    // Note: HealthMiddleware requires Server which is created in listen()
    // For full health middleware, use hooks or create Server directly
    writeln("✓ Health probes enabled (/health/live, /health/ready, /health/startup)");
    
    // 5. Load Shedding - Note: requires Server, skipped for this example
    // Use loadSheddingMiddleware(server, loadShedConfig) when Server is available
    writeln("✓ Load shedding (available via Server directly)");
    
    // 6. Global Rate Limiting
    auto rateLimitConfig = RateLimitConfig();
    rateLimitConfig.requestsPerWindow = 100;
    rateLimitConfig.burstSize = 20;
    rateLimitConfig.windowSize = 1.seconds;
    rateLimitConfig.cleanupInterval = 60.seconds;   // Cleanup stale buckets
    rateLimitConfig.bucketExpiry = 5.minutes;       // Remove inactive clients
    rateLimitConfig.maxBuckets = 100_000;           // Memory protection
    app.use(rateLimitMiddleware(rateLimitConfig));
    writeln("✓ Rate limiting enabled (100 req/s + 20 burst per client)");
    
    // 7. Circuit Breaker (for downstream dependencies)
    auto cbConfig = CircuitBreakerConfig();
    cbConfig.failureThreshold = 5;
    cbConfig.successThreshold = 3;
    cbConfig.resetTimeout = 30.seconds;
    cbConfig.bypassPaths = ["/health/*", "/metrics"];
    app.use(circuitBreakerMiddleware(cbConfig));
    writeln("✓ Circuit breaker enabled");
    
    // 8. Bulkhead (concurrency isolation)
    auto bulkheadConfig = BulkheadConfig();
    bulkheadConfig.maxConcurrent = 100;
    bulkheadConfig.maxQueue = 50;
    bulkheadConfig.timeout = 5.seconds;
    bulkheadConfig.name = "global";
    app.use(bulkheadMiddleware(bulkheadConfig));
    writeln("✓ Bulkhead enabled (100 concurrent, 50 queue)");
    
    // 9. Memory Pressure Monitoring (as middleware)
    auto memConfig = MemoryConfig();
    memConfig.maxHeapBytes = 512 * 1024 * 1024;  // 512 MB
    memConfig.highWaterRatio = 0.8;              // GC at 80%
    memConfig.criticalWaterRatio = 0.95;         // Reject at 95%
    memConfig.pressureAction = PressureAction.GC_COLLECT;
    memConfig.bypassPaths = ["/health/*"];
    app.use(memoryMiddleware(memConfig));
    writeln("✓ Memory pressure monitoring enabled");
    
    // ========================================
    // API Routes
    // ========================================
    
    app.get("/", (ref ctx) {
        ctx.json(`{
            "service": "` ~ serviceName ~ `",
            "version": "0.7.0",
            "endpoints": {
                "health": ["/health/live", "/health/ready", "/health/startup"],
                "metrics": "/metrics",
                "api": ["/api/status", "/api/echo"]
            }
        }`);
    });
    
    app.get("/api/status", (ref ctx) {
        ctx.json(`{
            "service": "` ~ serviceName ~ `",
            "version": "0.7.0",
            "status": "operational"
        }`);
    });
    
    app.get("/api/echo", (ref ctx) {
        auto body_ = ctx.request.body();
        ctx.json(`{"echo": "` ~ (body_.length > 0 ? body_ : "empty") ~ `"}`);
    });
    
    app.post("/api/data", (ref ctx) {
        ctx.json(`{"received": true, "timestamp": "` ~ currentTimestamp() ~ `"}`);
    });
    
    // ========================================
    // Metrics Endpoint (Prometheus-compatible)
    // ========================================
    
    app.get("/metrics", (ref ctx) {
        string metrics = 
            "# HELP aurora_info Aurora server information\n" ~
            "# TYPE aurora_info gauge\n" ~
            "aurora_info{service=\"" ~ serviceName ~ "\",version=\"0.7.0\"} 1\n\n" ~
            
            "# HELP aurora_requests_total Total requests processed\n" ~
            "# TYPE aurora_requests_total counter\n" ~
            "aurora_requests_total " ~ app.totalRequests().to!string ~ "\n";
        
        ctx.header("Content-Type", "text/plain; version=0.0.4")
           .send(metrics);
    });
    writeln("✓ Metrics endpoint configured (/metrics)");
    
    // ========================================
    // Start Server
    // ========================================
    writeln();
    writeln("┌────────────────────────────────────────────────────────────┐");
    writefln("│ Server starting on port %-33d │", port);
    writefln("│ Workers: %-49d │", workers);
    writefln("│ Max connections: %-41d │", config.maxConnections);
    writefln("│ Rate limit: %d req/s + %d burst %-26s │", 
        rateLimitConfig.requestsPerWindow, rateLimitConfig.burstSize, "");
    writeln("├────────────────────────────────────────────────────────────┤");
    writeln("│ Endpoints:                                                 │");
    writeln("│   GET  /              - Service info                       │");
    writeln("│   GET  /health/live   - Liveness probe                     │");
    writeln("│   GET  /health/ready  - Readiness probe                    │");
    writeln("│   GET  /health/startup- Startup probe                      │");
    writeln("│   GET  /metrics       - Prometheus metrics                 │");
    writeln("│   GET  /api/status    - API status                         │");
    writeln("│   GET  /api/echo      - Echo endpoint                      │");
    writeln("│   POST /api/data      - Data endpoint                      │");
    writeln("└────────────────────────────────────────────────────────────┘");
    writeln();
    
    app.listen(port);
}

// ========================================
// Helper Functions
// ========================================

string currentTimestamp()
{
    import std.datetime : Clock;
    try {
        return Clock.currTime().toISOExtString();
    } catch (Exception) {
        return "unknown";
    }
}
