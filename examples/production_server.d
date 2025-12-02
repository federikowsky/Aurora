/**
 * Aurora Production Server
 * 
 * Production-ready server configuration with:
 * - Multiple workers
 * - Security headers
 * - CORS
 * - Health checks
 * - Graceful shutdown
 */
module examples.production_server;

import aurora;
import std.process : environment;
import std.conv : to;

void main()
{
    // Configuration from environment
    ushort port = 8080;
    uint workers = 4;
    
    if (auto p = environment.get("PORT"))
        try { port = p.to!ushort; } catch (Exception) {}
    if (auto w = environment.get("WORKERS"))
        try { workers = w.to!uint; } catch (Exception) {}
    
    auto config = ServerConfig.defaults();
    config.numWorkers = workers;
    config.port = port;
    
    auto app = new App(config);
    
    // Security middleware
    auto secConfig = SecurityConfig();
    secConfig.enableXSSProtection = true;
    secConfig.enableContentTypeOptions = true;
    secConfig.enableFrameOptions = true;
    app.use(new SecurityMiddleware(secConfig));
    
    // CORS middleware
    auto corsConfig = CORSConfig();
    corsConfig.allowedOrigins = ["*"];
    corsConfig.allowedMethods = ["GET", "POST", "PUT", "DELETE", "PATCH"];
    app.use(new CORSMiddleware(corsConfig));
    
    // Health endpoints
    app.get("/health", (ref Context ctx) {
        ctx.header("Content-Type", "application/json")
           .send(`{"status":"healthy"}`);
    });
    
    app.get("/health/live", (ref Context ctx) {
        ctx.send("OK");
    });
    
    app.get("/health/ready", (ref Context ctx) {
        ctx.header("Content-Type", "application/json")
           .send(`{"ready":true}`);
    });
    
    // Metrics endpoint
    app.get("/metrics", (ref Context ctx) {
        auto requests = app.totalRequests();
        ctx.header("Content-Type", "application/json")
           .send(`{"total_requests":` ~ requests.to!string ~ `}`);
    });
    
    // API routes
    app.get("/api/status", (ref Context ctx) {
        ctx.header("Content-Type", "application/json")
           .send(`{"service":"aurora","version":"1.0.0"}`);
    });
    
    import std.stdio : writefln;
    writefln("Production server starting...");
    writefln("  Port: %d", port);
    writefln("  Workers: %d", workers);
    
    app.listen(port);
}
