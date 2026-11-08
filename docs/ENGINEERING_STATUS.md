# Engineering state and North Star scorecard

**Current assessment: 8 November 2026. Production readiness: HOLD.** This is Aurora's sole current scorecard and decision register. It records current evidence and open hypotheses; it is not a task sequence. [NORTH_STAR](NORTH_STAR.md) and [AGENTS](../AGENTS.md) govern direction and work. [specs](specs.md), [API](API.md) and [TEST_REGISTRY](TEST_REGISTRY.md) own observed architecture, public contracts and test selection. Code, selected dependencies and pinned executions win when prose diverges.

## Revisions and reporting boundary

GitHub metadata was reacquired on 8 November. The actual default branch of every first-party repository remains `main`.

| Repository | Implementation / selected revision | Boundary |
|---|---|---|
| Aurora | [`2776a91075be28c692d915ce2ea26a0be04ff342`](https://github.com/federikowsky/Aurora/commit/2776a91075be28c692d915ce2ea26a0be04ff342) | Upgrade uses the actual HTTP method and version. [PR #7](https://github.com/federikowsky/Aurora/pull/7) remains the admission boundary |
| Wire | `6c5965eb71dbe81a9abc74832bf7a8020835ae5b` | Same exact SHA selected by Aurora; numeric HTTP version comes from Wire |
| FastjsonD | `23a51d692103a0b77cba153afa2994df0c14f4d3` | Same exact SHA selected; no change |
| Aurora-WebSocket | [`4bfb2c8f33194edcd6bca4217857174fa82d7bdf`](https://github.com/federikowsky/Aurora-WebSocket/commit/4bfb2c8f33194edcd6bca4217857174fa82d7bdf) | Aurora pins the verified Git commit; the published `v1.0.1` tag is unchanged and does not contain this repair |

This update starts from the previous complete report cutoff, **2026-11-08T07:49:35Z**, with Aurora `0b226effd8f16ecc666f44f8293b12c7ec874995` and its [main CI artifact](https://github.com/federikowsky/Aurora/actions/runs/42460124751/artifacts/13609595660). The new implementation boundary is `2776a91075be28c692d915ce2ea26a0be04ff342`. Prior response and admission results below are retained as dated evidence.

## Evidence ledger

MEASURED = direct execution/artifact; OBSERVED = inspected code/log; INFERRED = consequence reasoned from evidence; UNVERIFIED = insufficient evidence. Historical results are labelled and are not fresh checks.

| Evidence | Pinned scope | Result |
|---|---|---|
| Upgrade socket reproduction | Aurora `0b226eff` with a fixture only, WebSocket tag `v1.0.1` | **MEASURED:** valid synchronous echo/close passes; POST, HTTP/1.0, an invalid Base64 alphabet and a key decoding to 18 bytes each get HTTP 101; a same-worker task joining the HTTP task then gets EOF instead of echo |
| Opening handshake repair | Aurora implementation `2776a910` (local tree `9c268455efa51200bbd34e91eb8f3909c485e940`), WebSocket `4bfb2c8f` | **MEASURED:** 5/5 socket scenarios in debug and 5/5 in release; valid masked echo and close, four invalid requests reach application HTTP 400. Aurora-WebSocket debug/release builds and all 9 unit modules pass |
| Aurora local gates | same implementation tree, Linux x86-64/LDC 1.42.0 | **MEASURED:** debug/release builds, 47 unit modules, 6 HTTP socket groups, 24 admission scenarios, 400 logger process exits, release response bounds, example, benchmark controls, microbench and D-GC profile |
| Release-only validation and ELF footprint | public `2776a910`, independent release caches; baseline `0b226eff` selects WebSocket tag `v1.0.1` | **MEASURED:** 5/5 socket scenarios again; the canonical HTTP server has 28,832 additional `.text` bytes and 59,632 additional `size` text/data/bss bytes. The candidate retains 158 WebSocket symbols where the baseline retains none. This is a packaging/linkage cost, not evidence of request-path work |
| [Hosted HTTP cost control](https://github.com/federikowsky/Aurora/actions/runs/42471357376/artifacts/13614240262) | PR head `4f766fe3`, baseline `0b226eff`, 5 blocks across 3 routes | **MEASURED, INDICATIVE:** 45/45 eligible. Paired median useful throughput: plaintext +0.9%, JSON -14.0%, echo -14.0%. Every route's block deltas cross zero and identical-baseline throughput spread reaches 34.4%. The adverse medians remain visible; no causal timing conclusion |
| Skip-outer-close experiment | unintegrated patch on Aurora `0b226eff`, WebSocket tag `v1.0.1` | **MEASURED:** deferred echo works, but an open upgrade evades `maxConnections=1`, survives `App.stop()` in the live process and does not terminate TCP within one second of replying to a peer Close frame |
| Peer Close isolated in Aurora-WebSocket | `4bfb2c8f`, release with existing `MockWebSocketStream` | **MEASURED:** sends the correct Close reply and sets `connection.connected=false`, but `stream.connected` remains `true`; this localizes the missing stream close seen in the socket experiment |
| Admission socket reproduction on distributed default | Aurora `3b1bdb00847966921deee0043820a61bd6ad44b7` plus fixture only | **MEASURED, red:** limit 1 with one held handler admits a competitor with HTTP 200 instead of 503 |
| Candidate local functional matrix | source-equivalent `c6d6650a0fd640b1d0a27b447521e370ccd89e9d` | **MEASURED:** 12/12 scenarios pass in debug and 12/12 in release: one/two workers, limits 0/1/2, burst, handler exception, keep-alive/pipelining and slow-client write timeout |
| Candidate local broad gates | same candidate | **MEASURED:** debug/release build, 47 modules, logger lifecycle 400 exits, response bounds, minimal example, protocol 6/6, microbenchmark, benchmark configuration and D-GC profile pass |
| [PR #7 CI](https://github.com/federikowsky/Aurora/actions/runs/42458659205) | public head `28287d196bd56d048a84bb11ba4f2df4ecbdd0cf`; merge test `ad703ed9c50db761262bb24215ecee8025541f91` | **MEASURED:** all functional jobs pass; artifact `13608751456`, digest `sha256:825591e8ec905b8dfb15474612d424fa51d0e63e4db2071de2deff5380394e09` |
| PR hosted admission cost artifact | same PR head, five A1/B/A2 blocks, three routes | **MEASURED, INDICATIVE:** 45/45 eligible, no response/socket errors; plaintext throughput -19.69% paired median while CPU/request improves 14.34%; JSON +1.61%; echo -1.80%; runner variance and contradictory metrics prevent a causal regression claim |
| [Main CI](https://github.com/federikowsky/Aurora/actions/runs/42459470704) and [artifact 13609277111](https://github.com/federikowsky/Aurora/actions/runs/42459470704/artifacts/13609277111) | merge `3f04a01ac143c59ccbc893ec3195633dd1237aad` | **MEASURED:** every main functional step passes; digest `sha256:074d9a29238b2b72216bc2785d815c743f6ccd9627537e5845235194216a379b` |
| Local controlled disabled admission comparisons | old vs candidate, ten plaintext blocks total; three-route 3-block set plus 7-block plaintext set | **MEASURED, INDICATIVE:** all responses eligible; combined plaintext throughput median -1.30% with sign changes and very high A/A dispersion; no stable regression or equivalence claim |
| Local enabled admission comparisons | candidate disabled vs limit 1000, three blocks × three routes | **MEASURED, INDICATIVE:** paired CPU/request medians plain -0.31%, JSON +1.94%, echo -3.21%; throughput -0.35%, +0.38%, +3.63%; A/A spread reaches 42.8% |
| D-GC allocation profile | implementation `2776a910`; 10,000 warm-up / 100,000 measurement; preallocated output | **MEASURED:** nine restricted parser/router/response/routed-no-I/O paths are 0 B/op; `method()+path()` remains 32 B/op. No WebSocket allocation claim |
| Previous response integration | Aurora `ca18dea3b0f4cdaa2311d979e187851f56643f60` | **MEASURED, historical:** authoritative `HTTPResponse`, header/framing/HEAD/status regression matrix and 0 B/op response lifecycle integrated |
| Previous Wire ownership repair | Wire `6c5965e` selected by Aurora | **MEASURED, historical:** Wire 62/62 plus Aurora consumer gates pass; overlapping live parsers own independent native state |

The dated raw evidence archive preserves commands, environment, red/green logs, benchmark rows, analyses, hosted artifacts and patch. GitHub Actions and artifacts above are public primary evidence. Conversational summaries are not implementation proof.

## Decision: Server-wide admission owns the full active HTTP request

**OBSERVED:** the former code incremented the atomic counter inside a lexical block whose `scope(exit)` ran before handler dispatch and response writing. The configured limit therefore reserved only a few instructions and did not bound active requests.

The integrated contract reserves one slot after a complete request is parsed and before dispatch. The reservation spans routing, middleware/handler work, response serialization and socket write, and is released at request-iteration exit on success, exception, timeout or keep-alive continuation. A rejected request rolls its optimistic increment back before returning `503 Service Unavailable` with `Retry-After: 1`. Limit `0` remains disabled. Idle keep-alive connections and incomplete reads consume no request slot.

Alternatives pruned:

- per-worker counters do not enforce the documented Server-wide limit;
- releasing before response write leaves slow-client resource occupancy unbounded;
- a queue or custom semaphore adds state, scheduling and cancellation semantics that the rejection contract does not require;
- moving admission into Wire confuses HTTP parsing ownership with Aurora runtime resource policy;
- weakening the test to accept eventual admission would preserve the reproduced defect.

The implementation reuses D's existing `core.atomic` primitive and adds no dependency, queue, scheduler or allocator.

## Decision: the upgrade validator receives actual request facts

Aurora checks the numeric HTTP version at its HTTP/1.1 transport boundary and forwards the request's actual method. Aurora-WebSocket owns handshake validation; it checks the length, alphabet and padding of the 16-byte nonce without allocating a decoded buffer. It retains the encoded key for the accept hash, as specified by [RFC 6455](https://www.rfc-editor.org/rfc/rfc6455#section-4.2). The checks run only in the upgrade helper. There is no public signature change, new dependency or separate validator in Aurora. Malformed requests that previously got 101 now leave an HTTP error response to the caller.

## Current capabilities and open contracts

| Area / owner | Established | Remaining gap |
|---|---|---|
| Endpoint/API/DX | **OBSERVED:** `App` + `ref Context`, runtime routing and common entry remain small | No automatic domain-typed binding; value and semantics require user-journey evidence |
| B1 output capacity / Aurora | **MEASURED:** exact bounded response writer and release checks pass | Partial socket writes and every low-level/hijack path are not certified |
| B2 request lifetime / Wire | **MEASURED:** independent live parsers and Aurora consumer pass | Input remains borrowed; cold/overlap allocation and untested bounds are workload-dependent |
| B3 buffered response / Aurora | **MEASURED:** headers, framing, injection, HEAD success/error and 204/304 pass end to end | Repeated same-name fields; broader upgrade/compression/low-level matrix |
| B4 admission / Aurora | **MEASURED:** Server-wide active-request limit holds through response write for tested one/two-worker scenarios | Sustained open-loop overload, fairness and stable cost on a dedicated runner remain **UNVERIFIED** |
| B5 middleware/router / Aurora | **OBSERVED:** `Router.use` is stored but not dispatched; misses bypass parts of pipeline | Explicit policy/order/miss/subrouter semantics |
| Opening handshake / Aurora and Aurora-WebSocket | **MEASURED:** valid 101/echo/close; non-GET, HTTP/1.0, malformed key and wrong decoded key length rejected | Broader handshake and frame compliance, resource limits and Autobahn remain **UNVERIFIED** |
| B6 lifecycle / Aurora and Aurora-WebSocket | **MEASURED:** normal logger and admission cleanup; HTTP task exit closes a deferred upgrade | Keep one transport owner through handoff, count live upgrades and make shutdown/peer close terminate transport. Removing outer close alone fails all three resource checks |
| B7 metrics / Aurora | **OBSERVED:** Server writes and WorkerState getters have different ownership | One accounting owner and live request/error/413/431/timeout assertions |
| B8 input/errors / Aurora + FastjsonD | **OBSERVED:** silent field failure, separate mapper policy and downstream errors mapped as 400 | Explicit input/domain/infrastructure semantics and migration |
| B9 low-level handler / Aurora | **OBSERVED:** `ResponseBuffer` is passed by value | Output loss is **INFERRED** pending a socket reproduction |
| B10 tooling/portability | **MEASURED:** canonical worker/limit flags and admission/response controls | Empty-cache install, DMD/other OS, stress/real-world/Autobahn remain **UNVERIFIED** |

`queueRequest` remains a TODO/503 fallback. Parser/router tests pass inside the 47-module suite. Complete RFC/security audit, sustained fuzzing, router mutation/concurrency proof, trace propagation, observability off/on cost and soak certification do not exist.

## Allocation and performance boundaries

Parser core, keep-alive, raw accessors, static/inline-parameter router, low-level preallocated builder, `HTTPResponse.buildInto`, response lifecycle and routed request without I/O measure 0 D-GC B/op. `method()+path()` remains 32 B/op. Initialization, network, logging, exceptions, native allocation, Wire cold/overlap leases, pool misses and overflow are excluded. GC was collected then disabled during measurement; zero collections do not prove production pause freedom. LDC AOT was used; no JIT or cross-compiler claim applies.

The admission counter's common-path cost is not resolved to a stable number. Local tests are noisy and cross zero; the hosted plaintext throughput anomaly did not reproduce locally and conflicts with improved CPU/request. This evidence supports correctness and absence of response errors, but neither performance equivalence nor a causal regression. A dedicated controlled runner is required before using small deltas as an architectural decision.

## Multidimensional scorecard

| Dimension | Proven / observed | Unknown / deficient |
|---|---|---|
| Correctness | **MEASURED:** 47 modules; response contracts; parser lifetime; admission across dispatch/write | Hijack and low-level handler boundaries; wider lifecycle matrix |
| Protocol | **MEASURED:** 6 HTTP socket groups, admission matrix, opening handshake and synchronous WebSocket echo/close | Repeated fields, full upgrade conformance and fuzzing **UNVERIFIED** |
| Performance / tail | **MEASURED:** scoped component and comparative HTTP evidence with dispersion; mixed-cache timing runs are not used for comparison | No stable regression gate; open-loop saturation and controlled-arrival tails unknown |
| CPU efficiency | **MEASURED, INDICATIVE:** whole-process CPU/request comparisons recorded | Admission cost not stable; cycles/instructions/syscalls/locks **UNVERIFIED** |
| Memory efficiency | **MEASURED:** response common-path D-GC allocation removed; parser allocation shape known | Native bytes, retention and memory/connection under realistic concurrency |
| Allocations | **MEASURED:** restricted Aurora common paths 0 B/op; method+path 32 B/op | No end-to-end or native zero-allocation claim |
| Scaling | **MEASURED:** admission limit works with one/two workers in tested scenarios | Scaling efficiency, placement, fairness and many-core behavior unknown |
| Resilience | **MEASURED:** write timeout, logger exit, admission rollback/release, parser isolation | Cancellation, drain, startup failure and sustained overload |
| Security | **MEASURED:** release-active bounds, conflicting framing probes, response injection rejection, bounded tested admission and rejection of tested invalid upgrades | Full smuggling/injection/exhaustion audit and secure upgrade lifetime |
| Observability | **MEASURED:** logger exit and raw benchmark evidence | Metrics ownership inaccurate; trace contracts and off/on cost unknown |
| API / DX | **OBSERVED:** common entry retained; admission semantics documented; derived framing hidden | Repeated response fields and input/error semantics remain awkward |
| Documentation | **OBSERVED:** API/spec/test registry match integrated response/admission contracts | Code-derived facts must not be duplicated into competing current state |
| Packaging / release | **OBSERVED:** all three first-party dependencies are source-pinned; WebSocket `v1.0.1` predates the selected fix. **MEASURED:** additional linked WebSocket code in the release HTTP benchmark | DUB single-file fixtures can resolve different transitive versions from the root lock. Investigate why the selected dependency is retained and isolate build profiles; other compiler/platform matrix unknown |
| Compatibility / ecosystem | **MEASURED:** Linux x86-64/LDC 1.42 consumer | DMD, other platforms and independent adoption unknown |
| Debt / complexity | **OBSERVED:** one response owner; admission uses one counter and lexical lifetime | Middleware, metrics, input/error and hijack responsibilities remain distributed |

## Decisions and next discriminator

The opening handshake repair preserves each component's authority. The experiment rules out skipping the socket close while leaving connection accounting at HTTP task exit. B3 stays closed for buffered responses and B4 for the measured admission contract. No new dependency or synchronization primitive was introduced.

**Dominant production uncertainty:** whether a simple, worker-affine ownership boundary can support deferred use without leaking live sockets from connection accounting and shutdown. The existing early close and the untracked lifetime after suppressing it are both reproduced failures.

**Next discriminator, revisable:** repair and verify stream termination after a peer Close in the owning WebSocket layer. For handoff, compare a session that stays under the original connection owner with explicit transfer of the socket and its accounting. Reject any design that cannot demonstrate post-handler operation, 503 at the tested connection cap, release after peer Close or disconnect, and transport termination on stop while the process is alive. A working echo alone is insufficient.

The hosted plaintext admission anomaly remains open and does not explain the upgrade failures. No user decision is outstanding. [The prior canonical state](https://github.com/federikowsky/Aurora/blob/0b226effd8f16ecc666f44f8293b12c7ec874995/docs/ENGINEERING_STATUS.md) preserves earlier experiments. Reacquire refs and reevaluate priorities before changing the lifecycle contract.
