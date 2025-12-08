# D Framework Benchmark Comparison

## Test Environment

| Component | Specification |
|-----------|---------------|
| **Hardware** | MacBook Pro M4 |
| **CPU** | Apple M4 (10 cores: 4 performance + 6 efficiency) |
| **RAM** | 16 GB |
| **OS** | macOS |
| **Network** | Localhost (loopback) |

## Methodology

Following [TechEmpower Framework Benchmarks](https://www.techempower.com/benchmarks/) methodology:

1. **Plaintext Test** (`GET /`)
   - Response: `Hello, World!` (text/plain)
   - Tests raw throughput and routing efficiency

2. **JSON Test** (`GET /json`)
   - Response: `{"message":"Hello, World!"}` (application/json)
   - Tests JSON serialization + routing

3. **Test Parameters**
   - Duration: 30 seconds per test
   - Warmup: 5 seconds
   - Tool: `wrk`
   - Threads: 4
   - Connections: 100, 1000

## Running Benchmarks

### Prerequisites

```bash
# Install wrk
brew install wrk
```

### Start Servers

In separate terminals:

```bash
# Terminal 1: Aurora (port 8080)
dub run --single benchmarks/server.d --build=release

# Terminal 2: vibe.d (port 8081)
dub run --single benchmarks/comparison/vibed_server.d --build=release

# Terminal 3: hunt-http (port 8082)
dub run --single benchmarks/comparison/hunt_server.d --build=release
```

### Run Comparison

```bash
./benchmarks/comparison/run_comparison.sh
```

## Results

Results are saved to `benchmarks/comparison/results_YYYYMMDD_HHMMSS.txt`

### Latest Results (December 2024)

| Framework | Plaintext (req/s) | JSON (req/s) | Latency (avg) |
|-----------|-------------------|--------------|---------------|
| vibe.d | 123,556 | 126,247 | 1.08ms |
| Aurora | 77,743 | 72,402 | 1.35ms |
| hunt-http | 47,590 | 52,151 | 2.07ms |

## Notes

- **Build Mode**: All tests run with `--build=release` for fair comparison
- **Port Assignment**: Aurora=8080, vibe.d=8081, hunt-http=8082
- **Localhost**: Tests run on loopback to eliminate network variables
- **Cold Start**: Each test includes a 5-second warmup phase

## Framework Versions

| Framework | Version |
|-----------|---------|
| Aurora | 1.0.0 |
| vibe.d | ~>0.10.0 |
| hunt-http | ~>0.8.2 |

