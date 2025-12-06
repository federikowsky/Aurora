# Aurora Changelog

All notable changes to Aurora HTTP Server Framework.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.8.0] - 2025-12-06 "Security Hardening"

Security header enhancements and production-ready authentication examples.

### Added

#### Security Headers Enhancement (`aurora.web.middleware.security`)
- **Cross-Origin-Opener-Policy (COOP)** - Controls browsing context isolation
  - `enableCOOP` - Enable/disable (disabled by default, can break popups)
  - `coopPolicy` - "unsafe-none", "same-origin-allow-popups", "same-origin"
- **Cross-Origin-Embedder-Policy (COEP)** - Prevents loading cross-origin resources
  - `enableCOEP` - Enable/disable (disabled by default, can break resources)
  - `coepPolicy` - "unsafe-none", "require-corp", "credentialless"
- **Cross-Origin-Resource-Policy (CORP)** - Controls which origins can embed resource
  - `enableCORP` - Enable/disable (disabled by default)
  - `corpPolicy` - "same-site", "same-origin", "cross-origin"
- Combined COOP + COEP enables cross-origin isolation for SharedArrayBuffer

#### Authentication Examples
- **`examples/auth_jwt.d`** - Complete JWT authentication example
  - Uses **jwtlited:phobos** library for production-ready HS256 signing
  - Token expiration and validation
  - Claims extraction and role-based access control
  - Public/protected route patterns
  - Documented with curl test commands
  - Best practices comments throughout
- **`examples/auth_apikey.d`** - Complete API Key authentication example
  - Header-based (X-API-Key) and query parameter authentication
  - Key scopes and permissions
  - Key expiration and disabling
  - Rate limiting considerations
  - Documented with curl test commands

### Tests
- 10 new tests for Cross-Origin headers (COOP, COEP, CORP)
- Total: 38 modules passing

---

## [0.7.0] - 2025-12-05 "Enterprise Features"

Advanced enterprise patterns and production example.

### Added

#### Rate Limiter Bucket Cleanup
- **Automatic bucket cleanup** - Removes inactive rate limit buckets
- `cleanupInterval` - How often to run cleanup (default: 60s)
- `bucketExpiry` - Remove buckets inactive for this duration (default: 300s)
- `maxBuckets` - Maximum tracked clients (default: 100,000)
- `RateLimiterStats` - Track active buckets, cleaned count, max buckets
- `cleanup()` method - Manual cleanup trigger
- `getStats()` method - Get current limiter statistics
- Automatic cleanup on `isAllowed()` calls (periodic)
- 5 new tests for bucket cleanup

#### Production Server Example
- **`examples/production_server.d`** - Enterprise-ready server configuration
  - All v0.7.0 enterprise features demonstrated
  - Distributed tracing with ConsoleSpanExporter
  - Security headers (OWASP recommended)
  - CORS configuration
  - Rate limiting with bucket cleanup
  - Circuit breaker
  - Bulkhead pattern for endpoint groups
  - Memory pressure monitoring
  - Prometheus-compatible /metrics endpoint
  - Environment variable configuration

---

## [Unreleased] - v0.6.0 "Enterprise Hardening"

Enterprise-grade stability features for high-load deployments.

### Added

#### Connection Limits & Backpressure
- **`maxConnections`** - Hard limit on concurrent connections (default: 10,000)
- **Hysteresis mechanism** - High/low water marks (80%/60%) prevent oscillation
- **In-flight request limiting** - `maxInFlightRequests` prevents server overload
- **HTTP 503 with Retry-After** - Graceful rejection when overloaded
- **`OverloadBehavior` enum** - Choose between `reject503`, `closeConnection`, `queueRequest`

#### Backpressure Metrics
- `server.isInOverload()` - Current overload state
- `server.getRejectedOverload()` - Connections rejected due to overload
- `server.getRejectedInFlight()` - Requests rejected due to in-flight limit
- `server.getOverloadTransitions()` - Times server entered overload state
- `server.getConnectionUtilization()` - Current connection ratio (0.0-1.0)
- `server.getConnectionHighWaterMark()` - Absolute high water threshold
- `server.getConnectionLowWaterMark()` - Absolute low water threshold

#### Kubernetes Health Probes (`aurora.web.middleware.health`)
- **`HealthMiddleware`** - Configurable health check middleware
- **Liveness probe** (`/health/live`) - Simple "process alive" check
- **Readiness probe** (`/health/ready`) - Checks startup, overload, custom deps
- **Startup probe** (`/health/startup`) - Track initialization completion
- **Custom readiness checks** - Pluggable database/cache/service checks
- **`HealthConfig`** - Configurable paths, detail level, caching
- **`HealthCheckResult`** - Structured check results with timing
- Integration with `server.isInOverload()` for automatic traffic shedding

#### Load Shedding Middleware (`aurora.web.middleware.loadshed`)
- **`LoadSheddingMiddleware`** - HTTP-level overload protection
- **Hysteresis-based shedding** - Prevents oscillation with high/low water marks
- **Probabilistic shedding** - Gradual degradation proportional to load
- **Bypass paths** - Critical endpoints skip shedding (glob patterns: `/health/*`)
- **`LoadSheddingConfig`** - Utilization thresholds, in-flight limits, bypass paths
- **`LoadSheddingStats`** - Track shed/bypassed/allowed requests
- Integration with `server.getConnectionUtilization()` for load awareness

