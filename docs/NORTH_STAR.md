# Aurora North Star

Normative product direction, consolidated from the owner's mandates of 27 September and 4 October 2026. This is the repository source of truth for architectural decision criteria, not a feature roadmap. Current user instructions and actual access controls retain precedence. Operational instructions live in [AGENTS.md](../AGENTS.md); implementation state lives in [ENGINEERING_STATUS.md](ENGINEERING_STATUS.md).

## The outcome

Make Aurora the natural first choice, ideally the de facto standard, for HTTP/REST backends in D. Leadership must emerge from the complete product: exceptional real performance and efficiency, correctness, robustness, security, predictable load behavior, API quality, simplicity, developer experience, maintainability, observability, interoperability, scalability, portability where sensible, compatibility and adoption.

These are simultaneous quality dimensions, not an ordered feature list. No aggregate score may hide a material regression. The FastAPI analogy concerns adoption only. Do not use it, Python, vibe.d, serverino, Hunt or another framework as an architectural template. Learn from demonstrated strengths and failures, then design for D's types, compiler, compile-time facilities, runtime and ecosystem.

## Surface, semantics and machinery

**Maximum capability with minimum exposed complexity and minimum necessary internal complexity.**

**Simple surface. Powerful core. Minimal machinery. Explicit semantics. Progressive control. Pay only for what you use.**

Developer experience is architectural. Minimize the framework knowledge required to build correct, high-performance applications. Common paths should express domain logic; automate mechanical, predictable plumbing. A typed endpoint returning a domain value is a design possibility, not a requirement to implement now.

**Explicit semantics, implicit plumbing:** automated behavior must remain deterministic, understandable and inspectable. Users must be able to discover where values came from, what decoding/normalization/validation occurred, why a route or handler was selected, what policy/middleware acted, why input was rejected, how the response was produced and where to change behavior. Convenience must not conceal silent coercion, errors, ownership or lifetime.

Prefer small orthogonal primitives and strong composition over large option/hook surfaces. Offer progressively available control: convenient API, configuration/policy, replacement or extension, direct capability APIs and low-level HTTP/runtime access where useful. These are user needs, not a mandate for five implementation layers. An advanced case must not require abandoning the framework or burden every common case.

Discover cohesive subsystem boundaries from real journeys and responsibilities—endpoint definition, input processing, authorization, domain work, output, errors, diagnosis. Do not start by building named boxes. Binding, decoding, normalization, coercion and validation may or may not belong together; evidence and the simplest complete model decide. Every abstraction, engine, hook and policy must earn its cost.

Use static knowledge and compile-time work when they improve type safety and eliminate runtime discovery or repeated work. Count compilation time, binary size, specialization bloat, diagnostics and maintenance as costs too. Optional features should impose zero or negligible measured cost when unused; their presence in the distribution must not silently enlarge the minimal request path.

## Elegance and multi-objective decisions

Elegance means solving the whole problem with the least accidental complexity compatible with its requirements. Prefer clear ownership, explicit dependencies, cohesive responsibilities, compact readable code and few states/conversions/copies/lifecycles. Apply SOLID, DRY, SRP and separation of concerns idiomatically, without ceremony or abstractions imported mechanically from other languages.

Before optimizing a mechanism, ask whether it should exist. Before a cache, ask why work is repeated; before a pool, why allocation is necessary; before an adapter, whether boundaries we own can agree directly. Localize complexity that genuinely buys necessary capability. Simplicity does not mean fewer useful features or code golf.

All implementation choices, public APIs and historical decisions are revisable; sunk cost is not a reason to preserve them. Rewrite only to solve a real problem or demonstrate net benefit. Repeated workarounds, duplicate representations, implicit states and difficult lifecycle coordination trigger a global review, not endless local patches.

Seek Pareto improvements. For a real trade-off, state it, measure benefits/costs across relevant workloads, seek a third option and document the chosen impact. Select each next intervention by expected global value: benefit and confidence, dimensions improved, regression risk, implementation/maintenance cost, reversibility, dependencies, complexity and future work unlocked. Never follow a historical roadmap by inertia.

## Real performance and evidence

Aim to compete with the strongest relevant implementations in D and other ecosystems where comparison is technically meaningful. Investigate a demonstrated gap down to its causes, including dependencies and kernel paths. Do not accept “more features” as an unmeasured explanation or a library boundary as the end of profiling.

