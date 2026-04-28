# AGENTS

## Repository identity

Aurora is a high-performance HTTP/1.1 backend framework for D. Treat the repository files, DUB configuration, tests, examples, benchmarks, and documentation as the source of truth.

Primary stack/runtime:

- D library managed by DUB.
- Public import path is `source`.
- Runtime I/O uses `vibe-core` and `eventcore` for fiber-aware networking and event loops.
- HTTP parsing is delegated to Wire.
- JSON integration uses fastjsond.
- WebSocket support is provided through aurora-websocket.

## Operating rules

- Do not work directly on `main`; create a dedicated branch for repository changes.
- Preserve public contracts unless the task explicitly requires an API change.
- Prefer small, evidence-based changes at the correct leverage point over broad rewrites.
- Keep dependencies minimal. Add one only when it is justified by correctness, stability, performance, or non-trivial capability.
- Do not claim test, benchmark, CI, or runtime success without observed output.
- For future temporary operator state, do not commit `.agent/` to the final merge diff unless explicitly requested.

## Public contracts and entry points

- `source/aurora/package.d` is the public aggregate import surface for `import aurora;`.
- `aurora.app.App` is the high-level application API and wraps `Server`, `Router`, and `MiddlewarePipeline`.
- User-facing API centers on `App`, `Context`, `Router`, middleware, `HTTPRequest`, and `HTTPResponse`.
- `aurora.http.HTTPRequest` wraps Wire parsing and exposes both convenient string accessors and raw/zero-copy access paths.
- `aurora.http.HTTPResponse` provides response construction, including preallocated-buffer building paths.

## Architecture boundaries

- Runtime/server internals live under `source/aurora/runtime/`.
- Runtime connection handling lives in `aurora.runtime.server`.
- Linux/FreeBSD use worker-pool mode; macOS/Windows use a single listener with fiber concurrency.
- Do not replace vibe-core/eventcore with a custom reactor or scheduler without explicit architectural intent and validation.
- Do not import or depend on vibe-d HTTP/REST server modules; vibe-core is used for fiber/runtime primitives only.
- Web framework concerns live under `source/aurora/web/`: routing, context, middleware, decorators, router mixins, errors, and protocol upgrade support.
- HTTP utilities live under `source/aurora/http/`: request parsing wrapper, response building, URL utilities, and form utilities.
- Schema validation and JSON serialization/deserialization live under `source/aurora/schema/`.
- Memory reuse utilities live under `source/aurora/mem/`.
- TLS/HTTPS termination is intentionally outside Aurora; deploy behind a reverse proxy or edge layer for TLS.

## Hot paths and sensitive surfaces

Treat these areas as high-risk and validate proportionally:

- HTTP parser integration and request completion semantics.
- Request parsing, routing, middleware execution, response building, connection handling, and buffer reuse.
- Response writer and `HTTPResponse.buildInto` buffer sizing/copy behavior.
- Router matching priority, path parameter storage, and sub-router mounting.
- Middleware ordering and mutation of `Context`, headers, body, and status.
- Backpressure, overload rejection, graceful shutdown, and worker-stat aggregation.
- CORS, security headers, request IDs, compression, validation, health/readiness responses, and tracing.
- JSON parsing/deserialization error handling via fastjsond.

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
- `tests/` -> unit, integration, real-world, stress, and Autobahn-related validation surfaces.
- `examples/` -> runnable examples and API usage references.
- `benchmarks/` -> performance comparison and benchmark servers.
- `docs/` -> API reference, technical specification, and roadmap.

## Validation commands

Use the strongest relevant checks available for the touched surface:

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

If DUB, a D compiler, or required system dependencies are unavailable, report validation as not currently runnable instead of inferring success.