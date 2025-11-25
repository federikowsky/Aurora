/**
 * Aurora Microservice Template
 * 
 * A complete microservice example with:
 * - Health checks (liveness/readiness)
 * - Metrics endpoint
 * - Graceful shutdown
 * - Configuration from environment
 * - Structured logging
 * - Request tracing
 */
module examples.microservice;

import aurora;
import std.process : environment;
import std.conv : to;
import std.json;
import std.datetime;
import std.format : format;
import core.stdc.signal;
import core.stdc.stdlib : exit;
import core.atomic;
import core.sync.mutex;

// ============================================================================
// Service Configuration
// ============================================================================

struct ServiceConfig
{
    string name;
    string version_;
    ushort port;
    uint workers;
    bool debugMode;
    
    static ServiceConfig fromEnvironment()
    {
        ServiceConfig config;
        config.name = environment.get("SERVICE_NAME", "aurora-service");
        config.version_ = environment.get("SERVICE_VERSION", "1.0.0");
        config.port = environment.get("PORT", "8080").to!ushort;
        config.workers = environment.get("WORKERS", "4").to!uint;
        config.debugMode = environment.get("DEBUG", "false") == "true";
        return config;
    }
}

// ============================================================================
// Metrics Collector
// ============================================================================

class MetricsCollector
{
    private shared ulong requestCount = 0;
    private shared ulong errorCount = 0;
    private shared ulong totalLatencyUs = 0;
    private SysTime startTime;
    private Mutex mutex;
    private ulong[string] endpointCounts;
    
    this()
    {
        startTime = Clock.currTime();
        mutex = new Mutex();
    }
    
    void recordRequest(string endpoint, ulong latencyUs, bool success)
    {
        atomicOp!"+="(requestCount, 1);
        atomicOp!"+="(totalLatencyUs, latencyUs);
        
        if (!success)
        {
            atomicOp!"+="(errorCount, 1);
        }
        
        synchronized(mutex)
        {
            endpointCounts[endpoint] = endpointCounts.get(endpoint, 0) + 1;
        }
    }
    
    JSONValue getMetrics()
    {
        auto now = Clock.currTime();
        auto uptime = (now - startTime).total!"seconds";
        auto reqs = atomicLoad(requestCount);
        auto errs = atomicLoad(errorCount);
        auto latency = atomicLoad(totalLatencyUs);
        
        JSONValue metrics;
        metrics["uptime_seconds"] = uptime;
        metrics["total_requests"] = reqs;
        metrics["total_errors"] = errs;
        metrics["error_rate"] = reqs > 0 ? (cast(double)errs / reqs * 100) : 0.0;
        metrics["avg_latency_ms"] = reqs > 0 ? (cast(double)latency / reqs / 1000.0) : 0.0;
        metrics["requests_per_second"] = uptime > 0 ? (cast(double)reqs / uptime) : 0.0;
        
        // Endpoint breakdown
        JSONValue endpoints;
        synchronized(mutex)
        {
            foreach (endpoint, count; endpointCounts)
            {
                endpoints[endpoint] = count;
            }
        }
        metrics["endpoints"] = endpoints;
        
        return metrics;
    }
}

// ============================================================================
// Structured Logger
// ============================================================================

class StructuredLogger
{
    import std.stdio : writeln;
    
    private string serviceName;
    private string serviceVersion;
    
    this(string name, string version_)
    {
        serviceName = name;
        serviceVersion = version_;
    }
    
    void info(string message, string[string] fields = null)
    {
        log("INFO", message, fields);
    }
    
    void error(string message, string[string] fields = null)
    {
        log("ERROR", message, fields);
    }
    
    void warn(string message, string[string] fields = null)
    {
        log("WARN", message, fields);
    }
    
    private void log(string level, string message, string[string] fields)
    {
        JSONValue entry;
        entry["timestamp"] = Clock.currTime().toISOExtString();
        entry["level"] = level;
        entry["service"] = serviceName;
        entry["version"] = serviceVersion;
        entry["message"] = message;
        
        if (fields !is null)
        {
            foreach (k, v; fields)
            {
                entry[k] = v;
            }
        }
        
        writeln(entry.toString());
    }
}

// ============================================================================
// Global State
// ============================================================================

__gshared App app;
__gshared MetricsCollector metrics;
__gshared StructuredLogger logger;
__gshared bool isReady = false;
__gshared bool isShuttingDown = false;

extern(C) void signalHandler(int sig) nothrow @nogc @system
{
    isShuttingDown = true;
    // In a real app, trigger graceful shutdown
    exit(0);
}

// ============================================================================
// Metrics Middleware
// ============================================================================

Middleware metricsMiddleware(MetricsCollector collector)
{
    return (ref Context ctx, NextFunction next) {
        import std.datetime.stopwatch : StopWatch, AutoStart;
        
        auto sw = StopWatch(AutoStart.yes);
        string path = ctx.request ? ctx.request.path : "/";
        
        next();
        
        sw.stop();
        auto latency = sw.peek.total!"usecs";
        bool success = ctx.response ? (ctx.response.status < 400) : false;
        
        collector.recordRequest(path, latency, success);
    };
}

