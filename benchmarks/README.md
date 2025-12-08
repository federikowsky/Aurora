# Aurora Benchmarks

Performance benchmark suite for Aurora HTTP Framework.

## Quick Start

1. **Start benchmark server** (release mode for accurate results):
   ```bash
   dub run --single benchmarks/server.d --build=release
   ```

2. **Run benchmarks** (in another terminal):
   ```bash
   ./benchmarks/run.sh
   ```

## Build Modes

| Mode | Command | Use Case |
|------|---------|----------|
| `debug` | `--build=debug` | Development (slow, with bounds checks) |
| `release` | `--build=release` | **Benchmarks** (optimized, no checks) |
| `release-debug` | `--build=release-debug` | Profiling (optimized + debug symbols) |

⚠️ **Always use `--build=release` for benchmarks!** Debug mode is 5-10x slower.

## Manual Testing

### Using wrk (recommended)

```bash
# Plain text
wrk -t4 -c100 -d30s http://localhost:8080/

# JSON
wrk -t4 -c100 -d30s http://localhost:8080/json

# Latency test
wrk -t4 -c100 -d30s --latency http://localhost:8080/
```

### Using hey

```bash
hey -n 100000 -c 100 http://localhost:8080/
```

### Using ab (Apache Bench)

```bash
ab -n 100000 -c 100 http://localhost:8080/
```

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Plain text "Hello, World!" |
| `/json` | GET | JSON response |
| `/delay` | GET | 10ms simulated delay |
| `/echo` | POST | Echo request body |

## Expected Results

On modern hardware (M1/M2 Mac, recent Intel/AMD):

| Endpoint | Expected req/s |
|----------|---------------|
| Plain text | 50,000-150,000+ |
| JSON | 40,000-100,000+ |

Results vary based on:
- CPU cores and speed
- Network stack
- Benchmark tool settings
- OS configuration

## Comparison

To compare with other frameworks:

```bash
# vibe.d
# Actix-web (Rust)
# Express.js (Node)
# Go net/http
```

Build equivalent "Hello World" servers and run same wrk commands.
