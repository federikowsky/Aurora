# Engineering state and North Star scorecard

**Current assessment: 25 November 2026. Production readiness: HOLD.** This is Aurora's sole current scorecard and decision register. It records current evidence and open hypotheses; it is not a task sequence. [NORTH_STAR](NORTH_STAR.md) and [AGENTS](../AGENTS.md) govern direction and work. [specs](specs.md), [API](API.md) and [TEST_REGISTRY](TEST_REGISTRY.md) own observed architecture, public contracts and test selection. Code, selected dependency revisions and pinned executions win when prose diverges.

MEASURED = direct execution or artifact; OBSERVED = inspected code, diff or log; INFERRED = reasoned consequence; UNVERIFIED = insufficient evidence. Historical evidence is not a current instruction.

## Revisions and reporting boundary

GitHub metadata was reacquired on 24 November and the integrated default was checked on 25 November. The actual default branch of all four first-party repositories remains `main`.

| Repository | Current implementation / selected revision | Boundary |
|---|---|---|
| Aurora | [`365472d3c2956ff2df72cbcf4f3853f8464422d5`](https://github.com/federikowsky/Aurora/commit/365472d3c2956ff2df72cbcf4f3853f8464422d5) | Implementation of [PR #19](https://github.com/federikowsky/Aurora/pull/19), integrated at [`abd6c191497c`](https://github.com/federikowsky/Aurora/commit/abd6c191497c7cf88b572d588aae57f136f592d2); prior default `fe181eaf` |
| Wire | [`6c5965eb71dbe81a9abc74832bf7a8020835ae5b`](https://github.com/federikowsky/Wire/commit/6c5965eb71dbe81a9abc74832bf7a8020835ae5b) | Exact revision selected by Aurora; no interval change |
| FastjsonD | [`23a51d692103a0b77cba153afa2994df0c14f4d3`](https://github.com/federikowsky/Fastjsond/commit/23a51d692103a0b77cba153afa2994df0c14f4d3) | Exact revision selected by Aurora; no interval change |
| Aurora-WebSocket | [`dacf2f10b0a999d1b373b0b1a16f4c1cd9767bb2`](https://github.com/federikowsky/Aurora-WebSocket/commit/dacf2f10b0a999d1b373b0b1a16f4c1cd9767bb2) | Exact revision selected by Aurora; terminal transport owner unchanged |

The last complete ecosystem interval is **2026-11-15T07:11:20Z–2026-11-22T06:39:44Z**, through PR #17 (`8d7d8492`). The 24–25 November assessment is a **focused middleware review**, based on default `fe181eaf`, not a new complete weekly cutoff. Dependencies and server dispatch are unchanged by this review.

## What changed and why

PR #17 was right to remove inert `Router.use`/public storage and run the global pipeline on the framework 404 and unmatched OPTIONS. Its global-only limitation was provisional. The old example kept a public-path exception list inside authentication; method-specific rules on the same path and nested separately authored endpoint sets make that a poor ownership boundary. A per-handler decorator alone does not cover routes added by another module.

The same middleware executor now serves `App.use`, `new Router(prefix, policies...)` and `withMiddleware(handler, policies...)`. The router binds policy to each effective handler at setup. No policy list in a match, group lookup per request or retained subrouter graph. Misses run only App policy; a registered OPTIONS route can run local policy. Imports snapshot child routes and reject conflicts before adding anything. Prefixes are read-only; a second call to the same borrowed continuation throws. See [contract, migration and caveats](API.md#middleware-and-policies).

**MEASURED:** under LDC 1.42.0 on Linux x86-64, release, eight rotated blocks, the isolated three-policy chain fell from 288 to 0 thread D-GC B/op; parsing, matching and actually executing global+group+route with checked headers/body used 640 vs 352 B/op. Manual wrapping on the new executor also used 352; the saving must not be attributed to the group API alone. The bare fixture was 0 B/op on both sides. Configuring the fixture with 128 additional leaves used 111,712 vs 53,152 D-GC bytes after replacing temporary split arrays with Phobos' lazy segment iterator. The real loopback mix had 30,720 correct measured responses, no timeouts and broad identical-baseline dispersion; throughput/tail equivalence remains **UNVERIFIED**. Native heap, total process allocations, high-depth stack and saturated many-worker behavior are unmeasured. [Raw per-run rows](../benchmarks/evidence/2026-11-24-policy.csv) and [reproduction](../benchmarks/README.md#endpoint-policy-cost).

As a stronger manual control the application also assembled each effective policy list once and shared it across corresponding endpoints, on the **old and new** executors. Old flat manual → new declarative used 192 → 0 D-GC B/op for three isolated policies, 592 → 352 for the actual global/group/route fixture, and 101,360 → 53,152 bytes per setup. New flat manual and new declarative both used 352 B/op on the protected fixture and respectively 53,216 / 53,152 bytes at setup. Consequently the new group syntax earns its place through coverage and ownership, not an inherent speed advantage over a well-composed manual handler. [Control patch](../benchmarks/evidence/2026-11-24-flat-control.diff), [all component observations](../benchmarks/evidence/2026-11-24-flat-control.csv). Apply the patch to the same benchmark source in both worktrees and pass the resulting `aurora_policy_flat` binaries to the same driver.

**Investigated control anomaly (not a throughput pass).** In the [final PR run](https://github.com/federikowsky/Aurora/actions/runs/45505930136/artifacts/14974145401), canonical `/json` ran no middleware, yet B was 13.8–26.0% below the paired baseline mean in all five blocks; two-worker processes consumed about 7.2 or 14 CPU-seconds over identical warm-up and measurement durations. An [independent hosted repetition](https://github.com/federikowsky/Aurora/actions/runs/45505411568/artifacts/14974181660) on the same source and benchmark (only scorecard/data differed) yielded -40.5% to +69.4% across five JSON blocks. Local pinned repetitions yielded −30.1% to +39.0% (two workers, five blocks) and −15.2% to +17.5% (one worker, four). In two local runs of the **same candidate binary** with two workers configured, five-second samples directly recorded one CPU-active thread or two (5.01/0.00 vs 4.98/4.96 thread CPU-seconds). This shows that configured workers do not guarantee two active serving threads. Listener placement vs connection distribution on hosted runners remains **UNVERIFIED**. Preserve all results; neither general speedup nor neutrality has been established. [Functional artifact incl. scoped socket and D-GC rows](https://github.com/federikowsky/Aurora/actions/runs/45505930136/artifacts/14973810467).

## Evidence ledger

| Evidence | Pinned scope | Result |
|---|---|---|
| Scoped-policy focused validation | code `365472d3` (same tree as local `00461ff6`); baseline `fe181eaf` | **MEASURED:** 18 real socket cases × debug/release × one/two workers, 47 unittest modules, and 8-block manual/manual/bound controls; [benchmark data](../benchmarks/evidence/2026-11-24-policy.csv). Baseline positive mount relocation and static-prefix/parameter selection probes both failed before the fix. |
| Repository interval | Four default branches and selected revisions | **OBSERVED:** no external code change or materially changed issue/PR before this cycle; dependency pins remain exact |
| Middleware baseline reproduction | Aurora `c23a47f3` plus fixture only | **MEASURED, red:** first unmatched `GET /missing` returns 404 without `X-Global-Policy`; build succeeds and probe exits 1 |
| Middleware candidate | local `e424b4651107c0a3f0e397f9394527c1c8f27b8c`, public head `88058506dbeee0e5ade0da47d130867dd008bacd`, identical tree `b5661fabf0768e9dd9510167067c1800433ac0df` | **MEASURED:** seven socket cases pass in debug and release; fake Router storage tests are replaced by an executable absence contract |
| [Middleware PR #17](https://github.com/federikowsky/Aurora/pull/17) | [PR CI `44994359096`](https://github.com/federikowsky/Aurora/actions/runs/44994359096) | **MEASURED:** functional job passes every step; [artifact `14743321574`](https://github.com/federikowsky/Aurora/actions/runs/44994359096/artifacts/14743321574), digest `sha256:e0a7f9c5e0b5845bed23ac3d7f6da3be15de629865c4f09a9cf9d74b753a9489` |
| Integrated main | merge `8d7d849208954857b273b5f67934529d19e1ea56` | **MEASURED:** every functional step passes on the integrated SHA; [main CI `44994725391`](https://github.com/federikowsky/Aurora/actions/runs/44994725391); [artifact `14743527708`](https://github.com/federikowsky/Aurora/actions/runs/44994725391/artifacts/14743527708), digest `sha256:1d953a6c3604299777f3da6a25c44b430266f5a55672be33fc01dba11bbc63d0` |
| Local broad gates | source-equivalent final tree; Linux x86-64, LDC 1.42.0 | **MEASURED:** debug/release build; 47 unit modules; 400 logger process scenarios; release response bounds; handler 2/2; HTTP 6/6; WebSocket 12/12; admission 24/24; middleware 14/14; minimal example and benchmark controls |
| Hosted D-GC profile | PR #17 functional artifact; 10,000 warm-up, 100,000 measured operations | **MEASURED:** parser, keep-alive, raw method/path, static/parameter routing, response paths and routed no-I/O remain 0 D-GC B/op in scope; `method()+path()` remains 32 B/op |
| Hosted component timing | same artifact and runner | **MEASURED, descriptive:** static route 24.989 ns/op in allocation profile; routed request without I/O 62.352 ns/op; no before/after causal claim |
| Hosted admission cost control | base `c23a47f3`, candidate `88058506`, PR #17 | **MEASURED, INDICATIVE:** 45/45 rows eligible with no response errors; identical-baseline throughput changes span -29.26% to +63.21%, while candidate-vs-pair-average changes span -40.35% to +40.75%. [Artifact `14742574381`](https://github.com/federikowsky/Aurora/actions/runs/44994359096/artifacts/14742574381), digest `sha256:04d67643c25679b61e68846276f5668ce7155bb4dee7082d4e2d1268210c2218`; no causal performance claim |

Earlier response, parser-lifetime, admission, logger, WebSocket and low-level-handler repairs remain established at their linked commits and CI in Git history. The dated report and raw archive preserve this cycle's commands, environment, red/green logs, patches and public artifacts.

## Current capability and open-contract register

| Area / owner | Established | Remaining gap |
|---|---|---|
| Endpoint/API/DX | **OBSERVED:** `App` plus `ref Context` keeps the common entry small; explicit low-level escape hatches exist | No automatic domain-typed binding; evaluate from user journeys, not subsystem taxonomy |
| B1 output capacity / Aurora | **MEASURED:** exact bounded response builder and release checks | Partial writes and every low-level/hijack variant are not certified |
| B2 request lifetime / Wire | **MEASURED:** independent live parser leases and Aurora consumer coverage | Field views borrow input; cold/overlap native cost remains workload-dependent |
| B3 buffered response / Aurora | **MEASURED:** headers, framing, injection, HEAD and no-body statuses pass end to end | Repeated same-name fields and broader compression/upgrade interaction |
| B4 admission / Aurora | **MEASURED:** Server-wide active-request cap covers dispatch and response write in tested one/two-worker cases | Sustained open-loop overload, fairness and stable dedicated-runner cost **UNVERIFIED** |
| B5 middleware/router / Aurora | **MEASURED:** one App policy boundary on match/miss; constructor and handler composition select local policies by matched endpoint, including explicit OPTIONS | Parser/admission precede policy; extreme nesting, many-worker contention and namespace-wide miss policy are not covered |
| B6 upgrade lifecycle / Aurora + Aurora-WebSocket | **MEASURED:** terminal peer Close reaches transport EOF while handler is active | Returning still ends ownership; asynchronous handoff, connection accounting and shutdown remain **UNVERIFIED** |
| B7 metrics / Aurora | **OBSERVED:** request/error counters are written in Server while Linux getters prefer WorkerState values that those paths do not update | One accounting owner and live one/two-worker assertions for requests, 4xx/errors and timeouts |
| B8 input/errors / Aurora + FastjsonD | **OBSERVED:** struct conversion failures are silently defaulted; validation uses a separate mapper and can map downstream exceptions to 400 | Explicit input/domain/infrastructure semantics and migration |
| B9 low-level handler / Aurora | **MEASURED:** borrowed writer produces a complete TCP response in debug/release | Legacy by-value handler source migration; this path still allocates response storage when used |
| B10 tooling/portability | **MEASURED:** Linux x86-64/LDC 1.42 functional matrix | Root lock selects older transitives than DUB single-file fixtures; DMD/other OS, fuzzing, soak and Autobahn remain **UNVERIFIED** |

## Allocation and performance boundaries

Historical PR #17 functional artifact (not a fresh scoped-policy benchmark) reports: parser core 0 B/op at 147.067 ns/op; raw method/path 0 B/op at 2.369 ns/op; static router 0 B/op at 24.989 ns/op; inline parameter router 0 B/op at 54.149 ns/op; preallocated response 0 B/op at 19.334 ns/op; response object builder 0 B/op at 40.472 ns/op; response lifecycle 0 B/op at 2.692 ns/op; routed request without I/O 0 B/op at 62.352 ns/op. `method()+path()` is 32 B/op at 66.327 ns/op. These values describe one hosted artifact and are not regression percentages.

The historical PR #17 A/A–A/B run used two workers, two server CPUs, two client CPUs, 100 closed-loop connections, five rotating blocks and three routes. Candidate median throughput was 67,296 requests/s plaintext, 64,375 JSON and 122,326 echo. Median p50/p95/p99/p99.9 latency was respectively 1.450/2.348/6.797/9.253 ms, 1.536/3.001/6.442/15.144 ms and 0.761/2.019/2.880/5.095 ms. Whole-process median CPU was 29.442, 31.139 and 15.970 us/request. Identical-baseline dispersion is wider than any defensible small-delta threshold, so these values describe the artifact and do not prove a regression or improvement.

That historical D-GC profile excludes initialization, network, logging, exceptions, native allocation, pool misses and overflow. GC was collected and disabled during measurement; zero collections do not prove production pause freedom. No project-wide zero-GC claim is valid.

## Multidimensional scorecard

| Dimension | Proven / observed | Unknown / deficient |
|---|---|---|
| Correctness | **MEASURED:** broad suite; response/admission/parser contracts; terminal WebSocket and low-level response; global and local endpoint policy boundaries | Metric ownership, input conversion and asynchronous upgrade ownership |
| Protocol | **MEASURED:** HTTP 6/6, WebSocket 6/6 per mode, focused middleware 18/18 for each worker count and build | Full RFC/fuzz/Autobahn, repeated headers and broader frame limits **UNVERIFIED** |
| Performance / tail | **MEASURED:** scoped component and network control artifacts retained with dispersion | No stable regression gate, open-loop saturation or controlled-arrival tail baseline |
| CPU efficiency | **MEASURED, INDICATIVE:** whole-process CPU/request rows exist | Hosted runner noise; cycles/instructions/syscalls/locks absent |
| Memory / allocations | **MEASURED:** restricted hot paths at 0 D-GC B/op; executed global+group+route fixture 352 B/op; raw and convenience accessors differ | Native bytes, retention, connection-scale RSS and end-to-end allocation |
| Scaling | **MEASURED:** admission with one/two configured workers | Effective per-thread serving load can differ between restarts with two workers configured; many-core efficiency and assignment remain open |
| Resilience / security | **MEASURED:** bounds, conflicting framing, response injection, admission, terminal Close, scoped denial and global policy on misses/preflight | Cancellation/drain/startup failure and sustained overload |
| Observability | **MEASURED:** logger lifecycle and raw artifacts; **OBSERVED:** duplicated counter ownership | Live public metric correctness, trace contract and off/on overhead |
| API / DX | **OBSERVED:** one middleware type; local policy attached to routes or immutable group membership, with explicit advanced writer | Breaking Router migration; input/error model remains fragmented |
| Documentation | **OBSERVED:** API/spec/test registry match the integrated tree; compiled middleware example demonstrates public/read/write separation | Keep examples and code-derived facts synchronized |
| Packaging / release / compatibility | **OBSERVED:** exact first-party pins; **MEASURED:** Linux/LDC consumer | No release tag for accumulated breaking changes; divergent transitive resolution; DMD/OS matrix and migration release needed |
| Debt / complexity | **OBSERVED:** one executor and one matched handler; retained subrouter graph and eager registration segment arrays removed | Metrics, input/error and upgrade-handoff responsibilities remain distributed |

## Current decision and next discriminator

Production readiness remains **HOLD**. Keep PR #17's App/fallback contract, support explicit group and route binding, and reject mutable, retroactive registration. The changed configuration and continuation rules need the [migration](API.md#middleware-and-policies) and an appropriate breaking-version release with the other accumulated changes; this review does not tag a release.

**Dominant current uncertainty:** runtime metric ownership. On Linux/FreeBSD, `Server.getRequests()` and related getters prefer `WorkerPool` aggregation once the pool exists, while request processing increments Server fields. A deployment can therefore serve real traffic while reporting counters from a different, mostly unwritten owner. This affects observability, overload decisions and the credibility of subsequent performance/resilience work.

**Next discriminator, revisable:** freeze public metric meanings and run a real-socket one/two-worker probe across successful responses, 404, handler exception and timeout/rejection exits. Associate listener creation, accepted connections and served requests with the actual thread/worker on each restart, then trace every increment/read to one owner. This discriminates uneven assignment from counters recording the wrong work before changing either. Accept only a design that preserves no-op cost discipline and produces executable assertions for each advertised counter. Reacquire refs and reevaluate global expected value before implementation; the distinct input/error defect remains a competing correctness candidate.

No user decision is currently outstanding.
