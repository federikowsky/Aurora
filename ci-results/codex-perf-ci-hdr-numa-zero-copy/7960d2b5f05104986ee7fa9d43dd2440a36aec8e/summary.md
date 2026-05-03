# Aurora Candidate Validation

- Candidate ref: codex/perf-ci-hdr-numa-zero-copy
- Candidate SHA: 7960d2b5f05104986ee7fa9d43dd2440a36aec8e
- Overall: fail
- Runner: Linux
- Run ID: 25273517022

| Check | Status | Exit |
| --- | --- | ---: |
| toolchain | pass | 0 |
| dub_build | pass | 0 |
| dub_release | pass | 0 |
| dub_unittest | fail | 2 |
| perf_latency | fail | 1 |
| perf_numa | pass | 0 |
| copy_budget | pass | 0 |
