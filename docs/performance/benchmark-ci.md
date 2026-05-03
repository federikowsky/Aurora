# Performance Benchmark CI

Aurora keeps performance validation outside the runtime hot path. The CI performance workflow produces artifacts for latency, throughput, NUMA/memory-locality, and zero-copy/copy-budget review.

Workflow triggers are `push` to `main` and `codex/**`, plus manual dispatch when available through the GitHub UI/API. On Ubuntu runners, executable-link validation installs the C++ runtime development packages required by the existing DUB link configuration.

## Latency benchmark

The latency workflow starts `benchmarks/server.d` in release mode and runs:

```bash
scripts/run_latency_benchmark_ci.sh
```

The runner writes artifacts under `artifacts/perf/latency/`:

- `latency.json` with p50, p90, p99, p999, max, mean, throughput, environment, and guard result.
- `latency_metrics.csv` with machine-readable metrics.
- `latency_histogram.csv` with power-of-two microsecond buckets.
- `latency_percentiles.hdr` as a text HDR-style percentile distribution.
- `latency_report.md` for CI summaries and human review.
- `server.log` with benchmark-server output.

`benchmarks/latency/baseline.json` is intentionally conservative because there is no stable historical GitHub-hosted runner baseline yet. Relative p99/p999 ratios are reported, while the enforced gate is an absolute sanity guard intended to catch clear server or benchmark malfunction. After enough stable runs exist, `relative_guard_enabled` can be promoted to a real relative regression gate.

## NUMA / memory-locality suite

Run manually or from CI with:

```bash
python3 benchmarks/numa/numa_locality.py
```

Supported parameters include `--threads`, `--size-mib`, `--stride`, `--passes`, `--cpu-node`, `--local-mem-node`, `--remote-mem-node`, `--cpu`, and `--membind`.

On Linux hosts with at least two NUMA nodes and `numactl`, the suite compares local and remote memory placement. On macOS, Windows, single-node Linux runners, or systems without `numactl`, it writes an explicit skip/report-only artifact and exits successfully. Use `--enforce` only for known NUMA-capable infrastructure.

Artifacts are written under `artifacts/perf/numa/`:

- `numa.json`
- `numa_results.csv`
- `numa_report.md`

## Copy-budget report

Run:

```bash
python3 scripts/check_copy_budget.py
```

Default mode is report-only. It scans known hot-path files for obvious copy/allocation markers and writes JSON, CSV, and Markdown artifacts under `artifacts/perf/copy-budget/`. See `docs/performance/zero-copy-copy-budget.md` for the review contract.
