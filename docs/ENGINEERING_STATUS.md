# Engineering state and North Star scorecard

**Current assessment: 18 October 2026. Production readiness: HOLD.** This is the sole current scorecard and decision register, not a task sequence. [NORTH_STAR](NORTH_STAR.md) and [AGENTS](../AGENTS.md) govern direction/work; [specs](specs.md), [API](API.md) and [TEST_REGISTRY](TEST_REGISTRY.md) describe the default. Candidate documentation describes its candidate, not distributed behavior. Code, selected dependencies and pinned executions establish implementation.

## Revisions and reporting boundary

GitHub metadata was reacquired on 18 October; all four actual default branches are `main`.

| Repository | Default / selected source | Integration boundary |
|---|---|---|
| Aurora | Initial default `87f9ee3f931329f49ff8f2e560613697f540d327`; tooling integrated at `099a466ef222d70b39ee155122cd93df5d41d91d` | [PR #6](https://github.com/federikowsky/Aurora/pull/6) adds canonical benchmark worker/limit controls, no runtime repair. Admission [PR #7](https://github.com/federikowsky/Aurora/pull/7) at `e811528aec5a54e4304729b41180934ec2736201` is **not integrated** |
| Wire | `82b6a5dfd606ebe2ac15c83d9430abdb58aec09b` | Same SHA selected by Aurora; no change. Old lease candidate `ced07d5c2c07b1c459b62e4e28e1612df2095ae2` is separate, not a merge instruction |
| FastjsonD | `23a51d692103a0b77cba153afa2994df0c14f4d3` | Same SHA selected; no change |
| Aurora-WebSocket | `edfbbc6d4e1a7f713a96faa13bebfbb44a51c9d2` | Aurora selects package `1.0.1`, not automatically this HEAD |

**Complete reporting interval: 2026-10-11T05:28:38Z → 2026-10-18T04:59:13Z**, default SHA `d5d9be42c1d802b8aa9b26cda9f46dbec646e5cd` → `87f9ee3f931329f49ff8f2e560613697f540d327`. Four default commits after the previous cutoff cover state, the logger repair `72b9717`, its merge `b1a18fa` and state `87f9ee3`. Those were prior-cycle outputs, now included in interval coverage. No later pre-cutoff default commit, newly changed PR/issue or release was found. Publications/checks on 18 October after cutoff are this cycle's output, to include in the next interval. Complete reporting means the declared scope, not certification of all platforms/failure modes.

Logger normal teardown is already integrated; this cycle does not rediscover it as an open normal-exit defect. [PR #4](https://github.com/federikowsky/Aurora/pull/4) was closed without merge as superseded by #7, preserving its branch/history. PR #7 includes the logger repair; old `6005d02` did not. No release, production operation, first-party dependency update or public API expansion was made. Exact other versions remain in `dub.selections.json`.

## Evidence ledger

MEASURED = execution/artifact; OBSERVED = inspected source/log; INFERRED = reasoned consequence; UNVERIFIED = insufficient evidence. Historical results are not fresh checks.

| Evidence | Pinned scope | Result |
|---|---|---|
| [Initial default CI](https://github.com/federikowsky/Aurora/actions/runs/38116032599), [artifact 11693079041](https://github.com/federikowsky/Aurora/actions/runs/38116032599/artifacts/11693079041) | `87f9ee3`; downloaded/inspected | **MEASURED, historical:** build, 47 modules, logger 400, capacity, protocol 5/5, profiles. SHA-256 `4d62e4ec7a4f2055d57a7c189f21a01a378f6c0441dfe15ac8e545c380d8dd0c` |
| Canonical benchmark configuration red/green | Initial server ignores flags; tooling source `98b66b158c95a525586d7e26c91b020c76645984` | **MEASURED:** requested worker=1/limit=17, exact plaintext and exit 0 verified after correction; 47 modules pass. Defaults preserved by source inspection |
| [Tooling CI](https://github.com/federikowsky/Aurora/actions/runs/39099384199) and [integrated CI](https://github.com/federikowsky/Aurora/actions/runs/39099592211) | Source `98b66b1`, integrated `099a466`, same tree `8e8c7772d1ca1022ff0ad0dbcd7a58d75db24afa` | **MEASURED:** both successful |
| Admission red/green | Baseline runtime `87f9ee3`; candidate runtime published in `2075b4badfa255814ce14542561c0b8f5c24eae3`, CI-only child `e811528` | **MEASURED:** baseline held limit=1 incorrectly returns 200 to contender; candidate passes 12 socket scenarios in each debug/release |
| [Candidate CI](https://github.com/federikowsky/Aurora/actions/runs/39100030202), [functional artifact 12125758012](https://github.com/federikowsky/Aurora/actions/runs/39100030202/artifacts/12125758012) | Merge `4923588d1b4c4832c961f6c503c50ea51f160cac` and candidate `e811528` share tree `5eb42d2a4b0b08242a6c40bceb5858d0abb6043c` | **MEASURED:** builds, 47 modules, logger 400, release capacity, minimal example, protocol 5/5, admission 12+12, measurement parser 3, profiles pass. Download digest `529d4ef9773900b22de8b6eac4ac1867076a5e386bd95daecb714a5e0dcf0bfa` |
| [Hosted cost artifact 12126466749](https://github.com/federikowsky/Aurora/actions/runs/39100030202/artifacts/12126466749) | Exact baseline `099a466` vs candidate `e811528` | **MEASURED:** 45 server processes, rotating identical A1/A2 vs B, calibrated wait4. Digest `b3fbaafdd365a3647de3d4a1d4dc62992d54dfca660fb50c38ae0e8bb808589a` |
| Fresh local gates and costs | Same frozen runtime sources; local development builds preceded publication, hashes/raw patch retained | **MEASURED:** builds, 47 modules exit 0, logger 400, admission 12+12, capacity, protocol 5/5, 3 allocation + 3 microbenchmark processes; 45 two-worker + 27 one-worker HTTP processes |
| CPU counter validation | Each comparison run; busy child process_time vs Linux wait4 | **MEASURED:** counters agree within 0.1 s; initial 1.2 s child gives 1.2267 s process CPU vs 1.2300 s wait4 CPU. Prior /proc ticks remain discarded, not reused |

[Dated raw archive](https://chatgpt.com/api/library/files/libfile_a8933294ff688191bc14257f3a36c251/download) (owner-authenticated), SHA-256 `0cb9997c905519732c63a6b8b987546263dfbf857651688c56325ff60663c5fb`, preserves commands, source patches, red/green failures, environment, all local/hosted rows, summaries, diagnostic launcher and downloaded CI artifacts. Public GitHub artifacts above remain the independently accessible primary evidence.

The first hosted cost attempt at `2075b4b` failed before measurements because cgroup quota files were absent. CI-only `e811528` records unavailable quotas as UNVERIFIED instead of inventing them; no runtime/harness change. Review also found that errored wrk completions could be mislabeled useful throughput. A red/green 3-test parser check now excludes any warm-up/measurement socket/status errors, retains raw output and fails collection. All 117 primary HTTP server processes were eligible with no reported socket/status errors; separate exact-byte controls pass. Sampling body content is not proof that every measured response body was verified.

## Decision: admission correctness proven, integration acceptance not cleared

**OBSERVED:** the default reservation guard exits the admission `if` before dispatch. The candidate keeps it in the request iteration through dispatch/write/error exits, rolling back rejected work before 503. The counter is Server-wide, not per-worker. Existing D scope guards and `core.atomic` suffice: 11 added/2 removed runtime lines, no semaphore, scheduler, cleanup registry, dependency or new public API.

Tests cover workers 1/2, limits 0/1/2, held handlers, burst 16 with limit 2, exception 500/reuse, idle keep-alive, pipelining and write-timeout cleanup. Multi-worker socket placement is not forced. These do not certify cancellation/hijack/fairness or every overload policy. Candidate API/specs/changelog explain the corrected Server-wide semantics.

Before results, acceptance required correctness, no candidate errors, paired median CPU/request within 5%, and throughput/tail effects no worse than identical-binary A/A variability. **That gate did not pass.** Local two-worker echo and hosted plaintext/echo exceed the CPU criterion. Wide intervals and contradictory one-worker results prevent both causal regression attribution and an equivalence claim. Hosted plaintext peak RSS also shows an adverse signal. Do not silently relax the threshold because CI is green. Default B4 remains open; no permission is pending.

Alternatives considered: per-exit cleanup duplication (more missed-exit risk), new semaphore/scheduler (unnecessary mechanism), removing the protection (breaks capability), accepting the patch as cost-free from noisy timing (unsupported). Canonical server options reuse `std.getopt`; wait4, affinity and pinned wrk replace invalid accounting without adding runtime instrumentation.

## Controlled cost evidence

Local: Linux 6.18.55/KVM x86-64, Intel Xeon Platinum 8573C, 9 visible CPUs, quota 8 cores, 8 GiB memory limit/9.8 GiB visible RAM, no swap. Hosted: Ubuntu 24.04/Linux 6.17.0-1022-azure, Microsoft VM, AMD EPYC 7763, 4 logical CPUs (2 cores with SMT), 15 GiB RAM/3 GiB swap; cgroup quotas unavailable. Both LDC 1.42.0, DMD 2.112.1, LLVM 21.1.8, DUB 1.41.0, release `-O2 -release -enable-inlining`; selected packages unchanged. Local cache is populated: no empty-cache-install claim.

Canonical servers: workers 2 on CPUs 0,1; wrk threads 2 on CPUs 2,3, connections 100, separate processes, 2 s warm-up + 5 s measurement, five blocks per environment, rotating A1/B/A2 order. A1/A2 run the exact same executable. The one-worker diagnostic uses CPU 0, three blocks, other settings unchanged. CPU affinity is not physical isolation; hosted CPU 0,1 may share an SMT core. Local/hosted/one-worker timing is **NON-COMPARABLE** across configurations; compare variants only within each matrix. Across weeks, CPU/kernel/worker counts/wrk link configuration also differ.

Routes: plaintext Hello World, JSON object, 1 KiB POST echo; extra plaintext/JSON and 64 KiB binary-echo response controls. Native `wait4` CPU includes server startup/control/warm-up/shutdown and all warm+measured requests, not pure steady-state CPU/request. Peak RSS is process high-water KiB, not bytes/connection or native allocation. Latency is closed-loop wrk; raw p50/p95/p99/p99.9 and all rows retained. No controlled-arrival SLO, cycles/instructions, native allocation or power metric.

wrk source `a211dd5a7050b1f9e8a9870b95513060e72ac4a0`, built with supported `WITH_OPENSSL=/usr` (libssl/libcrypto 3); bundled OpenSSL build failed locally with assembler CFI errors, raw logs retained. No load-generator source change or TLS workload.

| Matrix / route | Paired median CPU B/sqrt(A1*A2) | Approximate 95% interval of paired geometric mean | Paired median throughput ratio |
|---|---:|---:|---:|
| Local 2 workers / | 0.972 | 0.847–1.105 | 1.324 |
| Local 2 workers /json | 0.982 | 0.769–1.253 | 0.997 |
| Local 2 workers /echo | 1.070 | 0.748–1.546 | 0.984 |
| Hosted 2 workers / | 1.216 | 0.872–1.357 | 1.146 |
| Hosted 2 workers /json | 1.000 | 0.817–1.076 | 0.959 |
| Hosted 2 workers /echo | 1.176 | 0.873–1.392 | 1.168 |
| Local 1 worker / | 0.956 | 0.777–1.128 | 1.096 |
| Local 1 worker /json | 0.976 | 0.798–1.259 | 1.083 |
| Local 1 worker /echo | 0.942 | 0.888–0.984 | 1.044 |

**MEASURED, INDICATIVE:** local two-worker identical-baseline CPU ratios range 0.452–2.034 on plaintext, 0.977–1.459 on echo. This directly invalidates a precise small-effect claim, not proof of host noise as the cause. Ratios above are not speedup claims; median and interval estimate different statistics. Small samples, non-stationarity, multiple endpoints and no multiplicity correction limit nominal intervals. Hosted plaintext paired peak-RSS ratio median 1.130, geometric-mean interval 1.005–1.272; retain this adverse signal without declaring a leak or proven patch effect.

Additional GC diagnostics: nine separately instrumented processes at the same sources, one block, normal collector policy and `--DRT-gcopt=profile:1`. Whole-process collection counts A1/B/A2: plaintext 26/23/32, JSON 245/45/317, echo 162/196/201; largest reported pause 31 ms. **MEASURED, INDICATIVE:** GC activity is real in the HTTP path, not proof that GC explains the candidate effect (unequal work, setup/warm-up included, one block). The default environment-only GC option produced no summary and is invalid profiler evidence. Runtime CLI option was verified separately; diagnostic times do not clear the frozen gate or provide B/op. Durable raw results are linked in the dated report.

## Current capabilities and open contracts

| Area / owner | Established | Remaining gap |
|---|---|---|
| Endpoint/API/DX | **OBSERVED:** App + ref Context, runtime routing, existing common entry | No automatic domain-typed binding; do not invent a feature roadmap |
| B1 output capacity / Aurora | **MEASURED:** integrated bounded writer; release checks pass again | Not proof of all aliasing/framing semantics |
| B2 request lifetime / Wire | **MEASURED, 11 October historical:** two live wrappers alias at unchanged selected SHA; **OBSERVED** current parser pool still has one thread-local parser without busy fallback | Independent owner-level leases, native cleanup/failure/cost and consumer pin |
| B3 response boundary / Aurora | **OBSERVED:** status/type/body forwarding can lose headers; historical socket failure | Headers/framing/injection/HEAD/204/304/error contracts at socket |
| B4 admission / Aurora | **MEASURED:** default red, new logger-fixed candidate green | Cost acceptance unresolved; not integrated |
| B5 middleware/router / Aurora | **OBSERVED:** Router.use stored but not dispatched; misses bypass global pipeline | Explicit policy/order/miss/subrouter semantics |
| B6 lifecycle / Aurora | **MEASURED:** integrated logger normal-exit repair passes fresh 400 checks locally and 400 CI | **OBSERVED:** hijack outer cleanup, polling and weak startup-failure propagation; cancellation/drain/abrupt/concurrent teardown unknown |
| B7 metrics / Aurora | **OBSERVED:** Server writes vs WorkerState getter ownership mismatch; historical live zero count | One accounting owner and fresh request/error/413/431/timeout assertions |
| B8 input/errors / Aurora + FastjsonD | **OBSERVED:** silent field failure/separate mapper policy/downstream errors caught as 400 | Explicit input/domain/infrastructure error semantics and migration |
| B9 low-level handler / Aurora | **OBSERVED:** ResponseBuffer passed by value | Output loss is **INFERRED**, needs socket reproduction |
| B10 tooling/portability | **MEASURED:** canonical worker/limit flags and response control; **OBSERVED:** legacy paths/dormant tools | Empty-cache package, other compiler/OS, stress/realworld/Autobahn remain UNVERIFIED |

`queueRequest` remains TODO/503 fallback; prior gzip/zlib framing finding remains open. Parser/router unit tests pass within the 47-module suite; no new fuzzing, complete RFC/security audit, router mutation/concurrency proof, trace propagation, enabled/disabled observability cost or soak/overload certification.

Allocation: three local candidate profiles and fresh CI agree with pinned baseline artifact: parser core, keep-alive, raw accessors, static/inline-parameter router and preallocated builder 0 D-GC B/op; method()+path() 32; response lifecycle and routed request without I/O 384. **MEASURED**, 10,000 warm-up/100,000 measurement operations, pre-measure GC.collect then GC disabled. Setup/warm-up/network/logging/exceptions/native allocation/pool misses/overflow excluded; zero collection here is forced, not production pause freedom. LDC AOT, no JIT/cross-compiler claim. Three 1,000,000-iteration microbenchmark processes after 10,000 warm-up were collected; no compatible timing baseline or admission execution in those paths, so they cannot clear B4.

## Multidimensional scorecard

| Dimension | Proven / observed | Unknown / deficient |
|---|---|---|
| Correctness | **MEASURED:** 47 modules, capacity, logger, candidate admission red/green | B2/B3/B4 default and other dispatch boundaries |
| Protocol | **MEASURED:** 5 socket framing/retirement/deadline probes | Exhaustive encoding/framing/upgrade/fuzz **UNVERIFIED** |
| Performance / tail | **MEASURED:** 117 primary process comparisons, A/A controls, p50/p95/p99/p99.9 | No timing equivalence; adverse CPU/RSS signals, open-loop saturation unknown |
| CPU efficiency | **MEASURED:** calibrated whole-process wait4 CPU/request | Steady-state attribution, cycles/instructions/syscalls/locks **UNVERIFIED** |
| Memory efficiency | **MEASURED:** process peak RSS; **OBSERVED:** borrowing/pools | Native allocations, retention, memory/connection; B2 |
| Allocations | **MEASURED:** restricted 0/32/384 D-GC B/op | No end-to-end zero-allocation claim |
| Scaling | **MEASURED:** one/two-worker contract/cost runs | Configurations do not establish scaling efficiency/fairness |
| Resilience | **MEASURED:** write timeout, logger exit, candidate permit cleanup | Default admission, cancellation/drain/start failure/soak |
| Security | **MEASURED:** release-active bounds guard | Lost headers, complete audit and exhaustion unknown |
| Observability | **MEASURED:** logger exit; calibrated CPU evidence | Metric ownership inaccurate; off/on cost and trace contracts unknown |
| API / DX | **OBSERVED:** common entry retained; no new runtime concepts | Correct existing contracts before convenience; no user-journey metric |
| Documentation | **OBSERVED:** one current owner, candidate/default separated | Historical evidence must not become normative instructions |
| Packaging / release | **OBSERVED:** exact selected pins, no Aurora release | Clean install and version/support policy unknown |
| Compatibility / ecosystem | **MEASURED:** LDC 1.42/Linux x86-64 consumer | DMD/other platforms and independent adoption unknown |
| Debt / complexity | **OBSERVED:** measurement reuses OS/D/wrk, no new runtime mechanism | Duplicate representation/accounting/input ownership remains |

## Decision and next discriminator

The North Star still selects reliable existing contracts over a rewrite, new subsystem or cosmetic API. This cycle removed measurement blindness and separated a proven permit-lifetime correction from an unproven performance claim. It does not establish the current runtime as the best design point.

**Dominant integration uncertainty:** why identical-binary process CPU/RSS varies, and whether the candidate adds a repeatable cost after accounting for it. One-worker results weaken a simple universal guard-overhead hypothesis; they do not prove a multi-worker scheduler cause. GC diagnostics are discriminating evidence, not a reason to change collector policy speculatively.

**Next highest-value experiment (revisable):** profile one pinned baseline/candidate/control at the worker/runtime/GC boundary with valid counters and longer stable windows, decomposing idle, useful request CPU and collection/scheduler work; inspect the generated disabled/enabled admission cleanup paths. Require candidate-specific repeatability beyond A/A variation before attributing cost or accepting equivalence. Enabled-limit cost remains unmeasured because the disabled-path gate did not clear. B2 lease ownership and B3 header/framing remain competing correctness interventions, not tasks automatically queued behind B4. No permission is outstanding; no new API, custom scheduler or GC tuning is justified by this evidence.

[Prior canonical state](https://github.com/federikowsky/Aurora/blob/87f9ee3f931329f49ff8f2e560613697f540d327/docs/ENGINEERING_STATUS.md) retains earlier experiments, raw archives and superseded decisions. History is not a second current scorecard; external files are entry points only. Reacquire refs and contested evidence before the next decision.
