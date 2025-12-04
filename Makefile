# ============================================================================
# Aurora - High-Performance HTTP Framework for D
# ============================================================================

# Compiler Configuration
DC       := ldc2
AR       := ar

# Directories
BUILD_DIR    := build
SRC_DIR      := source
TEST_DIR     := tests
EXAMPLES_DIR := examples

# Wire dependency (git submodule in lib/wire)
WIRE_DIR     := lib/wire
WIRE_SRC     := $(WIRE_DIR)/source
WIRE_LIB     := $(WIRE_DIR)/build/libwire.a

# Fastjsond dependency (git submodule in lib/fastjsond)
FASTJSOND_DIR := lib/fastjsond
FASTJSOND_SRC := $(FASTJSOND_DIR)/source
FASTJSOND_LIB := $(FASTJSOND_DIR)/build/libfastjsond.a

# Output
LIB_NAME     := libaurora.a
LIB_OUT      := $(BUILD_DIR)/$(LIB_NAME)

# Compiler Flags
DFLAGS       := -O3 -mcpu=native -I$(SRC_DIR) -I$(WIRE_SRC) -I$(FASTJSOND_SRC)
DFLAGS_DEBUG := -g -I$(SRC_DIR) -I$(WIRE_SRC) -I$(FASTJSOND_SRC)
DFLAGS_LIB   := $(DFLAGS) -lib -oq

# Linker flags for Wire and Fastjsond
LDFLAGS      := -L$(WIRE_DIR)/build -lwire -L$(FASTJSOND_DIR)/build -lfastjsond -L-lc++

# Source Files (all D files in source/aurora)
D_SOURCES := $(shell find $(SRC_DIR) -name '*.d')

# Example sources and targets (auto-discovered)
EXAMPLE_SOURCES := $(wildcard $(EXAMPLES_DIR)/*.d)
EXAMPLE_TARGETS := $(patsubst $(EXAMPLES_DIR)/%.d,$(BUILD_DIR)/%,$(EXAMPLE_SOURCES))

# ============================================================================
# Phony Targets
# ============================================================================

.PHONY: all clean lib test help info check-wire examples

# Default Target
all: lib

# Help
help:
	@echo "=========================================================="
	@echo "  make all           - Build library (default)"
	@echo "  make lib           - Build static library"
	@echo "  make test          - Run tests via DUB"
	@echo "  make test-cov      - Run tests with coverage (output in coverage/)"
	@echo "  make clean-cov     - Clean coverage files"
	@echo "  make examples      - Build example servers"
	@echo "  make clean         - Remove all build artifacts"
	@echo "  make info          - Show build configuration"
	@echo "  make help          - Show this help message"
	@echo ""
	@echo "Build directory: $(BUILD_DIR)/"
	@echo "Library output:  $(LIB_OUT)"

# ============================================================================
# Build Rules
# ============================================================================

# Create build directory
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Check Wire dependency
check-wire:
	@if [ ! -f $(WIRE_LIB) ]; then \
		echo "Building Wire dependency..."; \
		$(MAKE) -C $(WIRE_DIR) lib; \
	fi

# Check Fastjsond dependency
check-fastjsond:
	@if [ ! -f $(FASTJSOND_LIB) ]; then \
		echo "Building Fastjsond dependency..."; \
		$(MAKE) -C $(FASTJSOND_DIR) lib; \
	fi

# Build static library
lib: check-wire check-fastjsond $(LIB_OUT)

$(LIB_OUT): $(D_SOURCES) | $(BUILD_DIR)
	@echo "[DC] Building library: $@"
	@$(DC) $(DFLAGS_LIB) $(D_SOURCES) -of=$@ -od=$(BUILD_DIR)
	@echo "✓ Library built: $@"
	@echo "  Size: $$(du -h $@ | cut -f1)"

# Run tests via DUB (unit-threaded needs DUB for dependency resolution)
test: check-wire check-fastjsond
	@echo "Running tests via DUB..."
	@dub test

# Run tests with coverage (outputs to coverage/ folder)
test-cov: check-wire check-fastjsond
	@echo "Running tests with coverage..."
	@mkdir -p coverage
	@dub test --build=unittest-cov
	@echo "Moving coverage files to coverage/..."
	@find . -maxdepth 1 -name "*.lst" -exec mv {} coverage/ \; 2>/dev/null || true
	@find . -maxdepth 1 -name "..-*" -name "*.lst" -exec mv {} coverage/ \; 2>/dev/null || true
	@mv ..-*.lst coverage/ 2>/dev/null || true
	@echo "✓ Coverage files in coverage/"
	@echo "  To view: ls coverage/*.lst"

# Clean coverage files
clean-cov:
	@echo "Cleaning coverage files..."
	@rm -rf coverage/*.lst
	@rm -f *.lst ..-*.lst
	@echo "✓ Coverage files cleaned"

# ============================================================================
# Examples (Pattern Rule - builds any example automatically)
# ============================================================================

# Pattern rule: build any example from examples/*.d
$(BUILD_DIR)/%: $(EXAMPLES_DIR)/%.d $(LIB_OUT) | $(BUILD_DIR)
	@echo "[DC] Building $*..."
	@$(DC) $(DFLAGS) $< $(LIB_OUT) $(WIRE_LIB) $(FASTJSOND_LIB) -of=$@ -od=$(BUILD_DIR) -L-lc++
	@echo "✓ Built: $@"

# Build all examples
examples: $(EXAMPLE_TARGETS)
	@echo "✓ All examples built in $(BUILD_DIR)/"
	@echo "  Targets: $(notdir $(EXAMPLE_TARGETS))"

# ============================================================================
# Utility Targets
# ============================================================================

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)
	@rm -f aurora libaurora.a
	@rm -rf coverage/*.lst
	@rm -f *.lst ..-*.lst
	@echo "✓ Clean complete"

# Show build info
info:
	@echo "Build Configuration"
	@echo "==================="
	@echo "D Compiler:    $(DC)"
	@echo "D Flags:       $(DFLAGS)"
	@echo "Build Dir:     $(BUILD_DIR)"
	@echo "Wire Dir:      $(WIRE_DIR)"
	@echo "Fastjsond Dir: $(FASTJSOND_DIR)"
	@echo ""
	@echo "Source Files"
	@echo "============"
	@echo "D Sources:     $(words $(D_SOURCES)) files"
	@echo ""
	@echo "Output"
	@echo "======"
	@echo "Library:       $(LIB_OUT)"

# Rebuild everything
rebuild: clean all
