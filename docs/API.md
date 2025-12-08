# Aurora API Reference

> **Version 1.0.0** | Enterprise HTTP Framework for D

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Core API](#core-api)
   - [App](#app)
   - [Context](#context)
   - [ServerConfig](#serverconfig)
3. [HTTP Types](#http-types)
   - [HTTPRequest](#httprequest)
   - [HTTPResponse](#httpresponse)
4. [Schema Validation](#schema-validation)
   - [UDA Validators](#uda-validators)
   - [Usage Examples](#schema-usage)
5. [Memory Management](#memory-management)
   - [BufferPool](#bufferpool)
   - [ObjectPool](#objectpool)
   - [Arena](#arena)
6. [Enterprise Middleware](#enterprise-middleware)
   - [Rate Limiting](#rate-limiting)
   - [Circuit Breaker](#circuit-breaker)
   - [Bulkhead](#bulkhead)
   - [Load Shedding](#load-shedding)
   - [Health Probes](#health-probes)
   - [Memory Pressure](#memory-pressure)
7. [Security Middleware](#security-middleware)
   - [Security Headers](#security-headers)
   - [CORS](#cors)
   - [Request ID](#request-id)
8. [Observability](#observability)
   - [Tracing (OpenTelemetry)](#tracing)
   - [Logging](#logging)
9. [WebSocket](#websocket)
10. [Examples](#examples)

---

## Quick Start

```d
import aurora;

void main() {
    auto app = new App();
    
    app.get("/", (ref Context ctx) {
        ctx.send("Hello, Aurora!");
    });
    
    app.listen(8080);
}
```

---

## Core API

### App

Main application class. Entry point for all Aurora applications.

```d
import aurora;

auto app = new App();                    // Default config
auto app = new App(ServerConfig.init);   // Custom config
```

**Methods:**

| Method | Description |
|--------|-------------|
| `get(path, handler)` | Register GET route |
| `post(path, handler)` | Register POST route |
| `put(path, handler)` | Register PUT route |
| `delete_(path, handler)` | Register DELETE route |
| `patch(path, handler)` | Register PATCH route |
| `use(middleware)` | Add global middleware |
| `group(prefix, fn)` | Create route group with prefix |
| `listen(port)` | Start server on port |
| `listen(port, callback)` | Start server with ready callback |

### Context

Request/response context passed to handlers.

```d
app.get("/users/:id", (ref Context ctx) {
    // Request data
    auto id = ctx.params["id"];           // Route parameters
    auto page = ctx.query.get("page", "1"); // Query string
    auto body = ctx.body;                  // Request body (string)
    auto json = ctx.json;                  // Parsed JSON body
    
    // Response
    ctx.send("Hello");                     // Send text
    ctx.json(["name": "Aurora"]);          // Send JSON
    ctx.status(201).send("Created");       // Set status
    ctx.setHeader("X-Custom", "value");    // Set header
});
```

### ServerConfig

Server configuration with production defaults.

```d
auto config = ServerConfig.defaults();

// Network
config.host = "0.0.0.0";
config.port = 8080;
config.numWorkers = 4;                     // 0 = auto-detect CPU cores

// Security Limits
config.maxHeaderSize = 64 * 1024;          // 64KB max header
config.maxBodySize = 10 * 1024 * 1024;     // 10MB max body
config.readTimeout = 30.seconds;           // Slowloris protection
config.writeTimeout = 30.seconds;
config.keepAliveTimeout = 120.seconds;
config.maxRequestsPerConnection = 1000;

// Connection Limits (Enterprise)
config.maxConnections = 10_000;
config.connectionHighWater = 0.8;          // Reject at 80%
config.connectionLowWater = 0.6;           // Resume at 60%
config.maxInFlightRequests = 1000;
config.overloadBehavior = OverloadBehavior.reject503;
config.retryAfterSeconds = 5;
```

---

## Enterprise Middleware

### Rate Limiting

Token bucket rate limiting with per-client tracking.

```d
import aurora.web.middleware.ratelimit;

auto config = RateLimitConfig();
config.requestsPerWindow = 100;            // 100 requests
config.windowSize = 1.seconds;             // per second
config.burstSize = 20;                     // Allow bursts of 20
config.cleanupInterval = 60.seconds;       // GC stale buckets
config.bucketExpiry = 5.minutes;           // Remove inactive clients
config.maxBuckets = 100_000;               // Memory protection

app.use(rateLimitMiddleware(config));
```

---

## HTTP Types

### HTTPRequest

Parsed HTTP request (wraps Wire parser).

```d
import aurora.http;

// In handler, request is parsed automatically
app.get("/api", (ref Context ctx) {
    auto method = ctx.request.method();     // "GET", "POST", etc.
    auto path = ctx.request.path();         // "/api"
    auto query = ctx.request.query();       // Query string
    auto header = ctx.request["Content-Type"]; // Get header
    auto body = ctx.request.body();         // Request body
    
    if (ctx.request.shouldKeepAlive()) {
        // Connection will be reused
    }
});
```

**Methods:**

| Method | Return | Description |
|--------|--------|-------------|
| `method()` | `string` | HTTP method (GET, POST, etc.) |
| `path()` | `string` | Request path without query string |
| `query()` | `string` | Query string (without `?`) |
| `body()` | `string` | Request body |
| `opIndex(name)` | `string` | Get header by name |
| `hasHeader(name)` | `bool` | Check if header exists |
| `shouldKeepAlive()` | `bool` | Keep-alive requested |
| `isComplete()` | `bool` | Fully parsed |
| `hasError()` | `bool` | Parse error occurred |

### HTTPResponse

HTTP response builder.

```d
import aurora.http;

auto response = HTTPResponse(200, "OK");
response.setHeader("Content-Type", "application/json");
response.setBody(`{"status": "ok"}`);

// Build into buffer (zero-allocation)
ubyte[] buffer = new ubyte[response.estimateSize()];
size_t written = response.buildInto(buffer);
```

**Methods:**

| Method | Description |
|--------|-------------|
| `setHeader(name, value)` | Set response header |
| `setBody(content)` | Set response body |
| `estimateSize()` | Estimate buffer size needed |
| `buildInto(buffer)` | Build response into buffer (zero-alloc) |

---

## Schema Validation

Pydantic-like validation using D's UDA system.

### UDA Validators

| UDA | Description | Example |
|-----|-------------|---------|
| `@Required` | Field cannot be null/empty | `@Required string name;` |
| `@Range(min, max)` | Numeric value in range | `@Range(1, 100) int age;` |
| `@Min(value)` | Minimum value | `@Min(0) int count;` |
| `@Max(value)` | Maximum value | `@Max(1000) int limit;` |
| `@Email` | Valid email format | `@Email string email;` |
| `@Length(min, max)` | String length range | `@Length(1, 50) string name;` |

### Schema Usage

```d
import aurora.schema.validation;

struct CreateUserRequest {
    @Required 
    string name;
    
    @Required @Email 
    string email;
    
    @Range(18, 120) 
    int age;
    
    @Length(8, 100) 
    string password;
}

app.post("/users", (ref Context ctx) {
    CreateUserRequest req;
    // ... parse from ctx.body ...
    
    try {
        validate(req);  // Throws ValidationException on failure
        // Process valid request
    } catch (ValidationException e) {
        ctx.status(400).json([
            "error": e.message,
            "field": e.field
        ]);
    }
});
```

---

## Memory Management

Low-level memory management for high-performance scenarios.

### BufferPool

Zero-allocation buffer management.

```d
import aurora.mem.pool;

auto pool = new BufferPool();

// Acquire buffer
auto buffer = pool.acquire(BufferSize.MEDIUM);  // 16KB
// ... use buffer ...
pool.release(buffer);

// Or by exact size
auto buf = pool.acquire(4096);
pool.release(buf);

// Metrics
writeln("Hit ratio: ", pool.hitRatio());
```

**Buffer Sizes:**

| Size | Bytes | Use Case |
|------|-------|----------|
| `TINY` | 1 KB | Small headers |
| `SMALL` | 4 KB | Typical requests |
| `MEDIUM` | 16 KB | Medium bodies |
| `LARGE` | 64 KB | File uploads |
| `HUGE` | 256 KB | Streaming |

### ObjectPool

Generic object pool for reusing allocations.

```d
import aurora.mem.object_pool;

auto pool = new ObjectPool!MyConnection(
    () => new MyConnection(),  // Factory
    100                        // Max pooled
);

auto conn = pool.acquire();
scope(exit) pool.release(conn);
// ... use conn ...
```

### Arena

Arena allocator for temporary allocations.

```d
import aurora.mem.arena;

auto arena = new Arena(64 * 1024);  // 64KB arena

// Allocate (fast, no individual free)
auto data = arena.allocate(1024);
auto more = arena.allocate(512);

// Reset all at once
arena.reset();
```

---

## WebSocket

WebSocket integration via Aurora-WebSocket library.

```d
import aurora;
import aurora.web.websocket;

app.get("/ws", (ref Context ctx) {
    auto ws = upgradeWebSocket(ctx);
    if (ws is null) {
        ctx.status(400).send("WebSocket upgrade failed");
        return;
    }
    scope(exit) ws.close();

    // Echo loop
    while (ws.connected) {
        auto msg = ws.receive();
        if (msg.isNull) break;
        ws.send(msg.get.text);
    }
});
```

**WebSocket Methods:**

| Method | Description |
|--------|-------------|
| `receive()` | Receive next message |
| `send(text)` | Send text message |
| `sendBinary(data)` | Send binary data |
| `ping()` | Send ping frame |
| `close(code, reason)` | Close connection |

See [specs.md](specs.md#21-websocket-integration) for full WebSocket API.

---

## Enterprise Middleware (continued)

**Headers returned:**
- `X-RateLimit-Limit`: Max requests per window
- `X-RateLimit-Remaining`: Remaining requests
- `X-RateLimit-Reset`: Window reset timestamp
- `Retry-After`: Seconds until retry (when limited)

### Circuit Breaker

Prevents cascading failures with three-state circuit.

```d
import aurora.web.middleware.circuitbreaker;

auto config = CircuitBreakerConfig();
config.failureThreshold = 5;               // Open after 5 failures
config.successThreshold = 3;               // Close after 3 successes
config.resetTimeout = 30.seconds;          // Half-open after 30s
config.bypassPaths = ["/health/*"];        // Always allow health checks

app.use(circuitBreakerMiddleware(config));
```

**States:**
- `CLOSED`: Normal operation
- `OPEN`: Rejecting requests (503)
- `HALF_OPEN`: Testing recovery

### Bulkhead

Isolates failures between endpoint groups.

```d
import aurora.web.middleware.bulkhead;

auto config = BulkheadConfig();
config.maxConcurrent = 100;                // Max concurrent requests
config.maxQueue = 50;                      // Max queued requests
config.timeout = 5.seconds;                // Queue timeout
config.name = "api";                       // Bulkhead identifier

// Per-group isolation
app.group("/api", (r) {
    r.use(bulkheadMiddleware(config));
});

app.group("/admin", (r) {
    auto adminConfig = BulkheadConfig();
    adminConfig.maxConcurrent = 10;
    r.use(bulkheadMiddleware(adminConfig));
});
```

### Load Shedding

Probabilistic request rejection under load.

```d
import aurora.web.middleware.loadshed;

auto config = LoadSheddingConfig();
config.shedProbability = 0.1;              // Shed 10% when overloaded
config.criticalPaths = ["/health/*"];      // Never shed these
config.priorityHeader = "X-Priority";      // Priority header name
config.priorityBypass = ["critical"];      // Bypass values

app.use(loadSheddingMiddleware(server, config));
```

### Health Probes

Kubernetes-ready health endpoints.

```d
import aurora.web.middleware.health;

auto config = HealthConfig();
config.livenessPath = "/health/live";
config.readinessPath = "/health/ready";
config.startupPath = "/health/startup";
config.includeDetails = false;             // Security: hide in prod

app.use(healthMiddleware(server, config));

// Mark startup complete after initialization
server.markStartupComplete();
```

**Endpoints:**
- `GET /health/live` - Process alive (always 200)
- `GET /health/ready` - Ready to serve (checks overload)
- `GET /health/startup` - Startup complete

### Memory Pressure

GC pressure monitoring and automatic response.

```d
import aurora.mem.pressure;

auto config = MemoryConfig();
config.maxHeapBytes = 512 * 1024 * 1024;   // 512 MB
config.highWaterRatio = 0.8;               // GC at 80%
config.criticalWaterRatio = 0.95;          // Reject at 95%
config.pressureAction = PressureAction.GC_COLLECT;

app.use(memoryPressureMiddleware(config));
```

---

## Security Middleware

### Security Headers

OWASP recommended security headers.

```d
import aurora.web.middleware.security;

auto config = SecurityConfig();

// Basic headers (enabled by default)
config.enableContentTypeOptions = true;    // X-Content-Type-Options: nosniff
config.enableFrameOptions = true;          // X-Frame-Options: DENY
config.enableXSSProtection = true;         // X-XSS-Protection: 1; mode=block
config.referrerPolicy = "no-referrer";

// HTTPS headers
config.enableHSTS = true;                  // Strict-Transport-Security
config.hstsMaxAge = 31536000;              // 1 year
config.hstsIncludeSubDomains = true;

// Content Security Policy
config.enableCSP = true;
config.cspDirective = "default-src 'self'";

// Cross-Origin headers (v0.8.0+)
config.enableCOOP = true;                  // Cross-Origin-Opener-Policy
config.coopPolicy = "same-origin";
config.enableCOEP = true;                  // Cross-Origin-Embedder-Policy
config.coepPolicy = "require-corp";
config.enableCORP = true;                  // Cross-Origin-Resource-Policy
config.corpPolicy = "same-origin";

app.use(new SecurityMiddleware(config));
```

### CORS

Cross-Origin Resource Sharing.

```d
import aurora.web.middleware.cors;

auto config = CORSConfig();
config.allowedOrigins = ["https://example.com"];  // Or ["*"] for all
config.allowedMethods = ["GET", "POST", "PUT", "DELETE"];
config.allowedHeaders = ["Content-Type", "Authorization"];
config.exposedHeaders = ["X-Request-ID"];
config.allowCredentials = true;
config.maxAge = 86400;                     // Preflight cache 24h

app.use(new CORSMiddleware(config));
```

### Request ID

Request correlation for distributed tracing.

```d
import aurora.web.middleware.requestid;

auto config = RequestIdConfig();
config.headerName = "X-Request-ID";        // Header name
config.generateIfMissing = true;           // Auto-generate UUID

app.use(requestIdMiddleware(config));

// Access in handlers
app.get("/", (ref Context ctx) {
    auto requestId = getRequestId(ctx);
    log.info("Request: ", requestId);
});
```

---

## Observability

### Tracing

OpenTelemetry-compatible distributed tracing with W3C Trace Context.

```d
import aurora.tracing;

// Console exporter (development)
auto exporter = new ConsoleSpanExporter();

// Or implement SpanExporter for OTLP, Jaeger, etc.
app.use(tracingMiddleware("my-service", exporter));
```

**Trace Context propagation:**
- Parses incoming `traceparent` header
- Generates trace ID if missing
- Propagates to downstream services

### Logging

Structured logging with context.

```d
import aurora.logging;

auto logger = getLogger("my-module");

logger.info("Request processed", [
    "requestId": requestId,
    "duration": duration.toString
]);
```

---

## Examples

### Production Server

See `examples/production_server.d` for a complete enterprise configuration.

### Authentication

- `examples/auth_jwt.d` - JWT authentication with jwtlited
- `examples/auth_apikey.d` - API Key authentication with scopes

### Microservice

See `examples/microservice.d` for service mesh patterns.

---

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| 1.0.0 | Dec 2025 | Production release, API freeze |
| 0.8.0 | Dec 2025 | Cross-Origin headers, auth examples |
| 0.7.0 | Dec 2025 | Bulkhead, memory pressure |
| 0.6.0 | Dec 2025 | Enterprise hardening |
| 0.5.0 | Nov 2025 | Initial public release |

---

*Aurora HTTP Framework - Built for Production*
