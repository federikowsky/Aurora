# Working on Aurora

## Read before changing the project

1. [North Star](docs/NORTH_STAR.md): permanent product and engineering criteria.
2. [Engineering state](docs/ENGINEERING_STATUS.md): revision-qualified capabilities, evidence, unresolved problems and hypotheses.
3. [Current architecture](docs/specs.md), [public contracts](docs/API.md) and [validation guide](docs/TEST_REGISTRY.md), as relevant to the task.

Code, manifests and executable tests are authoritative for implementation. Documentation must describe their limitations, not replace inspection. A candidate branch, successful component test or historical report is not evidence that a fix is integrated or a public contract works end to end. Reacquire GitHub metadata and the actual default branch; pin every repository, dependency, execution and artifact to its revision.

## Decision discipline

Start from the user journey and the observed problem. Prefer small orthogonal primitives, explicit semantics, inspectable behavior and progressively available control. Minimize both exposed complexity and necessary internal machinery. Do not create subsystem boxes, policies or hooks because the North Star mentions them. Do not impose a typed endpoint API, compile-time routing or a runtime rewrite without comparative evidence.

Reevaluate priorities after material findings. Close correctness and memory-safety defects in their owning component; do not follow a historical TODO sequence. Explore credible alternatives, including eliminating the mechanism. Use D, Phobos, runtime, OS and established libraries before substantial custom code. Preserve useful working choices when no better choice is demonstrated.

Aurora, Wire, FastjsonD and Aurora-WebSocket are the first-party ecosystem. The latter three are permanent strategic dependencies, with evolvable internals/APIs; repair their responsibilities in their repositories. Other dependencies are tools to evaluate, not permanent constraints.

## Authority and safe execution

The owner has authorized autonomous engineering, testing, documentation, commits, publication and technically justified integration across these four repositories, including scheduled maintenance. Old read-only reports are historical, not current restrictions. Do not ask again for work already authorized. Respect actual credentials, branch protections and current user instructions; never bypass them. Do not infer authorization for production changes, destructive history rewriting, extraordinary spending or unrelated repositories.

Use an isolated branch/worktree and preserve others' changes. An ordinary PR is not required unless repository rules require it. Publish validated, reviewable changes without force-updating shared history. A release is a separate readiness decision: CI success alone does not establish production readiness. Report local/published/integrated/released state separately.

## Verification and evidence

Derive commands from manifests/workflows and [TEST_REGISTRY](docs/TEST_REGISTRY.md). For behavioral changes, reproduce the defect first and add a regression check at the failing contract boundary; assertions on helpers alone do not prove socket behavior. Test applicable debug/release paths and failure/cleanup paths. Keep scope proportional; documentation-only edits require link/claim/snippet checks, not indiscriminate performance reruns.

For performance-sensitive changes, freeze a representative baseline and falsifier, vary one causal factor, measure correctness plus relevant costs and control workloads, then accept or reject. Record exact command, source/patch identity, dependency pins, clean/dirty state, environment, compiler/build flags, input, warm-up, repetitions, GC/profiler and raw results. Separate D-GC/native/stack/reuse and setup/runtime. Compare only compatible configurations; report dispersion and errors. Never recover a score by restoring incorrect behavior.

Tag important conclusions MEASURED (execution/artifact), OBSERVED (inspected code/log), INFERRED (reasoning), UNVERIFIED (insufficient evidence). Do not treat a claim in a comment, filename or old report as proof.

## Keep continuity small

Update the existing document that owns the fact. ENGINEERING_STATUS owns the current scorecard, open problems and decision hypotheses; do not add parallel TODO/roadmap/handoff files. Git history and dated evidence preserve superseded material. Never prepend another competing “current” state above an old current state. Keep durable raw evidence linked by revision and digest where possible. Historical plans confer no priority or permission.

The main conversation coordinates continuity; the repository must remain sufficient to resume without that conversation. The scheduled task and external context files are entry points to this repository, not independent architectural authorities. At completion reconcile them, report what changed and what remains unknown, and select the next intervention from evidence.
