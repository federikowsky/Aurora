# Aurora Changelog

All notable changes to Aurora HTTP Server Framework.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.5.0] - 2025-12-04 "Solid Foundation"

Production hardening release focused on reliability, RFC compliance, and observability.

### Added

#### Middleware
- **Rate Limiting Middleware** (`aurora.web.middleware.ratelimit`)
  - Token bucket algorithm with configurable burst
  - Per-client rate limiting (by IP, custom key)
  - 429 Too Many Requests with Retry-After header
  - Thread-safe implementation
  
- **Request ID Middleware** (`aurora.web.middleware.requestid`)
  - UUID v4 generation for request tracing
  - Preserves existing X-Request-ID headers (configurable)
  - ID validation (rejects invalid/malicious IDs)
  - Custom header name and generator support
  - Context storage for downstream access

#### Metrics
- **P99 Latency Tracking** (`PercentileHistogram`)
  - Reservoir sampling (1000 samples)
  - P50, P90, P95, P99 percentile methods
  - Prometheus export with quantile labels
  - Thread-safe observations
  - Integration with Metrics registry

#### Tests
- **Graceful Shutdown Tests** (`tests/integration/graceful_shutdown_test.d`)
  - Signal handling (SIGTERM, SIGINT)
  - In-flight request completion
  - Timeout behavior
  - State transitions

- **Fiber Crash Isolation Tests** (`tests/integration/fiber_isolation_test.d`)
  - Request isolation verification
  - Crash propagation prevention
  - Fiber pool recovery

- **Connection Limit Tests** (`tests/integration/connection_limits_test.d`)
  - Maximum connection handling
  - Connection stats API
  - Graceful rejection

- **RFC 7230 Compliance Tests** (in `tests/unit/http/http_test.d`)
  - Host header validation (10 test cases)
  - Content-Length validation (10 test cases)
  - HTTP/1.1 requirements enforcement

- **Rate Limit Middleware Tests** (`tests/unit/web/ratelimit_test.d`)
  - 25 test cases covering all scenarios

- **Request ID Middleware Tests** (`tests/unit/web/requestid_test.d`)
  - 25 test cases covering generation, preservation, validation

- **Percentile Histogram Tests** (`tests/unit/metrics/percentile_test.d`)
  - 25 test cases for statistical accuracy

- **Logger Middleware Tests** (`tests/unit/web/logger_test.d`)
  - 20 test cases (re-enabled)

- **Validation Middleware Tests** (`tests/unit/web/validation_test.d`)
  - 20 test cases (re-enabled)

- **OWASP WSTG-INPV-03 Tests** (HTTP Verb Tampering)
  - 10 test cases in `http_test.d`
  - Unknown method rejection
  - Case sensitivity validation
  - Method override header detection
  - Null byte injection prevention

- **OWASP WSTG-INPV-04 Tests** (HTTP Parameter Pollution)
  - 10 test cases in `http_test.d`
  - Duplicate parameter preservation
  - Mixed encoding handling
  - Query/body parameter separation
  - Semicolon separator awareness

### Changed

- Test module count: 27 → 31 modules
- Total test cases: ~400 → 540+
- Coverage media: 81% → 87%

### Fixed

- Validation middleware body parsing null reference bug
- Flaky timing test threshold in middleware_test.d

### Security

- Request ID validation rejects injection attempts
- Rate limiting protects against DoS attacks
- Host header validation per RFC 7230
- **OWASP WSTG-INPV-03**: HTTP Verb Tampering protection (strict method validation)
- **OWASP WSTG-INPV-04**: HTTP Parameter Pollution awareness tests

---

## [0.4.0] - 2025-12-02 "Extensibility"

Extensibility release with hooks, lifecycle management, and improved middleware.

### Added

- **Lifecycle Hooks** (`aurora.runtime.hooks`)
  - `onServerStart`, `onServerStop`
  - `onRequestStart`, `onRequestEnd`
  - `onError` for centralized error handling
  
- **CORS Middleware** (`aurora.web.middleware.cors`)
  - Configurable origins, methods, headers
  - Preflight request handling
  - Credentials support

- **Security Middleware** (`aurora.web.middleware.security`)
  - Security headers (X-Content-Type-Options, etc.)
  - Content-Security-Policy
  - Configurable policies

- **HTTP Smuggling Tests** (OWASP WSTG-INPV-15)
  - 15 test cases for request smuggling prevention

### Changed

- HTTP module coverage: 49% → 89%
- Context coverage: 73% → 100%
- Middleware pipeline performance optimizations

---

## [0.3.0] - 2025-11-28 "Performance"

Performance-focused release with memory optimizations.

### Added

- **Arena Allocator** (`aurora.mem.arena`)
  - Request-scoped allocation
  - Automatic cleanup
  
- **Object Pool** (`aurora.mem.object_pool`)
  - Reusable response builders
  - Reduced GC pressure

- **Buffer Pool** (`aurora.mem.pool`)
  - Pre-allocated buffers
  - Lock-free acquisition

- **Metrics System** (`aurora.metrics`)
  - Counter, Gauge, Histogram
  - Prometheus export format

### Performance

- Throughput: 1800 RPS → 2400+ RPS
- P99 latency: 15ms → 8ms
- Memory per request: 4KB → 1.2KB

---

## [0.2.0] - 2025-11-20 "Web Framework"

Web framework features release.

### Added

- **Router** (`aurora.web.router`)
  - Path parameter extraction (`:id`)
  - Wildcard routes (`*`)
  - Method-based routing

- **Middleware Pipeline** (`aurora.web.middleware`)
  - Chain of responsibility pattern
  - Next function for flow control

- **Context** (`aurora.web.context`)
  - Request/response pointers
  - Storage for middleware data sharing
  - Helper methods (json, send, status)

- **JSON Schema Validation** (`aurora.schema`)
  - fastjsond integration
  - Validation middleware

---

## [0.1.0] - 2025-11-15 "Foundation"

Initial release with core HTTP functionality.

### Added

- **HTTP Parser** (Wire library integration)
  - Zero-copy parsing
  - < 5μs parse time
  
- **HTTP Request/Response**
  - Full HTTP/1.1 support
  - Keep-alive connections

- **Multi-threaded Server**
  - Fiber-based concurrency
  - Worker pool
  - Configurable thread count

- **Logging** (`aurora.logging`)
  - Log levels (DEBUG, INFO, WARN, ERROR)
  - Formatted output

- **Configuration** (`aurora.config`)
  - JSON config files
  - Environment variable override

---

## Version History

| Version | Date | Codename | Focus |
|---------|------|----------|-------|
| 0.5.0 | 2025-12-04 | Solid Foundation | Production hardening |
| 0.4.0 | 2025-12-02 | Extensibility | Hooks, CORS, Security |
| 0.3.0 | 2025-11-28 | Performance | Memory, Metrics |
| 0.2.0 | 2025-11-20 | Web Framework | Router, Middleware |
| 0.1.0 | 2025-11-15 | Foundation | Core HTTP |
