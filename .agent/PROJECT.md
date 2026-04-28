# PROJECT

## Project identity
Repo: federikowsky/Aurora
Primary goal: High-performance HTTP/1.1 backend framework for D with an Express-like API and production-oriented middleware.
Primary stack/runtime: D library managed by DUB; runtime uses vibe-core/eventcore for fiber-aware I/O; HTTP parsing uses Wire; JSON integration uses fastjsond; WebSocket support is via aurora-websocket.

## Stable architecture snapshot
- `import aurora;` re-exports the public framework surface from `source/aurora/package.d`.
- `aurora.app.App` is the high-level application API and wraps `Server`, `Router`, and `MiddlewarePipeline`.
- Runtime connection handling lives in `aurora.runtime.server`; Linux/FreeBSD use worker-pool mode, while macOS/Windows use a single listener with fiber concurrency.
- Web framework concerns are separated under `aurora.web.*`: routing, context, middleware, decorators, router mixins, errors, and protocol upgrade support.
- HTTP request/response types live in `aurora.http`; parsing wraps Wire and response building includes preallocated-buffer paths.
- Memory reuse and hot-path allocation control are explicit concerns through `aurora.mem.*` and BufferPool usage in runtime paths.

## Critical boundaries and invariants
- Do not replace vibe-core/eventcore with a custom reactor or scheduler without explicit architectural intent and validation.
- Do not import or depend on vibe-d HTTP/REST server modules; vibe-core is used for fiber/runtime primitives.
- Preserve `import aurora;` as the public package entry point.
- Preserve zero-copy / low-allocation behavior around HTTP parsing, routing, response building, and connection buffers.
- TLS/HTTPS termination is outside Aurora and belongs to a reverse proxy or deployment edge.

## Non-negotiable constraints
- Public API changes require explicit scope and documentation updates.
- Security-sensitive defaults must be conservative and covered by tests or clearly bounded validation.
- Hot-path changes must consider time complexity, memory churn, copies, allocations, fiber scheduling cost, and I/O behavior.
- New dependencies must be justified by correctness, stability, performance, or non-trivial capability.
- Do not claim test, benchmark, or CI success without actual observed output.

## Accepted stable decisions
- Aurora is a DUB-managed D library with `source` as import path.
- Core tests are run through D runtime unittests via `tests/runner.d` and `dub test`.
- Release builds use configured DUB release build flags.
- Middleware is opt-in and includes rate limiting, circuit breaker, bulkhead, load shedding, health, security, CORS, compression, request ID, validation, and tracing surfaces.

## Important area map
- `source/aurora/package.d` -> public aggregate import surface.
- `source/aurora/app.d` -> high-level user API and server lifecycle bridge.
- `source/aurora/runtime/server.d` -> server runtime, connection lifecycle, backpressure, stats, graceful stop.
- `source/aurora/runtime/worker.d` -> multi-worker coordination on supported platforms.
- `source/aurora/http/` -> HTTP request parsing wrapper, response building, URL/form utilities.
- `source/aurora/web/` -> router, context, middleware pipeline, decorators, upgrade path.
- `source/aurora/web/middleware/` -> enterprise and security middleware.
- `source/aurora/schema/` -> validation, JSON serialization/deserialization, schema exceptions.
- `source/aurora/mem/` -> BufferPool, object pool, arena, memory pressure utilities.
- `tests/` -> unit, integration, real-world, stress, Autobahn-related validation surfaces.
- `examples/` -> runnable examples and API usage references.
- `benchmarks/` -> performance comparison and benchmark servers.
- `docs/` -> API reference, technical specification, roadmap.

## Sensitive surfaces
- HTTP parser integration and request completion semantics.
- Response writer and `HTTPResponse.buildInto` buffer sizing/copy behavior.
- Router matching priority, path parameter storage, and sub-router mounting.
- Middleware ordering and mutation of `Context`, headers, body, and status.
- Backpressure, overload rejection, graceful shutdown, and worker aggregation.
- CORS, security headers, request IDs, compression, validation, and health/readiness responses.
- JSON parsing/deserialization error handling via fastjsond.

## Recurring useful commands
- `dub build`
- `dub build --build=release`
- `dub test`
- `dub test --config=unittest-cov`
- `make build`
- `make release`
- `make test`
- `make test-cov`
- `dub run :minimal_server`
- `dub run :production_server`
- `dub run --single benchmarks/server.d --build=release`