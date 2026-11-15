# Engineering state and North Star scorecard

**Current assessment: 15 November 2026. Production readiness: HOLD.** This is Aurora's sole current scorecard and decision register. It records current evidence and open hypotheses; it is not a task sequence. [NORTH_STAR](NORTH_STAR.md) and [AGENTS](../AGENTS.md) govern direction and work. [specs](specs.md), [API](API.md) and [TEST_REGISTRY](TEST_REGISTRY.md) own observed architecture, public contracts and test selection. Code, selected dependency revisions and pinned executions win when prose diverges.

MEASURED = direct execution or artifact; OBSERVED = inspected code, diff or log; INFERRED = reasoned consequence; UNVERIFIED = insufficient evidence. Historical evidence is not a current instruction.

## Revisions and reporting boundary

GitHub metadata was reacquired on 15 November. The actual default branch of all four first-party repositories remains `main`.

| Repository | Current implementation / selected revision | Boundary |
|---|---|---|
| Aurora | [`62af33c2380e9ed3fb21b0a80233027c1a935200`](https://github.com/federikowsky/Aurora/commit/62af33c2380e9ed3fb21b0a80233027c1a935200) | Peer-close integration and a working low-level handler response contract |
| Wire | [`6c5965eb71dbe81a9abc74832bf7a8020835ae5b`](https://github.com/federikowsky/Wire/commit/6c5965eb71dbe81a9abc74832bf7a8020835ae5b) | Exact revision selected by Aurora; no interval change |
| FastjsonD | [`23a51d692103a0b77cba153afa2994df0c14f4d3`](https://github.com/federikowsky/Fastjsond/commit/23a51d692103a0b77cba153afa2994df0c14f4d3) | Exact revision selected by Aurora; no interval change |
| Aurora-WebSocket | [`dacf2f10b0a999d1b373b0b1a16f4c1cd9767bb2`](https://github.com/federikowsky/Aurora-WebSocket/commit/dacf2f10b0a999d1b373b0b1a16f4c1cd9767bb2) | Owns and terminates its stream after completed Close or terminal protocol failure; selected by Aurora |

The complete interval is **2026-11-08T10:56:05Z–2026-11-15T07:00:53Z**, from Aurora `6746c051e07d53e96e72023e251e67ac0921ce01` through implementation `62af33c2380e9ed3fb21b0a80233027c1a935200`. No repository had pre-existing commits, materially changed issues or pull requests in that interval before the work recorded here.

## What changed and why

1. **WebSocket terminal ownership.** On the previous Aurora-WebSocket revision, receiving a peer Close sent the correct reply and marked the protocol connection closed while leaving the owned `IWebSocketStream` connected. `terminateTransport()` now makes the protocol and transport transition one operation. It is reused by local close, completed peer close and terminal protocol failure. Aurora pins that owner-side repair and proves TCP EOF while the application handler is still active.
2. **Low-level response propagation.** `RequestHandler` formerly received `ResponseBuffer` by value; the server then read its untouched original and emitted no bytes. It now borrows `scope ref ResponseBuffer`. The change is source-breaking for a legacy handler signature; migration is adding `ref`. Keeping source compatibility required shared backing state or pointer indirection for a path whose old contract could not work, so the smaller explicit borrow was chosen.

No new dependency, runtime discovery, queue, hook, subsystem or request-path abstraction was introduced. The WebSocket fix is in its owning first-party repository. The handler fix reuses D reference semantics and adds no common-path work beyond making the existing mutation visible.

## Evidence ledger

| Evidence | Pinned scope | Result |
|---|---|---|
| Repository interval | Four default branches at the starting boundary | **OBSERVED:** no external commit, materially changed issue or PR before this cycle |
| Isolated peer Close red/green | Aurora-WebSocket `4bfb2c8f` → `dacf2f10`; Linux x86-64, LDC 1.42.0 | **MEASURED:** before, Close reply plus `connection.connected=false` but `stream.connected=true`; after, debug/release builds and all unit modules pass, Close reply preserved and stream closed |
| Aurora consumer red/green | Aurora old pin vs `dacf2f10`; real TCP | **MEASURED:** old pin times out waiting for EOF while handler remains active; new pin passes 6/6 in debug and 6/6 in release |
| [WebSocket integration PR #14](https://github.com/federikowsky/Aurora/pull/14) | public head `ea5f0288dc031bb6f954b8eb181f4d42566be9de`, merge `52c3cf6d0ca87d463d89abff382ff95546ea926e` | **MEASURED:** [PR CI](https://github.com/federikowsky/Aurora/actions/runs/43685865103) and [main CI](https://github.com/federikowsky/Aurora/actions/runs/43686155100) pass; [main artifact `14150607511`](https://github.com/federikowsky/Aurora/actions/runs/43686155100/artifacts/14150607511), digest `sha256:61fee0cb83a5ea1e95e12e1323c7a6287ad0253e0d73e7876414116f828c29f0` |
| Low-level handler reproduction | Aurora `52c3cf6d` plus fixture only | **MEASURED, red:** handler calls `write`, client receives EOF with an empty status line |
| Low-level handler candidate | local `ff1f727d`, public head `3188412293cbcc0a5791501ad791f73663c1f1a9` | **MEASURED:** TCP response passes in debug and release; full local functional matrix passes after adding the standalone fixture to both unittest exclusion lists |
| [Low-level handler PR #15](https://github.com/federikowsky/Aurora/pull/15) | implementation `62af33c2380e9ed3fb21b0a80233027c1a935200` | **MEASURED:** [PR CI `43687442692`](https://github.com/federikowsky/Aurora/actions/runs/43687442692) and [main CI `43687704972`](https://github.com/federikowsky/Aurora/actions/runs/43687704972) pass the new socket gate and the complete functional job; [main artifact `14150488702`](https://github.com/federikowsky/Aurora/actions/runs/43687704972/artifacts/14150488702), digest `sha256:114abcdc279d0286eb9a15d174fa0e0354b8512e8ceba0eb9495edd369f6b0ef` |
| Local broad gates | source-equivalent candidate on Linux x86-64/LDC 1.42.0 | **MEASURED:** debug/release build; 47 unit modules; 400 logger exits; release response bounds; handler 2/2; HTTP 6/6; WebSocket 12/12; admission 24/24; example and benchmark controls |
| D-GC allocation profile | main `62af33c2` hosted artifact; 10,000 warm-up, 100,000 measured operations | **MEASURED:** parser core, keep-alive, raw method/path, static and parameter routing, both preallocated response paths, response lifecycle and routed request without I/O are 0 D-GC B/op; allocating `method()+path()` remains 32 B/op; zero claim is restricted to these paths |
| Hosted HTTP cost control | PR #15, baseline `52c3cf6d`, candidate `31884122`, 5 A1/B/A2 blocks × 3 routes | **MEASURED, INDICATIVE:** 45/45 measurements eligible and no response errors. Identical-baseline throughput changes span -46.67% to +50.94%; candidate deltas span -34.31% to +42.37%. The runner does not support a causal regression or improvement claim |

The dated report and raw archive preserve commands, environment, red/green logs, hosted artifacts, patches and analyses. Git history and linked Actions remain primary evidence.

## Current capability and open-contract register

| Area / owner | Established | Remaining gap |
|---|---|---|
| Endpoint/API/DX | **OBSERVED:** `App` plus `ref Context` keeps the common entry small; explicit low-level escape hatches exist | No automatic domain-typed binding; evaluate from user journeys, not subsystem taxonomy |
| B1 output capacity / Aurora | **MEASURED:** exact bounded response builder and release checks | Partial writes and every low-level/hijack variant are not certified |
| B2 request lifetime / Wire | **MEASURED:** independent live parser leases and Aurora consumer coverage | Field views borrow input; cold/overlap native cost remains workload-dependent |
| B3 buffered response / Aurora | **MEASURED:** headers, framing, injection, HEAD and no-body statuses pass end to end | Repeated same-name fields and broader compression/upgrade interaction |
| B4 admission / Aurora | **MEASURED:** Server-wide active-request cap covers dispatch and response write in tested one/two-worker cases | Sustained open-loop overload, fairness and stable dedicated-runner cost **UNVERIFIED** |
| B5 middleware/router / Aurora | **OBSERVED:** `Router.use` stores middleware but App dispatch does not execute it; misses bypass the global pipeline | Public semantics can mislead security policy; route/group/miss order and inheritance need one explicit contract |
| B6 upgrade lifecycle / Aurora + Aurora-WebSocket | **MEASURED:** terminal peer Close now reaches transport EOF while handler is active | Returning still ends ownership; asynchronous handoff, connection accounting and shutdown remain **UNVERIFIED** |
| B7 metrics / Aurora | **OBSERVED:** Server writes and WorkerState readers have different ownership | One accounting owner and live 4xx/timeout/request assertions |
| B8 input/errors / Aurora + FastjsonD | **OBSERVED:** silent conversion failures, distinct mapper policy and downstream errors mapped as 400 | Explicit input/domain/infrastructure semantics and migration |
| B9 low-level handler / Aurora | **MEASURED:** borrowed writer produces a complete TCP response in debug/release | Legacy by-value handler source migration; this path still allocates response storage when used |
| B10 tooling/portability | **MEASURED:** Linux x86-64/LDC 1.42 functional matrix | Root lock selects older transitives than DUB single-file fixtures; DMD/other OS, fuzzing, soak and Autobahn remain **UNVERIFIED** |

## Allocation and performance boundaries

The current hosted restricted-path profile reports: parser core 0 B/op at 145.930 ns/op; raw method/path 0 B/op at 1.890 ns/op; static router 0 B/op at 26.490 ns/op; inline parameter router 0 B/op at 52.954 ns/op; preallocated response 0 B/op at 18.899 ns/op; response object builder 0 B/op at 53.303 ns/op; response lifecycle 0 B/op at 2.693 ns/op; routed request without I/O 0 B/op at 62.105 ns/op. `method()+path()` is 32 B/op at 66.003 ns/op. These single hosted runs are direct measurements, not regression percentages.

The latest network control is unsuitable for a before/after claim: identical-baseline changes reach -46.67% to +50.94%. Candidate medians were 67,262 requests/s plaintext, 64,861 JSON and 144,891 echo, with median p50/p95/p99/p99.9 respectively 1.445/1.537/5.517/13.842 ms, 1.492/1.650/4.790/15.616 ms and 0.651/1.130/1.909/3.920 ms. These describe that artifact only. Neither integrated change targets the normal buffered HTTP benchmark path.

The D-GC profile excludes initialization, network, logging, exceptions, native allocation, pool misses and overflow. GC was collected and disabled during measurement; zero collections do not prove production pause freedom. No project-wide zero-GC claim is valid.

## Multidimensional scorecard

| Dimension | Proven / observed | Unknown / deficient |
|---|---|---|
| Correctness | **MEASURED:** broad suite; response/admission/parser contracts; peer Close transport termination; low-level response propagation | Middleware policy and asynchronous upgrade ownership |
| Protocol | **MEASURED:** HTTP 6/6, WebSocket 6/6 per mode, terminal Close reply/EOF | Full RFC/fuzz/Autobahn, repeated headers and broader frame limits **UNVERIFIED** |
| Performance / tail | **MEASURED:** scoped component and noisy network artifacts retained with dispersion | No stable regression gate, open-loop saturation or controlled-arrival tail baseline |
| CPU efficiency | **MEASURED, INDICATIVE:** whole-process CPU/request rows exist | Runner modes invalidate a small-delta decision; cycles/instructions/syscalls/locks absent |
| Memory / allocations | **MEASURED:** restricted hot paths at 0 D-GC B/op; one 32 B/op convenience path identified | Native bytes, retention, connection-scale RSS and end-to-end allocation |
| Scaling | **MEASURED:** admission with one/two workers | Many-core efficiency, placement and fairness |
| Resilience / security | **MEASURED:** bounds, conflicting framing, response injection, admission, terminal Close | Middleware policy boundary, cancellation/drain/startup failure/sustained overload |
| Observability | **MEASURED:** logger lifecycle and raw artifacts | Metric ownership, trace contract and off/on overhead |
| API / DX | **OBSERVED:** explicit borrowed low-level writer; common high-level path unchanged | Router-local middleware looks available but is inert; input/error model remains fragmented |
| Documentation | **OBSERVED:** API/spec/test registry own their contracts; this file is the only scorecard | Keep examples and code-derived facts synchronized |
| Packaging / release / compatibility | **OBSERVED:** exact first-party pins; **MEASURED:** Linux/LDC consumer | WebSocket release tag predates fixes; divergent transitive resolution; DMD/OS matrix and migration release needed |
| Debt / complexity | **OBSERVED:** both repairs centralize ownership without new machinery | Middleware, metrics, input/error and handoff responsibilities remain distributed |

## Current decision and next discriminator

Production readiness remains **HOLD**. The two reproduced correctness failures are closed at their owning boundaries. The handler change deliberately spends source compatibility to remove a nonfunctional contract; a release note and versioning decision are required before a public release, but no additional runtime compatibility layer is justified.

**Dominant current uncertainty:** middleware policy semantics. `Router.use` and group-oriented examples present a policy boundary that the dispatch path does not execute. Documentation warns about it, but a security-sensitive API cannot rely on users discovering a warning.

**Next discriminator, revisable:** freeze user-visible cases for global middleware, route-local policy, groups/subrouters, misses, `OPTIONS`, exceptions and ordering; reproduce them through App/socket dispatch; then choose the smallest coherent result. Credible outcomes include integrating one composable policy chain, removing/deprecating the inert API until semantics exist, or exposing a narrower primitive. Reject designs that add layers or hooks without making handler selection, executed policy and rejection reasons inspectable. Reacquire refs and reevaluate global expected value before implementation.

No user decision is currently outstanding.
