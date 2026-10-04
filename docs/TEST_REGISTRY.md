# Validation guide

The executable sources, DUB configurations and workflow at the checkout SHA define what runs. This guide records entry points and blind spots, not a manually maintained coverage percentage or test count. Results and revisions belong in [ENGINEERING_STATUS](ENGINEERING_STATUS.md).

## Ordinary validation

From the repository root with LDC 1.42.0, DUB and native C/C++ toolchain available:

```bash
git rev-parse HEAD
git status --porcelain=v1
dub build --compiler=ldc2
dub build --compiler=ldc2 --build=release
dub test --compiler=ldc2 --config=unittest
dub build tests/integration/protocol_probe_server.d --single --compiler=ldc2 --build=release
python3 tests/integration/http_framing_probe.py ./tests/integration/aurora_protocol_probe_server
```

The Python probe starts/stops its local fixture on port 8080. Ensure that port is free; it exercises fragmented Content-Length, pipelined ordering, fragmented chunked bodies, retirement headers and write timeout. [Source](../tests/integration/http_framing_probe.py) is authoritative for assertions and timeouts.

`DUB_HOME` may select an isolated package cache without changing `HOME`. `--skip-registry=all` is an offline fallback only when all selected dependencies are already available; it is not proof of a clean installation. Preserve and report the selections file and exact dependency revisions.

## What CI covers

[ci.yml](../.github/workflows/ci.yml) runs debug/release builds, the unittest configuration, the documented minimal example build, the HTTP probe, microbenchmark and D-GC profiler, then uploads logs. It triggers on default configured `main` pushes, PRs targeting `main` and manual dispatch. Recheck actual default metadata if the branch changes; the workflow itself is currently hard-coded.

[validate-candidate.yml](../.github/workflows/validate-candidate.yml) accepts a candidate ref and records its checkout SHA. Its optional latency/NUMA/copy-budget hooks refer to files absent from this baseline, so skipped steps are not validations. It is not equivalent to ordinary CI.

Unit selection excludes `tests/stress/*`, `tests/realworld/*` and the standalone protocol server. Some integration-named modules only check API availability/state; others skip network checks when no server runs. “Modules passed” does not mean every scenario was exercised. Coverage is optional via `unittest-cov`; no current percentage is certified.

## Additional suites

- [HTTP unit tests](../tests/unit/http) and [router tests](../tests/unit/web) cover selected malformed inputs, boundaries, precedence and backtracking. They do not establish full RFC compliance, fuzz coverage or concurrent mutation safety.
- [Stress tests](../tests/stress) and [realworld fixtures](../tests/realworld/README.md) are experimental and outside ordinary CI. Inspect their dependencies, server assumptions and resource costs before execution.
- [Benchmarks](../benchmarks/README.md) separate component cost, allocations and network measurements. They are not correctness or readiness substitutes.
- Candidate-only buffer/request lifetime regressions live on the pinned candidate branch in the state register. A default-branch suite cannot claim them until integrated.

For a new behavior fix, add the smallest meaningful executable contract test at the failing boundary, run it red then green, exercise relevant exit/error/reuse paths and link raw results. Test selection must follow risk and information gain, not historical suite size. Never report a timed-out, skipped or assertion-disabled run as a pass.
