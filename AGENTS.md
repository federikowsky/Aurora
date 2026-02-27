# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

Aurora is a high-performance HTTP/1.1 framework written in D. It is a library (not a deployed web app) with no external service dependencies (no databases, caches, etc.).

### System dependencies

- **D compiler**: LDC2 (installed via `sudo apt-get install -y ldc`). Ships with DUB (build tool / package manager).
- **C++ toolchain**: `g++`, `libstdc++-13-dev`, `libc++-dev`, `libc++abi-dev` are required. The `fastjsond` dependency embeds simdjson (C++) and links against both `libstdc++` and `libc++`.
- **Linker fix**: A symlink `/usr/lib/x86_64-linux-gnu/libstdc++.so -> /usr/lib/gcc/x86_64-linux-gnu/13/libstdc++.so` is needed because the default Ubuntu 24.04 package does not place it in the linker search path.
- **c++ alternative**: The default `c++` command on Ubuntu 24.04 points to `clang++`, which cannot find `libstdc++` headers. Run `sudo update-alternatives --set c++ /usr/bin/g++` to fix this.

### Build / test / run commands

See `Makefile` for convenient targets. Key commands:

| Action | Command |
|--------|---------|
| Build (debug) | `dub build` |
| Build (release) | `dub build --build=release` |
| Run tests | `dub test` |
| Run example | `dub run --single examples/<name>.d` (requires recipe comment) or compile directly: `ldc2 -Isource <file>.d` |

### Known issues

- `dub test` reports **1/44 modules FAILED** due to a pre-existing timing-dependent assertion in `tests/unit/web/ratelimit_test.d:222` ("Should still be blocked with partial refill"). This is a flaky test unrelated to environment setup.
- DUB emits warnings about `-unittest` and `-cov` flags in `dub.json` configurations. These are harmless.
- Example files (e.g. `examples/minimal_server.d`) lack DUB recipe comments, so `dub run --single` won't work on them directly. To run examples, either add a recipe comment or compile with `ldc2` using appropriate import paths.

### Running an Aurora server for testing

Create a temporary single-file with a DUB recipe comment:
```d
/+ dub.sdl:
    name "my_test"
    dependency "aurora" path="/workspace"
+/
import aurora;
void main() {
    auto app = new App();
    app.get("/", (ref Context ctx) { ctx.send("Hello!"); });
    app.listen(8080);
}
```
Then: `dub run --single my_test.d`
