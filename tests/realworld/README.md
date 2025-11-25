# Real-World Performance Tests

This directory contains stress tests and benchmarks for Aurora HTTP server.

## Test Servers

### Multi-Core Server (`multicore_server.d`)
HTTP server using 8 worker threads. Default port: 8080.

```bash
# Build
ldc2 -O3 -I../../source -I../../lib/wire/source \
    multicore_server.d $(find ../../source -name '*.d') \
    ../../lib/wire/build/libwire.a -of=multicore_server

# Run
./multicore_server --workers=8 --port=8080
```

### Single-Core Server (`singlecore_server.d`)
HTTP server using 1 worker thread. Default port: 8081.

```bash
# Build
ldc2 -O3 -I../../source -I../../lib/wire/source \
    singlecore_server.d $(find ../../source -name '*.d') \
    ../../lib/wire/build/libwire.a -of=singlecore_server

# Run
./singlecore_server --port=8081
```

## Stress Test Clients

### 1. Gradual Stress Test (`gradual_stress.py`)
Incremental load testing with increasing concurrency levels.

```bash
# Test single server
python3 gradual_stress.py --host 127.0.0.1 --port 8080

# Compare multi-core vs single-core
python3 gradual_stress.py --compare
```

### 2. Sustained Load Test (`sustained_load.py`)
Long-running test to detect memory leaks and stability issues.

```bash
# Run for 60 seconds
python3 sustained_load.py --duration 60 --concurrency 100

# Run for 5 minutes
python3 sustained_load.py --duration 300 --concurrency 200
```

### 3. Spike Test (`spike_test.py`)
Tests server behavior under sudden traffic spikes.

```bash
python3 spike_test.py --host 127.0.0.1 --port 8080
```

### 4. Endpoint Mix Test (`endpoint_mix.py`)
Realistic traffic pattern with mixed endpoint types.

```bash
python3 endpoint_mix.py --requests 50000 --concurrency 100
```

## Quick Benchmark

Run all servers and compare:

```bash
# Terminal 1: Multi-core server
./multicore_server --workers=8

# Terminal 2: Single-core server  
./singlecore_server

# Terminal 3: Run comparison
python3 gradual_stress.py --compare
```

## Expected Results

| Metric | Single-Core | Multi-Core (8) | Speedup |
|--------|-------------|----------------|---------|
| Peak Throughput | ~15K req/s | ~55K req/s | 3-4x |
| P99 Latency | ~5ms | ~0.5ms | 10x better |
| Memory | ~8 MB | ~8 MB | Same |
| CPU Idle | 0% | 0% | Same |
