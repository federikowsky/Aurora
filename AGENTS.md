# AGENTS.md

This guide applies to the entire repository.

## Project identity

Aurora is a D HTTP/1.1 backend framework distributed as a DUB library package named `aurora`. The public user-facing entry point is `import aurora;` plus the high-level `App` API for route registration, middleware registration, and server startup.

Use repository files as the source of truth when this guide conflicts with code. Keep operational changes bounded and evidence-based.

## Stack and runtime

- Language/runtime: D, built with DUB.
- Package manifest: `dub.json`.
- Target type: library.
- Source import root: `source`.
- Main dependencies in `dub.json`: `vibe-core`, `eventcore`, `mir-algorithm`, `unit-threaded`, `aurora-websocket`, `wire`, and `fastjsond`.
- Runtime I/O/concurrency: `vibe-core`/`eventcore`; Linux and FreeBSD use a multi-worker `SO_REUSEPORT` path, while macOS and Windows use a single-listener fiber-based path.
- HTTP parsing: Wire-backed HTTP/1.1 parsing through `aurora.http`.
- JSON: `fastjsond` integration through `aurora.schema.json`.

Prefer LDC for performance-sensitive validation and release builds when available. Use DMD for quick local compile feedback when that is the available compiler.

## Public contracts to preserve

- `source/aurora/package.d` is the package-level export surface. Do not remove or rename public imports without an explicit compatibility decision.
- `App` in `source/aurora/app.d` is the primary ergonomic API. Preserve fluent route, middleware, hook, exception-handler, and `listen` behavior unless a task explicitly changes the public API.
- `Context` in `source/aurora/web/context.d` is the handler and middleware request scope. Treat connection hijacking and streaming ownership rules as sensitive.
- `Router` in `source/aurora/web/router.d` owns path matching, route composition, path parameters, and route priority.
- `HTTPRequest` and `HTTPResponse` in `source/aurora/http/package.d` are public HTTP protocol types. Preserve zero-copy/raw accessor behavior and response-building semantics unless intentionally changing the contract.
- Middleware remains opt-in unless a task explicitly changes default behavior.

## Architecture map

- `source/aurora/app.d` -> high-level application facade over server, router, middleware, hooks, and exception handlers.
- `source/aurora/runtime/server.d` -> server lifecycle, connection handling, keep-alive loop, request dispatch, response writing, limits, backpressure, and platform runtime selection.
- `source/aurora/runtime/worker.d` -> Linux/FreeBSD multi-worker coordinator using `SO_REUSEPORT`.
- `source/aurora/web/router.d` -> radix-tree routing, route parameters, sub-router composition, and route matching.
- `source/aurora/web/context.d` -> per-request context, middleware storage, response helpers, WebSocket/SSE upgrade and hijack support.
- `source/aurora/web/middleware/` -> middleware chain and built-in middleware modules.
- `source/aurora/http/` -> Wire-backed request parsing, response building, URL handling, and form parsing.
- `source/aurora/schema/` -> schema validation, JSON serialization/deserialization, and schema exceptions.
- `source/aurora/mem/` -> buffer pools, object pools, and arena allocation utilities.
- `source/aurora/tracing/`, `source/aurora/logging.d`, `source/aurora/metrics.d`, `source/aurora/config.d` -> observability and configuration support.
- `examples/` -> runnable usage examples.
- `tests/` -> unit, integration, real-world, and stress test surfaces.
- `benchmarks/` -> performance comparison and benchmark entry points.
- `docs/` -> API reference, architecture/specification material, roadmap, and changelog.

## Hot paths and performance rules

Treat these areas as performance-sensitive:

- `Server.processConnection`, keep-alive handling, overload checks, timeout handling, and response writes.
- `ResponseWriter`, `HTTPResponse.buildInto`, and helpers in `aurora.http.util`.
- `HTTPRequest.parse`, raw query/form/header accessors, and Wire integration.
- `Router.match`, `PathParams`, `ContextStorage`, and middleware pipeline execution.
- Buffer and object pooling under `source/aurora/mem/`.
- Compression, rate limiting, circuit breaker, bulkhead, load shedding, health, security, request-id, validation, and tracing middleware.

Before changing these paths, check allocation behavior, copying, data lifetime, request/connection bounds, and cross-platform behavior. Prefer single-pass parsing, bounded memory growth, and existing optimized primitives over custom rewrites.

## Sensitive surfaces

Be especially careful with:

- HTTP parser completion/error handling and upgrade handling.
- Header/body size limits, read/write/keep-alive timeouts, max requests per connection, and overload/backpressure behavior.
- WebSocket/SSE `hijack()` and `streamResponse()` connection ownership.
- CORS defaults, security headers, request IDs, tracing propagation, health endpoints, and metrics visibility.
- Compression content encoding and response body mutation.
- Schema deserialization type errors and JSON buffer lifetimes.
- Platform-specific runtime behavior: Linux/FreeBSD workers versus macOS/Windows single listener.
- Public package exports and examples referenced from docs.

## Validation commands

Run the strongest relevant subset available for the touched surface.

Basic compile/package checks:

```bash
dub build
dub build --build=release
```

Unit test configurations declared in `dub.json`:

```bash
dub test --config=unittest
dub test --config=unittest-cov
```

Integration/server configurations declared in `dub.json`:

```bash
dub run --config=test-server
dub run --config=fiber-test
```

Example and benchmark commands documented in the README:

```bash
dub run :minimal_server
dub run :production_server
dub run --single benchmarks/server.d --build=release
./benchmarks/comparison/run_comparison.sh
```

If a command is unavailable because DUB, a D compiler, or platform dependencies are missing, report that exact limitation instead of claiming validation.

## CI and workflow status

The repository has a minimal GitHub Actions validation baseline in `.github/workflows/ci.yml`. It runs on pushes to `main`, pull requests targeting `main`, and manual dispatch.

The baseline uses LDC on Ubuntu to:

```bash
dub build --compiler=ldc2
dub build --compiler=ldc2 --build=release
dub test --compiler=ldc2 --config=unittest
```

Treat these checks as the minimum required validation for changes that affect buildable code, DUB configuration, tests, or public exports. Add narrower or stronger checks for touched integration, benchmark, middleware, parser, routing, memory, WebSocket/SSE, or platform-runtime surfaces when relevant.

## Change discipline

- Work on a dedicated branch for repository changes.
- Keep documentation changes narrow and derived from observed files.
- Preserve architecture boundaries unless the task explicitly requires changing them.
- Avoid adding dependencies for marginal convenience.
- Do not open pull requests unless branch protection, automation, or the task requires one.
- Merge only when the task author has authorized integration and the relevant validation is satisfied or precisely bounded.
