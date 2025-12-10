#!/bin/bash
#
# Aurora Full Benchmark Suite
#
# Runs comprehensive benchmarks across multiple scenarios to measure
# REAL performance, not just trivial "hello world" cases.
#
# Prerequisites:
#   brew install wrk
#
# Usage:
#   1. Start Aurora server:
#      dub run --single benchmarks/profiling_server.d --build=release
#
#   2. Run this script:
#      ./benchmarks/run_full_benchmark.sh
#
#   3. (Optional) For comparison, start vibe-d server on port 8081:
#      dub run --single benchmarks/comparison/vibed_server.d --build=release
#      ./benchmarks/run_full_benchmark.sh --vibed
#

set -e

# Configuration
DURATION="${DURATION:-30s}"
THREADS="${THREADS:-4}"
CONNECTIONS="${CONNECTIONS:-100}"
WARMUP="${WARMUP:-5s}"

# Default to Aurora port
PORT="${PORT:-8080}"
SERVER_NAME="Aurora"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --vibed)
            PORT=8081
            SERVER_NAME="vibe-d"
            shift
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --connections)
            CONNECTIONS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

BASE_URL="http://localhost:$PORT"

# Check for wrk
if ! command -v wrk &> /dev/null; then
    echo "ERROR: wrk not found. Install with: brew install wrk"
    exit 1
fi

# Check if server is running
if ! curl -s "$BASE_URL/" > /dev/null 2>&1; then
    echo "ERROR: Server not running on $BASE_URL"
    echo ""
    echo "Start the server first:"
    echo "  Aurora:  dub run --single benchmarks/profiling_server.d --build=release"
    echo "  vibe-d:  dub run --single benchmarks/comparison/vibed_server.d --build=release"
    exit 1
fi

# Results file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="benchmarks/results"
mkdir -p "$RESULTS_DIR"
SERVER_NAME_LOWER=$(echo "$SERVER_NAME" | tr '[:upper:]' '[:lower:]')
RESULTS_FILE="$RESULTS_DIR/${SERVER_NAME_LOWER}_benchmark_$TIMESTAMP.txt"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║             Full Benchmark Suite - $SERVER_NAME                        ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "Configuration:"
echo "  Server:      $SERVER_NAME ($BASE_URL)"
echo "  Duration:    $DURATION"
echo "  Threads:     $THREADS"
echo "  Connections: $CONNECTIONS"
echo "  Warmup:      $WARMUP"
echo ""
echo "Results will be saved to: $RESULTS_FILE"
echo ""

# Initialize results file
{
    echo "# $SERVER_NAME Benchmark Results"
    echo "# Date: $(date)"
    echo "# Duration: $DURATION, Threads: $THREADS, Connections: $CONNECTIONS"
    echo "# Hardware: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Unknown')"
    echo ""
} > "$RESULTS_FILE"

# Function to run a single benchmark
run_benchmark() {
    local name="$1"
    local endpoint="$2"
    local method="${3:-GET}"
    local extra_args="${4:-}"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Testing: $name"
    echo "Endpoint: $method $endpoint"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Warmup (silent)
    echo "  Warming up..."
    wrk -t$THREADS -c$CONNECTIONS -d$WARMUP "$BASE_URL$endpoint" $extra_args > /dev/null 2>&1 || true

    # Actual benchmark
    echo "  Running benchmark..."
    local result
    result=$(wrk -t$THREADS -c$CONNECTIONS -d$DURATION --latency "$BASE_URL$endpoint" $extra_args 2>&1)

    # Extract metrics
    local reqs=$(echo "$result" | grep "Requests/sec" | awk '{print $2}')
    local latency_avg=$(echo "$result" | grep "Latency" | head -1 | awk '{print $2}')
    local latency_p50=$(echo "$result" | grep "50%" | awk '{print $2}')
    local latency_p99=$(echo "$result" | grep "99%" | awk '{print $2}')
    local transfer=$(echo "$result" | grep "Transfer/sec" | awk '{print $2}')

    # Display results
    echo ""
    echo "  Results:"
    echo "    Requests/sec:  $reqs"
    echo "    Latency avg:   $latency_avg"
    echo "    Latency p50:   $latency_p50"
    echo "    Latency p99:   $latency_p99"
    echo "    Transfer/sec:  $transfer"
    echo ""

    # Save to file
    {
        echo "## $name"
        echo "Endpoint: $method $endpoint"
        echo ""
        echo "$result"
        echo ""
        echo "---"
        echo ""
    } >> "$RESULTS_FILE"
}

# Create Lua script for POST test
POST_SCRIPT=$(mktemp)
cat > "$POST_SCRIPT" << 'EOF'
wrk.method = "POST"
wrk.headers["Content-Type"] = "application/json"
wrk.body = '{"name":"Test User","email":"test@example.com","age":30,"role":"member"}'
EOF

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "                    RUNNING BENCHMARK SUITE"
echo "════════════════════════════════════════════════════════════════════"
echo ""

# Run all benchmarks
run_benchmark "Plaintext (13 bytes)" "/"
run_benchmark "JSON Small (~50 bytes)" "/json"
run_benchmark "JSON Medium (~1KB)" "/json/medium"
run_benchmark "Body 4KB" "/body/4k"
run_benchmark "Body 16KB" "/body/16k"
run_benchmark "REST + Headers" "/api/users/123"

# POST test (if endpoint exists)
if curl -s -X POST -H "Content-Type: application/json" -d '{}' "$BASE_URL/api/users" > /dev/null 2>&1; then
    run_benchmark "POST + Body Parse" "/api/users" "POST" "-s $POST_SCRIPT"
else
    echo "  Skipping POST test (endpoint not available)"
fi

# Cleanup
rm -f "$POST_SCRIPT"

# Summary
echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "                       BENCHMARK COMPLETE"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "Results saved to: $RESULTS_FILE"
echo ""

# Print quick summary table
echo "Quick Summary (req/s):"
echo "┌─────────────────────────┬────────────┐"
echo "│ Scenario                │ Requests/s │"
echo "├─────────────────────────┼────────────┤"
grep -A 20 "^## " "$RESULTS_FILE" | grep "Requests/sec" | while read line; do
    reqs=$(echo "$line" | awk '{print $2}')
    printf "│ %-23s │ %10s │\n" "..." "$reqs"
done
echo "└─────────────────────────┴────────────┘"
echo ""
echo "For detailed results, see: $RESULTS_FILE"