Benchmarks measure the product; they do not specify it. No benchmark-only code paths, removed protections, artificial production configurations, biased workloads, handicapped competitors, selective reporting or overfitting. PGO/LTO/CPU specialization are valid when deployable, declared and fairly compared. Include holdout workloads. Independent benchmarks such as TechEmpower are possible external validation, not a prescribed next feature.

Use the measurement level that discriminates the decision: micro/component/end-to-end, realistic input and middleware, concurrency/scaling, stress/soak/overload/failure paths and platform coverage. Measure useful throughput, tail latency, CPU/request, cycles/instructions, allocations, RSS/connection, copying, syscall/scheduler/contention/cache costs as relevant. Per-watt claims need actual energy evidence. Observe errors and saturation, not only successful averages.

For a sensitive change: hypothesis and falsifier; frozen baseline; isolated change; repeated compatible measurement; correctness and control workloads; explicit cost/benefit decision. Keep raw output, environment, command and exact revisions. A noisy run is not an improvement. Distinguish MEASURED, OBSERVED, INFERRED and UNVERIFIED; label incompatible timing comparisons NON-COMPARABLE or INDICATIVE.

Zero D-GC is a property of a specified measured path, not the framework. Distinguish GC/native/stack allocation, pooling, reuse, amortization, zero-copy, copy minimization and ownership transfer. Include/exclude warm-up, harness, initialization, logging, exceptions and I/O explicitly. Zero collections with GC disabled proves neither zero allocation nor pause-free production operation.

## Correctness, security and operation

Incorrect requests, dropped connections, hidden failures or removed safeguards are not performance wins. Validate protocol semantics, framing and ambiguous headers, size/encoding boundaries, malformed/fragmented input, upgrade, trust boundaries and exhaustion against applicable standards and executable checks.

Make ownership and lifetimes explicit across request buffers, output, sockets, asynchronous work and shutdown. Distinguish validation, infrastructure and programming errors, recovery and termination. Avoid silent fallback that changes the public contract. Protect secrets and integrity with least privilege.

Evaluate partial I/O, slow clients, churn, cancellation, deadlines, fairness, races, bounded queues/resources, overload and graceful degradation. Retry/circuit breaker/rate limit mechanisms are warranted by actual needs, not by a checklist. Logging, metrics and tracing must be useful, accurate and have measured enabled/disabled costs.

## Ecosystem, reuse and compatibility

Aurora, Wire, FastjsonD and Aurora-WebSocket form one first-party architectural system. Wire, FastjsonD and Aurora-WebSocket are permanent strategic dependencies: use, maintain, test, simplify and improve them. Their boundaries and implementations remain evolvable. Correct defects in the owning repository; avoid permanent Aurora workarounds. Give each important responsibility one authoritative owner.

For other dependencies, reuse first. Seriously assess D/Phobos/runtime, compiler facilities, OS APIs and mature native libraries before significant custom networking, scheduling, synchronization, allocation, codecs or other mechanisms. Compare correctness, maturity, maintenance, runtime/build cost, portability, API, licensing, security and supply chain. Prefer reuse that removes machinery; do not accept a demonstrated bottleneck or add a heavy library for a trivial benefit. Custom code needs a concrete advantage unavailable through reasonable reuse.

Review the D ecosystem and toolchains periodically. Treat semantic versions, deprecation, migrations, reproducible packaging, release notes and compiler/platform support as product contracts. A beneficial breaking change requires rationale, impact, alternatives, migration and a version strategy. Do not promise compatibility based only on a successful build on one machine.

## Continuity and success

Keep one multidimensional scorecard in ENGINEERING_STATUS: correctness, protocol, performance/tail, CPU/memory/allocation efficiency, scaling, resilience/security, observability, API/DX, documentation, packaging/compatibility/ecosystem, debt and accidental complexity. Each area distinguishes evidence from unknowns; no synthetic total score.

Source code and pinned executions establish present behavior. Current documentation explains contracts and limits. Historical reports preserve evidence; open hypotheses carry falsifiers; obsolete directions are not instructions. This main conversation coordinates architectural continuity, but code and current files must suffice to resume without old chat summaries.

Success means that the complete system makes it difficult to find a compelling technical reason to prefer another D solution for most modern HTTP/REST backends. Preserve that objective, not any particular technique or current design. No sentence here is permission to introduce unnecessary machinery.
