# Aurora

[![CI](https://github.com/federikowsky/Aurora/actions/workflows/ci.yml/badge.svg)](https://github.com/federikowsky/Aurora/actions/workflows/ci.yml)

Aurora is an HTTP/1.1 backend framework for D. Its goal is a simple application surface, explicit semantics and exceptional real efficiency. The current implementation provides `App`, routing, `Context`, opt-in middleware, JSON helpers and fiber-based networking.

**Engineering preview.** Production readiness, complete HTTP compliance and end-to-end zero allocation are not established. Important response, request-lifetime and runtime contracts remain open; see the revision-qualified [engineering state](docs/ENGINEERING_STATUS.md). A passing CI badge covers that workflow's checks, not all public promises.

## First local service

Use a source checkout until a tested package/release path is documented. LDC 1.42.0 on Linux x86-64 is the validated configuration; native dependencies also require a C/C++ compiler and platform C++ runtime. Other compiler/platform claims are unverified.

```bash
git clone https://github.com/federikowsky/Aurora.git
cd Aurora
git rev-parse HEAD
dub run examples/minimal_server.d --single --compiler=ldc2
```

Then request `http://localhost:8080/`. The example uses the local checkout:

```d
import aurora;

void main()
{
    auto app = new App();
    app.get("/", (ref Context ctx) {
        ctx.send("Hello from Aurora!");
    });
    app.listen(8080);
}
```

`App` currently accepts `ref Context` handlers. Typed domain-input handlers are a design possibility, not an implemented API. `ctx.json(value)` serializes a value; it is not an input getter. For reproducibility record the checkout SHA and preserve `dub.selections.json`.

## Where to look

| Question | Authoritative entry point |
|---|---|
| What should guide decisions? | [North Star](docs/NORTH_STAR.md) |
| How should maintenance work? | [AGENTS.md](AGENTS.md) |
| What works, fails or remains unknown? | [Engineering state and scorecard](docs/ENGINEERING_STATUS.md) |
| How does the actual system work? | [Architecture and ownership](docs/specs.md) |
| What does the public API mean? | [Public contracts](docs/API.md), then linked source |
| What is actually tested? | [Validation guide](docs/TEST_REGISTRY.md), DUB and workflows |
| How are costs measured? | [Benchmark guide](benchmarks/README.md) |
| Which examples are maintained? | [Examples](examples/README.md) |

Wire, FastjsonD and Aurora-WebSocket are the first-party ecosystem. Runtime I/O uses vibe-core/eventcore. Exact dependency selections belong to [dub.selections.json](dub.selections.json), not a parallel version table.

Historical plans, release prose and benchmark numbers are evidence of earlier work, not current capability guarantees. Their pinned sources are indexed in the engineering state. Licensed under [MIT](LICENSE).
