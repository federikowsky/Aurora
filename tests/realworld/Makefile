# Real-World Tests Makefile
# Uses pre-built Aurora library

DC       := ldc2
AURORA   := ../..
BUILD    := $(AURORA)/build
SRC      := $(AURORA)/source
WIRE_SRC := $(AURORA)/lib/wire/source
WIRE_LIB := $(AURORA)/lib/wire/build/libwire.a

# Compile flags (using pre-built library for speed)
DFLAGS   := -I$(SRC) -I$(WIRE_SRC)
LDFLAGS  := $(BUILD)/libaurora.a $(WIRE_LIB)

# Targets
SERVERS  := multicore_server singlecore_server

.PHONY: all clean servers

all: servers

servers: $(SERVERS)

multicore_server: multicore_server.d
	@echo "[DC] $@"
	@$(DC) $(DFLAGS) $< $(LDFLAGS) -of=$@

singlecore_server: singlecore_server.d
	@echo "[DC] $@"
	@$(DC) $(DFLAGS) $< $(LDFLAGS) -of=$@

clean:
	rm -f $(SERVERS)

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
