# Examples

Start with the maintained local-checkout example:

```bash
# From repository root
dub run examples/minimal_server.d --single --compiler=ldc2
```

It binds port 8080 and replies to `/`. Its embedded DUB recipe uses the parent checkout; no `:minimal_server` subpackage exists. [README](../README.md) explains toolchain and readiness limits.

Other examples are demonstrations and investigation fixtures, not production templates or an audited security system. Some have embedded single-file DUB recipes, some rely on DUB configurations, and some contain old import/dependency assumptions. Inspect each file before running; there is no supported universal `dub run :production_server` command.

For actual public behavior consult [API contracts](../docs/API.md). In particular, `ctx.json(value)` is output serialization; local subrouter middleware, custom response headers, validation and asynchronous hijack have recorded limitations. Presence in an example does not close them.

Add examples only for useful user journeys. Keep common cases small, compile/run their documented commands and check observable output. Do not hide framework plumbing behind undocumented semantics or add options merely to showcase them.
