# Change history

## Unreleased — 18 October 2026

- Hold Server-wide request admission through dispatch and response writing; roll back rejection before writing 503. Previously the configured limit was ineffective. Applications must size it as a total Server budget, not per-worker. Add debug/release socket regression coverage.
- Expose canonical benchmark worker/admission settings and collect controlled A/A–A/B evidence with process CPU, output checks and raw errors.

- Own the process-wide logger mutex and normal shutdown at module scope; join/drain the daemon before runtime finalization. Add debug/release process-exit and concurrent-first-access checks.

- Return immediately when `buildResponseInto` capacity is exhausted to prevent integer-wrap writes before an undersized output slice. Document partial-output semantics; test capacity, framing and ownership in debug/release.
- Run the bounded-response contract in release in CI, using the configured `DUB_HOME` directly.

- Consolidate product direction, explicit semantics and progressive control in `docs/NORTH_STAR.md`.
- Establish one current architecture, public-contract guide, validation guide and engineering state.
- Replace inaccurate readiness, package, API and performance claims with revision-qualified evidence and limitations.
- Retire the old linear plan/roadmap as current instructions; preserve their immutable Git history.
- Provide an executable single-file DUB recipe for the minimal example and build it in CI.
- Keep dependency selections during `make clean` and align `make test` with CI selection.

This is not a release announcement. No Aurora GitHub release/tag or supported semantic-version package is established by this change. The previous changelog used release labels and coverage/performance claims that were not backed by corresponding publication metadata.

The full earlier history is preserved [at the inspected baseline](https://github.com/federikowsky/Aurora/blob/3416660672229179b947e54bf4bfb650309aa38e/CHANGELOG.md). It records historical intent and claims, not current normative contracts. New release entries must link an actual tag/commit, tests, compatibility/migration information and evidence.
