#!/bin/bash
# Aurora Benchmark Runner
# 
# Prerequisites:
#   - wrk (brew install wrk / apt install wrk)
#   - hey (go install github.com/rakyll/hey@latest)
#
# Usage:
#   # First, start the benchmark server in release mode:
#   dub run --single benchmarks/server.d --build=release
#   
#   # Then run this script:
#   ./benchmarks/run.sh
#
# Build modes:
#   debug         - Development (slow, bounds checking enabled)
#   release       - Production (optimized, no bounds checking) <- USE THIS
#   release-debug - Profiling (optimized + debug symbols)

set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║           Aurora Benchmark Suite v1.0.0                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "⚠️  Make sure server was started with: --build=release"
echo ""

# Check if server is running
if ! curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "ERROR: Benchmark server not running!"
    echo "Start it with: dub run --single benchmarks/server.d --build=release"
    exit 1
fi

echo "Server detected at http://localhost:8080"
echo ""

# Check for benchmark tools
WRK_AVAILABLE=false
HEY_AVAILABLE=false

if command -v wrk &> /dev/null; then
    WRK_AVAILABLE=true
fi

if command -v hey &> /dev/null; then
    HEY_AVAILABLE=true
fi

if ! $WRK_AVAILABLE && ! $HEY_AVAILABLE; then
    echo "ERROR: No benchmark tool found!"
    echo "Install wrk: brew install wrk (macOS) or apt install wrk (Linux)"
    echo "Install hey: go install github.com/rakyll/hey@latest"
    exit 1
fi

# Benchmark configuration
DURATION=10s
THREADS=4
CONNECTIONS=100

echo "Configuration:"
echo "  Duration: $DURATION"
echo "  Threads: $THREADS"
echo "  Connections: $CONNECTIONS"
echo ""

# Run benchmarks with wrk
if $WRK_AVAILABLE; then
    echo "═══════════════════════════════════════════════════════════════"
    echo "Benchmark: Plain Text (GET /)"
    echo "═══════════════════════════════════════════════════════════════"
    wrk -t$THREADS -c$CONNECTIONS -d$DURATION http://localhost:8080/
    echo ""

    echo "═══════════════════════════════════════════════════════════════"
    echo "Benchmark: JSON Response (GET /json)"
    echo "═══════════════════════════════════════════════════════════════"
    wrk -t$THREADS -c$CONNECTIONS -d$DURATION http://localhost:8080/json
    echo ""

    echo "═══════════════════════════════════════════════════════════════"
    echo "Benchmark: Latency Test (GET /delay - 10ms simulated)"
    echo "═══════════════════════════════════════════════════════════════"
    wrk -t$THREADS -c$CONNECTIONS -d$DURATION http://localhost:8080/delay
    echo ""
fi

# Run benchmarks with hey (alternative)
if $HEY_AVAILABLE && ! $WRK_AVAILABLE; then
    echo "═══════════════════════════════════════════════════════════════"
    echo "Benchmark: Plain Text (GET /) - using hey"
    echo "═══════════════════════════════════════════════════════════════"
    hey -n 50000 -c $CONNECTIONS http://localhost:8080/
    echo ""

    echo "═══════════════════════════════════════════════════════════════"
    echo "Benchmark: JSON Response (GET /json) - using hey"
    echo "═══════════════════════════════════════════════════════════════"
    hey -n 50000 -c $CONNECTIONS http://localhost:8080/json
    echo ""
fi

echo "═══════════════════════════════════════════════════════════════"
echo "Benchmark complete!"
echo "═══════════════════════════════════════════════════════════════"
