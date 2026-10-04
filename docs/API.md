# Public contracts and present limitations

This is a curated contract guide, not a duplicate signature catalog. Follow the linked source at your checkout revision for exact overloads and types. [ENGINEERING_STATUS](ENGINEERING_STATUS.md) records implementation evidence and defects. The [North Star](NORTH_STAR.md) describes desired quality, not already-shipped capabilities.

## Defining endpoints

[App](../source/aurora/app.d) exposes `get`, `post`, `put`, `delete_`, `patch`, `route`, `includeRouter`, `use`, hooks, exception registration and lifecycle methods. Current handlers use `ref Context`; automatic binding to a domain-typed handler is not implemented.

```d
app.get("/users/:id", (ref Context ctx) {
    ctx.json(["id": ctx.params["id"]]);
});
```

[Router](../source/aurora/web/router.d) selects by method and path, with static before parameter before wildcard matching and backtracking. Four path parameters fit inline; overflow can allocate. `normalizePath` is not a complete URI canonicalizer. Percent-encoding, dot segments, Unicode and concurrent registration have no comprehensive verified contract. Register routes before serving; do not infer safe concurrent mutation.

`App.group`, a `listen(port, callback)` overload and an input getter `ctx.json` advertised in old prose are not the current API. Use source/examples instead of adapting old snippets by guesswork.

## Request data and lifetime

[Context](../source/aurora/web/context.d) gives access to `request`, `response`, `params` and request-local storage. Query/body access belongs to [HTTPRequest](../source/aurora/http/package.d), not fictional `ctx.query`/`ctx.body` getters. Raw accessor views are borrowed; convenience accessors can copy/allocate. Neither a `Context` copy nor a raw view extends the backing buffer's lifetime. Make an explicitly owned copy when data must outlive dispatch.

Independent live request wrappers are unsafe with the default Wire revision; a tested candidate exists but is not automatically selected by the default manifest. See the state register.

## Producing output

`ctx.status(code)`, `ctx.header(name, value)`, `ctx.send(text)` and `ctx.json(value)` update the response. `json` serializes its argument; a pre-serialized JSON string becomes a JSON string value, not an object. To send already encoded JSON explicitly, set content type and send the encoded text, validating it as appropriate.

**Current limitation:** the App runtime preserves status/content type/body but drops other `HTTPResponse` headers. Redirect/cookie/CORS/security-header APIs must not be treated as working end-to-end guarantees. `HTTPResponse`'s map also cannot represent repeated identical header keys. The runtime and response builder are not yet one authoritative output contract. Complete HEAD/204/304/framing semantics require further tests.

The low-level `aurora.http.util.buildResponseInto` has an insufficient-slice memory-safety defect in the inspected default baseline; a fix is only present in the candidate. See B1 in the state register before using this builder.

## Middleware and policies

[MiddlewarePipeline](../source/aurora/web/middleware/package.d) executes registered global middleware around a matched handler. `next()` controls continuation. A global middleware is currently bypassed when no route matches, including an unmatched OPTIONS preflight. Registering `Router.use` currently stores middleware without integrating it into App dispatch; subrouter policy inheritance is not implemented. Do not use it as an authentication boundary.

Rate limiting, CORS, security headers, tracing, health, circuit-breaker, bulkhead and other modules exist; this is not a claim that their complete network/concurrency semantics are verified. Health/load-shedding helpers requiring Server do not automatically compose through App's private Server. Authentication/authorization samples are application examples, not a built-in audited security system.

## JSON input and validation

[schema/json.d](../source/aurora/schema/json.d) maps FastjsonD values to D types and implements serialization. Struct decoding currently catches field conversion failures and leaves defaults. Integer narrowing and borrowed string fields need explicit care. It is not strict typed input validation.

[schema/validation.d](../source/aurora/schema/validation.d) provides UDA-based validation. The distinct [validation middleware](../source/aurora/web/middleware/validation.d) uses `std.json` and a different mapper; it does not automatically enforce those UDAs and exposes mapped data through `onValidated`. Its exception scope includes `next()`, so downstream exceptions can become 400 responses. Three exported exception classes share `ValidationException`; qualify the module when needed.

These paths are not a unified automatic binding/normalization/validation contract. Their consolidation is an open design question, not approval for a new subsystem or permissive silent coercion.

## Errors, lifecycle and escape hatches

App supports typed exception-handler registration and request/response/error/start/stop hooks. Verify actual dispatch ordering in [Server](../source/aurora/runtime/server.d); an API name does not prove every failure invokes it.

`Context.hijack`, streaming/SSE and WebSocket helpers exist, but asynchronous connection handoff is unsafe under the current outer cleanup. Do not assume post-handler ownership transfer is reliable. Request-admission permits and multi-worker metrics have separate open defects. Logger implicit shutdown has a historical crash reproducer; an explicit shutdown workaround is not a proven whole-application lifecycle contract.

Low-level Server, request/response and runtime APIs provide advanced access, with their own contracts and costs. They are not substitutes for fixing misleading high-level semantics. Changes to public behavior need compatibility analysis, explicit migration when breaking, and executable consumer tests.
