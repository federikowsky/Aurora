# Public contracts and present limitations

This is a curated contract guide, not a duplicate signature catalog. Follow the linked source at your checkout revision for exact overloads and types. [ENGINEERING_STATUS](ENGINEERING_STATUS.md) records implementation evidence and defects. The [North Star](NORTH_STAR.md) describes desired quality, not already-shipped capabilities.

## Defining endpoints

Register an endpoint on [App](../source/aurora/app.d) with its HTTP verb, path and handler. Handlers receive `ref Context`:

```d
app.get("/users/:id", (ref Context ctx) {
    ctx.json(["id": ctx.params["id"]]);
});
```

[Router](../source/aurora/web/router.d) selects by method and path, with static before parameter before wildcard matching and backtracking. Four path parameters fit inline; overflow can allocate. `normalizePath` is not a complete URI canonicalizer. Percent-encoding, dot segments, Unicode and concurrent registration have no comprehensive verified contract. Register routes before serving; do not infer safe concurrent mutation.

For endpoints with a shared prefix or policy, use [a group](#middleware-and-policies). To start serving, call `app.listen(port)`; register a startup callback separately with `app.onStart(hook)` if needed. Automatic binding to a domain-typed handler is not implemented.

## Request data and lifetime

[Context](../source/aurora/web/context.d) gives access to `request`, `response`, `params` and request-local storage. Query/body access belongs to [HTTPRequest](../source/aurora/http/package.d), not fictional `ctx.query`/`ctx.body` getters. Raw accessor views are borrowed; convenience accessors can copy/allocate. Neither a `Context` copy nor a raw view extends the backing buffer's lifetime. Make an explicitly owned copy when data must outlive dispatch.

Independent live request wrappers retain separate parser state with the selected Wire revision. Each wrapper still borrows its own input bytes, so those buffers must remain alive and unchanged until their wrappers are released. Sequential parses reuse an idle parser; cold or overlapping wrappers can allocate parser state on the native heap.

## Producing output

`ctx.status(code)`, `ctx.header(name, value)`, `ctx.send(text)` and `ctx.json(value)` update the response. `json` serializes its argument; a pre-serialized JSON string becomes a JSON string value, not an object. To send already encoded JSON explicitly, set content type and send the encoded text, validating it as appropriate.

The App runtime serializes the complete `HTTPResponse`: application headers survive to the socket, field-name replacement is case-insensitive, and invalid names, control characters and response-splitting values are rejected. Aurora owns buffered framing: it derives `Content-Length` from the final body, selects `Connection` from the connection lifecycle and does not forward an application `Transfer-Encoding`. A `HEAD` response retains the selected representation length but sends no body; informational, 204, 205 and 304 responses send no body or `Content-Length`. These computed fields are wire state and are not materialized in `getHeaders()`.

`getHeaders()` is a read-only view. Code that previously mutated its returned map must migrate to `setHeader` or `Context.header`; this keeps validation and case-insensitive replacement on the only mutation path.

`HTTPResponse` still uses one value per case-insensitive field name, so it cannot represent repeated fields such as multiple `Set-Cookie` lines. That is a current public limitation; do not join such values unless the field's HTTP semantics explicitly permit it. The low-level response helper remains available for callers that intentionally own their complete response contract.

The low-level `aurora.http.util.buildResponseInto` returns bytes written, or `0` when capacity is insufficient. Exhaustion is sticky: later fragments cannot resume writing. On failure, bytes inside the supplied slice may have changed and must be discarded; bytes outside it are preserved. The capacity regression tests exercise debug and release. This does not make the helper a complete HTTP response model or establish an input/output aliasing contract. See the revision-qualified evidence in the state register.

The direct `Server(RequestHandler, ServerConfig)` entry point passes a borrowed
request pointer and a borrowed `ref ResponseBuffer` to the handler. The writer
is valid only for that call; write the response before returning. Handlers made
for the former by-value signature must add `ref` to their `ResponseBuffer`
parameter. The by-value form mutated a copy and could not emit a response.

## Middleware and policies

Declare a policy where it applies. In this [working example](../examples/middleware_example.d), every admitted request gets a request ID. Health is public; reading a report requires identification, and changing it also requires write permission. `health`, `read` and `update` below stand for application handlers.

```d
app.use(requestIdMiddleware());
app.get("/health", health);

app.group("/reports", identify, (reports) {
    reports.get("/:id", read);
    reports.put("/:id", requireWriter, update);
});
```

Leave out the policy when none is needed. For several policies on the same group or route, pass them as one list in execution order, for example `[identify, requireWriter]`.

### Dispatch and registration contract

- After a single method/path match, App middleware wraps the selected handler or the framework 404. Matched parameters are available even to global middleware. Parser/framing failures and admission rejections precede App dispatch.
- Incoming order is App registration order, outer to inner groups, route policies left to right, then handler. Returning unwinds in reverse. The same instance explicitly registered twice executes twice; distinct groups may share a stateful limiter. The application owns synchronization of mutable state across workers.
- `next()` is borrowed, synchronous and optional. Call it at most once per invocation; a second attempt throws even if the first threw. Do not save or schedule it. Middleware can catch downstream exceptions; otherwise they reach the App exception boundary. Use `scope(exit)` for unconditional cleanup.
- A miss, including a wrong method, runs no local policy. A registered `OPTIONS` gets its own route policies if the global chain continues. Unmatched `OPTIONS` goes through the global chain and fallback; a global policy such as CORS can respond first. Unknown URLs under a group prefix are still misses.
- Configure before serving. Policy membership is copied at registration. Group paths are local, including custom methods (`reports.addRoute("OPTIONS", "/:id", handler)`). Groups nest, run their definition block once and return no routing handle. Routes attach only if the definition finishes and the mount has no conflicts; external application side effects are not rolled back.
- Duplicate method/pattern and inconsistent capture names on the same parameter/wildcard node are configuration errors. Static, parameter and wildcard alternatives can coexist. A static prefix with no handler is not a match.

### Independently built routers and reusable handlers

When another module supplies a `Router`, attach it with `includeRouter(child)` or use `parent.mount("/v1", child)` on a Router to add a mount prefix. This snapshots the child's routes without retaining it; later changes do not propagate. A separately constructed `new Router(prefix, policies...)` accepts the same local policies. Its verb helpers add its prefix, whereas its low-level `addRoute` expects the full path in that router. No live or concurrent reconfiguration is supported.

Use [withMiddleware](../source/aurora/web/middleware/chain.d) when the result must itself be a `Handler` value, for instance to pass it to another component. Ordinary endpoint registration already handles the composition.

**Migration:** existing route calls and explicitly assembled modules remain valid. A verb name now denotes overloads: if you previously used `auto addPut = &router.put;`, write `void delegate(string, Handler) addPut = &router.put;` (on App the return type is `App`). Keep cross-cutting policy on `App.use`. Do not restore the former inert `Router.use` or mutate a middleware array. Replace writes to `prefix` and traversal of `subRouters` with explicit construction and mounting; the internal recursion arguments to `includeRouter` are gone. Replace deliberate last-wins route overrides with one explicit handler. Annotate named middleware/class continuations `scope NextFunction next`; move asynchronous work onto independently owned data, outside the continuation. Stateful class policies can expose a compatible `Middleware` delegate (e.g. `bulkhead.middleware()`).

Rate limiting, CORS, security headers, tracing, health, circuit-breaker, bulkhead and other modules exist; this is not a claim that their complete network/concurrency semantics are verified. Health/load-shedding helpers requiring Server do not automatically compose through App's private Server. Authentication/authorization samples are application examples, not a built-in audited security system.

## JSON input and validation

[schema/json.d](../source/aurora/schema/json.d) maps FastjsonD values to D types and implements serialization. Struct decoding currently catches field conversion failures and leaves defaults. Integer narrowing and borrowed string fields need explicit care. It is not strict typed input validation.

[schema/validation.d](../source/aurora/schema/validation.d) provides UDA-based validation. The distinct [validation middleware](../source/aurora/web/middleware/validation.d) uses `std.json` and a different mapper; it does not automatically enforce those UDAs and exposes mapped data through `onValidated`. Its exception scope includes `next()`, so downstream exceptions can become 400 responses. Three exported exception classes share `ValidationException`; qualify the module when needed.

These paths are not a unified automatic binding/normalization/validation contract. Their consolidation is an open design question, not approval for a new subsystem or permissive silent coercion.

## Errors, lifecycle and escape hatches

App supports typed exception-handler registration and request/response/error/start/stop hooks. Verify actual dispatch ordering in [Server](../source/aurora/runtime/server.d); an API name does not prove every failure invokes it.

[`upgradeWebSocket`](../source/aurora/web/websocket.d) accepts an HTTP/1.1 GET with a valid upgrade handshake. Aurora passes the parsed method to Aurora-WebSocket, which also validates the `Sec-WebSocket-Key` as a Base64 encoding of 16 bytes. Rejection at validation returns `null` before hijack, leaving the HTTP response to the application. Applications accepting non-GET or HTTP/1.0 upgrades must use HTTP/1.1 GET clients. A received Close is acknowledged and closes the owned transport before `receive()` reports end of stream. Use the upgraded connection within the handler and close it there: returning from the handler still lets Aurora's outer cleanup close the socket. This limitation also applies to `Context.hijack` and streaming/SSE.

Multi-worker metrics have a separate open defect. The logging module owns its process-wide singleton and joins/drains its flush thread during normal module teardown. Explicit `Logger.shutdown()` remains supported after application producers have stopped; shutdown does not restart the singleton. This does not guarantee abrupt-signal termination, application daemon-thread coordination or arbitrary concurrent shutdown/configuration.

Low-level Server, request/response and runtime APIs provide advanced access, with their own contracts and costs. They are not substitutes for fixing misleading high-level semantics. Changes to public behavior need compatibility analysis, explicit migration when breaking, and executable consumer tests.

## Request admission

`ServerConfig.maxInFlightRequests` bounds active HTTP requests **across one Server**, including all workers and response writes. A complete parsed request reserves a place before dispatch; completion, errors/timeouts and dispatch exit release it. Idle keep-alive connections and incomplete reads do not occupy a place. `0` disables this limiter. Excess requests receive 503 with `Retry-After` and connection close, without invoking the handler; their temporary atomic reservation is rolled back before the rejection write.

Compatibility: previous code released the place before dispatch and did not enforce the configured limit; its per-worker comment was misleading. Applications can now see intended 503 responses under load. Size the value as the total Server budget. This repair does not implement `queueRequest`, bound response memory or certify connection-admission/hijack lifecycles.
