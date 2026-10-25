# Engineering state and North Star scorecard

**Current assessment: 25 October 2026. Production readiness: HOLD.** This is Aurora's sole current scorecard and decision register. It is evidence, not a task sequence. [NORTH_STAR](NORTH_STAR.md) and [AGENTS](../AGENTS.md) govern direction and work; [specs](specs.md), [API](API.md) and [TEST_REGISTRY](TEST_REGISTRY.md) describe current architecture, contracts and test selection. Code, selected dependencies and pinned executions win when prose diverges.

## Revisions and reporting boundary

GitHub metadata was reacquired on 25 October; the actual default branch of every first-party repository is `main`.

| Repository | Current default / selected revision | Boundary |
|---|---|---|
| Aurora | `15ccc3b1b9b17ec2d225b010045b63dab4e2342b` | [PR #8](https://github.com/federikowsky/Aurora/pull/8) selects the integrated Wire ownership repair in both DUB files and adds a consumer regression |
| Wire | `6c5965eb71dbe81a9abc74832bf7a8020835ae5b` | [PR #3](https://github.com/federikowsky/Wire/pull/3) gives every live wrapper an exclusive parser lease; same SHA selected by Aurora |
| FastjsonD | `23a51d692103a0b77cba153afa2994df0c14f4d3` | Same exact SHA selected; no change this cycle |
| Aurora-WebSocket | `edfbbc6d4e1a7f713a96faa13bebfbb44a51c9d2` | Aurora selects package `1.0.1`, not automatically repository HEAD; no change this cycle |

**Complete reporting interval: 2026-10-18T04:59:13Z → 2026-10-25T05:55:51Z**, Aurora default `87f9ee3f931329f49ff8f2e560613697f540d327` → `76fadb5cd35a9fb959ab2f70d77fd551de1ba84e` at the cutoff. Commits `98b66b1`, `099a466` and `76fadb5` after the preceding cutoff complete benchmark-control integration and state reconciliation. There were no later pre-cutoff commits, materially changed issues, releases or first-party dependency defaults.

Wire and Aurora publications on 25 October after the cutoff are current-cycle outputs and become the operational baseline above. Complete reporting means the declared scope was examined; it is not certification of all platforms, protocol cases or failure modes.

## Evidence ledger

MEASURED = direct execution/artifact; OBSERVED = inspected code/log; INFERRED = consequence reasoned from evidence; UNVERIFIED = insufficient evidence. Historical results are not fresh checks.

| Evidence | Pinned scope | Result |
|---|---|---|
| Wire lifetime suite on old source | `82b6a5dfd606ebe2ac15c83d9430abdb58aec09b` | **MEASURED, red:** ordinary 55 tests pass, but five of seven added lifetime cases fail: overlapping live wrappers, non-LIFO reuse, move/replacement, incomplete-input isolation and error isolation |
| Wire candidate and integrated suite | candidate `e40d6e853daea170321d5327e04d255025bf5777`, merge `6c5965e` | **MEASURED:** 62/62 tests, debug/release build and downstream link smoke pass; candidate and merge Actions succeed |
| Aurora consumer gates | source tree from PR #8, exact Wire `6c5965e` | **MEASURED:** debug/release builds; 47 modules; logger 400/400 exits; release response contract; minimal example; protocol 5/5; benchmark configuration; allocation and microbenchmark executables pass |
| [Aurora PR CI](https://github.com/federikowsky/Aurora/actions/runs/40168946679), [artifact 12590011772](https://github.com/federikowsky/Aurora/actions/runs/40168946679/artifacts/12590011772) | PR head `4d0ea47f04bfaf9efb5fdfb6e22acbb0fa9a24d2` | **MEASURED:** all jobs pass; artifact digest `sha256:4b49fecf8965e9d7f1646052abb80d1b5ffd9aa06acceb283269567edbeaf557` |
| Sequential Wire native allocation counter | old vs integrated implementation, 20,000 warm-up then measured loop | **MEASURED:** both report zero `calloc` and zero `free` during sequential measurement |
| Three simultaneously live parsers | 1,000 repetitions | **MEASURED:** old source allocates zero by incorrectly aliasing; repaired source reports 6,000 `calloc` and 6,000 `free`, corresponding to two additional live native parser instances per repetition and their internal allocations |
| Wire parse timing | 7×3M and 10×10M iterations, pinned CPU, alternating binaries | **MEASURED, INDICATIVE:** medians differ by about 1–5%, but CV reaches 29.5% and paired outliers reach 1.95; no reliable regression or improvement claim |
| Aurora allocation profile | exact new pin, 10,000 warm-up / 100,000 measurement | **MEASURED:** established 0/32/384 D-GC B/op scopes unchanged; zero native-allocation claim is not made |
| Previous admission evidence | default `76fadb5`; open [PR #7](https://github.com/federikowsky/Aurora/pull/7) head `e811528aec5a54e4304729b41180934ec2736201` | **MEASURED, historical:** correction passes functional gates; performance acceptance remains unresolved, so it is not integrated |

The dated raw evidence archive preserves commands, environment, red/green logs, benchmark rows, counter harness and patches. GitHub Actions and artifacts above are the public primary evidence. Do not promote conversational summaries to implementation proof.

## Decision: parser ownership corrected at its authoritative owner

**OBSERVED:** old Wire `parseHTTP` reset and reused one thread-local native parser while an earlier `ParserWrapper` could still be alive. A later parse therefore overwrote the earlier wrapper's method, target, body, completion and error state. Aurora could not repair that without copying or duplicating parser ownership.

The integrated design gives each live wrapper an exclusive parser lease. A thread holds at most one idle parser: acquisition detaches it; release caches it on the releasing thread or frees it if the slot is occupied. Thread exit frees only the idle parser. Moves and cross-thread release are covered. Parsed field views still borrow the caller's input bytes.

Alternatives pruned:

- a global pool adds contention and lifecycle machinery to the sequential fast path;
- copying parsed requests adds representation, copies and allocation at the wrong boundary;
- allocating every parse discards proven sequential reuse;
- a bounded free list adds state to optimize uncommon overlap before workload evidence justifies it.

The chosen design preserves zero native allocation after warm-up for sequential parsing and pays native allocation only for additional simultaneously live parsers. That is explicit ownership rather than a general zero-allocation claim. Wire is the authoritative owner; Aurora adds only a consumer contract and exact dependency selection.

## Current capabilities and open contracts

| Area / owner | Established | Remaining gap |
|---|---|---|
| Endpoint/API/DX | **OBSERVED:** `App` + `ref Context`, runtime routing and common entry remain small | No automatic domain-typed binding; its value and semantics require user-journey evidence |
| B1 output capacity / Aurora | **MEASURED:** bounded writer and release checks pass | Not proof of complete response/framing behavior |
| B2 request lifetime / Wire | **MEASURED:** independent live parsers, non-LIFO/move/thread/error/incomplete isolation; Aurora consumer green | Input bytes remain borrowed; cold/overlap native allocation and memory bounds beyond tested cases remain workload-dependent |
| B3 response boundary / Aurora | **OBSERVED:** runtime forwarding can lose application headers; historical socket failure | One authoritative emission contract for headers, framing, injection, HEAD/204/304 and errors |
| B4 admission / Aurora | **MEASURED:** distributed default still fails held-request limit; candidate functionally green | Candidate cost acceptance unresolved; not integrated |
| B5 middleware/router / Aurora | **OBSERVED:** `Router.use` is stored but not dispatched; misses bypass parts of the pipeline | Explicit policy/order/miss/subrouter semantics |
| B6 lifecycle / Aurora | **MEASURED:** normal logger teardown passes 400 checks locally and in CI | Hijack outer cleanup, polling, startup failure, cancellation/drain/abrupt/concurrent teardown |
| B7 metrics / Aurora | **OBSERVED:** Server writes and WorkerState getters have different ownership | One accounting owner and live request/error/413/431/timeout assertions |
| B8 input/errors / Aurora + FastjsonD | **OBSERVED:** silent field failure, separate mapper policy and downstream errors mapped as 400 | Explicit input/domain/infrastructure semantics and migration |
| B9 low-level handler / Aurora | **OBSERVED:** `ResponseBuffer` is passed by value | Output loss is **INFERRED** pending a socket reproduction |
| B10 tooling/portability | **MEASURED:** canonical worker/limit flags and response controls | Empty-cache install, DMD/other OS, stress/real-world/Autobahn remain **UNVERIFIED** |

`queueRequest` remains a TODO/503 fallback. The previous gzip/zlib framing finding remains open. Parser/router unit tests pass inside the 47-module suite; complete RFC/security audit, sustained fuzzing, router mutation/concurrency proof, trace propagation, observability off/on cost and soak/overload certification do not exist.

## Allocation and performance boundaries

Aurora's fresh exact-pin profile retains these D-GC measurements: parser core, keep-alive, raw accessors, static/inline-parameter router and preallocated response builder 0 B/op; `method()+path()` 32 B/op; response lifecycle and routed request without I/O 384 B/op. Initialization, network, logging, exceptions, native allocation, Wire cold/overlap leases, pool misses and overflow are excluded. GC was collected then disabled during measurement; zero collections in that interval do not prove production pause freedom. LDC AOT was used; no JIT or cross-compiler claim applies.

The Wire benchmark is a component test without network, one thread, one pinned CPU, `-O3 -release -enable-inlining`, a 15-byte JSON POST request and wrapped libc `calloc/free`. Large timing variance falsifies a precise small-delta conclusion. It does prove the ownership/allocation shape: sequential reuse remains allocation-free after warm-up, while additional live parsers require native storage.

## Multidimensional scorecard

| Dimension | Proven / observed | Unknown / deficient |
|---|---|---|
| Correctness | **MEASURED:** 47 modules, response capacity, logger, independent parser lifetime | B3 response and B4 default admission; other dispatch boundaries |
| Protocol | **MEASURED:** 5 socket framing/retirement/deadline probes | Exhaustive encoding, framing, upgrade and fuzzing **UNVERIFIED** |
| Performance / tail | **MEASURED:** component and historical HTTP evidence with raw dispersion | No stable regression gate; open-loop saturation and controlled-arrival tails unknown |
| CPU efficiency | **MEASURED:** historical calibrated whole-process CPU/request; Wire component timing | Steady-state attribution, cycles/instructions/syscalls/locks **UNVERIFIED** |
| Memory efficiency | **MEASURED:** sequential/overlap native allocation shape; process peak RSS historically | Native bytes, retention and memory/connection under realistic concurrency |
| Allocations | **MEASURED:** restricted Aurora 0/32/384 D-GC B/op; Wire libc call counts | No end-to-end zero-allocation claim |
| Scaling | **MEASURED:** selected one/two-worker contract/cost runs | Scaling efficiency, placement and fairness not established |
| Resilience | **MEASURED:** write timeout, logger exit, parser error/incomplete isolation | Default admission, cancellation, drain, startup failure and soak |
| Security | **MEASURED:** release-active output bounds and conflicting-framing probes | Header loss, full request-smuggling/injection/exhaustion audit |
| Observability | **MEASURED:** logger exit; historical calibrated CPU evidence | Metrics ownership inaccurate; trace contracts and off/on cost unknown |
| API / DX | **OBSERVED:** common entry retained; parser ownership hidden behind existing API | Existing response/input semantics remain hard to explain reliably |
| Documentation | **OBSERVED:** ownership and allocation caveats reconciled in one current owner | Future changes must keep code-derived facts out of duplicate prose |
| Packaging / release | **MEASURED:** both Aurora Wire pins select exact integrated SHA | Wire source is integrated but no `v1.0.5` tag/release exists; clean-install matrix unknown |
| Compatibility / ecosystem | **MEASURED:** Linux x86-64/LDC 1.42 consumer | DMD, other platforms and independent adoption unknown |
| Debt / complexity | **OBSERVED:** repair removed aliasing without an Aurora adapter or runtime layer | Duplicate response, metrics and input/error responsibilities remain |

## Decisions and next discriminator

The North Star continues to favor correction of authoritative boundaries over a rewrite, new subsystem or convenience veneer. B2 is closed at Wire and integrated by Aurora. No responsibility moved to FastjsonD or Aurora-WebSocket, and no external dependency or custom allocator was introduced.

**Dominant product-level correctness uncertainty:** the actual Aurora response emission contract. Header loss can break cookies, CORS, cache policy, security headers and middleware semantics in the common HTTP path. It competes with the known default admission defect; admission already has a functionally validated candidate whose cost gate needs a more discriminating environment, while B3 still lacks a minimal current socket reproduction and clear ownership decision.

**Next highest-value intervention, revisable:** freeze and reproduce the response boundary end to end, then establish one authoritative header/framing/ownership contract across `HTTPResponse`, builder and runtime write for ordinary, HEAD, 204, 304, errors and duplicate/injection cases. First falsifier: if current `main` preserves application headers and correct framing across that matrix, deprioritize B3 and return to admission profiling. Do not redesign the representation or add typed-handler machinery before the socket evidence identifies the owner and cost.

No user decision is outstanding. Wire's next release tag remains an operational packaging action once a release-capable credential/tool is available; lack of a tag does not reopen the integrated source correction.

[Prior canonical state](https://github.com/federikowsky/Aurora/blob/76fadb5cd35a9fb959ab2f70d77fd551de1ba84e/docs/ENGINEERING_STATUS.md) preserves earlier experiments and decisions. History is evidence, not a second current scorecard. Reacquire refs and contested measurements before the next decision.
