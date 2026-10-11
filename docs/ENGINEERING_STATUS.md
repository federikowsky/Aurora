# Engineering state and North Star scorecard

**Current assessment: 11 October 2026. Production readiness: HOLD.** This is the sole current scorecard and decision register, not a task sequence. [NORTH_STAR](NORTH_STAR.md) and [AGENTS](../AGENTS.md) govern direction and work; [specs](specs.md), [API](API.md) and [TEST_REGISTRY](TEST_REGISTRY.md) describe the current default implementation. Code, selected dependencies and revision-qualified executions establish behavior. Candidate documentation describes its candidate, not the distributed default.

## Revisions, interval and integration boundary

Authoritative GitHub metadata was reacquired on 11 October; all four default branches are `main`.

| Repository | Default runtime/source inspected | Candidate / selected consumer boundary |
|---|---|---|
| Aurora | `72b9717e44b2f54e4052f7b3621cc292c46d7d8e` (logger lifecycle; integrated after cutoff) | [PR #4](https://github.com/federikowsky/Aurora/pull/4), `6005d023f5104f90b968b399125b1136d17b8b45`; runtime fix at `47371b9e3df1789b11ff91efce1c35f2ad385316`; **not integrated** |
| Wire | `82b6a5dfd606ebe2ac15c83d9430abdb58aec09b` | Same SHA selected by Aurora; old lease candidate `ced07d5c2c07b1c459b62e4e28e1612df2095ae2` remains separate |
| FastjsonD | `23a51d692103a0b77cba153afa2994df0c14f4d3` | Same SHA selected by Aurora; no change this cycle |
| Aurora-WebSocket | `edfbbc6d4e1a7f713a96faa13bebfbb44a51c9d2` | Aurora selects package `1.0.1`, not automatically this HEAD |

The logger repair was integrated at `b1a18fa304e1171fc513a14b9c9e414d79625afe` after the reporting cutoff; its runtime source is `72b9717e44b2f54e4052f7b3621cc292c46d7d8e`. Subsequent state-only publication does not change it. Reacquire refs before work. Exact remaining package versions belong to `dub.selections.json`. The old combined Aurora candidate `fdff62d7dc342432bcee3523413199397c98b657` is historical evidence, not an instruction to merge.

**Complete reporting interval: 2026-10-04T17:02:13Z → 2026-10-11T05:28:38Z.** Initial inspection this cycle: 04:56:24Z. The interval starts at default `3416660672229179b947e54bf4bfb650309aa38e` and ends at default `d5d9be42c1d802b8aa9b26cda9f46dbec646e5cd`. Four default commits on 4 October cover documentation, two bounded-writer iterations and CI. Their scoped evidence was already recorded but did not advance the previous complete cutoff. This cycle adds two candidate commits and PR #4; no other updated issues/PRs or new release were found before inspection. Publication/checks after cutoff are explicitly this cycle's output. Complete reporting does not mean every platform, failure mode or benchmark is validated.

## Evidence ledger

MEASURED = execution/artifact; OBSERVED = inspected code/log; INFERRED = reasoned consequence; UNVERIFIED = missing evidence. Historical results never silently become fresh tests.

| Evidence | Exact scope | Result |
|---|---|---|
| [Default CI](https://github.com/federikowsky/Aurora/actions/runs/37228204573), [artifact 11312946809](https://github.com/federikowsky/Aurora/actions/runs/37228204573/artifacts/11312946809) | `d5d9be4`; downloaded/digest checked | **MEASURED:** build/unit/protocol/capacity/profile evidence; artifact SHA-256 `5aae4def74ac533b9f3026fa43f92f9573fb4845104b14b4fde650458be794b2` |
| Local baseline and red admission test | `d5d9be4`, LDC 1.42.0 | **MEASURED:** 47 modules exit 0; held limit=1 incorrectly admits contender with HTTP 200 instead of 503 |
| Local candidate validation | Runtime `47371b9`, final test tree `6005d02` | **MEASURED:** debug/release builds; 47 modules; capacity release check; 5 protocol probes; 12 admission scenarios in each debug/release, exit 0 |
| [Candidate CI](https://github.com/federikowsky/Aurora/actions/runs/38114521922), [functional artifact](https://github.com/federikowsky/Aurora/actions/runs/38114521922/artifacts/11693535421) | PR merge `f979cfff16506cd2c46bdffb243f08de7818e7fe`, tree `c10a895287995a5f097dcd427273e07afcadfb13` exactly equals candidate `6005d02` | **MEASURED:** 47 modules, capacity, minimal example, framing 5/5, admission 12 debug + 12 release; profile steps pass. Artifact digest `9e291e672c9794d8ec6ad45f5936fc8c7e9e8b4ca717e5f25c0a3921f8342c1b` |
| [Paired HTTP artifact](https://github.com/federikowsky/Aurora/actions/runs/38114521922/artifacts/11692967319) | Exact checkouts `d5d9be4` vs `6005d02`, one hosted runner | **MEASURED:** 3 counterbalanced pairs, 3 endpoints; exact-byte controls; one baseline echo read error, none reported for candidate. Digest `4abe352af1c0753a66c2664c996117a4d368fa4edd403c97c3c4a9401ad32b20` |
| [Local raw archive](https://chatgpt.com/api/library/files/libfile_b6eb1ad2c6a88191a69f7cb5c99f1fd4/download) (owner-authenticated) | Commands, environment, patches, red/green logs, all timing samples, CI downloads, probe source | **MEASURED:** SHA-256 `366e64f34bc8ea724f1e717b3ea280ef37490e9023905dd1cc71d9e23170816f`; public CI links above remain independently available |
| Fresh Wire live-request probe | Selected `82b6a5d`, two independent buffers, two live wrappers | **MEASURED:** first `GET /first` becomes `POST /second` after second parse; enforcement fails (program exit 1, DUB exit 2). B2 reconfirmed |
| Profiling calibration | Current local sandbox | **MEASURED:** busy-loop /proc CPU ticks remain zero; discarded. strace fails `PTRACE_TRACEME: Operation not permitted`; no CPU/request or syscall result |

[Earlier state and primary evidence links](https://github.com/federikowsky/Aurora/blob/d5d9be42c1d802b8aa9b26cda9f46dbec646e5cd/docs/ENGINEERING_STATUS.md) preserve the September investigations, 4 October full validation and bounded-writer experiments. They remain historical evidence. In particular, B1 was closed at `414d2f83420bdac605cadc5c98338ce61fd6c6f2`; its release canary/capacity checks passed again this cycle. No claim of exhaustive HTTP correctness follows.

## Admission candidate: ownership, not another subsystem

**OBSERVED:** the old `scope(exit)` belongs to the admission `if` block and releases before dispatch. The atomic counter already belongs to the Server; a comment incorrectly describes a per-worker limit. **MEASURED:** the socket reproduction confirms the consequence.

The isolated candidate keeps the reservation until the request iteration exits, covering dispatch and response write; rejected reservations are rolled back before writing 503. Existing D scope guards and `core.atomic` solve the problem. Alternatives considered: duplicate cleanup at each exit (more states/missed-exit risk), new semaphore/scheduler (unnecessary machinery), removing the limit (loses a public protection). No dependency or public API was added. Runtime diff: 11 added / 2 removed lines. Claiming per-worker behavior is replaced by explicit Server-wide semantics in candidate documentation.

Tests cover worker settings 1/2, limits 0/1/2, held handlers, burst 16 with limit 2, exception 500 then reuse, idle keep-alive, pipelining, slow response write and timeout cleanup. They establish permit lifetime, not comprehensive connection admission, cancellation, hijack or scheduler fairness. Multi-worker mode is exercised; socket assignment to each worker is not forced. Review found no blocking correctness defect in this scoped change.

**Decision: published, not integrated.** Functional gates pass. An adverse local HTTP signal remains causally unresolved; the hosted comparison is also dispersed. A successful benchmark job is evidence collection, not a performance gate. No new permission is needed; the remaining constraint is technical evidence. Default users still have B4. No release was made.

## New evidence changed the decision: logger lifecycle

A fresh [default CI](https://github.com/federikowsky/Aurora/actions/runs/38115141628) at documentation-only `21565760ba787cbc268524df0d22abf0940dc797` printed 47 passing modules, then exited with program code -11 / DUB exit 2. Later checks were skipped. **MEASURED:** this is a failed process, not a green suite. [Failure artifact](https://github.com/federikowsky/Aurora/actions/runs/38115141628/artifacts/11692558740), SHA-256 `612e4dda07ea986998691abc94715f4245e6e682db45dee7c5c493dfd109ac0f`.

A minimal release program using only `Logger.get().info()` crashed 11/20 times at implicit exit versus 0/20 with explicit shutdown. **OBSERVED:** singleton state was process-global but its initialization mutex was thread-local; automatic shutdown depended on a GC object destructor while a daemon used GC-managed resources. **INFERRED:** teardown ordering explains the isolated failure; the exact crashing instruction was not acquired.

The separate [logger repair](https://github.com/federikowsky/Aurora/commit/72b9717e44b2f54e4052f7b3621cc292c46d7d8e) assigns construction/destruction and mutex to the shared module, joins/drains the daemon before runtime finalization, and removes the redundant object finalizer. D shared module lifecycle is the existing native mechanism; no new API, shutdown manager or dependency. Log/request hot-path source is unchanged. Explicit shutdown remains supported after producers stop; no logger restart, abrupt-signal or concurrent shutdown/reconfiguration guarantee.

**MEASURED:** final local source passes 400 separate process exit/output checks (50 per unused/implicit/explicit/eight-thread simultaneous-first-access mode, debug and release), library debug/release, 47 modules plus 20 repeated suite exits, protocol 5/5. An earlier intermediate repetition failed unchanged buffer_pool_test.d:293 `Release latency too high` (exit 1, not SIGSEGV); retained, assertion not weakened, causal attribution unknown. Review found no blocking defect after fixture exclusions in both unittest configurations. [Logger CI](https://github.com/federikowsky/Aurora/actions/runs/38115741159) passed 400 further process checks, 47 modules, capacity, protocol and profiles. PR merge `8fdda938555575dda0fbe4bb4b93ab2ff63ca3bc`, candidate `72b9717` and integrated merge `b1a18fa` have identical tree `482c0ded80951721a40f4402ff0e02f2a2ee0aa3`. [Artifact 11692394988](https://github.com/federikowsky/Aurora/actions/runs/38115741159/artifacts/11692394988), digest `f95bb7ec920b3571ebabdf450079141370a8c05e294c168607865830b297e0de`. One fresh CI allocation profile also confirms the same restricted 0/32/384 B/op values; no new HTTP comparison of this runtime was performed.

The normal logger teardown defect is closed in the integrated repair's tested scope. B6's other lifecycle problems remain open. This pivot superseded making performance A/A the immediate next implementation: a reproducible process crash had greater global value to address. No throughput improvement or total lifecycle safety is inferred. [Supplemental raw archive](https://chatgpt.com/api/library/files/libfile_c7cb3bf1f4d88191979145944c8f1e86/download) (owner-authenticated), SHA-256 `f45d4a85f539310208d2d2e39c093162aee610ea1f1cb1f5801972f7c552dd69`, preserves the failure, red/green processes, interim timing failure, final commands, review and downloaded CI artifact.

## Cost evidence and comparison limits

These measurements compare admission baseline `d5d9be4` with runtime `47371b9` / public candidate `6005d02`, before the separate logger repair. They are not new performance/allocation measurements of `72b9717`.

Local: Linux 6.18.44, KVM x86-64, Intel Xeon Platinum 8573C; 9 visible CPUs, cgroup quota 8 cores, memory limit 8 GiB. Hosted: Ubuntu 24.04/Linux 6.17.0-1022-azure, Microsoft virtualization, AMD EPYC 9V74, 4 CPUs, 15 GiB visible RAM/3 GiB swap; CPU/memory quotas not captured. Both LDC 1.42.0 / DMD 2.112.1 / LLVM 21.1.8 / DUB 1.41.0, release builds. Tracked trees clean for baseline/public candidate; local development builds have the recorded runtime patch; hosted untracked `artifacts/` contains evidence. Default and candidate dependency selections unchanged. Local builds use existing cache, not an empty-cache install.

HTTP: canonical server, 9 local / 4 hosted workers, admission limits disabled, client/server share host; wrk `a211dd5a7050b1f9e8a9870b95513060e72ac4a0`, 4 threads/100 connections, 3 s warm-up + 10 s measurement, restart each variant; no CPU isolation/affinity. Plaintext, JSON, 1 KiB echo; separate plaintext and 64 KiB binary echo equality controls pass. Normal runtime GC; no allocation profiler on HTTP. Latency is closed-loop, not an overload SLO. Local pairs 1–3 accepted; pair 0 excluded for overlapping functional tests, raw retained. Hosted order alternates across 3 pairs. Environments are **NON-COMPARABLE** with one another or previous weekly runners.

| Environment / endpoint | Baseline / candidate median req/s | CV % baseline / candidate | Median p99 ms baseline / candidate | Median p99.9 ms baseline / candidate |
|---|---:|---:|---:|---:|
| Local `/` | 92233.29 / 67878.95 | 10.62 / 15.27 | 20.630 / 44.877 | 67.621 / 72.393 |
| Local `/json` | 82320.11 / 47722.39 | 6.24 / 33.01 | 27.983 / 59.620 | 74.615 / 89.042 |
| Local `/echo` | 110047.62 / 73738.46 | 9.80 / 33.57 | 26.798 / 97.850 | 68.588 / 190.189 |
| Hosted `/` | 91336.09 / 92082.73 | 22.50 / 28.97 | 6.846 / 8.120 | 11.518 / 13.663 |
| Hosted `/json` | 87461.97 / 84289.79 | 22.74 / 26.05 | 6.872 / 6.383 | 11.309 / 10.826 |
| Hosted `/echo` | 114827.74 / 111308.94 | 15.72 / 24.77 | 5.272 / 5.478 | 8.302 / 7.871 |

**MEASURED, INDICATIVE:** accepted local samples total 14,084,738 requests, no reported socket/status errors. Excluded pair 0 has two read errors. Three reverse-order plaintext controls still vary: candidate/base 39387/82026, 50882/85382, 90858/65967 req/s. Hosted echo has one baseline read error. These are neither evidence of timing equivalence nor proof the guard causes the slowdown. No regression percentage or improvement is asserted. Raw p50/p95, individual samples and errors are retained.

Components: three alternating processes per variant; 10,000 warm-up / 1,000,000 timing iterations; no I/O. Median ns/op baseline→candidate: static router 47.21→45.05, parameter router 91.12→90.54, Context 12.00→12.82, builder 27.22→27.12, response lifecycle 518.04→456.64, routed-no-I/O 550.21→521.08. **INDICATIVE:** these do not execute admission and cannot clear its end-to-end gate.

Allocation profiler: 10,000 warm-up / 100,000 measured iterations, 3 processes per variant, GC.collect before measurement and GC disabled during it. All six outputs agree: parser core, keep-alive flag, raw accessors, static/inline-parameter router and preallocated builder **0 D-GC B/op**; convenience method()+path() **32**; response lifecycle and routed-no-I/O **384**. **MEASURED**, restricted scope only. Setup/warm-up/network/logging/exceptions/native allocation/pool misses excluded; zero collections with GC disabled does not prove production pause freedom. LDC is AOT; no JIT claim, no cross-compiler guarantee.

## Actual capabilities and remaining contract gaps

| Area / owner | Current evidence | Closure requirement / unknown |
|---|---|---|
| Endpoint/API/DX | **OBSERVED:** App + ref Context, runtime router; no automatic domain-typed binding | Preserve the working common path; do not add fictional APIs to match aspirations |
| B1 output capacity / Aurora | **MEASURED:** bounded writer integrated, fresh release check passes | Not a proof of every aliasing/framing contract |
| B2 request lifetime / Wire | **MEASURED:** fresh two-live-request alias reproduction at selected SHA | Owner-level independent leases, cleanup/failure/native cost and selected consumer pin |
| B3 response boundary / Aurora | **OBSERVED:** writer still forwards status/type/body rather than all headers; previous socket failure retained | Header/framing/injection/duplicate/HEAD/204/304/error contracts at socket |
| B4 admission / Aurora | **MEASURED:** default fails, isolated candidate passes functionality | Resolve candidate timing uncertainty; integrate only with an explicit technical decision |
| B5 middleware/router / Aurora | **OBSERVED:** Router.use stored but not dispatched; misses bypass global pipeline | Explicit policy/order/miss/subrouter behavior; no new hook family by default |
| B6 lifecycle / Aurora | **MEASURED:** normal logger teardown repaired and repeated process checks pass; **OBSERVED:** hijack outer cleanup, polling and weak startup-failure propagation remain | Cancellation/drain/start failure and abrupt/concurrent logger shutdown remain unvalidated |
| B7 metrics / Aurora | **OBSERVED:** Server writes and WorkerState getter ownership differ; historical live zero count | One accounting owner; request/error/413/431/timeout live assertions |
| B8 input/errors / Aurora + FastjsonD boundary | **OBSERVED:** silent field failures, separate mapper policies, downstream errors caught as 400 | Explicit input/domain/infrastructure error contract and migration |
| B9 low-level handler / Aurora | **OBSERVED:** ResponseBuffer passed by value | Output-loss consequence remains **INFERRED** pending socket reproduction |
| B10 tooling/portability | **OBSERVED:** legacy paths/dormant tools; ordinary CI covers LDC/Linux | Clean install, alternative compiler/OS, stress/realworld/Autobahn are **UNVERIFIED** |

`queueRequest` remains a TODO/503 fallback; the gzip branch's zlib framing finding remains open. No complete security audit, sustained overload, trace propagation or enabled/disabled observability cost has been established. Source inspection is not a fresh end-to-end test of these defects.

## Multidimensional scorecard

| Dimension | Established | Still unknown / deficient |
|---|---|---|
| Correctness | **MEASURED:** 47 modules, B1 pass, B4 candidate red/green, logger teardown repair | B2/B3/B4 default; other dispatch paths |
| Protocol | **MEASURED:** 5 fragmentation/pipeline/retirement/deadline probes | **UNVERIFIED:** exhaustive framing/encoding/upgrade/fuzz compliance |
| Performance / tail | **MEASURED:** two-environment paired data, explicit errors and dispersion | Causal adverse signal; controlled-arrival p99.9 and useful-load SLOs |
| CPU efficiency | **MEASURED:** invalid local CPU counter calibration | CPU/request, cycles/instructions, syscall/lock attribution |
| Memory efficiency | **OBSERVED:** borrowed state/pools; B2 lifetime failure | Native allocation, RSS/connection, retention/exhaustion |
| Allocation behavior | **MEASURED:** unchanged selected 0/32/384 D-GC B/op | Network, middleware/error, native total; no server-wide zero allocation |
| Scalability | **MEASURED:** one/two-worker contract tests, four/nine-worker load | Scaling efficiency, fairness, contention |
| Resilience | **MEASURED:** framing/write timeout; B4 candidate cleanup; normal logger module teardown | Default admission, cancellation, drain/startup failure, soak |
| Security | **MEASURED:** B1 bounds guard regression passes | **UNVERIFIED:** comprehensive audit; lost security headers remain |
| Observability | **MEASURED:** logger normal shutdown fixed; **OBSERVED:** metric ownership mismatch | Accurate events, useful diagnostics, off/on overhead |
| API quality / DX | **OBSERVED:** small common entry; candidate limit semantics explicit | Correct public contracts before more convenience APIs; user journey measurements |
| Documentation | **OBSERVED:** canonical owner map retained, links checked | Candidate and default must remain distinct; historical reports not normative |
| Packaging / release | **OBSERVED:** no Aurora GitHub release; exact selections | Registry packaging/empty-cache delivery and release policy validation |
| Compatibility | **MEASURED:** LDC 1.42/Linux x86-64 | DMD/other platforms/version minima **UNVERIFIED** |
| Ecosystem readiness | **OBSERVED:** first-party ownership and selected revisions explicit | Integrated lease contract, consumer compatibility, real adoption |
| Debt / accidental complexity | **OBSERVED:** duplicated representation/accounting/input state | Eliminate causes, not add compensating layers |

## Decision and next discriminator

The North Star does not select a rewrite or a new subsystem. It increases the value of predictable existing contracts: the current experiment fixes ownership using existing mechanisms. B4 outranked the previous suggested B2 experiment because a bounded, independently testable correction could improve overload correctness, API truth and DX together. Fresh evidence now changes the next decision again.

**Dominant integration uncertainty after the logger repair:** whether the admission candidate has a material disabled-path cost or whether run/host variability dominates. A second environment reduced neither dispersion nor causal uncertainty sufficiently to claim equivalence. Local /proc accounting is invalid and ptrace is denied; do not fabricate profiling or bypass restrictions.

The late process failure was investigated and repaired before returning to this question. **Next highest-information action (revisable):** first reconcile the admission branch with the logger-fixed default and rerun its contract gates (the old candidate does not contain the logger fix); then, on a runner with valid process CPU accounting, interleave identical-binary A/A controls with pinned A/B, fix worker/client CPU budget and randomize/counterbalance order. Use the public comparison harness; record CPU/request and throughput/tails/errors, verify counter calibration, and preserve exact-byte controls. Falsifier: repeatable candidate-specific degradation larger than A/A dispersion, with attributable CPU or scheduling cost. If confirmed, simplify the scope/cleanup code generation without restoring early release; if falsified with adequate precision, integrate the safety fix. No preset acceptable percentage is retrofitted to these samples. B2 and B3 remain competing high-value correctness repairs once this gate can be decided. No user permission is outstanding.

## Historical versus normative state

[Prior canonical state](https://github.com/federikowsky/Aurora/blob/d5d9be42c1d802b8aa9b26cda9f46dbec646e5cd/docs/ENGINEERING_STATUS.md) retains the document audit, old raw artifact references and superseded decisions. Deleted plan/ROADMAP material remains in Git history. No parallel history tree, new roadmap, subsystem catalog or competing scorecard is introduced. External North Star/state files are entry points only. Reacquire source, rerun contested evidence and update this owner when findings change.
