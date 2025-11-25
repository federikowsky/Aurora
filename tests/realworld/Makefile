# Real-World Tests Makefile
# Uses pre-built Aurora library

DC       := ldc2
AURORA   := ../..
BUILD    := $(AURORA)/build
SRC      := $(AURORA)/source
WIRE_SRC := $(AURORA)/lib/wire/source
WIRE_LIB := $(AURORA)/lib/wire/build/libwire.a
FASTJSOND_SRC := $(AURORA)/lib/fastjsond/source
FASTJSOND_LIB := $(AURORA)/lib/fastjsond/build/libfastjsond.a

# Compile flags
# Note: -lowmem reduces memory usage during compilation
DFLAGS   := -O2 -I$(SRC) -I$(WIRE_SRC) -I$(FASTJSOND_SRC) -lowmem
LDFLAGS  := $(BUILD)/libaurora.a $(WIRE_LIB) $(FASTJSOND_LIB) -L-lc++

# Test sources and targets (auto-discovered)
TEST_SOURCES := $(wildcard *_server.d)
TEST_TARGETS := $(patsubst %.d,%,$(TEST_SOURCES))

.PHONY: all clean servers test

all: servers

servers: $(TEST_TARGETS)

# Pattern rule: build any server from *_server.d
%: %.d
	@echo "[DC] $@ (lowmem mode)"
	@$(DC) $(DFLAGS) $< $(LDFLAGS) -of=$@

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
