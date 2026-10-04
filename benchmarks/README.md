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
