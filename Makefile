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

# Output
LIB_NAME     := libaurora.a
LIB_OUT      := $(BUILD_DIR)/$(LIB_NAME)

# Compiler Flags
DFLAGS       := -O3 -mcpu=native -I$(SRC_DIR) -I$(WIRE_SRC)
DFLAGS_DEBUG := -g -I$(SRC_DIR) -I$(WIRE_SRC)
DFLAGS_LIB   := $(DFLAGS) -lib -oq

# Linker flags for Wire
LDFLAGS      := -L$(WIRE_DIR)/build -lwire

# Source Files (all D files in source/aurora)
D_SOURCES := $(shell find $(SRC_DIR) -name '*.d')

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

# Build static library
lib: check-wire $(LIB_OUT)

$(LIB_OUT): $(D_SOURCES) | $(BUILD_DIR)
	@echo "[DC] Building library: $@"
	@$(DC) $(DFLAGS_LIB) $(D_SOURCES) -of=$@ -od=$(BUILD_DIR)
	@echo "✓ Library built: $@"
	@echo "  Size: $$(du -h $@ | cut -f1)"

# Run tests via DUB (unit-threaded needs DUB for dependency resolution)
test: check-wire
	@echo "Running tests via DUB..."
	@dub test

# Build example: mt_test
$(BUILD_DIR)/mt_test: $(EXAMPLES_DIR)/mt_test.d $(LIB_OUT) | $(BUILD_DIR)
	@echo "[DC] Building mt_test..."
	@$(DC) $(DFLAGS) $< $(LIB_OUT) $(WIRE_LIB) -of=$@ -od=$(BUILD_DIR)
	@echo "✓ Built: $@"

# Build all examples
examples: $(BUILD_DIR)/mt_test
	@echo "✓ Examples built"

# ============================================================================
# Utility Targets
# ============================================================================

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)
	@rm -f aurora libaurora.a
	@echo "✓ Clean complete"

# Show build info
info:
	@echo "Build Configuration"
	@echo "==================="
	@echo "D Compiler:    $(DC)"
	@echo "D Flags:       $(DFLAGS)"
	@echo "Build Dir:     $(BUILD_DIR)"
	@echo "Wire Dir:      $(WIRE_DIR)"
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
