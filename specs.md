# Aurora Framework - Core V0 Specification

## Document Control

**Project Name:** Aurora Backend Framework  
**Language:** D (DMD/LDC)  
**Target Platforms:** Linux (primary), macOS, Windows  
**Document Version:** V0 Core  
**Status:** Design Specification  
**Classification:** Internal - Technical Architecture

> [!NOTE]
> **V0 Core Scope**: This specification covers ONLY the HTTP engine core infrastructure.
> Extended features (DI, ORM, GraphQL, WebSocket, Auth, etc.) are deferred to future phases.

---

## 1. EXECUTIVE SUMMARY

### 1.1 Project Identity

**Aurora** è un framework backend HTTP/REST scritto in D, progettato per prestazioni estreme, scalabilità lineare e overhead minimo. Il framework V0 fornisce l'infrastruttura core per costruire server HTTP ad alte performance.

### 1.2 Core Principles

1. **Performance-First Architecture**: Ogni decisione di design deve essere giustificata da misurazioni di performance.

2. **Zero-Copy Everywhere**: Ogni copia di dati deve essere eliminata o giustificata esplicitamente.

3. **Hardware-Aware**: Il framework sfrutta cache CPU, NUMA quando disponibile, e permette l'uso di SIMD dove il compiler non può auto-vectorize.

4. **Predictable Performance**: Nessuna allocazione GC nella hot path. Timing deterministico per operazioni critiche.

5. **Minimal Dependencies**: Ogni dipendenza esterna è selezionata come "best-in-class".

6. **Type-Safe Data Handling**: Sistema di schema compile-time per validazione e serializzazione dati.

7. **Compiler-Friendly**: Permettiamo a LDC2 con -O3 di fare il suo lavoro. Implementiamo solo ottimizzazioni che il compiler non può fare.

### 1.3 Performance Targets (Hard Requirements)

Su hardware di riferimento (Intel Xeon/AMD EPYC, 16+ core, 10Gbit NIC):

- **Throughput plaintext**: ≥ 95% delle prestazioni di un server HTTP manuale su eventcore
- **Latency p99 (hello world)**: < 100μs @ 10K RPS
- **Allocations per request**: 0 nel core framework (esclusi handler utente)
- **Context switches per request**: ≤ 1 (fiber switch)
- **CPU efficiency**: > 90% user-space time sotto carico
- **Memory efficiency**: < 50KB per connessione concorrente
- **Scalability**: Linear scaling fino a saturazione NIC su tutti i core disponibili

---

## 2. TECHNOLOGY STACK & DEPENDENCIES

### 2.1 Language & Compiler

**Language**: D (versione minima: 2.105)  
**Primary Compiler**: LDC (LLVM-based) per produzione  
**Secondary Compiler**: DMD per sviluppo rapido

**Rationale**: LDC offre ottimizzazioni LLVM (PGO, LTO, auto-vectorization) critiche per performance.

**Compiler Recommendations**:
- Produzione: Use `-O3 -release -boundscheck=off -mcpu=native` come minimo
- Consider `-flto=full` per cross-module inlining
- Use PGO quando possibile: compilare con profiling, generare profilo, ricompilare con profilo
- Il compiler con -O3 gestisce: inlining, loop unrolling, constant propagation, vectorization automatica

> [!TIP]
> Lasciare che il compiler faccia il suo lavoro. Non forzare inline, unrolling, o branch hints senza profiling data.

### 2.2 Core Dependencies (Mandatory, No Alternatives)

#### 2.2.1 I/O Asynchronous Layer
**Library**: `eventcore` (latest stable)  
**Purpose**: Cross-platform event loop abstraction (epoll/kqueue/IOCP/io_uring)  
**Integration**: Direct API usage, no high-level wrappers

**Configuration**:
- Linux: Prefer io_uring when kernel ≥ 5.10, fallback to epoll
- macOS: kqueue
- Windows: IOCP

#### 2.2.2 Fiber Runtime
**Library**: `vibe-core` (isolated from vibe-d web stack)  
**Purpose**: Cooperative multitasking, fiber scheduling, synchronization primitives  
**Integration**: Use only `vibe.core.task`, `vibe.core.sync`, `vibe.core.core`

**Constraints**:
- MUST NOT import any vibe-d HTTP/REST modules
- MUST NOT use vibe-d's HTTP server implementation
- Use only for fiber primitives and event integration