#### Circuit Breaker Middleware (`aurora.web.middleware.circuitbreaker`)
- **`CircuitBreakerMiddleware`** - Failure isolation to prevent cascading failures
- **Three-state machine** - CLOSED → OPEN → HALF_OPEN → CLOSED recovery cycle
- **Configurable thresholds** - Failure count to open, success count to close
- **Automatic recovery** - Reset timeout triggers HALF_OPEN test state
- **Bypass paths** - Critical endpoints skip circuit breaker (glob patterns)
- **Status code detection** - Configurable failure status codes (default: 5xx)
- **`CircuitBreakerConfig`** - Thresholds, timeouts, bypass paths, retry-after
- **`CircuitBreakerStats`** - Track opens/closes, failures, rejected requests
- **Thread-safe** - Atomic operations for concurrent request handling
- **503 with X-Circuit-State** - Clear signaling when circuit is open

#### Distributed Tracing (`aurora.tracing`)
- **W3C Trace Context** - Full Level 1 compliance for `traceparent` header
- **`TraceContext`** - Parse, generate, and propagate trace context
  - `parse()` - Parse incoming traceparent headers
  - `generate()` - Create new trace context with random IDs
  - `child()` - Create child context (same trace-id, new span-id)
  - `toTraceparent()` - Serialize to W3C format
- **`Span`** - Request span with timing and metadata
  - Timing: `startTime`, `endTime`, `getDuration()`
  - Attributes: string, long, bool, double values
  - Events: timestamped events with attributes
  - Status: UNSET, OK, ERROR with message
  - Kinds: INTERNAL, SERVER, CLIENT, PRODUCER, CONSUMER
- **`SpanExporter` interface** - Pluggable export backends
  - `ConsoleSpanExporter` - Pretty-prints spans (development)
  - `NoopSpanExporter` - Discards spans (testing)
  - `BatchingSpanExporter` - Buffers spans for efficient export
  - `MultiSpanExporter` - Sends to multiple backends
- **`TracingMiddleware`** - Automatic request tracing
  - Extracts/generates trace context from headers
  - Creates server span with HTTP attributes
  - Configurable sampling probability
  - Exclude paths (health, metrics)
- **Helper functions** - `getTraceId()`, `getSpanId()`, `getTraceparent()`
- **Zero dependencies** - Pure D implementation

#### WebSocket Backpressure (`websocket.backpressure`) — Aurora-WebSocket 1.1.0
- **`BackpressureWebSocket`** - Wrapper for flow control on WebSocket connections
- **Send buffer tracking** - `bufferedAmount` property like HTML5 WebSocket API
- **High/low water marks** - Hysteresis-based state machine (FLOWING → PAUSED → CRITICAL)
- **Slow client detection** - Automatic detection with configurable timeout
- **`SlowClientAction`** - DISCONNECT, DROP_MESSAGES, LOG_ONLY, CUSTOM
- **Message priority queues** - CONTROL > HIGH > NORMAL > LOW ordering
- **`SendBuffer`** - Thread-safe buffer with priority queue support
- **Callbacks** - `onDrain`, `onSlowClient`, `onStateChange` events
- **`BackpressureStats`** - Track buffered amount, dropped messages, state transitions

#### Bulkhead Middleware (`aurora.web.middleware.bulkhead`)
- **`BulkheadMiddleware`** - Resource isolation pattern from "Release It!"
- **Per-group concurrency limits** - Isolate /api, /admin, /reports endpoint groups
- **Semaphore-based control** - Max concurrent requests with optional queueing
- **Queue with timeout** - Configurable wait time for queued requests
- **Fail-fast mode** - Set `maxQueue=0` for immediate rejection
- **`BulkheadState`** - NORMAL, FILLING, OVERLOADED state tracking
- **`BulkheadConfig`** - maxConcurrent, maxQueue, timeout, name
- **`BulkheadStats`** - Track active, queued, completed, rejected, timed-out calls
- **Thread-safe** - Atomic counters with condition variable signaling
- **503 with X-Bulkhead-Name** - Clear rejection signaling with bulkhead identifier

#### Memory Management (`aurora.mem.pressure`)
- **`MemoryMonitor`** - Proactive GC heap monitoring and pressure management
- **`MemoryConfig`** - maxHeapBytes, high/critical water ratios, GC interval
- **`MemoryState`** - NORMAL (< 80%), PRESSURE (80-95%), CRITICAL (> 95%)
- **`PressureAction`** - GC_COLLECT, LOG_ONLY, CUSTOM, NONE actions
- **`MemoryMiddleware`** - Rejects requests in CRITICAL state with 503
- **Automatic GC.collect()** - Triggered on high water with rate limiting
- **Pressure callbacks** - Custom handling on state transitions
- **`MemoryStats`** - usedBytes, gcCollections, rejectedRequests, utilization
- **Bypass paths** - Health probes exempt from rejection (glob patterns)
- **Kubernetes integration** - Configure based on container memory limits

### Changed
- `ServerConfig` extended with backpressure configuration fields
- Connection handling now checks backpressure before accepting

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
