#!/bin/bash
#
# Aurora vs vibe-d Performance Analysis Script
#
# This script runs controlled benchmarks and collects detailed metrics
# for performance comparison and bottleneck identification.
#
# Usage:
#   ./benchmarks/comparison/run_benchmark_analysis.sh
#
# Requirements:
#   - wrk installed (brew install wrk)
#   - Servers must be running on ports 8080 (Aurora) and 8081 (vibe-d)
#

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Aurora vs vibe-d Performance Analysis                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Configuration
DURATION=30s
THREADS=4
CONNECTIONS=100
WARMUP=5s
RUNS=3  # Number of runs for statistical significance

# Check for wrk
if ! command -v wrk &> /dev/null; then
    echo "ERROR: wrk not found. Install with: brew install wrk"
    exit 1
fi

# Results file
RESULTS_FILE="benchmarks/comparison/analysis_$(date +%Y%m%d_%H%M%S).txt"

echo "Test Configuration:"
echo "  Duration: $DURATION"
echo "  Threads: $THREADS"
echo "  Connections: $CONNECTIONS"
echo "  Warmup: $WARMUP"
echo "  Runs per test: $RUNS"
echo ""
echo "Results will be saved to: $RESULTS_FILE"
echo ""

{
    echo "# Aurora vs vibe-d Performance Analysis"
    echo "# Date: $(date)"
    echo "# Hardware: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Unknown')"
    echo "# Duration: $DURATION, Threads: $THREADS, Connections: $CONNECTIONS"
    echo "# Runs per test: $RUNS"
    echo ""
} > "$RESULTS_FILE"

# Function to check if server is running
check_server() {
    local port=$1
    local name=$2
    
    if ! curl -s "http://localhost:$port/" > /dev/null 2>&1; then
        echo "ERROR: $name server not running on port $port"
        echo "Please start it with:"
        if [ "$name" = "Aurora" ]; then
            echo "  dub run --single benchmarks/server.d --build=release"
        else
            echo "  dub run --single benchmarks/comparison/vibed_server.d --build=release"
        fi
        return 1
    fi
    return 0
}

# Function to extract metrics from wrk output
extract_metrics() {
    local output=$1
    
    # Extract requests/sec
    local reqs=$(echo "$output" | grep "Requests/sec" | awk '{print $2}')
    
    # Extract latency (avg, p50, p99)
    local latency_avg=$(echo "$output" | grep "Latency" | awk '{print $2}')
    local latency_p50=$(echo "$output" | grep "50%" | awk '{print $2}')
    local latency_p99=$(echo "$output" | grep "99%" | awk '{print $2}')
    
    echo "$reqs|$latency_avg|$latency_p50|$latency_p99"
}

# Function to run benchmark multiple times and calculate statistics
run_benchmark_stats() {
    local name=$1
    local port=$2
    local endpoint=$3
    
    echo "Testing $name $endpoint ($RUNS runs)..."
    
    # Check server
    if ! check_server "$port" "$name"; then
        echo "  SKIPPED" >> "$RESULTS_FILE"
        return
    fi
    
    local reqs_array=()
    local latency_avg_array=()
    local latency_p50_array=()
    local latency_p99_array=()
    
    # Run multiple times
    for i in $(seq 1 $RUNS); do
        echo -n "  Run $i/$RUNS... "
        
        # Warmup
        wrk -t$THREADS -c$CONNECTIONS -d$WARMUP "http://localhost:$port$endpoint" > /dev/null 2>&1
        
        # Actual benchmark
        local result=$(wrk -t$THREADS -c$CONNECTIONS -d$DURATION "http://localhost:$port$endpoint" 2>&1)
        
        # Extract metrics
        local metrics=$(extract_metrics "$result")
        local reqs=$(echo "$metrics" | cut -d'|' -f1)
        local latency_avg=$(echo "$metrics" | cut -d'|' -f2)
        local latency_p50=$(echo "$metrics" | cut -d'|' -f3)
        local latency_p99=$(echo "$metrics" | cut -d'|' -f4)
        
        reqs_array+=("$reqs")
        latency_avg_array+=("$latency_avg")
        latency_p50_array+=("$latency_p50")
        latency_p99_array+=("$latency_p99")
        
        echo "$reqs req/s"
    done
    
    # Calculate average using awk
    local count=${#reqs_array[@]}
    local reqs_avg=$(printf '%s\n' "${reqs_array[@]}" | awk '{sum+=$1; count++} END {if(count>0) printf "%.2f", sum/count; else printf "0"}')
    
    # Find min/max
    local reqs_min=$(printf '%s\n' "${reqs_array[@]}" | sort -n | head -1)
    local reqs_max=$(printf '%s\n' "${reqs_array[@]}" | sort -n | tail -1)
    
    echo "  Average: $reqs_avg req/s (min: $reqs_min, max: $reqs_max)"
    echo ""
    
    # Save to file
    {
        echo "## $name $endpoint"
        echo "Average req/s: $reqs_avg"
        echo "Min req/s: $reqs_min"
        echo "Max req/s: $reqs_max"
        echo "Runs: ${reqs_array[*]}"
        echo ""
    } >> "$RESULTS_FILE"
}

# Check both servers
echo "Checking servers..."
check_server 8080 "Aurora" || exit 1
check_server 8081 "vibe.d" || exit 1
echo "✓ Both servers running"
echo ""

# PLAINTEXT TEST
echo "═══════════════════════════════════════════════════════════════════"
echo "                        PLAINTEXT TEST (GET /)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

run_benchmark_stats "Aurora" 8080 "/"
run_benchmark_stats "vibe.d" 8081 "/"

# JSON TEST
echo "═══════════════════════════════════════════════════════════════════"
echo "                        JSON TEST (GET /json)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

run_benchmark_stats "Aurora" 8080 "/json"
run_benchmark_stats "vibe.d" 8081 "/json"

# HIGH CONCURRENCY TEST
echo "═══════════════════════════════════════════════════════════════════"
echo "                        HIGH CONCURRENCY (1000 connections)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

CONNECTIONS=1000

run_benchmark_stats "Aurora" 8080 "/"
run_benchmark_stats "vibe.d" 8081 "/"

echo "═══════════════════════════════════════════════════════════════════"
echo "                        BENCHMARK COMPLETE"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Results saved to: $RESULTS_FILE"