#### 2.2.3 HTTP Parser
**Library**: `Wire` (D wrapper for llhttp, version ≥ 1.0.0)  
**Repository**: [github.com/federikowsky/Wire](https://github.com/federikowsky/Wire)  
**Purpose**: HTTP/1.1 parsing, zero-copy, zero-allocation, fully compliant with RFC 7230

**Key Features**:
- Zero allocations during parsing (complete @nogc)
- Parse time: 1-7 μs per request
- Throughput: 300-2,000 MB/sec
- Thread-local parser pooling
- Cache-optimized data structures (64-byte aligned)
- Battle-tested (llhttp used by Node.js)

**API Example**:
```d
import wire;

auto req = parseHTTP(data);  // @nogc nothrow
if (!req) {
    // Parse error
    return;
}

auto method = req.getMethod();  // StringView (zero-copy)
auto path = req.getPath();
auto host = req.getHeader("Host");
```

**Supported**:
- ✅ HTTP/1.1 only
- ✅ All standard methods (GET, POST, PUT, DELETE, etc.)
- ✅ Keep-alive connection management
- ✅ Up to 64 headers per request

**NOT Supported** (out of scope):
- ❌ HTTP/2, HTTP/3 (handled by reverse proxy)
- ❌ WebSocket protocol (only headers parsed)
- ❌ Chunked encoding parsing (body as-is)
- ❌ Multipart body parsing (raw bytes only)

#### 2.2.4 JSON Parser
**Library**: `simdjson` (C++ library, version ≥ 3.0)  
**Purpose**: JSON parsing with SIMD acceleration (GB/s throughput)  
**Binding**: Custom D binding with @nogc interface

**Requirements**:
- On-demand parsing (lazy field access)
- Zero-copy string views into original buffer
- Validation in single pass
- Support for streaming API for large payloads

#### 2.2.5 TLS/HTTPS Support
**Decisione Architetturale**: Aurora **NON gestisce TLS/HTTPS direttamente**.

**Filosofia**: Aurora è un framework minimalista che gestisce solo plain HTTP. TLS/HTTPS è responsabilità del reverse proxy (nginx, Caddy, Traefik, etc.).

**Pattern**: Allineato con framework leader (Express.js, Flask, Gin, Koa) che delegano TLS a reverse proxy.

**Setup Produzione**:
- Aurora ascolta su porta HTTP (es. 8080)
- Reverse proxy (nginx/Caddy) gestisce TLS/HTTPS su porta 443
- Reverse proxy fa proxy_pass a Aurora su porta 8080
- Aurora riceve solo plain HTTP (già decriptato)

**Vantaggi**:
- Aurora rimane minimalista e focalizzato su performance
- Reverse proxy gestisce certificati, renewal, OCSP stapling
- Separazione delle responsabilità (infrastruttura vs applicazione)
- Pattern standard nell'industria

#### 2.2.6 Compression
**Library**: `zlib-ng` (zlib replacement with SIMD, version ≥ 2.1)  
**Purpose**: gzip/deflate with AVX2/NEON acceleration  
**Binding**: Direct C binding

**Usage**: Optional middleware for response compression (disabled by default for performance)

### 2.3 Additional Dependencies (Selected Best-in-Class)

#### 2.3.1 Memory Allocator
**Library**: `mimalloc` (Microsoft, version ≥ 2.1)  
**Purpose**: High-performance allocator with thread-local caching  
**Integration**: Linked as system allocator replacement

**Rationale**: Superior fragmentation behavior, O(1) allocations, excellent multi-thread scaling

#### 2.3.2 Hashing
**Library**: `xxHash` (version ≥ 0.8)  
**Purpose**: Non-cryptographic hash for routing, caching  
**Binding**: Custom D binding

**Rationale**: xxHash3 offers 30GB/s+ throughput, ideal for hot paths

#### 2.3.3 Logging Backend
**Implementation**: Custom implementation using memory-mapped ring buffers  
**Purpose**: Lock-free logging with async flush  
**No external dependency**

#### 2.3.4 Metrics
**Implementation**: Custom Prometheus-compatible exporter  
**Purpose**: /metrics endpoint with lock-free counters  
**No external dependency**

---

## 3. ARCHITECTURE OVERVIEW

### 3.1 Layered Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    USER APPLICATION LAYER                    │
│  (Handlers, Middleware, Business Logic - GC allowed)         │
└─────────────────────────────────────────────────────────────┘
                              ↕
┌─────────────────────────────────────────────────────────────┐
│                    FRAMEWORK API LAYER                       │
│  (Router, Context, HTTPRequest/HTTPResponse, Schema)         │
│                       @nogc boundary                          │
└─────────────────────────────────────────────────────────────┘
                              ↕
┌─────────────────────────────────────────────────────────────┐
│                  PROTOCOL PROCESSING LAYER                   │
│  (HTTP parser, Keep-alive, Chunked, Compression)             │
│                      @nogc required                           │
└─────────────────────────────────────────────────────────────┘
                              ↕
┌─────────────────────────────────────────────────────────────┐
│                   CONCURRENCY RUNTIME LAYER                  │
│  (Fiber scheduler, Work stealing, Task queue)                │
│                      @nogc required                           │
└─────────────────────────────────────────────────────────────┘
                              ↕
┌─────────────────────────────────────────────────────────────┐
│                     I/O REACTOR LAYER                        │
│  (eventcore wrapper, Socket management, Timers)              │
│                      @nogc required                           │
└─────────────────────────────────────────────────────────────┘
                              ↕
┌─────────────────────────────────────────────────────────────┐
│                    SYSTEM INTERFACE LAYER                    │
│  (eventcore → epoll/kqueue/IOCP/io_uring)                    │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Module Breakdown

#### 3.2.1 Runtime Modules (aurora.runtime.*)

- **aurora.runtime.reactor**: Event loop wrapper, socket lifecycle
- **aurora.runtime.scheduler**: Fiber scheduling, work stealing
- **aurora.runtime.worker**: Worker thread abstraction
- **aurora.runtime.fiber**: Fiber management, context switching

#### 3.2.2 Memory Modules (aurora.mem.*)

- **aurora.mem.pool**: Buffer pools, object pools
- **aurora.mem.allocator**: Custom allocator abstraction
- **aurora.mem.arena**: Arena allocator for temporary allocations

#### 3.2.3 Network Modules (aurora.net.*)

- **aurora.net.http**: HTTP/1.1 server implementation (Wire integration)
- **aurora.net.socket**: Socket abstraction, connection management
- **aurora.net.listener**: Accept loop, connection dispatcher

**Note**: 
- TLS/HTTPS is handled by reverse proxy (nginx, Caddy)
- HTTP/2, HTTP/3 are handled by reverse proxy
- Aurora focuses ONLY on HTTP/1.1

#### 3.2.4 Web Framework Modules (aurora.web.*)

- **aurora.web.router**: Radix tree router, path matching
- **aurora.web.context**: Request context, lifetime management
- **aurora.web.middleware**: Middleware pipeline, execution chain
- **aurora.web.response**: Response builder, streaming, status codes
- **aurora.web.handler**: Handler abstraction, routing integration

#### 3.2.5 Schema System Modules (aurora.schema.*)

- **aurora.schema.base**: BaseSchema, BaseSettings classes
- **aurora.schema.validation**: Validation engine, UDA processing
- **aurora.schema.codegen**: Compile-time code generation
- **aurora.schema.attributes**: UDA definitions (@Required, @Range, etc.)

#### 3.2.6 Extension Modules (aurora.ext.*)

Aurora provides only framework-inherent extensions directly related to HTTP protocol handling.

**Philosophy**: Aurora focuses on CORE infrastructure only. Business logic (JWT, rate limiting) must be provided by external libraries chosen by the user.

**V0 Modules** (framework-inherent only):

- **aurora.ext.cors**:
  - CORS (Cross-Origin Resource Sharing) middleware
  - This is framework-inherent (HTTP headers), not business logic
  - Handles preflight requests (OPTIONS) and adds CORS headers

- **aurora.ext.security**:
  - Security headers middleware (CSP, HSTS, X-Frame-Options, etc.)
  - This is framework-inherent (HTTP headers), not business logic

> [!IMPORTANT]
> These are the ONLY extension modules in V0. All other functionality (JWT, rate limiting, metrics, logging) must be implemented by the user using external libraries.

#### 3.2.7 Utility Modules (aurora.util.*)

- **aurora.util.config**: Configuration system, ENV loading

- **aurora.util.hash**: xxHash wrappers
- **aurora.util.string**: String operations, parsing
- **aurora.util.time**: High-resolution timing, date parsing
- **aurora.util.intrinsics**: SIMD wrappers, CPU detection
- **aurora.util.log**: Lock-free logging infrastructure
- **aurora.util.metrics**: Lock-free metrics counters

---

## 4. SCHEMA SYSTEM (Pydantic-like for D)

**Package**: `aurora.schema.*`

### 4.1 Design Philosophy

**Obiettivo**: Fornire un sistema type-safe, compile-time validato per:
- Parsing e validazione input HTTP (JSON/form data)
- Serializzazione output
- Gestione configurazioni e variabili d'ambiente
- Zero boilerplate, massima ergonomia

**Principi**:
- **Compile-Time Validation**: Errori di schema rilevati a compile-time
- **Zero Runtime Overhead**: Tutta la reflection/codegen a compile-time
- **Type Safety**: Impossibile avere type mismatch tra schema e dati
- **Composable**: Schema nidificabili e riutilizzabili
- **Minimal Boilerplate**: UDA (User Defined Attributes) per metadati

### 4.2 Core Components

#### 4.2.1 BaseSchema (Input/Output Models)

Classe base per definire modelli di dati con validazione automatica.

#### 4.2.2 BaseSettings (Configuration Management)

Classe base per configurazioni con supporto ENV variables.

#### 4.2.3 User Defined Attributes (UDA)

Available validation attributes:
- `@Required`, `@Optional`
- `@Alias("json_name")`
- `@Range(min, max)`, `@MinLength(n)`, `@MaxLength(n)`
- `@Email`, `@URL`, `@Pattern("regex")`
- `@Validator(func, "error message")`

### 4.3 Performance Characteristics

**Compile-Time Overhead**: +5-10% compilation time (one-time cost)

**Runtime Performance**:
- **Parsing**: ~90% velocità di simdjson raw (overhead validation)
- **Serialization**: ~95% velocità di hand-written JSON builder
- **Validation**: O(fields) linear scan
- **Memory**: Zero allocazioni extra vs hand-written

> [!NOTE]
> Il compiler con -O3 ottimizzerà automaticamente le validation checks generate a compile-time.

---

## 5. CORE RUNTIME ARCHITECTURE

**Package**: `aurora.runtime.*`

### 5.1 Threading Model

#### 5.1.1 Thread Architecture

**Formula Worker Count**:
```d
numWorkers = max(1, numPhysicalCores - 1);
// -1 per lasciare spazio ad acceptor thread + OS
```

**Thread Roles**:
- **Worker Threads** (N): Handle HTTP requests, run fibers, event loops
- **Acceptor Thread** (1): Dedicated accept() loop, distribuisce connessioni ai workers
- **Auxiliary Threads** (0-2): Async logging flush, metrics aggregation (optional)

**Rationale**: 
- 1 worker per core fisico (non logico) per massimizzare cache L1/L2 hit
- Hyperthreading aumenta contention su cache, meglio evitare
- Acceptor thread separato evita contention su accept() mutex

#### 5.1.2 Worker Thread Structure

**Worker Struct** (`aurora.runtime.worker`):
```d
align(64) struct Worker {  // Cache-line aligned
    // Hot data (first 64 bytes)
    uint id;                        // Worker ID (0..N-1)
    Thread thread;                  // OS thread handle
    Reactor* reactor;               // Event loop (eventcore wrapper)
    FiberScheduler* scheduler;      // Fiber ready queue
    
    // Memory management
    MemoryPool* memoryPool;         // Thread-local buffer pool
    ArenaAllocator* arena;          // Temporary allocations
    
    // NUMA affinity
    uint numaNode;                  // NUMA node ID
    cpu_set_t cpuMask;              // CPU affinity mask
    
    // Stats (separate cache line to avoid false sharing)
    align(64) struct Stats {
        ulong requestsProcessed;
        ulong bytesReceived;
        ulong bytesSent;
        ulong fibersExecuted;
        ulong eventsProcessed;
    }
    
    // Cold data
    string name;                    // "Worker-0", "Worker-1", ...
    bool running;                   // Shutdown flag
}
```

**Worker Lifecycle**:
```d
// 1. Initialization (main thread)
void initWorkers(uint numWorkers) {
    detectNUMATopology();
    
    for (uint i = 0; i < numWorkers; i++) {
        worker = &workers[i];
        worker.id = i;
        worker.numaNode = i % numNUMANodes;
        
        // Allocate on correct NUMA node
        worker.memoryPool = allocateOnNUMA(worker.numaNode);
        worker.reactor = new Reactor();
        worker.scheduler = new FiberScheduler();
        
        // Launch thread
        worker.thread = new Thread(&workerMain, worker);
        worker.thread.start();
    }
}

// 2. Worker Main Loop (worker thread)
void workerMain(Worker* worker) @nogc {
    // Set thread affinity
    setThreadAffinity(worker.cpuMask);
    
    // Worker run loop
    while (worker.running) {
        // Try get fiber from scheduler
        fiber = worker.scheduler.dequeue();
        
        if (fiber) {
            // Execute fiber until yield/complete
            fiber.resume();
            worker.stats.fibersExecuted++;
        } else {
            // No work, poll for events
            worker.reactor.poll(timeout: 1.msecs);
        }
    }
    
    // Cleanup
    worker.reactor.shutdown();
    worker.memoryPool.flush();
}

// 3. Shutdown (main thread)
void shutdownWorkers() {
    foreach (worker; workers) {
        worker.running = false;
    }
    
    foreach (worker; workers) {
        worker.thread.join();
    }
}
```

#### 5.1.3 Thread Affinity & NUMA

**NUMA Topology Detection**:
```d
struct NUMATopology {
    uint numNodes;                  // Number of NUMA nodes
    uint coresPerNode;              // Cores per node
    uint[] nodeForCore;             // nodeForCore[coreId] = numaNode
}

NUMATopology detectNUMATopology() {
    version(linux) {
        // Use libnuma or /sys/devices/system/node/
        return detectNUMALinux();
    } else {
        // Fallback: assume single NUMA node
        return NUMATopology(1, totalCores, ...);
    }
}
```

**Thread Pinning Strategy**:
```d
void setThreadAffinity(Worker* worker) {
    version(linux) {
        cpu_set_t cpuset;
        CPU_ZERO(&cpuset);
        
        // Pin to specific core on NUMA node
        uint coreId = worker.id % coresPerNode;
        uint node = worker.numaNode;
        uint globalCore = node * coresPerNode + coreId;
        
        CPU_SET(globalCore, &cpuset);
        pthread_setaffinity_np(pthread_self(), sizeof(cpuset), &cpuset);
    }
}
```

**Memory Affinity**:
```d
// Allocate memory on specific NUMA node
void* allocateOnNUMA(uint numaNode, size_t size) {
    version(linux) {
        // Use numa_alloc_onnode()
        return numa_alloc_onnode(size, numaNode);
    } else {
        // Fallback to regular malloc
        return malloc(size);
    }
}
```

**Benefits**:
- ✅ Workers access local memory (low latency)
- ✅ No cross-NUMA traffic for hot paths
- ✅ Cache locality preserved (worker → core → L1/L2 cache)
- ✅ Predictable performance (no core migration penalties)

**Config Option**:
```d
struct ServerConfig {
    bool enableNUMAAffinity = true;   // Auto-detect and pin
    bool enableCPUAffinity = true;    // Pin workers to cores
    uint forcedNUMANode = uint.max;   // Override (for testing)
}
```


### 5.2 Fiber Scheduling

**Package**: `aurora.runtime.scheduler`

Aurora uses **vibe-core** for fiber primitives but implements a custom scheduler integrated with the event loop.

#### 5.2.1 Fiber Model

**vibe-core Integration**:
```d
import vibe.core.task;

// Fiber creation (vibe-core API)
auto fiber = runTask({
    handleRequest(connection);
});

// Fiber yielding
fiber.yield();  // Suspend until resume

// Fiber sleep (event-driven)
sleep(100.msecs);  // Yields fiber, wakes on timer
```

**Fiber States**:
- `READY`: In scheduler queue, waiting to run
- `RUNNING`: Currently executing on worker
- `WAITING`: Suspended on I/O or timer
- `COMPLETED`: Finished execution, ready for cleanup

#### 5.2.2 Scheduler Implementation

**vibe-core TaskQueue Integration**:
```d
// Aurora wraps vibe-core scheduler
struct FiberScheduler {
    // vibe-core manages fiber queue internally
    // Aurora only needs to integrate with event loop
    
    void scheduleTask(void delegate() @safe nothrow task) {
        runTask(task);  // vibe-core API
    }
    
    void yield() {
        Task.yield();  // vibe-core API
    }
    
    void sleep(Duration timeout) {
        vibe.core.core.sleep(timeout);  // vibe-core sleep
    }
}
```

**Worker Event Loop Integration**:
```d
void workerMain(Worker* worker) {
    // vibe-core event loop integration
    runEventLoop();  // vibe-core manages fiber scheduling + event loop
}
```

> [!NOTE]
> **vibe-core handles**:  
> - Fiber creation, suspension, resumption
> - Event loop integration (via eventcore)
> - Task queue management
>  
> **Aurora adds**:  
> - HTTP-specific connection handling
> - Request routing and middleware execution
> - Memory pool integration

#### 5.2.3 Work Stealing (Future Enhancement)

**Current V0**: NO work stealing (vibe-core default per-thread scheduling)

**Future**: Implement custom work-stealing queue on top of vibe-core:
```d
// Future enhancement (not in V0)
Fiber* tryStealFromOthers() {
    for (otherWorker in workers) {
        if (fiber = otherWorker.scheduler.steal()) {
            return fiber;
        }
    }
    return null;
}
```

**V0 Decision**: KISS principle - use vibe-core defaults, optimize later if needed.

---

### 5.3 Event Loop (Reactor)

**Package**: `aurora.runtime.reactor`

Aurora wraps **eventcore** for event loop, integrated with **vibe-core** fiber scheduling.

#### 5.3.1 Reactor Interface

**Reactor Design** (thin wrapper around eventcore):
```d
struct Reactor {
    EventDriver driver;  // eventcore driver (platform-specific)
    
    // Poll for events (called by vibe-core event loop)
    void poll(Duration timeout) @nogc {
        driver.processEvents(timeout);
    }
    
    // Register socket for events
    void registerSocket(Socket socket, EventMask mask, void delegate() callback) {
        driver.registerFD(socket.handle, mask, callback);
    }
    
    // Unregister socket
    void unregisterSocket(Socket socket) {
        driver.unregisterFD(socket.handle);
    }
}
```

**Event Types** (eventcore):
- `FDRead`: Socket readable
- `FDWrite`: Socket writable
- `Timer`: Timeout expired
- `Signal`: OS signal received

#### 5.3.2 eventcore Platform Backends

**Linux (io_uring / epoll)**:
```d
version(linux) {
    // Prefer io_uring (kernel >= 5.10)
    if (hasIOUring()) {
        driver = createIOUringDriver();
    } else {
        driver = createEpollDriver();
    }
}
```

**macOS (kqueue)**:
```d
version(OSX) {
    driver = createKqueueDriver();
}
```

**Windows (IOCP)**:
```d
version(Windows) {
    driver = createIOCPDriver();
}
```

**vibe-core Integration**:
```d
// vibe-core automatically uses eventcore
// Aurora doesn't need to manage this directly
runEventLoop();  // vibe-core + eventcore integration
```

#### 5.3.3 Timer Management

**Timer Wheel** (vibe-core provides):
```d
// Register timeout (vibe-core API)
auto timer = setTimer(timeout, {
    onTimeout(connection);
});

// Cancel timer
timer.stop();
```

**Connection Timeouts**:
- Read timeout: 30s default
- Write timeout: 30s default
- Keep-alive timeout: 60s default
- Idle timeout: 120s default

```d
struct ConnectionTimeouts {
    Duration readTimeout = 30.seconds;
    Duration writeTimeout = 30.seconds;
    Duration keepAliveTimeout = 60.seconds;
    Duration idleTimeout = 120.seconds;
}
```

---

### 5.4 Connection Management

**Package**: `aurora.net.http`

#### 5.4.1 Connection State Machine (Event-Driven)

**Critical**: Aurora uses **event-driven** connection handling (NO blocking `while` loops).

**Connection States**:
```d
enum ConnectionState {
    NEW,                // Just accepted
    READING_HEADERS,    // Reading HTTP request line + headers
    READING_BODY,       // Reading request body (if present)
    PROCESSING,         // Executing handler (user code)
    WRITING_RESPONSE,   // Sending HTTP response
    KEEP_ALIVE,         // Waiting for next request on same connection
    CLOSING             // Shutdown initiated
}
```

**Connection Struct**:
```d
align(64) struct Connection {
    // Hot data (first cache line)
    Socket socket;
    ConnectionState state;
    Worker* worker;              // Owner worker
    Fiber fiber;                 // Handler fiber (vibe-core)
    
    // Buffers
    ubyte[] readBuffer;          // From memoryPool
    size_t readPos;              // Current read position
    ubyte[] writeBuffer;         // Response buffer
    size_t writePos;             // Current write position
    
    // Parsed request (from Wire)
    ParsedHttpRequest* wireRequest;
    
    // Aurora request/response
    HTTPRequest request;
    HTTPResponse response;
    
    // Timers
    TimerID readTimer;
    TimerID writeTimer;
    TimerID keepAliveTimer;
    
    // Metadata
    MonoTime lastActivity;
    bool keepAlive;
    
    // Stats
    ulong requestsServed;
}
```

#### 5.4.2 Event-Driven Connection Flow

**Pattern**: Event handlers called when events arrive (NO polling loops!)

```d
// Connection accepted (acceptor thread)
void onConnectionAccepted(Socket socket) {
    // Dispatch to worker (round-robin)
    worker = selectWorker();
    
    // Create fiber for this connection
    runTask({
        handleConnection(worker, socket);
    });
}

// Fiber: handle connection lifecycle
void handleConnection(Worker* worker, Socket socket) @safe {
    conn = allocateConnection(worker, socket);
    conn.state = ConnectionState.READING_HEADERS;
    
    // Register for read events
    worker.reactor.registerSocket(socket, FDRead, {
        onReadable(conn);
    });
    
    // Set read timeout
    conn.readTimer = setTimer(readTimeout, {
        onReadTimeout(conn);
    });
    
    // Yield fiber, wait for event
    yield();
}

// Event: socket readable
void onReadable(Connection* conn) @nogc {
    // Read data
    n = conn.socket.receive(conn.readBuffer[conn.readPos .. $]);
    if (n <= 0) {
        closeConnection(conn);
        return;
    }
    
    conn.readPos += n;
    conn.lastActivity = MonoTime.currTime;
    
    // Try parse HTTP request
    auto req = parseHTTP(conn.readBuffer[0 .. conn.readPos]);
    
    if (!req) {
        if (req.getErrorCode() != 0) {
            // Parse error
            sendBadRequest(conn);
            return;
        }
        // Need more data, wait for next read event
        return;
    }
    
    // Parse success!
    conn.state = ConnectionState.PROCESSING;
    conn.wireRequest = req;
    
    // Cancel read timer
    conn.readTimer.stop();
    
    // Route and execute handler
    routeAndExecute(conn);
}

// Route request and execute handler
void routeAndExecute(Connection* conn) {
    auto handler = router.match(
        conn.wireRequest.getMethod(),
        conn.wireRequest.getPath()
    );
    
    if (!handler) {
        send404(conn);
        return;
    }
    
    // Build request context
    buildRequestContext(conn);
    
    // Execute handler (user code - can use GC)
    try {
        handler(conn.request, conn.response);
    } catch (Exception e) {
        send500(conn, e);
        return;
    }
    
    // Send response
    conn.state = ConnectionState.WRITING_RESPONSE;
    sendResponse(conn);
}

// Send HTTP response
void sendResponse(Connection* conn) {
    // Build response headers
    buildResponseHeaders(conn);
    
    // Register for write events
    conn.worker.reactor.registerSocket(conn.socket, FDWrite, {
        onWritable(conn);
    });
    
    // Set write timeout
    conn.writeTimer = setTimer(writeTimeout, {
        onWriteTimeout(conn);
    });
    
    yield();
}

// Event: socket writable
void onWritable(Connection* conn) @nogc {
    // Write response data
    n = conn.socket.send(conn.writeBuffer[conn.writePos .. $]);
    if (n <= 0) {
        closeConnection(conn);
        return;
    }
    
    conn.writePos += n;
    
    // All data sent?
    if (conn.writePos >= conn.writeBuffer.length) {
        conn.writeTimer.stop();
        
        // Check keep-alive
        if (conn.keepAlive) {
            resetConnection(conn);  // Reuse for next request
            conn.state = ConnectionState.KEEP_ALIVE;
        } else {
            closeConnection(conn);
        }
    }
}

// Timeout handlers
void onReadTimeout(Connection* conn) {
    // Client too slow, close
    closeConnection(conn);
}

void onWriteTimeout(Connection* conn) {
    // Send timeout, close
    closeConnection(conn);
}
```

**Benefits**:
- ✅ Zero CPU usage when idle (fiber sleeps)
- ✅ Scalable (thousands of connections = zero overhead)
- ✅ No busy-wait loops
- ✅ Pattern standard in async frameworks (Node.js, Tokio, async/await)

#### 5.4.3 Connection Pool

**Connection Reuse** (keep-alive):
```d
void resetConnection(Connection* conn) {
    // Reset for next request on same connection
    conn.readPos = 0;
    conn.writePos = 0;
    conn.wireRequest = null;
    conn.state = ConnectionState.READING_HEADERS;
    conn.lastActivity = MonoTime.currTime;
    
    // Re-register for read
    conn.worker.reactor.registerSocket(conn.socket, FDRead, {
        onReadable(conn);
    });
    
    // Set keep-alive timeout
    conn.keepAliveTimer = setTimer(keepAliveTimeout, {
        closeConnection(conn);
    });
}
```

**Pool Management**:
```d
// Per-worker connection pool (avoid allocations)
struct ConnectionPool {
    Connection[MAX_CONNECTIONS_PER_WORKER] pool;
    Connection*[] freeList;
    
    Connection* allocate() @nogc {
        if (freeList.length > 0) {
            return freeList.popBack();
        }
        return null;  // Pool exhausted
    }
    
    void release(Connection* conn) @nogc {
        conn.reset();
        freeList ~= conn;
    }
}
```

---

## 6. MEMORY MANAGEMENT

### 6.1 Memory Architecture

**Package**: `aurora.mem.*`

**Principle**: Zero allocazioni GC durante gestione richiesta HTTP nel core framework.

**Memory Zones**:
```
┌─────────────────────────────────────────────┐
│  User Handler Zone (GC allowed)             │  ← Application code
├─────────────────────────────────────────────┤
│  Framework Zone (@nogc boundary)            │  ← Aurora framework
│  - Schema validation                        │
│  - Middleware execution                     │
│  - Routing                                  │
├─────────────────────────────────────────────┤
│  Core Zone (@nogc required)                 │  ← HTTP/Network core
│  - HTTP parsing (Wire)                      │
│  - Connection handling                      │
│  - Buffer management                        │
│  - Event loop                               │
└─────────────────────────────────────────────┘
```

**Allocator Hierarchy**:
1. **Buffer Pool** (aurora.mem.pool): Pre-allocated buffers, thread-local
2. **Object Pool** (aurora.mem.pool): Reusable objects (Connection, HTTPRequest, etc.)
3. **Arena Allocator** (aurora.mem.arena): Temporary allocations, reset per-request
4. **mimalloc** (fallback): Large/unusual allocations
5. **GC** (user code only): Handler utente può usare GC liberamente

**Allocation Strategy**:
```d
// Hot path (per-request)
buffer = bufferPool.acquire(size);        // O(1) thread-local
conn = connectionPool.acquire();          // O(1) thread-local
tempData = arena.allocate(size);          // O(1) bump allocator

// Cold path (startup, rare)
config = GC.malloc(Config.sizeof);        // Allowed
largeBuffer = mimalloc.malloc(10MB);      // Fallback
```

### 6.2 Buffer Pool

**Package**: `aurora.mem.pool`

#### 6.2.1 Pool Configuration

**Size Buckets** (power-of-2 for alignment):
```d
enum BufferSize {
    TINY   = 1024,      // 1 KB   - Small responses, headers
    SMALL  = 4096,      // 4 KB   - Typical HTTP requests
    MEDIUM = 8192,      // 8 KB   - Large requests
    LARGE  = 65536,     // 64 KB  - File uploads, streaming
}

struct BufferPoolConfig {
    uint tinyBuffers = 256;      // 256 KB total
    uint smallBuffers = 128;     // 512 KB total
    uint mediumBuffers = 64;     // 512 KB total
    uint largeBuffers = 16;      // 1 MB total
    // Total per worker: ~2.25 MB
}
```

#### 6.2.2 Buffer Pool Implementation

**Thread-Local Buffer Pool** (per-worker):
```d
struct BufferPool {
    // Size bucket arrays (pre-allocated at startup)
    align(64) ubyte[][] tinyBuffers;
    align(64) ubyte[][] smallBuffers;
    align(64) ubyte[][] mediumBuffers;
    align(64) ubyte[][] largeBuffers;
    
    // Free lists (lock-free, thread-local)
    ubyte[]*[] tinyFreeList;
    ubyte[]*[] smallFreeList;
    ubyte[]*[] mediumFreeList;
    ubyte[]*[] largeFreeList;
    
    // Stats
    ulong acquireCount;
    ulong releaseCount;
    ulong fallbackCount;      // Fallback to mimalloc
    
    // Initialize pool (called once per worker at startup)
    void initialize(BufferPoolConfig config) @nogc {
        // Allocate on correct NUMA node
        tinyBuffers = allocateBuffers(config.tinyBuffers, BufferSize.TINY);
        smallBuffers = allocateBuffers(config.smallBuffers, BufferSize.SMALL);
        mediumBuffers = allocateBuffers(config.mediumBuffers, BufferSize.MEDIUM);
        largeBuffers = allocateBuffers(config.largeBuffers, BufferSize.LARGE);
        
        // Initialize free lists (all buffers available)
        tinyFreeList = tinyBuffers[];
        smallFreeList = smallBuffers[];
        mediumFreeList = mediumBuffers[];
        largeFreeList = largeBuffers[];
    }
    
    // Acquire buffer (O(1) thread-local)
    ubyte[] acquire(size_t size) @nogc {
        acquireCount++;
        
        // Select bucket
        if (size <= BufferSize.TINY) {
            if (tinyFreeList.length > 0) {
                return popBuffer(tinyFreeList);
            }
        } else if (size <= BufferSize.SMALL) {
            if (smallFreeList.length > 0) {
                return popBuffer(smallFreeList);
            }
        } else if (size <= BufferSize.MEDIUM) {
            if (mediumFreeList.length > 0) {
                return popBuffer(mediumFreeList);
            }
        } else if (size <= BufferSize.LARGE) {
            if (largeFreeList.length > 0) {
                return popBuffer(largeFreeList);
            }
        }
        
        // Pool exhausted, fallback to mimalloc
        fallbackCount++;
        return cast(ubyte[]) mimalloc.malloc(size)[0..size];
    }
    
    // Release buffer (O(1) thread-local)
    void release(ubyte[] buffer) @nogc {
        releaseCount++;
        
        // Determine bucket by size
        if (buffer.length == BufferSize.TINY) {
            tinyFreeList ~= buffer.ptr;
        } else if (buffer.length == BufferSize.SMALL) {
            smallFreeList ~= buffer.ptr;
        } else if (buffer.length == BufferSize.MEDIUM) {
            mediumFreeList ~= buffer.ptr;
        } else if (buffer.length == BufferSize.LARGE) {
            largeFreeList ~= buffer.ptr;
        } else {
            // Was allocated by mimalloc, free it
            mimalloc.free(buffer.ptr);
        }
    }
}
```

**Benefits**:
- ✅ O(1) acquire/release (no allocation, just pop/push from free list)
- ✅ Thread-local (zero contention, no locks)
- ✅ NUMA-aware (allocated on correct node at startup)
- ✅ Predictable (no GC pauses, deterministic timing)
- ✅ Fallback (mimalloc for unusual sizes)

### 6.3 Object Pools

**Package**: `aurora.mem.pool`

#### 6.3.1 Pooled Types

**Objects to Pool**:
```d
// Connection objects (reused per keep-alive)
struct ConnectionPool {
    Connection[MAX_CONNECTIONS_PER_WORKER] pool;
    Connection*[] freeList;
}

// HTTPRequest objects (reused per request)
struct HTTPRequestPool {
    HTTPRequest[MAX_CONCURRENT_REQUESTS] pool;
    HTTPRequest*[] freeList;
}

// HTTPResponse objects (reused per request)
struct HTTPResponsePool {
    HTTPResponse[MAX_CONCURRENT_REQUESTS] pool;
    HTTPResponse*[] freeList;
}
```

#### 6.3.2 Generic Object Pool

**Template**:
```d
struct ObjectPool(T) {
    T[] pool;              // Pre-allocated objects
    T*[] freeList;         // Available objects
    
    // Initialize pool
    void initialize(uint capacity) @nogc {
        pool = allocateOnNUMA(capacity * T.sizeof);
        freeList = pool.ptr[0..capacity];
    }
    
    // Acquire object (O(1))
    T* acquire() @nogc {
        if (freeList.length > 0) {
            return freeList.popBack();
        }
        return null;  // Pool exhausted
    }
    
    // Release object (O(1))
    void release(T* obj) @nogc {
        obj.reset();  // Clear state
        freeList ~= obj;
    }
}
```

**Usage**:
```d
// Per-worker object pools
struct Worker {
    ObjectPool!Connection connectionPool;
    ObjectPool!HTTPRequest requestPool;
    ObjectPool!HTTPResponse responsePool;
}

// Allocate connection
conn = worker.connectionPool.acquire();
// ... use connection ...
// Release back to pool
worker.connectionPool.release(conn);
```

### 6.4 Arena Allocator

**Package**: `aurora.mem.arena`

**Purpose**: Super-fast temporary allocations that are reset after request completes.

**Arena Implementation**:
```d
struct ArenaAllocator {
    ubyte[] buffer;        // Large pre-allocated buffer (e.g., 1 MB)
    size_t offset;         // Current allocation offset
    
    // Initialize arena
    void initialize(size_t capacity) @nogc {
        buffer = allocateOnNUMA(capacity);
        offset = 0;
    }
    
    // Allocate (O(1) bump allocator)
    void* allocate(size_t size) @nogc {
        // Align to 8 bytes
        size = (size + 7) & ~7;
        
        if (offset + size > buffer.length) {
            // Arena exhausted, fallback
            return mimalloc.malloc(size);
        }
        
        void* ptr = buffer.ptr + offset;
        offset += size;
        return ptr;
    }
    
    // Reset arena (O(1))
    void reset() @nogc {
        offset = 0;  // Just reset offset, no freeing!
    }
}
```

**Usage Pattern**:
```d
// Per-request lifecycle
void handleRequest(Connection* conn, Worker* worker) {
    // Allocate temporary data from arena
    tempBuffer = worker.arena.allocate(1024);
    parsedJson = worker.arena.allocate(JSONNode.sizeof);
    
    // ... use temp data ...
    
    // After request complete
    worker.arena.reset();  // O(1) reset, reuse arena
}
```

**Benefits**:
- ✅ O(1) allocate (just increment offset)
- ✅ O(1) reset (entire arena ready for reuse)
- ✅ Cache-friendly (sequential allocations)
- ✅ Zero fragmentation

### 6.5 GC Integration

**@nogc Boundaries**:
```d
// Core framework: @nogc required
@nogc nothrow
void handleConnectionCore(Connection* conn) {
    // All core operations @nogc
    parseHTTP(buffer);
    matchRoute(path);
    buildResponse(response);
}

// User handler: GC allowed
void userHandler(HTTPRequest req, HTTPResponse res) {
    // Can use GC freely
    string[] data = database.query("SELECT ...");
    auto json = serializeToJSON(data);  // GC allocations OK
    res.json(json);
}
```

**Escape Hatches** (when user needs @nogc):
```d
// User can opt-in to @nogc if desired
@nogc nothrow
void performanceHandler(HTTPRequest req, HTTPResponse res) {
    // User takes responsibility for @nogc
    // Must use manual memory management
}
```

### 6.6 Cache-Line Alignment & False Sharing Prevention

**Package**: `aurora.mem.*`

#### 6.6.1 Critical Structures

**Worker Stats** (separate cache lines):
```d
align(64) struct Worker {
    // Hot data (first 64 bytes - cache line 0)
    uint id;
    Thread thread;
    Reactor* reactor;
    FiberScheduler* scheduler;
    // ... 32 more bytes ...
    
    // Stats (separate cache line - cache line 1)
    align(64) struct Stats {
        ulong requestsProcessed;
        ulong bytesReceived;
        ulong bytesSent;
        ubyte[40] _padding;  // Pad to 64 bytes
    }
}
```

**Connection** (hot path optimization):
```d
align(64) struct Connection {
    // Hot data accessed by event handlers (first 64 bytes)
    Socket socket;
    ConnectionState state;
    Worker* worker;
    ubyte[] readBuffer;
    size_t readPos;
    // ...
    
    // Cold data (rarely accessed)
    string debugInfo;
    ulong connectionId;
}
```

#### 6.6.2 False Sharing Prevention

**Problem**: Multiple workers writing to nearby memory causes cache line ping-pong.

**Solution**: Separate cache lines for per-worker data.

```d
// BAD: False sharing!
struct BadWorkerArray {
    ulong workerStats[NUM_WORKERS];  // Adjacent memory!
}

// GOOD: Cache-line separated
struct GoodWorkerArray {
    align(64) struct PerWorkerStats {
        ulong requests;
        ubyte[56] _padding;  // Ensure 64-byte size
    }
    PerWorkerStats stats[NUM_WORKERS];  // Each worker on own cache line
}
```

**Verification**:
```d
static assert(Worker.Stats.sizeof == 64);
static assert(Worker.Stats.alignof == 64);
```

---

## 7. HTTP PROTOCOL LAYER

**Package**: `aurora.net.http`

### 7.1 HTTP Parser Integration (Wire)

**Integration Point**: Aurora uses Wire library for all HTTP parsing.

**Wire Features Used**:
- Zero-copy `StringView` for all string data
- Thread-local parser pooling (automatic)
- @nogc parsing with 1-7 μs latency
- Cache-optimized `ParsedHttpRequest` structure

**Aurora's Responsibility**:
- Socket I/O and buffering
- Connection lifecycle management
- Request dispatching to router
- Response building and sending

**Parsing Flow**:
```d
// 1. Read from socket
ubyte[] buffer = readFromSocket(socket);

// 2. Parse with Wire
auto req = parseHTTP(buffer);  // @nogc, 1-7 μs

// 3. Route request
auto handler = router.match(req.getMethod(), req.getPath());

// 4. Execute handler
handler(context);
```

### 7.2 HTTPRequest Representation

**Design**: Thin wrapper around Wire's `ParsedHttpRequest`.

**Aurora HTTPRequest API**:
```d
struct HTTPRequest {
    ParsedHttpRequest* wireRequest;  // Wire parser result
    
    // Zero-copy accessors (delegates to Wire)
    StringView method() @nogc { return wireRequest.getMethod(); }
    StringView path() @nogc { return wireRequest.getPath(); }
    StringView header(string name) @nogc { return wireRequest.getHeader(name); }
    
    // Aurora-specific extensions
    PathParams params;     // Extracted by router
    Context* context;      // Request-scoped data
}
```

### 7.3 HTTPResponse Builder

**Design**: Efficient response builder with write coalescing.

**API**:
```d
struct HTTPResponse {
    void status(int code) @nogc;
    void header(string name, string value) @nogc;
    void body(const(ubyte)[] data) @nogc;
    void json(T)(T data);  // Uses schema serialization
}
```

### 7.4 Keep-Alive Management

HTTP/1.1 persistent connections:
- Default: keep-alive enabled
- Respect `Connection: close` header
- Timeout idle connections (configurable)
- Reuse connection for multiple requests

> [!NOTE]
> **HTTP/1.1 ONLY**: Aurora does NOT support HTTP/2, HTTP/3, WebSocket protocol. These are handled by reverse proxy (nginx, Caddy) if needed.

---

## 8. ROUTING SYSTEM

**Package**: `aurora.web.router`

### 8.1 Router Architecture

**Data Structure**: Radix Tree (Compressed Trie) per O(K) lookup (K = path length)

**Rationale**: 
- ✅ Supports path parameters natively (`/users/:id`)
- ✅ Supports wildcard patterns (`/files/*filepath`)
- ✅ Cache-friendly (prefix sharing reduces memory)
- ✅ O(K) lookup vs O(K) hash + O(N) scan for collisions
- ✅ **Algorithmic choice the compiler cannot make**

### 8.2 Radix Tree Implementation

#### 8.2.1 Node Structure

```d
struct RadixNode {
    // Hot data (first cache line)
    string prefix;              // Path segment (e.g., "/users")
    NodeType type;              // STATIC, PARAM, WILDCARD
    Handler handler;            // Leaf node: request handler
    RadixNode*[] children;      // Child nodes
    
    // Parameter metadata (for :id nodes)
    string paramName;           // "id" in "/users/:id"
    
    // Stats (optional)
    ulong hitCount;             // Route popularity
}

enum NodeType {
    STATIC,      // Exact match: "/users"
    PARAM,       // Parameter: "/:id"
    WILDCARD     // Wildcard: "/*filepath"
}
```

#### 8.2.2 Route Registration

**API**:
```d
interface Router {
    void addRoute(string method, string path, Handler handler);
    Match match(string method, string path);
}

// Example usage
router.addRoute("GET", "/users", &listUsers);
router.addRoute("GET", "/users/:id", &getUser);
router.addRoute("POST", "/users", &createUser);
router.addRoute("GET", "/files/*filepath", &serveFile);
```

**Insertion Algorithm**:
```d
void addRoute(string method, string path, Handler handler) {
    // Get method-specific tree (separate tree per HTTP method)
    tree = methodTrees[method];
    
    // Split path into segments
    segments = path.split("/");  // [users, :id]
    
    // Insert into radix tree
    node = tree.root;
    foreach (segment; segments) {
        node = insertSegment(node, segment);
    }
    
    // Set handler at leaf
    node.handler = handler;
}

RadixNode* insertSegment(RadixNode* node, string segment) {
    // Check for existing child with matching prefix
    foreach (child; node.children) {
        commonLen = longestCommonPrefix(child.prefix, segment);
        
        if (commonLen > 0) {
            if (commonLen < child.prefix.length) {
                // Split existing node
                splitNode(child, commonLen);
            }
            
            if (commonLen < segment.length) {
                // Create new child for remaining segment
                return insertSegment(child, segment[commonLen..$]);
            }
            
            return child;
        }
    }
    
    // No matching child, create new node
    newNode = new RadixNode();
    newNode.prefix = segment;
    newNode.type = detectType(segment);  // STATIC | PARAM | WILDCARD
    node.children ~= newNode;
    return newNode;
}
```

#### 8.2.3 Path Matching (Lookup)

**Matching Algorithm** (O(K) where K = path length):
```d
struct Match {
    bool found;
    Handler handler;
    PathParams params;     // Extracted :param values
}

Match match(string method, string path) @nogc {
    tree = methodTrees[method];
    if (!tree) return Match(false);
    
    // Match path against tree
    params = PathParams();
    handler = matchRecursive(tree.root, path, params);
    
    return Match(handler !is null, handler, params);
}

Handler matchRecursive(RadixNode* node, string path, ref PathParams params) {
    foreach (child; node.children) {
        // Handle different node types
        switch (child.type) {
            case NodeType.STATIC:
                if (path.startsWith(child.prefix)) {
                    remaining = path[child.prefix.length .. $];
                    if (remaining.length == 0) {
                        return child.handler;  // Exact match
                    }
                    return matchRecursive(child, remaining, params);
                }
                break;
                
            case NodeType.PARAM:
                // Extract param value (up to next /)
                nextSlash = path.indexOf('/');
                if (nextSlash == -1) nextSlash = path.length;
                
                paramValue = path[0 .. nextSlash];
                params[child.paramName] = paramValue;
                
                remaining = path[nextSlash .. $];
                if (remaining.length == 0) {
                    return child.handler;
                }
                return matchRecursive(child, remaining, params);
                
            case NodeType.WILDCARD:
                // Capture rest of path
                params[child.paramName] = path;
                return child.handler;
        }
    }
    
    return null;  // No match
}
```

#### 8.2.4 Path Parameters

**PathParams Storage**:
```d
struct PathParams {
    // Small String Optimization (avoid allocation for common case)
    enum MAX_INLINE_PARAMS = 4;
    
    struct Param {
        string name;
        string value;
    }
    
    Param[MAX_INLINE_PARAMS] inlineParams;
    Param[] overflowParams;  // For rare cases with >4 params
    uint count;
    
    // Lookup param value
    string opIndex(string name) @nogc {
        for (i = 0; i < count && i < MAX_INLINE_PARAMS; i++) {
            if (inlineParams[i].name == name) {
                return inlineParams[i].value;
            }
        }
        
        foreach (param; overflowParams) {
            if (param.name == name) {
                return param.value;
            }
        }
        
        return null;
    }
    
    // Set param value
    void opIndexAssign(string value, string name) @nogc {
        if (count < MAX_INLINE_PARAMS) {
            inlineParams[count] = Param(name, value);
        } else {
            overflowParams ~= Param(name, value);
        }
        count++;
    }
}
```

### 8.3 Router Optimizations

**Compiled Routes** (optional future enhancement):
```d
// V0: Dynamic radix tree (runtime routing)
Match match(string path);

// Future: Compile-time route registration → generate switch/case
// (Only worth it if you have 100+ routes)
final switch (path) {
    case "/users": return &listUsers;
    case "/users/123": return &getUser;  // If all static
    // ...
}
```

**Hot Path Caching** (optional):
```d
// LRU cache for frequently accessed routes
struct RouteCache {
    Match[16] cache;  // Small cache (16 entries)
    string[16] keys;
    
    Match* lookup(string path) {
        // Check cache (fast path)
        foreach (i, key; keys) {
            if (key == path) return &cache[i];
        }
        return null;
    }
}
```

> [!NOTE]
> **V0 Decision**: Simple radix tree, NO caching. Profile first, optimize later if needed.

---

## 9. MIDDLEWARE SYSTEM

**Package**: `aurora.web.middleware`

### 9.1 Middleware Architecture

**Pattern**: Chain of Responsibility + Context Passing

**Middleware Signature**:
```d
alias Middleware = void delegate(Context ctx, NextFunction next);
alias NextFunction = void delegate();
alias Handler = void delegate(Context ctx);
```

**Pipeline**:
```
Request → Middleware1 → Middleware2 → ... → Handler → Response
            ↓              ↓                     ↓
          next()        next()               (no next)
```

### 9.2 Context Object

**Package**: `aurora.web.context`

**Context Design**:
```d
align(64) struct Context {
    // Request data (read-only after parse)
    HTTPRequest* request;
    StringView method;
    StringView path;
    PathParams params;
    
    // Response builder (writable)
    HTTPResponse* response;
    
    // Middleware storage (key-value)
    ContextStorage storage;
    
    // Connection metadata
    Connection* connection;
    Worker* worker;
    
    // State
    bool responseSent;
    Exception error;
    
    // Helpers
    void json(T)(T data) {
        response.header("Content-Type", "application/json");
        response.body(serializeJSON(data));
    }
    
    void send(string text) {
        response.body(cast(ubyte[]) text);
    }
    
    void status(int code) {
        response.status(code);
    }
}
```

**Context Storage** (middleware data sharing):
```d
struct ContextStorage {
    // Small String Optimization
    enum MAX_INLINE_VALUES = 4;
    
    struct Entry {
        string key;
        void* value;
    }
    
    Entry[MAX_INLINE_VALUES] inlineEntries;
    Entry[] overflowEntries;
    uint count;
    
    // Get value
    T get(T)(string key) {
        for (i = 0; i < count && i < MAX_INLINE_VALUES; i++) {
            if (inlineEntries[i].key == key) {
                return cast(T) inlineEntries[i].value;
            }
        }
        
        foreach (entry; overflowEntries) {
            if (entry.key == key) {
                return cast(T) entry.value;
            }
        }
        
        return T.init;
    }
    
    // Set value
    void set(T)(string key, T value) {
        if (count < MAX_INLINE_VALUES) {
            inlineEntries[count] = Entry(key, cast(void*) value);
        } else {
            overflowEntries ~= Entry(key, cast(void*) value);
        }
        count++;
    }
}
```

### 9.3 Middleware Pipeline Execution

**Pipeline Builder**:
```d
class MiddlewarePipeline {
    Middleware[] middlewares;
    Handler finalHandler;
    
    void use(Middleware mw) {
        middlewares ~= mw;
    }
    
    void execute(Context ctx) {
        executeChain(ctx, 0);
    }
    
    private void executeChain(Context ctx, uint index) {
        if (index >= middlewares.length) {
            // Reached end of chain, execute handler
            finalHandler(ctx);
            return;
        }
        
        // Execute current middleware
        auto currentMiddleware = middlewares[index];
        
        // Define next() function
        void next() {
            executeChain(ctx, index + 1);
        }
        
        // Call middleware with next()
        currentMiddleware(ctx, &next);
    }
}
```

**Execution Flow**:
```d
// Example: Request → Logger → Auth → Handler
pipeline.use(&loggerMiddleware);
pipeline.use(&authMiddleware);
pipeline.execute(ctx, &handleRequest);

void loggerMiddleware(Context ctx, NextFunction next) {
    auto start = MonoTime.currTime;
    
    next();  // Call next middleware
    
    auto duration = MonoTime.currTime - start;
    log.info("{} {} - {}ms", ctx.method, ctx.path, duration.msecs);
}

void authMiddleware(Context ctx, NextFunction next) {
    auto token = ctx.request.header("Authorization");
    
    if (!validateToken(token)) {
        ctx.status(401);
        ctx.send("Unauthorized");
        return;  // Short-circuit, don't call next()
    }
    
    // Store user in context
    ctx.storage.set("user", extractUser(token));
    
    next();  // Authenticated, continue
}

void handleRequest(Context ctx) {
    auto user = ctx.storage.get!User("user");
    ctx.json(["message": "Hello " ~ user.name]);
}
```

### 9.4 Built-In Middleware (V0)

**Package**: `aurora.web.middleware` + `aurora.ext.*`

#### 9.4.1 Logger Middleware

```d
void loggerMiddleware(Context ctx, NextFunction next) {
    auto start = MonoTime.currTime;
    auto method = ctx.method;
    auto path = ctx.path;
    
    next();
    
    auto duration = MonoTime.currTime - start;
    auto status = ctx.response.statusCode;
    
    log.info("{} {} {} - {}μs", method, path, status, duration.usecs);
}
```

#### 9.4.2 CORS Middleware (`aurora.ext.cors`)

```d
struct CORSConfig {
    string[] allowedOrigins = ["*"];
    string[] allowedMethods = ["GET", "POST", "PUT", "DELETE"];
    string[] allowedHeaders = ["*"];
    bool allowCredentials = false;
    uint maxAge = 86400;
}

void corsMiddleware(CORSConfig config) {
    return (Context ctx, NextFunction next) {
        // Handle preflight OPTIONS request
        if (ctx.method == "OPTIONS") {
            ctx.response.header("Access-Control-Allow-Origin", config.allowedOrigins[0]);
            ctx.response.header("Access-Control-Allow-Methods", config.allowedMethods.join(","));
            ctx.response.header("Access-Control-Allow-Headers", config.allowedHeaders.join(","));
            ctx.response.header("Access-Control-Max-Age", config.maxAge.to!string);
            ctx.status(204);
            return;
        }
        
        // Add CORS headers to response
        ctx.response.header("Access-Control-Allow-Origin", config.allowedOrigins[0]);
        
        next();
    };
}
```

#### 9.4.3 Security Headers Middleware (`aurora.ext.security`)

```d
void securityHeadersMiddleware(Context ctx, NextFunction next) {
    ctx.response.header("X-Content-Type-Options", "nosniff");
    ctx.response.header("X-Frame-Options", "DENY");
    ctx.response.header("X-XSS-Protection", "1; mode=block");
    ctx.response.header("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
    ctx.response.header("Content-Security-Policy", "default-src 'self'");
    
    next();
}
```

#### 9.4.4 Schema Validation Middleware

```d
void validateRequest(Schema)(Context ctx, NextFunction next) {
    try {
        // Parse and validate request body
        auto data = parseJSON(ctx.request.body);
        auto validated = Schema.validate(data);
        
        // Store validated data in context
        ctx.storage.set("validated", validated);
        
        next();
    } catch (ValidationException e) {
        ctx.status(400);
        ctx.json(["error": e.message]);
    }
}

// Usage
router.post("/users", validateRequest!UserSchema, &createUser);
```

---

### 9.5 Router Pattern & Composition (FastAPI-style)

> [!NOTE]
> Aurora supports both **declarative** (UDA + RouterMixin) and **imperative** (`router.post(path, handler)`) registration styles. 
> This documentation focuses on the declarative approach, recommended for production code.

**Package**: `aurora.web.router`

Aurora provides a **modular router system** inspired by FastAPI, allowing developers to organize routes in separate modules and compose them hierarchically.

#### 9.5.1 Router Class

**Router API**:
```d
class Router {
    string prefix;                // Route prefix (e.g., "/api")
    Route[] routes;               // Registered routes
    Middleware[] middlewares;     // Router-local middleware
    Router[] subRouters;          // Child routers
    
    // Constructor
    this(string prefix = "") { this.prefix = prefix; }
    
    // Register routes
    void get(string path, Handler handler);
    void post(string path, Handler handler);
    void put(string path, Handler handler);
    void delete_(string path, Handler handler);  // delete is keyword
    void patch(string path, Handler handler);
    
    // Middleware
    void use(Middleware mw) {
        middlewares ~= mw;
    }
    
    // Router composition
    void includeRouter(Router other) {
        subRouters ~= other;
    }
    
    // Auto-registration from module
    void autoRegister(alias Module)() {
        // Compile-time module scanning
        static foreach (member; __traits(allMembers, Module)) {
            static foreach (attr; __traits(getAttributes, __traits(getMember, Module, member))) {
                static if (is(typeof(attr) == Get)) {
                    this.get(attr.path, &__traits(getMember, Module, member));
                }
                static if (is(typeof(attr) == Post)) {
                    this.post(attr.path, &__traits(getMember, Module, member));
                }
                // ... altri metodi
            }
        }
    }
}
```

#### 9.5.2 RouterMixin Template

**Purpose**: Simplify router creation in modules.

**Definition**:
```d
template RouterMixin(string prefix) {
    // Global router for this module
    static Router router;
    
    // Module constructor (runs at startup)
    static this() {
        router = new Router(prefix);
        
        // Auto-register all handlers in this module
        router.autoRegister!(__MODULE__);
    }
}
```

**Usage in Module**:
```d
// routers/users.d
module myapp.routers.users;

import aurora;

@Get("/")
void listUsers(Context ctx) {
    ctx.json(db.users.all());
}

@Get("/:id")
void getUser(Context ctx) {
    ctx.json(db.users.find(ctx.params["id"]));
}

@Post("/")
void createUser(Context ctx) {
    auto user = ctx.jsonBody!User;
    db.users.insert(user);
    ctx.status(201).json(user);
}

// ONE LINE: creates and exports `router` ✨
mixin RouterMixin!("/users");
```

**What it does**:
- Creates a global `router` variable in the module
- Initializes it with prefix `/users`
- Auto-registers all functions with `@Get`, `@Post`, etc.

#### 9.5.3 Router Composition

**Pattern**: Compose routers hierarchically like FastAPI.

**Example - API Router**:
```d
// routers/api.d
module myapp.routers.api;

import aurora;
import myapp.routers.users;
import myapp.routers.posts;
import myapp.routers.products;

Router createAPIRouter() {
    auto api = new Router("/api/v1");
    
    // Auth middleware for all API routes
    api.use(&authMiddleware);
    
    // Include sub-routers
    api.includeRouter(users.router);      // → /api/v1/users/*
    api.includeRouter(posts.router);      // → /api/v1/posts/*
    api.includeRouter(products.router);   // → /api/v1/products/*
    
    return api;
}

// Export as module router
static Router router;
static this() {
    router = createAPIRouter();
}
```

**Main App**:
```d
// main.d
import aurora;
import myapp.routers.api;
import myapp.routers.admin;

void main() {
    auto app = new App();
    
    // Global middleware
    app.use(&loggingMiddleware);
    
    // Include routers
    app.includeRouter(api.router);      // /api/v1/*
    app.includeRouter(admin.router);    // /admin/*
    
    app.listen(8080);
}
```

**Route Resolution**:
```
Request: GET /api/v1/users/123

1. App routes → none match
2. App sub-routers:
   - api.router (prefix: /api/v1) → MATCH!
   - Strip prefix → /users/123
3. api.router sub-routers:
   - users.router (prefix: /users) → MATCH!
   - Strip prefix → /123
4. users.router routes:
   - GET /:id → MATCH!
   - Extract param: id = 123
5. Execute: getUser(ctx) with ctx.params["id"] = "123"
```

#### 9.5.4 Complete Example - E-commerce API

**Project Structure**:
```
myapp/
├── main.d
├── models/
│   ├── user.d
│   ├── product.d
│   └── order.d
├── routers/
│   ├── users.d          # mixin RouterMixin!("/users")
│   ├── products.d       # mixin RouterMixin!("/products")
│   ├── orders.d         # mixin RouterMixin!("/orders")
│   ├── api_v1.d         # Compose above routers
│   └── admin.d          # Admin routes
└── middleware/
    ├── auth.d
    └── admin.d
```

**routers/products.d**:
```d
module myapp.routers.products;

@Get("/")
void list(Context ctx) {
    auto category = ctx.query.get("category", "");
    auto limit = ctx.query.get("limit", "20").to!int;
    ctx.json(db.products.filter(category).limit(limit).all());
}

@Get("/:id")
void get(Context ctx) {
    ctx.json(db.products.find(ctx.params["id"]));
}

@Post("/")
void create(Context ctx) {
    auto product = ctx.jsonBody!Product;
    db.products.insert(product);
    ctx.status(201).json(product);
}

@Put("/:id")
void update(Context ctx) {
    auto product = ctx.jsonBody!Product;
    db.products.update(ctx.params["id"], product);
    ctx.json(product);
}

@Delete("/:id")
void remove(Context ctx) {
    db.products.delete(ctx.params["id"]);
    ctx.status(204);
}

mixin RouterMixin!("/products");
```

**routers/orders.d**:
```d
module myapp.routers.orders;

@Get("/")
void list(Context ctx) {
    ctx.json(db.orders.all());
}

@Post("/")
void create(Context ctx) {
    auto order = ctx.jsonBody!Order;
    db.orders.create(order);
    ctx.status(201).json(order);
}

@Get("/:id")
void get(Context ctx) {
    ctx.json(db.orders.find(ctx.params["id"]));
}

mixin RouterMixin!("/orders");
```

**routers/api_v1.d**:
```d
module myapp.routers.api_v1;

import myapp.routers.{users, products, orders};
import myapp.middleware.auth;

Router createAPIv1() {
    auto api = new Router("/api/v1");
    
    // All API routes require authentication
    api.use(&requireAuthMiddleware);
    
    // Include resource routers
    api.includeRouter(users.router);
    api.includeRouter(products.router);
    api.includeRouter(orders.router);
    
    return api;
}

static Router router;
static this() { router = createAPIv1(); }
```

**main.d**:
```d
import aurora;
import myapp.routers.{api_v1, admin};
import myapp.middleware.{logging, cors};

void main() {
    auto app = new App();
    
    // Global middleware
    app.use(&loggingMiddleware);
    app.use(&corsMiddleware);
    
    // Include routers
    app.includeRouter(api_v1.router);
    app.includeRouter(admin.router);
    
    app.listen(8080);
}
```

**Resulting Routes**:
```
GET    /api/v1/users              → listUsers
GET    /api/v1/users/:id          → getUser
POST   /api/v1/users              → createUser

GET    /api/v1/products           → listProducts
GET    /api/v1/products/:id       → getProduct
POST   /api/v1/products           → createProduct
PUT    /api/v1/products/:id       → updateProduct
DELETE /api/v1/products/:id       → removeProduct

GET    /api/v1/orders             → listOrders
POST   /api/v1/orders             → createOrder
GET    /api/v1/orders/:id         → getOrder

GET    /admin/dashboard           → adminDashboard
...
```

#### 9.5.5 Benefits

**Modularity**:
- ✅ One file = one logical router
- ✅ Easy to locate and maintain routes
- ✅ Clear separation of concerns

**Composition**:
- ✅ Routers can include other routers
- ✅ Middleware applied hierarchically
- ✅ Prefix stacking (api → v1 → users)

**Type Safety**:
- ✅ All registration at compile-time
- ✅ Route conflicts detected early
- ✅ No runtime registration overhead

**DX (Developer Experience)**:
- ✅ FastAPI-like ergonomics
- ✅ Minimal boilerplate (1 line `mixin`)
- ✅ Auto-registration via UDA

#### 9.5.6 Implementation Notes

**Router Registration Flow**:
```d
1. Module loaded → static this() runs
2. RouterMixin creates Router instance
3. autoRegister() scans module at compile-time
4. All @Get, @Post, etc. functions registered
5. Router available as module.router
```

**Middleware Execution Order**:
```
Request → App middleware → Router1 middleware → Router2 middleware → Handler
```

**Prefix Resolution**:
```d
app.includeRouter(api.router);  // prefix: /api
api.includeRouter(users.router); // prefix: /users

Final path: /api + /users + /:id = /api/users/:id
```

---

## 10. TLS/HTTPS SUPPORT

### 10.1 Decisione Architetturale

> [!WARNING]
> **Aurora NON gestisce TLS/HTTPS internamente.**

Aurora è progettato come plain HTTP/1.1 engine. TLS/HTTPS è **sempre** responsabilità del reverse proxy.

**Filosofia**: 
- Aurora = HTTP/1.1 engine (plain text protocol)
- Reverse proxy = TLS termination, HTTP/2, HTTP/3, WebSocket
- Clear separation of concerns

**Allineato con**: Express.js, Flask, Gin, Koa, Actix-web (nessuno gestisce TLS direttamente)

### 10.2 Setup Produzione

**Architettura Standard**:
```
Internet (HTTPS/443)
        ↓
   Reverse Proxy (nginx/Caddy)
   - TLS termination
   - HTTP/2, HTTP/3 support
   - Certificate management
   - OCSP stapling
        ↓
   Aurora (HTTP/8080)
   - Plain HTTP/1.1 only
   - Zero TLS overhead
   - Maximum performance
```

**Nginx Configuration**:
```nginx
server {
    listen 443 ssl http2;
    server_name api.example.com;
    
    ssl_certificate /etc/letsencrypt/live/api.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.example.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    
    location / {
        proxy_pass http://127.0.0.1:8080;  # Aurora plain HTTP
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Caddy Configuration** (auto-HTTPS):
```caddy
api.example.com {
    reverse_proxy 127.0.0.1:8080
}
# Caddy automatically handles TLS certificates via Let's Encrypt!
```

### 10.3 Vantaggi

✅ **Performance**: Aurora non ha overhead TLS (gestito da nginx ottimizzato)  
✅ **Semplicità**: Aurora rimane minimalista e focalizzato  
✅ **Sicurezza**: Reverse proxy dedicato gestisce certificati, renewal, OCSP  
✅ **Scalabilità**: Separazione infrastruttura (TLS) vs applicazione (business logic)  
✅ **Standard**: Pattern usato da tutti i framework moderni  
✅ **Flessibilità**: Cambio reverse proxy senza toccare Aurora  

### 10.4 Protocolli Supportati

**Aurora Supporta**:
- ✅ HTTP/1.1 (plain text)
- ✅ Connection: keep-alive
- ✅ Chunked transfer encoding (detection)

**Reverse Proxy Gestisce** (NON Aurora):
- ❌ TLS/HTTPS
- ❌ HTTP/2
- ❌ HTTP/3 (QUIC)
- ❌ WebSocket upgrade (protocol switch)
- ❌ Certificate management

> [!IMPORTANT]
> Security headers (HSTS, CSP, etc.) sono gestiti da Aurora middleware (`aurora.ext.security`) perché sono HTTP headers standard, non protocollo TLS.

---

## 11. LOGGING SYSTEM

**Package**: `aurora.util.log`

### 11.1 Logging Architecture

Aurora uses a **lock-free, async logging system** optimized for high-throughput environments.

**Design Principles**:
- ✅ Lock-free writes (no contention in hot path)
- ✅ Async flush to disk (non-blocking)
- ✅ Structured logging (JSON format)
- ✅ Zero-allocation for common log levels
- ✅ Per-worker buffers (no shared state)

### 11.2 Log Levels

```d
enum LogLevel {
    TRACE = 0,    // Very detailed (disabled in production)
    DEBUG = 1,    // Debug information
    INFO = 2,     // Informational messages
    WARN = 3,     // Warnings
    ERROR = 4,    // Errors (recoverable)
    FATAL = 5     // Fatal errors (process exits)
}
```

**Runtime Level Filtering**:
```d
// Set minimum level
log.setLevel(LogLevel.INFO);  // Ignores TRACE and DEBUG

// Per-module levels
log.setLevel("aurora.web.router", LogLevel.DEBUG);
```

### 11.3 Logging API

**Simple API**:
```d
import aurora.util.log;

// Basic logging
log.info("Server started on port {}", port);
log.error("Failed to connect: {}", errorMsg);
log.debug("Request processed in {}μs", duration);

// Structured logging
log.info("user_login", [
    "user_id": userId,
    "ip": remoteAddr,
    "duration_ms": duration.msecs
]);

// With context
log.withContext([
    "request_id": requestId,
    "method": method,
    "path": path
]).info("Request completed");
```

**Format Specifiers**:
```d
log.info("User {} logged in", username);           // String
log.info("Port: {}", port);                        // Int
log.info("Duration: {}ms", duration.msecs);        // Float
log.info("Success: {}", success);                  // Bool
log.info("Data: {}", jsonData);                    // JSON (auto-serialize)
```

### 11.4 Lock-Free Implementation

**Per-Worker Ring Buffer**:
```d
struct LogBuffer {
    enum BUFFER_SIZE = 1024 * 1024;  // 1 MB per worker
    
    align(64) ubyte[BUFFER_SIZE] buffer;
    shared size_t writePos;    // Atomic
    size_t readPos;            // Flusher thread only
    
    // Write log entry (lock-free)
    void write(LogEntry entry) @nogc {
        auto size = entry.serializedSize;
        auto pos = atomicFetchAdd(writePos, size);
        
        if (pos + size < BUFFER_SIZE) {
            // Write directly to buffer
            entry.serializeTo(buffer[pos .. pos + size]);
        } else {
            // Buffer full, drop or flush sync
            onBufferFull(entry);
        }
    }
}
```

**Async Flusher Thread**:
```d
void flusherThread() {
    while (running) {
        // Collect logs from all worker buffers
        foreach (worker; workers) {
            auto entries = worker.logBuffer.collect();
            writeToDisk(entries);
        }
        
        // Sleep briefly
        Thread.sleep(100.msecs);
    }
}
```

### 11.5 Structured Log Format

**JSON Lines Format** (one JSON object per line):
```json
{"timestamp":"2025-01-22T19:00:00Z","level":"INFO","module":"aurora.web.router","message":"Request processed","request_id":"abc123","method":"GET","path":"/users/123","duration_ms":15.2}
{"timestamp":"2025-01-22T19:00:01Z","level":"ERROR","module":"aurora.mem.pool","message":"Buffer pool exhausted","pool":"SMALL","allocated":128,"max":128}
```

**LogEntry Structure**:
```d
struct LogEntry {
    MonoTime timestamp;
    LogLevel level;
    string module;
    string message;
    string[string] context;  // Key-value pairs
    
    // Serialize to JSON
    void serializeTo(ubyte[] buffer) @nogc {
        // Fast JSON serialization (no allocations)
        auto writer = JSONWriter(buffer);
        writer.startObject();
        writer.field("timestamp", timestamp.toISOString());
        writer.field("level", level.toString());
        writer.field("module", module);
        writer.field("message", message);
        foreach (k, v; context) {
            writer.field(k, v);
        }
        writer.endObject();
    }
}
```

### 11.6 Performance Characteristics

**Hot Path** (log.info() call):
- Atomic increment: ~5-10 ns
- memcpy to ring buffer: ~50-100 ns
- **Total: ~60-110 ns** per log entry (no I/O!)

**Flush Thread** (background):
- Collects entries every 100ms
- Batch write to disk
- No impact on request handling

**Memory**:
- Per-worker buffer: 1 MB
- 8 workers = 8 MB total
- Minimal overhead

### 11.7 Log Output Destinations

**Stdout** (development):
```d
log.setOutput(LogOutput.STDOUT);
```

**File** (production):
```d
log.setOutput(LogOutput.FILE, "/var/log/aurora/app.log");
```

**File Rotation**:
```d
log.setRotation(RotationPolicy.DAILY);   // Rotate daily
log.setRotation(RotationPolicy.SIZE, 100.MB);  // Rotate at 100MB
```

**Syslog** (optional):
```d
log.setOutput(LogOutput.SYSLOG, "aurora");
```

### 11.8 Built-in Middleware Logging

**Logger Middleware** (already in 9.4.1):
```d
void loggerMiddleware(Context ctx, NextFunction next) {
    auto start = MonoTime.currTime;
    auto method = ctx.method;
    auto path = ctx.path;
    
    next();
    
    auto duration = MonoTime.currTime - start;
    auto status = ctx.response.statusCode;
    
    log.withContext([
        "method": method,
        "path": path,
        "status": status.to!string,
        "duration_us": duration.usecs.to!string
    ]).info("request_completed");
}
```

**Example Output**:
```json
{"timestamp":"2025-01-22T19:00:00Z","level":"INFO","module":"aurora.web.middleware","message":"request_completed","method":"GET","path":"/api/users/123","status":"200","duration_us":"1523"}
```

---

## 12. METRICS & OBSERVABILITY

**Package**: `aurora.util.metrics`

### 12.1 Metrics Architecture

Aurora provides a **lock-free metrics system** with Prometheus-compatible export.

**Design Principles**:
- ✅ Lock-free atomic operations (no contention)
- ✅ Per-worker counters (no false sharing)
- ✅ Prometheus text format export
- ✅ Zero overhead when not scraped
- ✅ Built-in framework metrics

### 12.2 Metric Types

```d
// Counter (monotonically increasing)
metrics.counter("http_requests_total").increment();
metrics.counter("bytes_sent_total").add(responseSize);

// Gauge (can go up/down)
metrics.gauge("active_connections").set(connCount);
metrics.gauge("memory_used_bytes").set(memUsage);

// Histogram (distribution)
metrics.histogram("request_duration_seconds").observe(duration);
```

### 12.3 Lock-Free Implementation

**Per-Worker Counters** (avoid false sharing):
```d
struct Counter {
    string name;
    string[string] labels;
    
    // Per-worker values (cache-line separated)
    align(64) struct PerWorkerValue {
        shared ulong value;
        ubyte[56] _padding;  // Total 64 bytes
    }
    
    PerWorkerValue[MAX_WORKERS] values;
    
    // Increment (lock-free, no contention)
    void increment(uint workerID = currentWorkerID) @nogc {
        atomicOp!"+="(values[workerID].value, 1);
    }
    
    // Get total (sum all workers)
    ulong total() {
        ulong sum = 0;
        foreach (ref val; values) {
            sum += atomicLoad(val.value);
        }
        return sum;
    }
}
```

**Gauge** (similar but set instead of inc):
```d
struct Gauge {
    align(64) struct PerWorkerValue {
        shared long value;  // Can be negative
        ubyte[56] _padding;
    }
    
    PerWorkerValue[MAX_WORKERS] values;
    
    void set(long newValue, uint workerID = currentWorkerID) @nogc {
        atomicStore(values[workerID].value, newValue);
    }
}
```

**Histogram** (buckets):
```d
struct Histogram {
    string name;
    double[] buckets;  // e.g., [0.001, 0.01, 0.1, 1.0, 10.0]
    
    Counter[buckets.length] bucketCounters;
    Counter count;
    Counter sum;
    
    void observe(double value) {
        // Increment appropriate bucket
        foreach (i, bucket; buckets) {
            if (value <= bucket) {
                bucketCounters[i].increment();
            }
        }
        count.increment();
        sum.add(cast(ulong)(value * 1_000_000));  // Store as μs
    }
}
```

### 12.4 Built-in Metrics

Aurora automatically tracks:

**HTTP Metrics**:
```
http_requests_total{method="GET",status="200"}
http_requests_total{method="POST",status="201"}
http_request_duration_seconds{method="GET",path="/users"}
http_request_size_bytes
http_response_size_bytes
```

**Connection Metrics**:
```
http_connections_active
http_connections_total
http_connections_keep_alive
```

**Worker Metrics**:
```
aurora_worker_requests_processed{worker="0"}
aurora_worker_tasks_queued{worker="0"}
```

**Memory Metrics**:
```
aurora_buffer_pool_allocated{size="SMALL"}
aurora_buffer_pool_available{size="SMALL"}
aurora_memory_used_bytes
```

**Implementation**:
```d
// In connection handler
void handleRequest(Context ctx) {
    auto start = MonoTime.currTime;
    
    // ... process request ...
    
    auto duration = (MonoTime.currTime - start).total!"usecs" / 1_000_000.0;
    
    // Record metrics
    metrics.counter("http_requests_total", [
        "method": ctx.method,
        "status": ctx.response.statusCode.to!string
    ]).increment();
    
    metrics.histogram("http_request_duration_seconds", [
        "method": ctx.method
    ]).observe(duration);
}
```

### 12.5 Prometheus Export

**Endpoint**: `GET /metrics`

**Prometheus Text Format**:
```
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",status="200"} 15234
http_requests_total{method="GET",status="404"} 423
http_requests_total{method="POST",status="201"} 8923

# HELP http_request_duration_seconds HTTP request duration
# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{method="GET",le="0.001"} 5123
http_request_duration_seconds_bucket{method="GET",le="0.01"} 14234
http_request_duration_seconds_bucket{method="GET",le="0.1"} 15123
http_request_duration_seconds_bucket{method="GET",le="+Inf"} 15234
http_request_duration_seconds_sum{method="GET"} 152.34
http_request_duration_seconds_count{method="GET"} 15234

# HELP http_connections_active Active HTTP connections
# TYPE http_connections_active gauge
http_connections_active 42
```

**Implementation**:
```d
@Get("/metrics")
void metricsEndpoint(Context ctx) {
    auto output = metrics.exportPrometheus();
    ctx.header("Content-Type", "text/plain; version=0.0.4");
    ctx.send(output);
}
```

### 12.6 Custom Metrics API

**User-defined metrics**:
```d
// In application code
auto requestsTotal = metrics.counter("myapp_requests_total", [
    "endpoint": "/api/users"
]);

void handleUsers(Context ctx) {
    requestsTotal.increment();
    // ... handle request ...
}

// Latency tracking
auto latency = metrics.histogram("myapp_db_query_duration_seconds");

void queryDatabase() {
    auto start = MonoTime.currTime;
    // ... query ...
    auto duration = (MonoTime.currTime - start).total!"usecs" / 1_000_000.0;
    latency.observe(duration);
}
```

### 12.7 Performance Characteristics

**Metric Update** (hot path):
- Atomic increment: ~5-10 ns
- No locks, no contention
- Cache-line aligned (no false sharing)

**Metric Export** (`/metrics` endpoint):
- Aggregates all worker counters
- O(N) where N = number of metrics
- Typical: ~1-2ms for 100 metrics

**Memory**:
- Per counter: 64 bytes × num_workers
- 100 metrics × 8 workers = 51 KB
- Negligible overhead

### 12.8 Integration with Monitoring

**Prometheus Scrape Config**:
```yaml
scrape_configs:
  - job_name: 'aurora'
    static_configs:
      - targets: ['localhost:8080']
    metrics_path: '/metrics'
    scrape_interval: 15s
```

**Grafana Dashboard** (recommended panels):
- Request rate (requests/sec)
- Request duration (p50, p95, p99)
- Error rate (5xx responses)
- Active connections
- Memory usage

**Alerting** (Prometheus rules):
```yaml
groups:
  - name: aurora
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.05
        annotations:
          summary: "High error rate detected"
```

---

## 13. ERROR HANDLING

**Package**: `aurora.web.error`

### 13.1 Error Handling Strategy

Aurora uses a **dual error handling** approach:
- **Core framework**: @nogc error codes (performance-critical)
- **User handlers**: Exceptions allowed (convenience)

### 13.2 Core Framework Errors (@nogc)

**Error Codes** (no exceptions in hot path):
```d
enum ErrorCode {
    OK = 0,
    PARSE_ERROR = 1,          // HTTP parse failed
    BUFFER_OVERFLOW = 2,      // Buffer pool exhausted
    ROUTE_NOT_FOUND = 3,      // No matching route
    TIMEOUT = 4,              // Request timeout
    CONNECTION_CLOSED = 5,    // Client disconnected
    INTERNAL_ERROR = 99       // Unexpected error
}

struct Result(T) {
    T value;
    ErrorCode error;
    
    bool isOk() { return error == ErrorCode.OK; }
    bool isError() { return error != ErrorCode.OK; }
}
```

**Usage in Core**:
```d
@nogc
Result!HTTPRequest parseRequest(ubyte[] buffer) {
    auto result = wireParser.parse(buffer);
    
    if (result.error != WireError.OK) {
        return Result!HTTPRequest(
            HTTPRequest.init,
            ErrorCode.PARSE_ERROR
        );
    }
    
    return Result!HTTPRequest(result.request, ErrorCode.OK);
}

// Caller checks
auto result = parseRequest(buffer);
if (result.isError()) {
    handleError(result.error);
    return;
}
auto request = result.value;
```

**Core Error Handling**:
```d
void handleCoreError(ErrorCode error, Connection* conn) @nogc {
    final switch (error) {
        case ErrorCode.PARSE_ERROR:
            sendErrorResponse(conn, 400, "Bad Request");
            break;
        case ErrorCode.ROUTE_NOT_FOUND:
            sendErrorResponse(conn, 404, "Not Found");
            break;
        case ErrorCode.TIMEOUT:
            conn.close();
            break;
        case ErrorCode.BUFFER_OVERFLOW:
            sendErrorResponse(conn, 503, "Service Unavailable");
            log.error("Buffer pool exhausted!");
            break;
        // ...
    }
}
```

### 13.3 User Handler Errors (Exceptions Allowed)

**Users can throw exceptions**:
```d
@Get("/users/:id")
void getUser(Context ctx) {
    auto id = ctx.params["id"].to!int;
    
    auto user = db.users.find(id);
    if (user.isNull) {
        throw new NotFoundException("User not found");  // ✅ OK!
    }
    
    ctx.json(user);
}

@Post("/users")
void createUser(Context ctx) {
    auto user = ctx.jsonBody!User;
    
    if (!user.isValid()) {
        throw new ValidationException("Invalid user data");  // ✅ OK!
    }
    
    db.users.insert(user);
    ctx.json(user);
}
```

**Exception Types**:
```d
// Base exception
class HTTPException : Exception {
    int statusCode;
    string[string] headers;
    
    this(int statusCode, string message) {
        super(message);
        this.statusCode = statusCode;
    }
}

// Specific exceptions
class NotFoundException : HTTPException {
    this(string message = "Not Found") {
        super(404, message);
    }
}

class ValidationException : HTTPException {
    this(string message) {
        super(400, message);
    }
}

class UnauthorizedException : HTTPException {
    this(string message = "Unauthorized") {
        super(401, message);
        headers["WWW-Authenticate"] = "Bearer";
    }
}

class ForbiddenException : HTTPException {
    this(string message = "Forbidden") {
        super(403, message);
    }
}

class InternalServerException : HTTPException {
    this(string message = "Internal Server Error") {
        super(500, message);
    }
}
```

### 13.4 Exception Catching (Framework Boundary)

**Framework catches user exceptions**:
```d
void executeHandler(Context ctx, Handler handler) {
    try {
        // Call user handler (may throw)
        handler(ctx);
        
    } catch (HTTPException e) {
        // Known HTTP exception
        ctx.status(e.statusCode);
        foreach (k, v; e.headers) {
            ctx.header(k, v);
        }
        ctx.json(["error": e.message]);
        
    } catch (Exception e) {
        // Unknown exception
        log.error("Unhandled exception in handler: {}", e.message);
        ctx.status(500);
        ctx.json(["error": "Internal Server Error"]);
    }
}
```

**Try-Catch Boundary**:
```
┌─────────────────────────────────────┐
│  Core Framework (@nogc)             │
│  - HTTP parsing                     │
│  - Routing                          │
│  - Connection management            │
│  → Uses error codes                 │
├─────────────────────────────────────┤  ← TRY/CATCH HERE
│  User Handlers (GC allowed)         │
│  - Business logic                   │
│  - Database queries                 │
│  - Can throw exceptions             │
└─────────────────────────────────────┘
```

### 13.5 Error Middleware

**Global error handler**:
```d
void errorMiddleware(Context ctx, NextFunction next) {
    try {
        next();  // Call next middleware/handler
        
    } catch (HTTPException e) {
        // Custom error response
        ctx.status(e.statusCode);
        ctx.json([
            "error": e.message,
            "status": e.statusCode,
            "path": ctx.path,
            "timestamp": Clock.currTime.toISOExtString()
        ]);
        
        // Log error
        if (e.statusCode >= 500) {
            log.error("Server error: {}", e.message);
        } else {
            log.warn("Client error: {}", e.message);
        }
        
    } catch (Exception e) {
        // Unexpected exception
        log.error("Unhandled exception", [
            "message": e.message,
            "file": e.file,
            "line": e.line.to!string
        ]);
        
        ctx.status(500);
        ctx.json(["error": "Internal Server Error"]);
    }
}

// Usage
app.use(&errorMiddleware);  // Global error handler
```

### 13.6 Error Responses

**Standard Error Format**:
```json
{
  "error": "User not found",
  "status": 404,
  "path": "/users/123",
  "timestamp": "2025-01-22T19:00:00Z"
}
```

**Validation Error Format**:
```json
{
  "error": "Validation failed",
  "status": 400,
  "path": "/users",
  "details": {
    "email": "Invalid email format",
    "age": "Must be greater than 0"
  }
}
```

**Helper Functions**:
```d
// Quick error responses
void notFound(Context ctx, string message = "Not Found") {
    ctx.status(404).json(["error": message]);
}

void badRequest(Context ctx, string message) {
    ctx.status(400).json(["error": message]);
}

void unauthorized(Context ctx) {
    ctx.status(401)
       .header("WWW-Authenticate", "Bearer")
       .json(["error": "Unauthorized"]);
}

// Usage in handler
@Get("/users/:id")
void getUser(Context ctx) {
    auto user = db.users.find(ctx.params["id"]);
    if (user.isNull) {
        return ctx.notFound("User not found");  // Early return
    }
    ctx.json(user);
}
```

### 13.7 Panic Recovery

**Catch D errors** (assert failures, segfaults via signals):
```d
void setupPanicHandler() {
    import core.runtime;
    
    Runtime.traceHandler = (info) {
        log.fatal("PANIC: {}", info.toString());
        
        // Attempt graceful shutdown
        shutdownGracefully();
        
        return 1;  // Exit code
    };
}
```

> [!CAUTION]
> D errors (assert failures, out-of-bounds) are **unrecoverable**. The process will exit. Use exceptions for recoverable errors.

### 13.8 Error Logging

**Automatic error logging**:
```d
// In error middleware
catch (HTTPException e) {
    if (e.statusCode >= 500) {
        log.error("http_error", [
            "status": e.statusCode.to!string,
            "message": e.message,
            "path": ctx.path,
            "method": ctx.method,
            "user_agent": ctx.request.header("User-Agent")
        ]);
    }
}
```

**Error metrics**:
```d
// Track error rates
metrics.counter("http_errors_total", [
    "status": statusCode.to!string,
    "path": ctx.path
]).increment();
```

---

## 14. CONFIGURATION SYSTEM

**Package**: `aurora.util.config`

### 14.1 Configuration Strategy

Aurora uses the **Schema System** (Section 4) for type-safe configuration.

**Configuration Sources** (priority order):
1. **ENV variables** (highest priority)
2. **Config file** (JSON/TOML)
3. **Default values** (in schema)

### 14.2 Configuration Schema

**Server Config**:
```d
struct ServerConfig {
    @Required
    @Range(1, 65535)
    int port = 8080;
    
    @Required
    string host = "0.0.0.0";
    
    @Range(1, 1024)
    int workers = 0;  // 0 = auto-detect
    
    @Required
    bool keepAlive = true;
    
    @Range(1, 3600)
    int keepAliveTimeout = 60;  // seconds
    
    @Range(1, 300)
    int requestTimeout = 30;
    
    @Range(1024, 1_000_000_000)
    ulong maxHeaderSize = 8192;
    
    @Range(0, 10_000_000_000)
    ulong maxBodySize = 10_000_000;  // 10 MB
}
```

**Full Config**:
```d
struct AppConfig {
    ServerConfig server;
    LogConfig log;
    MetricsConfig metrics;
    
    // User can extend
    string databaseUrl;
    int cacheSize = 1000;
}

struct LogConfig {
    @Required
    LogLevel level = LogLevel.INFO;
    
    @Required
    string output = "stdout";  // "stdout" | "file" | "syslog"
    
    string file = "/var/log/aurora/app.log";
    
    @Required
    bool structured = true;
}

struct MetricsConfig {
    @Required
    bool enabled = true;
    
    @Required
    string endpoint = "/metrics";
}
```

### 14.3 Loading Configuration

**From File**:
```d
// config.json
{
  "server": {
    "port": 8080,
    "host": "0.0.0.0",
    "workers": 8
  },
  "log": {
    "level": "INFO",
    "output": "file",
    "file": "/var/log/aurora/app.log"
  },
  "databaseUrl": "postgresql://localhost/mydb"
}
```

**Load and Validate**:
```d
import aurora.util.config;

void main() {
    // Load config file
    auto config = Config.load!AppConfig("config.json");
    
    // Schema validation happens automatically
    // Throws ValidationException if invalid
    
    // Use config
    auto app = new App(config.server);
    app.listen();
}
```

### 14.4 ENV Variable Overrides

**ENV Variable Format**: `AURORA_<SECTION>_<KEY>`

```bash
# Override server.port
export AURORA_SERVER_PORT=3000

# Override log.level
export AURORA_LOG_LEVEL=DEBUG

# Override database URL
export AURORA_DATABASE_URL="postgresql://prod-db/mydb"
```

**Load with ENV Overrides**:
```d
void main() {
    // Load config with ENV overrides
    auto config = Config.load!AppConfig("config.json", enableENV: true);
    
    // config.server.port = 3000 (from ENV)
    // config.log.level = LogLevel.DEBUG (from ENV)
    
    auto app = new App(config.server);
    app.listen();
}
```

**ENV Parsing**:
```d
struct Config {
    static T load(T)(string filename, bool enableENV = true) {
        // 1. Load from file
        auto config = parseFile!T(filename);
        
        // 2. Override from ENV
        if (enableENV) {
            config = applyENVOverrides(config);
        }
        
        // 3. Validate with schema
        validateSchema!T(config);
        
        return config;
    }
    
    private static T applyENVOverrides(T)(T config) {
        import std.process : environment;
        
        // For each field in T
        foreach (field; __traits(allMembers, T)) {
            auto envKey = "AURORA_" ~ field.toUpper();
            auto envValue = environment.get(envKey, null);
            
            if (envValue !is null) {
                // Parse and set field
                __traits(getMember, config, field) = parseValue(envValue);
            }
        }
        
        return config;
    }
}
```

### 14.5 Example: Production Config

**config.prod.json**:
```json
{
  "server": {
    "port": 8080,
    "host": "0.0.0.0",
    "workers": 0,
    "keepAliveTimeout": 120
  },
  "log": {
    "level": "INFO",
    "output": "file",
    "file": "/var/log/aurora/app.log",
    "structured": true
  },
  "metrics": {
    "enabled": true,
    "endpoint": "/metrics"
  },
  "databaseUrl": "postgresql://db.example.com/prod"
}
```

**With ENV Overrides**:
```bash
# Override for staging
export AURORA_SERVER_PORT=3000
export AURORA_DATABASE_URL="postgresql://staging-db.example.com/staging"
export AURORA_LOG_LEVEL=DEBUG

./myapp --config config.prod.json
```

---

## 15. GRACEFUL SHUTDOWN

**Package**: `aurora.runtime`

### 15.1 Shutdown Strategy

Aurora implements **graceful shutdown** to avoid dropping active requests.

**Sequence**:
1. Receive SIGTERM/SIGINT
2. Stop accepting new connections
3. Wait for active requests to complete (with timeout)
4. Close idle keep-alive connections
5. Shutdown workers
6. Cleanup resources
7. Exit

### 15.2 Signal Handling

**Setup Signal Handlers**:
```d
import core.sys.posix.signal;

void setupSignalHandlers() {
    // SIGTERM (graceful shutdown)
    signal(SIGTERM, &handleShutdownSignal);
    
    // SIGINT (Ctrl+C)
    signal(SIGINT, &handleShutdownSignal);
    
    // SIGPIPE (ignore - handle in code)
    signal(SIGPIPE, SIG_IGN);
}

extern(C) void handleShutdownSignal(int sig) nothrow @nogc @system {
    atomicStore(shutdownRequested, true);
}
```

### 15.3 Shutdown Sequence

**Main Shutdown Flow**:
```d
shared bool shutdownRequested = false;

void main() {
    setupSignalHandlers();
    
    auto app = new App();
    app.listen(8080);
    
    // Main loop
    while (!atomicLoad(shutdownRequested)) {
        Thread.sleep(100.msecs);
    }
    
    // Shutdown sequence
    log.info("Shutdown signal received, starting graceful shutdown...");
    app.shutdown();
    log.info("Shutdown complete");
}
```

**App Shutdown Implementation**:
```d
class App {
    shared bool shuttingDown = false;
    Listener listener;
    Worker[] workers;
    
    void shutdown(Duration timeout = 30.seconds) {
        atomicStore(shuttingDown, true);
        
        // Step 1: Stop accepting new connections
        log.info("Step 1: Stopping listener...");
        listener.stop();
        
        // Step 2: Wait for active requests to complete
        log.info("Step 2: Waiting for active requests...");
        waitForActiveRequests(timeout);
        
        // Step 3: Close idle keep-alive connections
        log.info("Step 3: Closing idle connections...");
        closeIdleConnections();
        
        // Step 4: Shutdown workers
        log.info("Step 4: Shutting down workers...");
        shutdownWorkers();
        
        // Step 5: Cleanup
        log.info("Step 5: Cleanup resources...");
        cleanup();
    }
    
    void waitForActiveRequests(Duration timeout) {
        auto start = MonoTime.currTime;
        
        while (true) {
            auto activeCount = countActiveRequests();
            
            if (activeCount == 0) {
                log.info("All requests completed");
                break;
            }
            
            auto elapsed = MonoTime.currTime - start;
            if (elapsed > timeout) {
                log.warn("Shutdown timeout, {} requests still active", activeCount);
                break;
            }
            
            log.debug("{} requests still active, waiting...", activeCount);
            Thread.sleep(100.msecs);
        }
    }
    
    ulong countActiveRequests() {
        ulong total = 0;
        foreach (worker; workers) {
            total += worker.activeRequests;
        }
        return total;
    }
    
    void closeIdleConnections() {
        foreach (worker; workers) {
            worker.closeIdleConnections();
        }
    }
    
    void shutdownWorkers() {
        foreach (worker; workers) {
            worker.shutdown();
            worker.thread.join();  // Wait for thread to exit
        }
    }
}
```

### 15.4 Worker Shutdown

**Worker graceful stop**:
```d
struct Worker {
    shared bool running = true;
    ulong activeRequests = 0;
    Connection[] connections;
    
    void run() {
        while (atomicLoad(running)) {
            // Process events
            reactor.poll(100.msecs);
        }
        
        // Cleanup
        cleanup();
    }
    
    void shutdown() {
        atomicStore(running, false);
    }
    
    void closeIdleConnections() {
        foreach (conn; connections) {
            if (conn.state == ConnectionState.KEEP_ALIVE) {
                conn.close();
            }
        }
    }
    
    void cleanup() {
        // Close all remaining connections
        foreach (conn; connections) {
            conn.close();
        }
        
        // Free resources
        bufferPool.cleanup();
        connectionPool.cleanup();
    }
}
```

### 15.5 Connection State During Shutdown

**Connection Lifecycle**:
```d
void handleConnection(Connection* conn) {
    // Check if shutting down
    if (atomicLoad(app.shuttingDown)) {
        // Don't accept keep-alive
        conn.keepAlive = false;
        
        // Send "Connection: close" header
        response.header("Connection", "close");
    }
    
    // Increment active count
    atomicOp!"++"(worker.activeRequests);
    
    // Process request
    processRequest(conn);
    
    // Decrement active count
    atomicOp!"--"(worker.activeRequests);
    
    // Close if shutting down
    if (!conn.keepAlive || app.shuttingDown) {
        conn.close();
    }
}
```

### 15.6 Timeout Handling

**Force shutdown** after timeout:
```d
void shutdown(Duration gracePeriod = 30.seconds, Duration forcePeriod = 5.seconds) {
    // Try graceful shutdown
    auto graceful = tryGracefulShutdown(gracePeriod);
    
    if (!graceful) {
        log.warn("Graceful shutdown timeout, forcing...");
        
        // Force close all connections
        forceCloseAllConnections();
        
        // Wait briefly for cleanup
        Thread.sleep(forcePeriod);
    }
}
```

### 15.7 Health Check During Shutdown

**Return 503 during shutdown**:
```d
@Get("/health")
void healthCheck(Context ctx) {
    if (atomicLoad(app.shuttingDown)) {
        ctx.status(503);
        ctx.json(["status": "shutting_down"]);
        return;
    }
    
    ctx.status(200);
    ctx.json(["status": "ok"]);
}
```

**Load balancer behavior**:
- Health check fails (503)
- Load balancer stops routing new requests
- Existing requests complete
- Server shuts down cleanly

---

## 16. TESTING & BENCHMARKING

### 16.1 Unit Tests

Coverage target: ≥ 80% per core modules

### 16.2 Load Testing

Tool: `wrk` per HTTP benchmarking

Scenarios:
- Plaintext benchmark (hello world)
- JSON small payload
- POST with body
- Concurrent connections

---

## 17. DEPLOYMENT & OPERATIONS

### 17.1 Production Checklist

- Compile con LDC -O3 -release
- Use PGO se possibile
- Systemd service file
- Health check endpoint
- Monitoring (Prometheus)

---

## 18. SECURITY CONSIDERATIONS

### 18.1 Input Validation

- Schema validation per tutti gli input
- Size limits per headers/body
- Timeout per operazioni

### 18.2 Slowloris Protection

- Connection timeout
- Request header timeout
- Keep-alive limits

### 18.3 Security Headers

Gestiti da `aurora.ext.security` middleware.

> [!NOTE]
> Rate limiting e circuit breaker **NON sono in V0** - usare librerie esterne.

---

## 19. OPTIMIZATION GUIDELINES

### 19.1 What the Compiler Does (LDC -O3)

**Don't manually optimize these** - let the compiler do it:
- Function inlining
- Loop unrolling
- Constant propagation
- Dead code elimination
- Basic SIMD auto-vectorization
- Branch prediction (without PGO data)
- Register allocation
- Common subexpression elimination

### 19.2 What We Must Do Manually

**Architectural optimizations** the compiler cannot do:
- **Algorithm choices**: Radix tree vs hash table
- **Memory layout**: Buffer pools, object pools, arenas
- **Lock-free structures**: Using atomics correctly
- **Cache-line alignment**: Padding to avoid false sharing
- **Zero-copy patterns**: Buffer views, avoiding memcpy
- **Custom allocators**: mimalloc integration
- **NUMA awareness**: Memory allocation on local node
- **SIMD for complex patterns**: When compiler can't auto-vectorize

### 19.3 Specific SIMD Usage

Use SIMD **only when**:
1. Profiling shows it's a bottleneck
2. Compiler with -O3 doesn't auto-vectorize
3. Pattern is too complex for compiler (e.g., multi-byte sequence scan)

Examples where manual SIMD might help:
- Finding CRLF in HTTP headers (multi-pattern scan)
- JSON escape sequence detection (complex character class)
- Path matching con multiple delimiters

> [!IMPORTANT]
> **Always benchmark first**. Manual SIMD può essere slower se il compiler fa un buon lavoro.

### 19.4 Cache-Aware Strategies

**Manual optimizations**:
- Align hot structures to cache lines (64 bytes)
- Add padding to prevent false sharing
- Group frequently-accessed fields together
- Separate read-only and read-write data

**Compiler-friendly code**:
- Use struct-of-arrays quando possibile (compiler vectorize better)
- Keep hot loops simple (compiler can optimize)
- Avoid pointer chasing (bad for prefetcher)

---

## 20. V0 ROADMAP

### 20.1 V0 Core Scope (THIS DOCUMENT)

**Included in V0**:
- ✅ Event loop (eventcore + vibe-core)
- ✅ HTTP/1.1 parser (llhttp)
- ✅ Routing (radix tree)
- ✅ Request/Response API
- ✅ JSON support (simdjson)
- ✅ Middleware pipeline
- ✅ Schema System (validation)
- ✅ Async logging
- ✅ Metrics (Prometheus)
- ✅ Configuration system
- ✅ CORS middleware
- ✅ Security headers middleware
-  ✅ Graceful shutdown
- ✅ Multi-threaded workers
- ✅ NUMA optimization
- ✅ Testing utilities

**Performance Target V0**:
- Throughput: ≥ 95% vs eventcore baseline
- Latency p99: < 100μs (plaintext)
- Memory: < 50KB per connection
- Linear scaling to available cores

**NOT in V0** (future phases):
- ❌ Dependency Injection
- ❌ Database Integration (ORM, query builder)
- ❌ OpenAPI/Swagger auto-generation
- ❌ Authentication & Authorization (JWT, OAuth2, RBAC)
- ❌ Background Jobs & Task Queue
- ❌ Advanced CLI Tool (code generation, scaffolding)
- ❌ WebSocket (full implementation)
- ❌ GraphQL
- ❌ Event System & Event Sourcing
- ❌ API Versioning
- ❌ Circuit Breaker & Resilience patterns
- ❌ Multi-Tenancy
- ❌ HTTP/2 (full implementation)

### 20.2 Future Phases (Post-V0)

#### Phase 1: Extended Features (v0.5)
- Authentication & Authorization (JWT, OAuth2, RBAC)
- Background Jobs system
- Advanced CLI tooling
- WebSocket support
- Testing utilities estese

#### Phase 2: Enterprise Features (v1.0)
- HTTP/2 full support
- GraphQL support
- Event Sourcing & CQRS
- API Versioning
- Multi-Tenancy

#### Phase 3: Ecosystem (v1.5+)
- Database ORM completo
- Message Queue integrations
- gRPC support
- Cloud provider SDKs
- Plugin system

---

## CONCLUSION

**Aurora V0 Core** fornisce un HTTP engine ad alte performance con focus su:

1. **Infrastruttura solida**: Event loop + HTTP parser + Routing + Middleware
2. **Performance**: Zero-copy, @nogc hot path, memory pools, NUMA awareness
3. **Developer Experience**: Schema system, type safety, minimal boilerplate
4. **Compiler-Friendly**: Lasciamo che LDC -O3 faccia ottimizzazioni automatiche
5. **Focused Scope**: Solo core HTTP engine, no bloat

**Differenze chiave da Specs completo**:
- ❌ Removed: DI, ORM, GraphQL, WebSocket, Auth, Background Jobs, Multi-Tenancy
- ❌ Removed: Manual optimization hints ridondanti (inline, unroll, branch hints)
- ✅ Kept: Core HTTP engine, schema system, performance architecture
- ✅ Kept: Ottimizzazioni che il compiler NON può fare (algorithm choices, memory layout, lock-free structures)

**Il V0 Core è pronto per**:
- Microservizi high-performance
- API RESTful con validazione type-safe
- Server HTTP custom con requirements specifici

---

**DOCUMENT VERSION**: V0 Core - {{ Generated }} 2025-01-22
