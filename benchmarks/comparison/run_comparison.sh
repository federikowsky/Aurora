#!/bin/bash
#
# Aurora Framework Benchmark Comparison
#
# Compares Aurora vs vibe.d vs hunt-http performance
#
# Test Environment:
#   Hardware: MacBook Pro (M4, 10 cores: 4P+6E, 16GB RAM)
#   OS: macOS
#   Tool: wrk
#   Build: release mode (-O)
#
# Prerequisites:
#   brew install wrk
#
# Usage:
#   1. Start servers in separate terminals:
#      Terminal 1: dub run --single benchmarks/server.d --build=release
#      Terminal 2: dub run --single benchmarks/comparison/vibed_server.d --build=release
#      Terminal 3: dub run --single benchmarks/comparison/hunt_server.d --build=release
#
#   2. Run this script:
#      ./benchmarks/comparison/run_comparison.sh
#

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║           D Framework Benchmark Comparison                     ║"
echo "║           Aurora vs vibe.d vs hunt-http                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Configuration
DURATION=30s
THREADS=4
CONNECTIONS=100
WARMUP=5s

# Check for wrk
if ! command -v wrk &> /dev/null; then
    echo "ERROR: wrk not found. Install with: brew install wrk"
    exit 1
fi

# Results file
RESULTS_FILE="benchmarks/comparison/results_$(date +%Y%m%d_%H%M%S).txt"

echo "Test Configuration:"
echo "  Duration: $DURATION"
echo "  Threads: $THREADS"
echo "  Connections: $CONNECTIONS"
echo "  Warmup: $WARMUP"
echo ""
echo "Results will be saved to: $RESULTS_FILE"
echo ""

{
    echo "# D Framework Benchmark Comparison"
    echo "# Date: $(date)"
    echo "# Hardware: MacBook Pro M4 (10 cores: 4P+6E, 16GB RAM)"
    echo "# Duration: $DURATION, Threads: $THREADS, Connections: $CONNECTIONS"
    echo ""
} > "$RESULTS_FILE"

# Function to run benchmark
run_benchmark() {
    local name=$1
    local port=$2
    local endpoint=$3
    
    echo "Testing $name $endpoint..."
    
    # Check if server is running
    if ! curl -s "http://localhost:$port$endpoint" > /dev/null 2>&1; then
        echo "  SKIPPED (server not running on port $port)"
        echo "  $name $endpoint: SKIPPED" >> "$RESULTS_FILE"
        return
    fi
    
    # Warmup
    wrk -t$THREADS -c$CONNECTIONS -d$WARMUP "http://localhost:$port$endpoint" > /dev/null 2>&1
    
    # Actual benchmark
    local result=$(wrk -t$THREADS -c$CONNECTIONS -d$DURATION "http://localhost:$port$endpoint" 2>&1)
    
    # Extract req/s
    local reqs=$(echo "$result" | grep "Requests/sec" | awk '{print $2}')
    
    # Extract latency
    local latency=$(echo "$result" | grep "Latency" | awk '{print $2}')
    
    echo "  Requests/sec: $reqs"
    echo "  Latency: $latency"
    echo ""
    
    {
        echo "## $name $endpoint"
        echo "$result"
        echo ""
    } >> "$RESULTS_FILE"
}

echo "═══════════════════════════════════════════════════════════════════"
echo "                        PLAINTEXT TEST (GET /)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

run_benchmark "Aurora" 8080 "/"
run_benchmark "vibe.d" 8081 "/"
run_benchmark "hunt-http" 8082 "/"

echo "═══════════════════════════════════════════════════════════════════"
echo "                        JSON TEST (GET /json)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

run_benchmark "Aurora" 8080 "/json"
run_benchmark "vibe.d" 8081 "/json"
run_benchmark "hunt-http" 8082 "/json"

echo "═══════════════════════════════════════════════════════════════════"
echo "                        HIGH CONCURRENCY (1000 connections)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

CONNECTIONS=1000

run_benchmark "Aurora" 8080 "/"
run_benchmark "vibe.d" 8081 "/"
run_benchmark "hunt-http" 8082 "/"

echo "═══════════════════════════════════════════════════════════════════"
echo "                        BENCHMARK COMPLETE"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Results saved to: $RESULTS_FILE"
