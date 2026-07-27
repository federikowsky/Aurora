# Aurora Candidate Validation

- Candidate ref: codex/perf-ci-hdr-numa-zero-copy
- Candidate SHA: b2e6149b7e20382f6b49184a30bfe01ffab39239
- Overall: fail
- Runner: Linux
- Run ID: 30256743136

| Check | Status | Exit |
| --- | --- | ---: |
| toolchain | pass | 0 |
| dub_build | pass | 0 |
| dub_release | pass | 0 |
| dub_unittest | fail | 2 |
| perf_latency | fail | 1 |
| perf_numa | pass | 0 |
| copy_budget | pass | 0 |
