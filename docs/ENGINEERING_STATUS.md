# Engineering state and North Star scorecard

**Current assessment: 8 November 2026. Production readiness: HOLD.** This is Aurora's sole current scorecard and decision register. It records evidence and open hypotheses; it is not a task sequence. [NORTH_STAR](NORTH_STAR.md) and [AGENTS](../AGENTS.md) govern direction and work. [specs](specs.md), [API](API.md) and [TEST_REGISTRY](TEST_REGISTRY.md) own observed architecture, public contracts and test selection. Code, selected dependencies and pinned executions win when prose diverges.

## Revisions and reporting boundary

GitHub metadata was reacquired on 8 November. The actual default branch of every first-party repository remains `main`.

| Repository | Implementation / selected revision | Boundary |
|---|---|---|
| Aurora | `ca18dea3b0f4cdaa2311d979e187851f56643f60` | [PR #10](https://github.com/federikowsky/Aurora/pull/10) makes `HTTPResponse` authoritative for buffered application responses |
| Wire | `6c5965eb71dbe81a9abc74832bf7a8020835ae5b` | Same exact SHA selected by Aurora; exclusive live parser leases remain integrated |
| FastjsonD | `23a51d692103a0b77cba153afa2994df0c14f4d3` | Same exact SHA selected; no change this interval |
| Aurora-WebSocket | `edfbbc6d4e1a7f713a96faa13bebfbb44a51c9d2` | Aurora selects package `1.0.1`, not automatically repository HEAD; no change this interval |

**Complete reporting interval: 2026-10-25T05:55:51Z → 2026-11-08T07:00:00Z**, Aurora default at the prior cutoff `76fadb5cd35a9fb959ab2f70d77fd551de1ba84e` → implementation merge `ca18dea3b0f4cdaa2311d979e187851f56643f60`. Publications immediately after the prior cutoff (`66aa01c`) and this interval's response integration are included. No first-party dependency revision changed. Complete reporting means the declared scope was examined; it is not certification of every platform, protocol case or failure mode.

## Evidence ledger

MEASURED = direct execution/artifact; OBSERVED = inspected code/log; INFERRED = consequence reasoned from evidence; UNVERIFIED = insufficient evidence. Historical results are labelled and are not fresh checks.

| Evidence | Pinned scope | Result |
|---|---|---|
| Response socket reproduction on old source | Aurora `66aa01c631610c267f4607eb644c4269692bcec3` plus the new fixture only | **MEASURED, red:** five established protocol groups pass; the new response group fails because `X-Aurora-Probe` is absent from the wire response |
| Candidate local gates | local source-equivalent commit `59c9a472182ee61bb96b06ce1704d0f1b669f3a5` | **MEASURED:** debug/release build, 47 modules, release response bounds, minimal example, protocol 6/6, benchmark configuration, allocation and microbenchmark executables pass |
| [PR #10 CI](https://github.com/federikowsky/Aurora/actions/runs/42455277160) and [artifact 13607129104](https://github.com/federikowsky/Aurora/actions/runs/42455277160/artifacts/13607129104) | PR head `0986346a412bab9f6c2bd91ecb99340f2c34cae2`; merge test SHA `abff8660cf0eafb36f06156cdb08ffa5cac1bb5b` | **MEASURED:** every CI step passes; artifact digest `sha256:1e9864bf01cdc33cbb77f97a61397ac1f0fa2facbe757cdfcce222ebbc281f57` |
| Main CI | implementation merge `ca18dea3b0f4cdaa2311d979e187851f56643f60` | **MEASURED:** [run 42455815450](https://github.com/federikowsky/Aurora/actions/runs/42455815450) completes successfully on the published default branch |
| D-GC allocation profile | old `66aa01c` versus source-equivalent candidate; 10,000 warm-up / 100,000 measurement; preallocated output | **MEASURED:** response lifecycle and routed no-I/O path fall from 384 to 0 B/op; actual `HTTPResponse.buildInto` is 0 B/op; `method()+path()` remains 32 B/op |
| Controlled HTTP A/B | old vs candidate, five alternating pairs, server CPU 2, `wrk` CPUs 3–6, one worker, 4 threads, 100 connections, 10 s | **MEASURED, INDICATIVE:** all responses correct and no socket/non-2xx errors; paired median throughput delta -0.98%, mean -1.03%, with deltas crossing -16.6% to +18.4% and CV about 11–12%; no reliable regression or improvement claim |
| Previous Wire ownership repair | integrated Wire `6c5965e` and Aurora pin | **MEASURED, historical:** Wire 62/62 plus Aurora consumer gates pass; sequential warmed parsing retains zero wrapped `calloc/free`, while overlapping live parsers allocate independent native state |
| Previous admission evidence | current distributed default and open [PR #7](https://github.com/federikowsky/Aurora/pull/7) head `e811528aec5a54e4304729b41180934ec2736201` | **MEASURED, historical:** default fails held-request limit; candidate is functionally green; performance acceptance remains unresolved |

The dated raw evidence archive preserves commands, environment, red/green logs, benchmark rows and patches. GitHub Actions and artifacts above are public primary evidence. Conversational summaries are not implementation proof.

## Decision: one authoritative buffered response contract

**OBSERVED:** the old runtime extracted only status, content type and body from `HTTPResponse`, then rebuilt bytes through a second API. Application headers could be discarded, while `HTTPResponse` also stored derived `Server`, `Connection` and `Content-Length` state that could diverge from the final wire representation.

The integrated design passes the complete `HTTPResponse` to serialization. One exact bounded `estimateSize`/`buildInto` contract now owns buffered application emission. Serialization derives final `Content-Length` and connection policy; preserves validated custom headers; applies default `Content-Type` and `Server` only when absent; suppresses bodies for `HEAD`, 1xx, 204, 205 and 304; and keeps representation length for successful and error `HEAD` responses. Header names, values and reason phrases reject control-character injection. The empty common response no longer allocates an associative header map, and middleware no longer synchronizes derived length manually.

Alternatives pruned:

- keeping two builders and forwarding more fields retains duplicate framing ownership;
- pre-populating derived headers preserves stale state and the 384 B/op common-path allocation;
- patching only the lost-header symptom leaves HEAD/status framing and injection inconsistent;
- replacing the bounded writer adds machinery without addressing the ownership defect.

`buildResponseInto` remains as a low-level fixed-response primitive. Repeated same-name fields such as multiple `Set-Cookie` values are still unsupported by the map representation and remain an explicit gap. `getHeaders()` is now a read-only view; callers mutate through validated `setHeader` / `Context.header`.

## Current capabilities and open contracts

| Area / owner | Established | Remaining gap |
|---|---|---|
| Endpoint/API/DX | **OBSERVED:** `App` + `ref Context`, runtime routing and common entry remain small | No automatic domain-typed binding; value and semantics still require user-journey evidence |
| B1 output capacity / Aurora | **MEASURED:** exact bounded response writer and release checks pass | Partial socket writes and every low-level/hijack path are not certified by this result |
| B2 request lifetime / Wire | **MEASURED:** independent live parsers, non-LIFO/move/thread/error/incomplete isolation; Aurora consumer green | Input bytes remain borrowed; cold/overlap native allocation and bounds beyond tested cases are workload-dependent |
| B3 buffered response / Aurora | **MEASURED:** application headers, framing, injection, HEAD success/error and 204/304 behavior pass end to end | Repeated same-name fields; broader compression, upgrade and low-level path matrix |
| B4 admission / Aurora | **MEASURED, historical:** distributed default fails held-request limit; candidate is functionally green | Candidate CPU/request, tail and saturation cost acceptance unresolved; not integrated |
| B5 middleware/router / Aurora | **OBSERVED:** `Router.use` is stored but not dispatched; misses bypass parts of the pipeline | Explicit policy/order/miss/subrouter semantics |
| B6 lifecycle / Aurora | **MEASURED:** normal logger teardown passes repeated checks locally and in CI | Hijack outer cleanup, polling, startup failure, cancellation/drain/abrupt/concurrent teardown |
| B7 metrics / Aurora | **OBSERVED:** Server writes and WorkerState getters have different ownership | One accounting owner and live request/error/413/431/timeout assertions |
| B8 input/errors / Aurora + FastjsonD | **OBSERVED:** silent field failure, separate mapper policy and downstream errors mapped as 400 | Explicit input/domain/infrastructure semantics and migration |
| B9 low-level handler / Aurora | **OBSERVED:** `ResponseBuffer` is passed by value | Output loss is **INFERRED** pending a socket reproduction |
| B10 tooling/portability | **MEASURED:** canonical worker/limit flags and response controls | Empty-cache install, DMD/other OS, stress/real-world/Autobahn remain **UNVERIFIED** |

`queueRequest` remains a TODO/503 fallback. Parser/router tests pass inside the 47-module suite. Complete RFC/security audit, sustained fuzzing, router mutation/concurrency proof, trace propagation, observability off/on cost and soak/overload certification do not exist.

## Allocation and performance boundaries

At the pinned response candidate, parser core, keep-alive, raw accessors, static/inline-parameter router, low-level preallocated builder, `HTTPResponse.buildInto`, response lifecycle and routed request without I/O measure 0 D-GC B/op. `method()+path()` remains 32 B/op. The old response lifecycle and routed request scopes were 384 B/op because default headers eagerly created an associative array. Initialization, network, logging, exceptions, native allocation, Wire cold/overlap leases, pool misses and overflow are excluded. GC was collected then disabled during measurement; zero collections do not prove production pause freedom. LDC AOT was used; no JIT or cross-compiler claim applies.

The HTTP A/B is a closed-loop localhost test without calibrated CPU/request or controlled arrival. Its high dispersion falsifies both the first apparent regression and any precise small-delta claim. It supports only that the corrected path served valid responses without a detectable large stable throughput loss in that environment. Tail latency, throughput/core and saturation behavior remain unresolved.

## Multidimensional scorecard

| Dimension | Proven / observed | Unknown / deficient |
|---|---|---|
| Correctness | **MEASURED:** 47 modules; response bounds/framing/headers; independent parser lifetime | B4 admission and other dispatch/lifecycle boundaries |
| Protocol | **MEASURED:** 6 socket groups including HEAD success/error, 204/304, framing and retirement | Exhaustive encoding, repeated fields, upgrade and fuzzing **UNVERIFIED** |
| Performance / tail | **MEASURED:** scoped component and HTTP evidence with raw dispersion | No stable regression gate; open-loop saturation and controlled-arrival tails unknown |
| CPU efficiency | **MEASURED:** historical calibrated whole-process CPU/request; current response A/B only indicative | Current response CPU/request, cycles/instructions/syscalls/locks **UNVERIFIED** |
| Memory efficiency | **MEASURED:** response common-path D-GC allocation removed; parser allocation shape known | Native bytes, retention and memory/connection under realistic concurrency |
| Allocations | **MEASURED:** restricted Aurora common response paths 0 B/op; method+path 32 B/op | No end-to-end or native zero-allocation claim |
| Scaling | **MEASURED, historical:** selected one/two-worker contract/cost runs | Scaling efficiency, placement and fairness not established |
| Resilience | **MEASURED:** write timeout, logger exit, parser isolation | Default admission, cancellation, drain, startup failure and soak |
| Security | **MEASURED:** release-active bounds, conflicting framing probes, response injection rejection | Full request-smuggling/injection/exhaustion audit |
| Observability | **MEASURED:** logger exit; historical calibrated CPU evidence | Metrics ownership inaccurate; trace contracts and off/on cost unknown |
| API / DX | **OBSERVED:** common entry retained; header mutation validated; derived framing hidden | Repeated response fields and input/error semantics remain awkward |
| Documentation | **OBSERVED:** API/spec/test registry and examples match the integrated response contract | Future changes must keep code-derived facts out of duplicate prose |
| Packaging / release | **MEASURED:** Aurora pins first-party source revisions exactly | Clean-install/compiler/platform matrix and new release tags unknown |
| Compatibility / ecosystem | **MEASURED:** Linux x86-64/LDC 1.42 consumer | DMD, other platforms and independent adoption unknown |
| Debt / complexity | **OBSERVED:** one application response owner; duplicate default/framing state removed | Admission, middleware, metrics and input/error responsibilities remain distributed |

## Decisions and next discriminator

The North Star continues to favor repairing authoritative boundaries over a rewrite, new subsystem or convenience veneer. B3 is closed for the buffered common path. No responsibility moved to Wire, FastjsonD or Aurora-WebSocket, and no dependency or custom allocator was introduced.

**Dominant production uncertainty:** admission under sustained load. The distributed default can exceed the configured held-request limit, so bounded resource behavior is false precisely when overload protection matters. A functionally validated candidate exists, but the current evidence cannot distinguish its CPU/request and tail cost from runner noise.

**Next highest-value intervention, revisable:** compare current `main` with PR #7 using pinned CPUs, calibrated whole-process CPU/request, correct-response accounting and open-loop saturation/overload tails. Accept only if the limit is enforced without a material common-path or tail regression; otherwise localize the cost before changing the design. If the candidate is dominated, prune it and revisit ownership rather than layering another queue. This decision follows current evidence and is not a roadmap obligation.

No user decision is outstanding. Reacquire refs and contested measurements before the next decision. [The prior canonical state](https://github.com/federikowsky/Aurora/blob/66aa01c631610c267f4607eb644c4269692bcec3/docs/ENGINEERING_STATUS.md) preserves earlier experiments; history is evidence, not a second current scorecard.