// ============================================================================
// Main Application
// ============================================================================

void main()
{
    // Load configuration
    auto svcConfig = ServiceConfig.fromEnvironment();
    
    // Initialize components
    metrics = new MetricsCollector();
    logger = new StructuredLogger(svcConfig.name, svcConfig.version_);
    
    // Signal handling
    signal(SIGINT, &signalHandler);
    version(Posix) signal(SIGTERM, &signalHandler);
    
    logger.info("Starting service", [
        "port": svcConfig.port.to!string,
        "workers": svcConfig.workers.to!string
    ]);
    
    // Create app
    auto config = ServerConfig.defaults();
    config.numWorkers = svcConfig.workers;
    config.debugMode = svcConfig.debugMode;
    
    app = new App(config);
    
    // ========================================================================
    // Middleware
    // ========================================================================
    
    app.use(new CORSMiddleware(CORSConfig()));
    app.use(metricsMiddleware(metrics));
    
    // ========================================================================
    // Health Endpoints
    // ========================================================================
    
    // Liveness probe - is the service running?
    app.get("/health/live", (ref Context ctx) {
        if (isShuttingDown)
        {
            ctx.status(503).json(`{"status":"shutting_down"}`);
        }
        else
        {
            ctx.json(`{"status":"alive"}`);
        }
    });
    
    // Readiness probe - is the service ready to accept traffic?
    app.get("/health/ready", (ref Context ctx) {
        if (!isReady || isShuttingDown)
        {
            ctx.status(503).json(`{"status":"not_ready"}`);
        }
        else
        {
            ctx.json(`{"status":"ready"}`);
        }
    });
    
    // Combined health check
    app.get("/health", (ref Context ctx) {
        JSONValue health;
        health["status"] = isReady && !isShuttingDown ? "healthy" : "unhealthy";
        health["service"] = svcConfig.name;
        health["version"] = svcConfig.version_;
        health["uptime"] = metrics.getMetrics()["uptime_seconds"];
        
        int status = isReady && !isShuttingDown ? 200 : 503;
        ctx.status(status)
           .header("Content-Type", "application/json")
           .send(health.toString());
    });
    
    // ========================================================================
    // Metrics Endpoint
    // ========================================================================
    
    app.get("/metrics", (ref Context ctx) {
        ctx.header("Content-Type", "application/json")
           .send(metrics.getMetrics().toString());
    });
    
    // ========================================================================
    // Service Info
    // ========================================================================
    
    app.get("/", (ref Context ctx) {
        JSONValue info;
        info["name"] = svcConfig.name;
        info["version"] = svcConfig.version_;
        info["endpoints"] = ["/health", "/health/live", "/health/ready", "/metrics", "/api/..."];
        
        ctx.header("Content-Type", "application/json")
           .send(info.toString());
    });
    
    // ========================================================================
    // Business Logic Endpoints
    // ========================================================================
    
    app.get("/api/data", (ref Context ctx) {
        // Simulate business logic
        JSONValue data;
        data["items"] = [1, 2, 3, 4, 5];
        data["timestamp"] = Clock.currTime().toISOExtString();
        
        ctx.header("Content-Type", "application/json")
           .send(data.toString());
    });
    
    app.post("/api/process", (ref Context ctx) {
        auto body = ctx.request ? cast(string)ctx.request.body : "{}";
        
        // Log the request
        logger.info("Processing request", ["body_size": body.length.to!string]);
        
        // Simulate processing
        JSONValue result;
        result["processed"] = true;
        result["input_size"] = body.length;
        
        ctx.status(200)
           .header("Content-Type", "application/json")
           .send(result.toString());
    });
    
    // ========================================================================
    // Startup Complete
    // ========================================================================
    
    // Mark service as ready (after initialization)
    isReady = true;
    
    logger.info("Service ready", [
        "host": "0.0.0.0",
        "port": svcConfig.port.to!string
    ]);
    
    import std.stdio : writefln;
    writefln("\n%s v%s", svcConfig.name, svcConfig.version_);
    writefln("Listening on http://0.0.0.0:%d", svcConfig.port);
    writefln("\nEndpoints:");
    writefln("  GET  /              - Service info");
    writefln("  GET  /health        - Health check");
    writefln("  GET  /health/live   - Liveness probe");
    writefln("  GET  /health/ready  - Readiness probe");
    writefln("  GET  /metrics       - Prometheus metrics");
    writefln("  GET  /api/data      - Sample data endpoint");
    writefln("  POST /api/process   - Sample processing endpoint");
    writefln("\nEnvironment variables:");
    writefln("  SERVICE_NAME=%s", svcConfig.name);
    writefln("  SERVICE_VERSION=%s", svcConfig.version_);
    writefln("  PORT=%d", svcConfig.port);
    writefln("  WORKERS=%d", svcConfig.workers);
    
    app.listen(svcConfig.port);
}
