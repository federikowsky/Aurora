# AGENTS

## Repository operating guide

This repository is Aurora: a high-performance HTTP/1.1 framework for D. Treat repository files, DUB configuration, tests, and docs as the source of truth.

## Bootstrap memory

Before changing code or docs, read the operational memory in this order when it exists:

1. `.agent/PROJECT.md`
2. `.agent/CURRENT.md`
3. `.agent/LOG.md`
4. Any artifact explicitly referenced from `.agent/CURRENT.md`

Keep `.agent/` concise and update it only when it improves handoff or recovery. Do not let it replace normal project documentation.

## Core boundaries

- Public package import is `source/aurora/package.d` via `import aurora;`.
- User-facing API centers on `aurora.app.App`, `aurora.web.Context`, `aurora.web.Router`, middleware, `aurora.http.HTTPRequest`, and `aurora.http.HTTPResponse`.
- Runtime/server internals live under `source/aurora/runtime/` and use `vibe-core`/`eventcore` for fiber-aware I/O.
- HTTP parsing is delegated to Wire; preserve zero-copy and completion semantics where exposed.
- The hot path includes request parsing, routing, middleware execution, response building, connection handling, and buffer reuse.
- TLS/HTTPS is intentionally outside Aurora; deploy behind a reverse proxy for TLS termination.

## Change discipline

- Do not work directly on `main`; create a dedicated branch for repo changes.
- Preserve public contracts unless the task explicitly requires an API change.
- Prefer small, evidence-based changes at the correct leverage point over broad rewrites.
- Avoid adding dependencies unless the benefit is clear for correctness, stability, performance, or capability.
- Keep security defaults conservative; middleware such as CORS, compression, health, request ID, and security headers are sensitive public surfaces.

## Validation

Use the strongest relevant checks available for the touched surface:

- `dub build`
- `dub build --build=release`
- `dub test`
- `dub test --config=unittest-cov`
- Targeted example or benchmark commands only when relevant, such as `dub run --single benchmarks/server.d --build=release`.

If a D compiler or DUB is unavailable in the execution environment, report validation as not currently runnable instead of inferring success.