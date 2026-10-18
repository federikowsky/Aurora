# Measuring Aurora

These fixtures expose costs; they do not certify production readiness or competitive rank. Read the [engineering state](../docs/ENGINEERING_STATUS.md) before interpreting results. Exact source revision, dependency selections and correctness checks are required.

## Available commands

From the repository root:

```bash
dub build benchmarks/allocation_profile.d --single --compiler=ldc2 --build=release
./benchmarks/aurora_allocation_profile
dub build benchmarks/microbench.d --single --compiler=ldc2 --build=release
./benchmarks/aurora_microbench
dub build benchmarks/server.d --single --compiler=ldc2 --build=release
./benchmarks/aurora_benchmark
```

With that server running locally, `bash benchmarks/run.sh` uses wrk (4 threads, 100 connections, 10 seconds per path) or a different hey fallback. They are different configurations, not interchangeable scores. `wrk --latency -t4 -c100 -d10s http://localhost:8080/` adds the percentiles exposed by wrk; it does not by itself provide a complete p99.9/SLO assessment.

## Known measurement limits

| Fixture | What it measures | What it does not establish |
|---|---|---|
| allocation_profile.d | Selected D-GC bytes/op; 10,000 warm-up, 100,000 measured operations, GC disabled during measurement | Native allocation, total network request cost, ordinary GC pause behavior, error/logging/middleware paths |
| microbench.d | Router, Context, arena and response component timings | Whole-framework efficiency; some loops lack consumed outputs or per-case warm-up, so inspect optimization before trusting tiny timings |
| server.d / run.sh | Plaintext, JSON and a delayed fixture over local HTTP | Default protection overhead (limits disabled); `/delay` uses blocking `Thread.sleep`, not asynchronous I/O |
| comparison/ | Historical competitor fixtures/results | Fair current comparison without frozen equivalent configurations and matching semantics |

Repeated clients against one server are not independent server forks. Restart/warm-up policy, client/server co-location and CPU contention must be recorded. Error responses and timeouts are not useful application throughput. Assertions, payload, route count, worker count and enabled protection/middleware are part of the configuration.

Before claiming a change: freeze command/workload/falsifier; record SHA and patch/dirty state, host/virtualization, OS/CPU/memory, compiler/runtime/build flags, duration/iterations, threads/connections, GC/profiler and raw output; repeat with dispersion; check held-out workloads and correctness. Use CPU/native allocation/RSS/scaling profiles only when their accounting is valid. Label different environments NON-COMPARABLE; retain unfavorable outcomes and failed measurements.

The old README's numbers are retained in [Git history](https://github.com/federikowsky/Aurora/blob/3416660672229179b947e54bf4bfb650309aa38e/benchmarks/README.md). They are not the current baseline. No benchmark exception permits incorrect framing, memory access or disabled security checks in the product.
## Explicit resource controls

The canonical server accepts `--workers=N` and `--in-flight=N`. Defaults remain
auto-detected workers and disabled in-flight admission. Use a worker count matching
the server CPU budget; these are ordinary `ServerConfig` settings, not alternative
benchmark-only dispatch paths. Report them alongside affinity/client resources.
`tests/integration/benchmark_config_probe.py` checks real startup, selected values,
response bytes and process exit; ordinary CI runs it on the release server.

## Admission A/A–A/B experiment (Linux)

`compare_admission.py BASE_BINARY CANDIDATE_BINARY WRK OUTPUT` uses two labels for
the identical baseline executable and one for the candidate, rotating order over
five blocks and three canonical routes. Defaults: disjoint server CPUs 0/1 and
client CPUs 2/3, two workers, two client threads, 100 connections, 2 s warm-up and
5 s measurement; `--limit=1000` exercises enabled admission. Pass explicit CPU
lists when these are unavailable. Both servers must support the resource options.

The script uses Linux affinity and `wait4`, not new framework instrumentation.
Calibrate CPU accounting first. Server CPU/request includes initialization, exact
byte controls, warm-up and shutdown; peak RSS includes all server memory. Neither
is a pure steady-state allocation metric. Errors are retained, not accepted as
useful throughput. Closed-loop latency is not an overload SLO. Compare only the
recorded compatible configurations, retaining A/A dispersion and adverse results.
