# Current architecture and ownership

Descriptive, not a future specification. Runtime inspected at Aurora `3416660672229179b947e54bf4bfb650309aa38e`, documentation baseline `3ef10f35acb701f3c7ee180df5b56482ab2a07b5`, and bounded-writer fix `414d2f83420bdac605cadc5c98338ce61fd6c6f2` on 4 October 2026. The older combined candidate remains separate. Candidate differences are explicit in [ENGINEERING_STATUS](ENGINEERING_STATUS.md). Code at the checkout revision wins over this map. Principles belong to [NORTH_STAR](NORTH_STAR.md); public behavior and caveats to [API](API.md).

## Request journey

1. [App](../source/aurora/app.d) collects routes, a global middleware pipeline, configuration, hooks and exception handlers. `listen()` constructs/configures `Server` and enters its runtime.
2. [Server](../source/aurora/runtime/server.d) uses vibe-core networking and tasks; [WorkerPool](../source/aurora/runtime/worker.d) manages the multi-listener worker path. Linux/FreeBSD code uses SO_REUSEPORT. Other paths exist but are not a tested support promise.
3. Aurora retains a receive buffer, incrementally frames a complete HTTP message, checks framing/size boundaries and passes it to [Wire via HTTPRequest](../source/aurora/http/package.d). Residual pipelined bytes are retained. Framing and field parsing are distinct current responsibilities; duplication cost has not justified replacing either.
4. [Router](../source/aurora/web/router.d) matches method/path and extracts parameters. `handleWithRouter` creates a per-request `Context` and `HTTPResponse`, invokes hooks and, only after a successful match, the global pipeline and handler.
5. [Context](../source/aurora/web/context.d) exposes borrowed request/response pointers, parameters, small storage and response/upgrade helpers. Domain work remains in the handler. JSON decoding, validation and serialization are explicit calls today, not an automatic typed-input pipeline.
6. `HTTPResponse` accumulates application output. The current runtime reconstructs the wire response from status/content type/body/keep-alive. This loses other response headers; it is an open defect, not intentional semantics.
7. The writer applies write deadlines; connection code decides keep-alive/retirement, compacts remaining input and cleans up. Hijack and request-admission lifetimes have known defects described in the state register.

## Responsibility map

| Owner | Actual responsibility / boundary | Cost or unresolved contract |
|---|---|---|
| Aurora App/Router | Registration, selection, parameters, global middleware orchestration | Runtime trie child search; local router middleware is stored but not dispatched |
| Aurora Server/WorkerPool | Connection lifecycle, message framing, dispatch, deadlines, admission, worker coordination | Duplicated metrics/state; admission scope and shutdown need validation |
| Wire | Native HTTP field parser and D request wrapper | Input views are borrowed; published candidate changes native parser lease lifetime |
| Aurora HTTP/Context | Request conveniences, response representation, per-request application access | Convenience copies/allocations; response model differs from actual output path |
| FastjsonD | Native JSON document/value parsing used by Aurora's schema mapper | Aurora retains its own template serialization/mapping; separate std.json validation mapper also exists |
| Aurora schema/middleware | UDA validation, JSON mapping, middleware validation | Distinct error/default semantics, silent conversion failures and duplicate exception names |
| Aurora-WebSocket | WebSocket protocol/types used by upgrade helpers | Aurora owns HTTP handoff; asynchronous ownership and full protocol validation remain open |
| vibe-core / eventcore | Task/fiber scheduling and network/event services | Aurora adds worker coordination; no demonstrated reason yet to replace this stack |
| Phobos / D runtime | Standard facilities, atomics/threads, D-GC and runtime lifecycle | AOT compilation; GC and native allocation are separate accounting domains |
| C/C++ runtime / OS | Native dependency allocation, socket/kernel I/O | Native bytes, syscall and CPU costs must be included in end-to-end profiles |

No component is declared optimal merely because it exists. No new subsystem split is approved by this map. A future input-processing boundary must be justified by real journeys and explicit semantics, including failures and inspectability.

## Ownership and data lifetime

The input buffer is retained through synchronous dispatch; raw accessor and route parameter views depend on that storage. A copied `Context` is not an owned request snapshot. Do not retain borrowed pointers/views into asynchronous work after dispatch. Buffer pooling/reuse reduces some repeated allocation; it does not establish zero native allocation or bounded RSS for every workload.

Wire's default parser lease can be reused while an earlier request wrapper is live. The candidate implements independent leases. See the exact revisions and test evidence before inferring which behavior a checkout has.

`HTTPResponse` contains an associative header map and body. Runtime output construction makes another representation/copy. The preallocated builder now keeps capacity exhaustion sticky and returns zero without writing outside its output slice. Partial output on failure must be discarded. Duplicate header names, framing authority and complete response output require one tested contract before redesigning representation for speed.

`Context.hijack()` marks its local state and returns a connection wrapper, but outer cleanup still closes the connection after dispatch. Synchronous use inside a callback is not proof of escaped asynchronous ownership. Server, worker and logger lifecycle ownership must be checked at actual exit paths, not inferred from API names.

## Configuration, errors and optional work

`ServerConfig` in [server.d](../source/aurora/runtime/server.d) is the runtime configuration authority; the separate configuration package maps file/environment data. Source is authoritative for fields/defaults. `App` has stored configuration and constructs its private Server in `listen`, which limits composition with helpers requiring an existing Server.

Router dispatch catches exceptions, invokes configured handlers, and falls back to 500. Some inner I/O paths suppress exceptions; validation middleware can convert a downstream exception into 400. Error APIs are not yet one consistent model. Status codes alone do not establish correct framing, headers or classification.

Empty global middleware skips pipeline execution, but this is only one optional cost. Hooks, Context/response construction, counters, JSON, tracing, logging, WebSocket code presence, binary/build costs and feature-enabled contention need separate evidence. `Noop` is not proof of zero construction work.

## Test and build boundaries

[dub.json](../dub.json) and [selections](../dub.selections.json) define the build graph. `.github/workflows/ci.yml` defines ordinary CI. Unit configuration excludes realworld/stress; some integration-named D modules assert APIs or skip network checks without a fixture. See [TEST_REGISTRY](TEST_REGISTRY.md). Native bindings require C/C++ compilation; an old compiler-minimum badge is not a compatibility matrix.

The earlier 5,383-line specification mixed design history, proposals and implementation claims. It is preserved in Git history and linked from the state register; it no longer governs architecture.
