#!/bin/bash
# Run Autobahn WebSocket compliance tests for Aurora
#
# Prerequisites:
# - Docker installed
# - Aurora autobahn server running
#
# Usage:
#   ./tests/autobahn/run_tests.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "========================================"
echo "  Autobahn WebSocket Compliance Tests"
echo "        (Aurora Integration)"
echo "========================================"
echo ""

# Create reports directory
mkdir -p "$SCRIPT_DIR/reports"

# Check if server is running
if ! nc -z localhost 9002 2>/dev/null; then
    echo "ERROR: Aurora WebSocket server not running on port 9002"
    echo ""
    echo "Start the server first:"
    echo "  cd $PROJECT_DIR"
    echo "  dub run -- examples/autobahn_server.d"
    echo ""
    echo "Or compile and run:"
    echo "  dub build"
    echo "  ./aurora examples/autobahn_server.d"
    echo ""
    exit 1
fi

echo "Running Autobahn tests..."
echo ""

# Run wstest
docker run -it --rm \
    -v "$SCRIPT_DIR:/config:ro" \
    -v "$SCRIPT_DIR/reports:/reports" \
    --network=host \
    crossbario/autobahn-testsuite \
    wstest -m fuzzingclient -s /config/fuzzingclient.json

echo ""
echo "========================================"
echo "  Tests Complete!"
echo "========================================"
echo ""
echo "Results are in: $SCRIPT_DIR/reports/"
echo "Open: $SCRIPT_DIR/reports/index.html"
