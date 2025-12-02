# Real-World Tests Makefile
# Uses pre-built Aurora library from main build

DC       := ldc2
AURORA   := ../..
BUILD    := $(AURORA)/build
SRC      := $(AURORA)/source
WIRE_SRC := $(AURORA)/lib/wire/source
WIRE_LIB := $(AURORA)/lib/wire/build/libwire.a
FASTJSOND_SRC := $(AURORA)/lib/fastjsond/source
FASTJSOND_LIB := $(AURORA)/lib/fastjsond/build/libfastjsond.a

# Compile flags - uses -O3 for maximum performance
# NOTE: Large CTFE buffers were moved to runtime init to avoid OOM
CFLAGS   := -c -O3 -mcpu=native -release -I$(SRC) -I$(WIRE_SRC) -I$(FASTJSOND_SRC)
LDFLAGS  := $(BUILD)/libaurora.a $(WIRE_LIB) $(FASTJSOND_LIB) -L-lc++

# Test sources and targets (auto-discovered)
TEST_SOURCES := $(wildcard *_server.d)
TEST_TARGETS := $(patsubst %.d,%,$(TEST_SOURCES))
TEST_OBJECTS := $(patsubst %.d,%.o,$(TEST_SOURCES))

.PHONY: all clean servers test fast lib

# Default: ensure lib is built first, then servers
all: lib servers

# Build Aurora library first (delegates to main Makefile)
lib:
	@$(MAKE) -C $(AURORA) lib

servers: $(TEST_TARGETS)

# Two-step build: compile then link
%.o: %.d
	@echo "[DC] Compiling $<..."
	@$(DC) $(CFLAGS) $< -of=$@

%: %.o $(BUILD)/libaurora.a
	@echo "[LD] Linking $@..."
	@$(DC) $< $(LDFLAGS) -of=$@
	@echo "    ✓ $@"

# Fast build (no optimization)
fast: CFLAGS := -c -O0 -I$(SRC) -I$(WIRE_SRC) -I$(FASTJSOND_SRC)
fast: $(TEST_TARGETS)

clean:
	rm -f $(TEST_TARGETS) *.o

# Run comparison test
test: servers
	@echo "Starting servers..."
	@./multicore_server --port=8080 &
	@sleep 1
	@./singlecore_server --port=8081 &
	@sleep 1
	@echo "Running stress test..."
	@python3 gradual_stress.py --compare
	@pkill -f multicore_server || true
	@pkill -f singlecore_server || true
