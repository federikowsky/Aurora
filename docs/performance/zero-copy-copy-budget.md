# Zero-Copy and Copy-Budget Contract

Aurora is performance-sensitive in the connection, parsing, routing, middleware, and response-writing paths. This contract gives reviewers and CI a shared checklist for keeping hot-path copies, allocations, and lifetime changes explicit.

## Hot-path scope

Treat these paths as copy-budget sensitive unless a narrower profile proves otherwise:

- `source/aurora/runtime/server.d`
- `source/aurora/http/`
- `source/aurora/web/router.d`
- `source/aurora/web/context.d`
- `source/aurora/mem/`
- Middleware that runs for every request, especially compression, tracing, request ID, validation, rate limiting, circuit breaker, bulkhead, load shedding, health, security, and CORS.

## Contract

1. Request parsing should keep zero-copy `StringView` / slice-style access wherever the input lifetime is bounded by the request/connection buffer.
2. Avoid structural copies of large parsed request/response state in the hot path. If ownership must change, prefer a pointer, view, move, or narrow copied value over copying an aggregate containing headers/body views.
3. Response construction should avoid avoidable intermediate buffers. Prefer `buildInto`/writer APIs and explicit buffer ownership.
4. New allocations in hot paths must be justified by correctness, safety, or a measured performance win. Fallback allocations must be outside the normal path or clearly bounded.
5. String concatenation, `.dup`, `.idup`, `array`, `Appender`, and `to!string` in hot paths require review because they often imply allocation or materialization.
6. Any new cache, queue, pool, buffer, histogram, or diagnostic map must have bounded growth and documented ownership.
7. Benchmark/report code must stay outside runtime request handling unless explicitly gated off.

## Review checklist

For each change touching a hot-path file:

- What data is copied, materialized, or newly allocated?
- Is the copy required for lifetime safety, fiber safety, or external API semantics?
- Is the cost bounded per request/connection and independent of untrusted input size?
- Can the same contract be satisfied with a view, borrowed slice, move, pool, or caller-owned buffer?
- Does the change alter the lifetime of parser buffers, request body views, header views, context storage, or response buffers?
- Does the change preserve Linux/FreeBSD multi-worker behavior and macOS/Windows single-listener behavior?
- Is there a targeted test, static report, or benchmark artifact that makes the new budget visible?

## CI guardrail

Run the static report locally or in CI:

```bash
python3 scripts/check_copy_budget.py
```

Default mode is report-only and writes:

- `artifacts/perf/copy-budget/copy_budget.json`
- `artifacts/perf/copy-budget/copy_budget_findings.csv`
- `artifacts/perf/copy-budget/copy_budget_report.md`

After findings are intentionally triaged and allowlisted, a stricter gate can be enabled with:

```bash
python3 scripts/check_copy_budget.py --fail-on-findings
```

The static report is a guardrail, not a proof. It catches obvious copy/allocation markers and keeps review focused, but reviewers must still validate lifetimes, ownership, and runtime placement.
