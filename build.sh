#!/bin/bash
# Aurora Build Script
# Uses DUB for proper dependency management and testing

set -e

echo "=== Building Aurora ==="

# Build Wire library
echo "[1/2] Building Wire library..."
cd ../Wire && make lib && cd - > /dev/null

# Run all tests with DUB
echo "[2/2] Running tests with dub..."
dub test

echo ""
echo "✅ Build complete!"
