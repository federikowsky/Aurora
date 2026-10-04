# Engineering state and North Star scorecard

**Operational re-baseline: 4 October 2026. Readiness: HOLD.** This file is the single current state/decision register. It is not a linear roadmap. [NORTH_STAR](NORTH_STAR.md) is normative direction; [specs](specs.md) describes architecture; [API](API.md) describes existing contracts; [TEST_REGISTRY](TEST_REGISTRY.md) describes executable checks. Source and revision-qualified raw evidence establish implementation truth.

## Revision and publication boundaries

GitHub metadata was reacquired on 4 October; all four default branches are `main`.

| Repository | Inspected default runtime baseline | Separately published candidate |
|---|---|---|
| [Aurora](https://github.com/federikowsky/Aurora) | `3416660672229179b947e54bf4bfb650309aa38e` | `fdff62d7dc342432bcee3523413199397c98b657` on `codex/north-star-contracts-20260927` |
| [Wire](https://github.com/federikowsky/Wire) | `82b6a5dfd606ebe2ac15c83d9430abdb58aec09b` | `ced07d5c2c07b1c459b62e4e28e1612df2095ae2` on `codex/parser-leases-20260927` |
| [FastjsonD](https://github.com/federikowsky/Fastjsond) | `23a51d692103a0b77cba153afa2994df0c14f4d3` | None assessed |
| [Aurora-WebSocket](https://github.com/federikowsky/Aurora-WebSocket) | `edfbbc6d4e1a7f713a96faa13bebfbb44a51c9d2` | None assessed; Aurora selects package `1.0.1`, not automatically repository HEAD |

The documentation re-baseline changes instructions/docs/build guidance, not these runtime implementations. Its commit and subsequent changes are available in Git history; reacquire the current ref rather than treating this table as a permanently current HEAD. Candidate code is **not integrated** merely because it is described here. Default manifests still select the default Wire revision. Exact other versions belong to `dub.selections.json`.

Latest complete validation cutoff: **2026-10-04T17:02:13Z**, covering from **2026-09-27T19:41:59.786058Z**; verification finished by 17:12:42Z. This documentation audit does not silently advance that full-validation interval. Its source review and checks are additional evidence, not a rerun of every benchmark.

## Evidence ledger

MEASURED = execution/artifact; OBSERVED = inspected code/log; INFERRED = reasoned consequence; UNVERIFIED = missing evidence. A result applies only to its stated path/revision/environment.

| Evidence | Revision / scope | Result and boundary |
|---|---|---|
| [Official Aurora CI](https://github.com/federikowsky/Aurora/actions/runs/30260959571) and [artifact](https://github.com/federikowsky/Aurora/actions/runs/30260959571/artifacts/8650892027) | Aurora default above, 27 July | **MEASURED:** debug/release/unit/protocol/profile steps pass. Artifact downloaded and SHA-256 checked on 4 October: `ec418d72aa0ada2197ee7c8f11a7ae2bed1460c9bb78224703c2970dd302d493`. Not current runtime coverage for untested paths. |
| [4 October raw archive](https://chatgpt.com/api/library/files/libfile_32eb62c4a3288191949348eb51f71a64/download) (owner-authenticated) | Default and candidate; Linux x86-64, LDC 1.42.0 / DUB 1.41.0 | **MEASURED:** default debug/release, 46 modules and protocol 5/5; candidate 48 modules. Archive SHA-256 `fd54ad1968a94f8c1e91dc9abaf15904d752721a095d950413bafc5e8606e985`. Raw commands/environment/results included. |
| Capacity / overlapping request probes, same archive | Default vs candidate, debug/release where applicable | **MEASURED:** default builder writes before supplied slice; candidate passes. Default live requests share mutated parser state; candidate preserves independence. Candidate fixes are not default behavior. |
| Socket contract probes, same archive | Default, one/two workers | **MEASURED:** 302 loses custom/Location/Set-Cookie headers; unmatched CORS preflight 404; max-in-flight 1 admits eight overlapping handlers in one-worker probe. |
| Allocation profile, same archive | Default, five valid processes, selected components | **MEASURED:** parser/raw accessors/router static+inline/builder: 0; method()+path(): 32; HTTPResponse lifecycle/routed-no-I/O: 384 D-GC B/op. Empty first output excluded. No native/E2E zero-allocation claim. |
| [Candidate Wire CI](https://github.com/federikowsky/Wire/actions/runs/36351309939) | `ced07d5c2c07b1c459b62e4e28e1612df2095ae2` | **MEASURED:** 62 tests and consumer link/run. Release assertion coverage differs from debug; do not equate both automatically. |
| [Cycle 3 evidence](https://chatgpt.com/api/library/files/libfile_2a12b96dca5881918c24b21127a27264/download) (owner-authenticated) | 27 September local candidate lineage; exact commands/trees in archive | **MEASURED:** paired/factorial performance showed an unresolved adverse signal; no equivalence claim. SHA-256 `7f71436a6ace2157b7f9bfc9bcb3636cc3f4339821630c2ea20295321cb9791c`. |
| Current documentation/API audit | Source at default and candidate above | **OBSERVED:** 13 Markdown files and 16 support files inspected; public claims, commands, policy dispatch and lifecycle mismatches identified. No new performance conclusion. |

Owner-authenticated evidence is a continuity aid, not a public downloadable guarantee. Public CI/source links remain independently available. Reproduce unavailable raw evidence before relying on a contested conclusion.

Additional re-baseline check: **MEASURED**, the new single-file minimal example recipe compiled with LDC 1.42.0 and returned HTTP 200 plus exactly `Hello from Aurora!` over TCP. Initial offline resolution failed because the package cache was incomplete; online resolution/build then succeeded. This is not a fully empty-cache install, portability or lifecycle certification. `make -n clean test` confirms that clean preserves selections and test selects the ordinary unittest configuration. Local Markdown links and whitespace checks pass.

## Actual capability map

| User journey | Implemented mechanism | Present boundary |
|---|---|---|
| Define endpoint | App + `ref Context` handler, runtime Router | **OBSERVED:** no automatic domain-typed endpoint binding |
| Receive HTTP | Incremental framing + Wire parser + borrowed request views | **MEASURED:** selected fragmented/malformed framing checks; default parser lifetime and output bounds defects remain |
| Select route | Method/static/parameter/wildcard precedence and backtracking | **MEASURED:** unit cases; complete normalization and concurrent mutation **UNVERIFIED** |
| Decode/validate input | FastjsonD-backed mapper; UDA validation; separate std.json middleware mapper | **OBSERVED:** different defaults/error policies; silent field conversion failure; no unified automatic contract |
| Apply policy | App middleware pipeline on matched routes | **OBSERVED:** Router.use storage not dispatched; misses bypass global pipeline; auth/RBAC examples are not built-in audited facilities |
| Produce output | Context helpers and HTTPResponse | **MEASURED:** status/body/content type work in probes, other headers disappear in Server serialization |
| Upgrade/stream | Context hijack/SSE/WebSocket adapters | **OBSERVED:** post-handler connection ownership is contradicted by outer cleanup; complete live semantics **UNVERIFIED** |
| Observe/control lifecycle | Hooks, logger, counters, traces, limits, worker coordination | **MEASURED/OBSERVED:** specific metrics/lifecycle/admission defects; module presence does not prove correctness |
| Install/extend | DUB source graph, small App entry point, advanced public modules | **OBSERVED:** no Aurora GitHub tags/releases at audit; DUB metadata request now blocked by HTTP 403. Clean registry install/support minima **UNVERIFIED** |

## Open problems and discriminating evidence

These are current findings, not an execution sequence. Reconfirm against the next inspected SHA.

| ID / owner | Finding / evidence strength | Closure evidence |
|---|---|---|
| B1 Aurora HTTP | **MEASURED:** insufficient output slice corrupts canary on default; bounded-write fix exists in candidate | Integrate a reviewed correct builder with capacity matrix, release/debug checks, framing and measured cost; never restore unsafe writes for speed |
| B2 Wire | **MEASURED:** simultaneous live request wrappers alias native parser state; candidate lease fix exists | Validate selected public pin, consumer lifetime/failure/cleanup and native costs; integrate in owning repository then consumer |
| B3 Aurora response boundary | **MEASURED:** application headers lost in success and error paths | Complete response contract at socket, framing/header precedence/injection/duplicates/lifetime; control payload and allocation measurements |
| B4 Aurora admission | **MEASURED:** configured limit ineffective; **OBSERVED:** scope-exit releases before dispatch | Hold reservation for defined request lifetime; verify concurrent rejection, every exit/error, reuse and disabled cost |
| B5 Aurora middleware | **OBSERVED:** scoped middleware unused; unmatched requests bypass global pipeline | Explicit composition/miss semantics and live policy/order tests; no new hook family by default |
| B6 Aurora lifecycle | **OBSERVED:** hijack outer close, polling coordination and weak startup failure propagation; historical logger SIGSEGV **MEASURED** at `3416660` in the [13 September archive](https://chatgpt.com/api/library/files/libfile_78e3f51376b0819191ea59caa987559e/download), not rerun in this audit | Ownership and stop/drain/start-failure tests; reproduce logger with stack before attributing exact cause |
| B7 Aurora metrics | **MEASURED** historically: multi-worker request getter stays zero; **OBSERVED:** readers/writers use different counters | One authoritative accounting path and live request/error/rejection/timeout assertions |
| B8 Aurora input/errors | **OBSERVED:** silent field failures, two mapper policies, duplicate exceptions, middleware catches downstream errors as 400 | Explicit strict/default/null/overflow/error contract and migration; preserve domain failures |
| B9 Aurora low-level handler | **OBSERVED:** ResponseBuffer passed by value and caller reads original | **INFERRED:** simple-handler output can be lost; socket reproduction required before claiming runtime failure |
| B10 tooling/coverage | **OBSERVED:** legacy config paths, Docker failures tolerated, Autobahn port/build mismatch, dormant candidate hooks | Repair the selected workflow/fixture with actual execution; do not count dormant scripts as coverage |

`queueRequest` remains a TODO with 503 fallback; compression's gzip branch uses zlib framing; buffer retention, optional-feature overhead and full security/compliance remain open. These source findings must not be advertised as complete capabilities.

## Multidimensional scorecard

| Dimension | Established evidence | Dominant unknown / next useful discriminator |
|---|---|---|
| Correctness | **MEASURED:** unit/probe passes plus B1–B4 failures | Whether all public dispatch paths preserve their contracts |
| Protocol | **MEASURED:** five framing/deadline probes | **UNVERIFIED:** comprehensive HTTP/upgrade/fuzz/differential compliance |
| Performance | **MEASURED:** component and HTTP samples; candidate adverse signal | **UNVERIFIED:** comparable production workload superiority / causal regression |
| Tail behavior | **MEASURED:** existing wrk distributions/errors | **UNVERIFIED:** controlled arrivals, p99.9, overload SLOs |
| CPU efficiency | **OBSERVED:** polling, copies, repeated representations | Valid attribution; 4 October /proc CPU accounting was invalid and excluded |
| Memory efficiency | **OBSERVED:** per-thread pools, borrowed views, native parser leases | **UNVERIFIED:** RSS/connection, retention, churn and exhaustion |
| Allocation behavior | **MEASURED:** selected 0/32/384 D-GC B/op | Native + network + middleware/error total; no whole-server zero allocation |
| Scalability | **MEASURED:** traffic on multi-worker configurations | **UNVERIFIED:** scaling efficiency, fairness, contention |
| Resilience | **MEASURED:** timeout/retirement checks; ineffective admission | B4/B6, cancellation, drain, sustained failures |
| Security | **MEASURED:** bounds defect and missing security headers | **UNVERIFIED:** complete audit, dependency vulnerabilities, exploitation scope |
| Observability | **OBSERVED/MEASURED:** counters/lifecycle diverge | Accurate events and enabled/disabled overhead |
| API quality | **OBSERVED:** small App entry point; contract gaps | Semantics and safe ownership before new convenience APIs |
| Developer experience | **OBSERVED:** obsolete commands and fictional API removed from guides | Clean install-to-service, inspection, diagnosis and migration measured with users |
| Documentation | **OBSERVED:** one source map; historical plans retired | Keep docs/code synchronized by executable examples and contract checks |
| Packaging/release | **OBSERVED:** no Aurora tag/release; exact dependency selections | **UNVERIFIED:** public package delivery, clean toolchain matrix |
| Compatibility | **MEASURED:** LDC 1.42 / Linux x86-64 evidence | Other compilers/platforms, versioned public API policy |
| Ecosystem readiness | **OBSERVED:** four first-party owners and dependencies mapped | Consumer integration/release path, actual adoption, third-party interoperability |
| Technical debt | **OBSERVED:** dormant knobs/scripts and lifetime issues | Close verified contract gaps before expanding surface |
| Accidental complexity | **OBSERVED:** duplicated response/counter/input models | **INFERRED:** single ownership can remove mechanisms; prove each change separately |

## Decisions and current hypotheses

**Confirmed direction:** preserve App/Context as the current common path; preserve first-party dependencies; keep existing framer/router/runtime until evidence justifies replacement; distinguish raw borrowing from convenience ownership. This is not a claim these components are optimal.

**Changed by the DX mandate:** public availability is not capability completion. A small API with implicit wrong behavior is not simple. Correctness at response/policy/lifetime boundaries can improve capability, safety, DX and inspectability simultaneously, without adding a subsystem. Do not implement fictional documented APIs to rescue stale documentation.

**Open alternatives:** reuse a complete existing response serializer versus converge writers on a shared bounded primitive; initialization-time policy composition versus runtime composition; explicit strict input entry point versus a versioned stricter default; existing event/synchronization primitives versus continued polling. None is selected merely by this list. Runtime/router rewrites and new subsystem catalogs lack discriminating evidence.

**Next-choice criterion:** first close a reproducible correctness/lifetime defect with high confidence, small semantic scope and broad user benefit, while investigating candidate integration risk. B4 is a bounded hypothesis with a precise lifetime cause; B1/B2 remain safety blockers and B3 has wider security/API impact. Choose again after the next experiment instead of treating these sentences as a roadmap. New feature design is premature while foundational contracts mislead users.

## Historical evidence, superseded direction and document inventory

The immutable [baseline tree](https://github.com/federikowsky/Aurora/tree/3416660672229179b947e54bf4bfb650309aa38e) preserves every replaced original. No evidence needs a duplicate `docs/history` tree.

| Files | Disposition / authority |
|---|---|
| README, AGENTS | Rewritten entry point and working rules; no duplicated architecture/results catalog |
| docs/specs.md, docs/API.md, docs/TEST_REGISTRY.md | Replaced mixed historical claims with current architecture, contracts and execution guidance |
| [plan.md](https://github.com/federikowsky/Aurora/blob/3416660672229179b947e54bf4bfb650309aa38e/plan.md), [ROADMAP](https://github.com/federikowsky/Aurora/blob/3416660672229179b947e54bf4bfb650309aa38e/docs/ROADMAP.md) | Removed from current tree; historical intent only, no normative priorities |
| CHANGELOG | Current unreleased changes; earlier release prose linked as historical claims, not verified releases |
| examples/README, benchmarks/README, benchmarks/comparison/README, tests/realworld/README | Narrow local guidance; unsupported recipes/results explicitly historical |
| .github/validation-trigger.txt, .gitmodules | Retired stale trigger/submodule metadata; no gitlinks existed, DUB is dependency authority |
| DUB manifests, workflows, tests, source | Executable authority for versions/selection/behavior; known stale paths and coverage limits remain explicit |
| Makefile, legacy Docker/realworld/Autobahn tools | Build convenience or experimental tools, not independent release/test authority |
| External North Star and scorecard entry files | Redirect to this repository; no competing normative copy or appended “current” histories |

Dated reports, old checkout instructions and previous roadmap choices are **historical evidence**. Hypotheses above are **open**, not decisions. The North Star/AGENTS are **normative**; code plus tests are **current implementation truth**. A later result can invalidate a hypothesis or supersede an implementation description without rewriting historical raw measurements.
