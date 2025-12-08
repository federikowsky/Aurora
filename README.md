<p align="center">
  <h1 align="center">Aurora</h1>
  <p align="center">
    <strong>High-Performance HTTP/1.1 Framework for D</strong>
  </p>
  <p align="center">
    <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
    <a href="https://dlang.org/"><img src="https://img.shields.io/badge/D-2.100+-red.svg" alt="D"></a>
    <a href="tests/"><img src="https://img.shields.io/badge/tests-38%20modules%20passing-brightgreen" alt="Tests"></a>
    <a href="https://code.dlang.org/packages/aurora"><img src="https://img.shields.io/dub/v/aurora" alt="DUB"></a>
  </p>
</p>

---

Aurora is a **production-ready** HTTP/1.1 framework for D, designed for enterprise workloads. It features zero-copy parsing, memory pools, fiber-based concurrency, and batteries-included middleware for rate limiting, circuit breaking, health probes, and distributed tracing.

## ✨ Highlights

| Feature | Description |
|---------|-------------|
| 🚀 **High Performance** | Zero-copy parsing, memory pools, ~100k+ req/s |
| 🎯 **Express-like API** | Familiar routing and middleware patterns |
| 📦 **Schema Validation** | Pydantic-like request/response validation |
| ⚡ **Enterprise Ready** | Rate limiting, circuit breaker, health probes |
| 🔒 **Security First** | OWASP headers, CORS, request ID tracking |
| 📊 **Observable** | W3C Trace Context, metrics, structured logging |

---

## 📖 Table of Contents

- [Installation](#-installation)
- [Quick Start](#-quick-start)
- [Documentation](#-documentation)
- [Enterprise Middleware](#-enterprise-middleware)
- [Benchmarks](#-benchmarks)
- [Examples](#-examples)
- [Contributing](#-contributing)
- [License](#-license)

---

## 📦 Installation

Add to your `dub.json`:

```json
{
    "dependencies": {
        "aurora": "~>1.0.0"
    }
}
```

Or with `dub.sdl`:

```sdl
dependency "aurora" version="~>1.0.0"
```

**Requirements**:
- D Compiler: DMD 2.100+ or LDC 1.30+
- OS: Linux, macOS, Windows

---

## 🚀 Quick Start

### Hello World

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

### REST API

```d
import aurora;

void main() {
    auto app = new App();
    
    // JSON response
    app.get("/api/users", (ref Context ctx) {
        ctx.json([
            ["id": "1", "name": "Alice"],
            ["id": "2", "name": "Bob"]
        ]);
    });
    
    // Route parameters
    app.get("/api/users/:id", (ref Context ctx) {
        auto id = ctx.params["id"];
        ctx.json(["id": id, "name": "User " ~ id]);
    });
    
    // POST with JSON body
    app.post("/api/users", (ref Context ctx) {
        auto data = ctx.json;
        ctx.status(201).json(["created": "true"]);
    });
    
    app.listen(8080);
}
```

### Production Server

```d
import aurora;
import aurora.web.middleware.ratelimit;
import aurora.web.middleware.circuitbreaker;
import aurora.web.middleware.security;
import aurora.tracing;

void main() {
    auto config = ServerConfig.defaults();
    config.port = 8080;
    config.maxConnections = 10_000;
    
    auto app = new App(config);
    
    // Security headers (OWASP recommended)
    app.use(new SecurityMiddleware(SecurityConfig()));
    
    // Rate limiting (100 req/s per client)
    auto rlConfig = RateLimitConfig();
    rlConfig.requestsPerWindow = 100;
    rlConfig.windowSize = 1.seconds;
    app.use(rateLimitMiddleware(rlConfig));
    
    // Circuit breaker
    auto cbConfig = CircuitBreakerConfig();
    cbConfig.failureThreshold = 5;
    cbConfig.resetTimeout = 30.seconds;
    app.use(circuitBreakerMiddleware(cbConfig));
    
    // Distributed tracing
    app.use(tracingMiddleware("my-service", new ConsoleSpanExporter()));
    
    // Routes
    app.get("/", (ref Context ctx) => ctx.send("OK"));
    
    app.listen(8080);
}
```

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [API Reference](docs/API.md) | Complete API documentation |
| [Technical Specs](docs/specs.md) | Architecture and internals |
| [Roadmap](docs/ROADMAP.md) | Planned future features |
| [Changelog](CHANGELOG.md) | Version history |

---

## 🏗️ Enterprise Middleware

All middleware is **opt-in**. Use only what you need.

| Middleware | Description | Module |
|------------|-------------|--------|
| **Rate Limiting** | Token bucket per-client | `aurora.web.middleware.ratelimit` |
| **Circuit Breaker** | Failure isolation | `aurora.web.middleware.circuitbreaker` |
| **Bulkhead** | Concurrency limits | `aurora.web.middleware.bulkhead` |
| **Load Shedding** | Probabilistic rejection | `aurora.web.middleware.loadshed` |
| **Health Probes** | K8s liveness/readiness | `aurora.web.middleware.health` |
| **Security Headers** | OWASP headers | `aurora.web.middleware.security` |
| **CORS** | Cross-origin requests | `aurora.web.middleware.cors` |
| **Request ID** | Correlation tracking | `aurora.web.middleware.requestid` |
| **Validation** | Schema validation | `aurora.web.middleware.validation` |
| **Tracing** | OpenTelemetry compatible | `aurora.tracing` |

---

## 📊 Benchmarks

### Test Environment

```
Hardware: MacBook Pro M4 (10 cores: 4P+6E, 16GB RAM)
OS: macOS
Tool: wrk -t4 -c100 -d10s
Build: --build=release
```

### Results

| Framework | Plaintext (req/s) | JSON (req/s) | Latency (avg) |
|-----------|-------------------|--------------|---------------|
| **vibe.d** | 123,556 | 126,247 | 1.08ms |
| **Aurora** | 77,743 | 72,402 | 1.35ms |
| **hunt-http** | 47,590 | 52,151 | 2.07ms |

> **Note**: Aurora prioritizes memory safety and enterprise features (rate limiting, circuit breaker, tracing, etc.) over raw throughput. vibe.d is a more minimal HTTP server optimized for pure performance.

### Key Tradeoffs

| Feature | Aurora | vibe.d | hunt-http |
|---------|--------|--------|-----------|
| Enterprise Middleware | ✅ Built-in | ❌ Manual | ❌ Manual |
| Schema Validation | ✅ UDA-based | ❌ Manual | ❌ Manual |
| WebSocket | ✅ Integrated | 🔧 Separate | ✅ Built-in |
| Memory Pools | ✅ Custom | ✅ GC-managed | ✅ GC-managed |
| Zero-copy Parsing | ✅ Wire | ✅ Internal | ❌ Standard |

### Running Benchmarks

```bash
# Start servers in separate terminals
dub run --single benchmarks/server.d --build=release                    # Aurora :8080
dub run --single benchmarks/comparison/vibed_server.d --build=release   # vibe.d :8081
dub run --single benchmarks/comparison/hunt_server.d --build=release    # hunt-http :8082

# Run comparison (in another terminal)
./benchmarks/comparison/run_comparison.sh
```

---

## 📁 Examples

| Example | Description |
|---------|-------------|
| [minimal_server.d](examples/minimal_server.d) | Simplest possible server |
| [rest_api.d](examples/rest_api.d) | RESTful API patterns |
| [production_server.d](examples/production_server.d) | Full enterprise config |

Run examples:

```bash
dub run :minimal_server
dub run :production_server
```

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

