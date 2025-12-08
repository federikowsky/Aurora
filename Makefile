# ============================================================================
# Aurora v1.0.0 - High-Performance HTTP Framework for D
# ============================================================================
#
# All dependencies (wire, fastjsond, aurora-websocket) are managed by DUB.
# This Makefile provides convenient shortcuts for common operations.
#
# ============================================================================

.PHONY: all build release test test-cov benchmark examples clean help

# Default target
all: build

# ============================================================================
# Help
# ============================================================================

help:
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║        Aurora HTTP Framework v1.0.0 - Build System         ║"
	@echo "╚════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Build Targets:"
	@echo "  all, build    Build library (debug mode)"
	@echo "  release       Build library (release mode, optimized)"
	@echo ""
	@echo "Test Targets:"
	@echo "  test          Run unit tests"
	@echo "  test-cov      Run tests with coverage report"
	@echo ""
	@echo "Benchmark:"
	@echo "  benchmark     Start benchmark server (release mode)"
	@echo ""
	@echo "Examples:"
	@echo "  examples      List available examples"
	@echo "  run-example   Run example (use: make run-example E=minimal_server)"
	@echo ""
	@echo "Utility:"
	@echo "  clean         Remove build artifacts"
	@echo "  deps          Fetch/update DUB dependencies"
	@echo "  info          Show build configuration"
	@echo ""

# ============================================================================
# Build Targets
# ============================================================================

build:
	@echo "Building Aurora (debug)..."
	@dub build
	@echo "✓ Build complete"

release:
	@echo "Building Aurora (release)..."
	@dub build --build=release
	@echo "✓ Release build complete"

# ============================================================================
# Test Targets
# ============================================================================

test:
	@echo "Running tests..."
	@dub test
	@echo "✓ Tests complete"

test-cov:
	@echo "Running tests with coverage..."
	@mkdir -p coverage
	@dub test --config=unittest-cov
	@mv *.lst coverage/ 2>/dev/null || true
	@echo "✓ Coverage report in coverage/"

# ============================================================================
# Benchmark
# ============================================================================

benchmark:
	@echo "Starting benchmark server (release mode)..."
	@echo "Use wrk or hey to test: http://localhost:8080/"
	@dub run --single benchmarks/server.d --build=release

# ============================================================================
# Examples
# ============================================================================

examples:
	@echo "Available examples:"
	@echo ""
	@ls -1 examples/*.d | sed 's/examples\//  /' | sed 's/\.d$$//'
	@echo ""
	@echo "Run with: make run-example E=<name>"
	@echo "Example:  make run-example E=minimal_server"

run-example:
ifndef E
	@echo "Error: specify example name with E=<name>"
	@echo "Example: make run-example E=minimal_server"
	@exit 1
endif
	@echo "Running example: $(E)"
	@dub run --single examples/$(E).d

# ============================================================================
# Utility
# ============================================================================

deps:
	@echo "Fetching dependencies..."
	@dub fetch --cache=local
	@echo "✓ Dependencies ready"

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf .dub build coverage
	@rm -f *.lst *.a aurora
	@rm -f dub.selections.json
	@echo "✓ Clean complete"

info:
	@echo "Aurora HTTP Framework v1.0.0"
	@echo ""
	@echo "Dependencies (from dub.json):"
	@grep -E '^\s+"[a-z-]+":' dub.json | head -10
	@echo ""
	@echo "D Compiler:"
	@dub --version | head -1
	@ldc2 --version | head -1 || dmd --version | head -1 || echo "No D compiler found"
