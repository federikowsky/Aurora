# Aurora Candidate Validation

- Candidate ref: codex/perf-ci-hdr-numa-zero-copy
- Candidate SHA: 40b9177357309c0134275f8b091372280aeb9db6
- Overall: fail
- Runner: Linux
- Run ID: 25273643657

| Check | Status | Exit |
| --- | --- | ---: |
| toolchain | pass | 0 |
| dub_build | fail | 2 |
| dub_release | fail | 2 |
| dub_unittest | fail | 2 |
| perf_latency | fail | 1 |
| perf_numa | pass | 0 |
| copy_budget | pass | 0 |
