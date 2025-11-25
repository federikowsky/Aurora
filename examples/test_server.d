/+ dub.sdl:
    name "test_server"
    dependency "aurora" path=".."
    dependency "vibe-core" version="~>2.8.6"
    dependency "eventcore" version="~>0.9.0"
+/
/**
 * Aurora Test Server
 * 
 * A comprehensive test server with multiple routers, middleware,
 * various response types, and edge case handlers.
 * 
 * Usage:
 *   dub run --single examples/test_server.d
 * 
 * Endpoints:
 *   GET  /                     - Home
 *   GET  /health               - Health check
 *   GET  /echo?msg=...         - Echo query param
 *   POST /echo                 - Echo body
 *   GET  /delay/:ms            - Delayed response
 *   GET  /status/:code         - Return specific status
 *   GET  /size/:bytes          - Return N bytes
 *   GET  /headers              - Return all request headers
 *   POST /json                 - Parse and echo JSON
 *   GET  /api/v1/users         - List users
 *   GET  /api/v1/users/:id     - Get user
 *   POST /api/v1/users         - Create user
 *   PUT  /api/v1/users/:id     - Update user
 *   DELETE /api/v1/users/:id   - Delete user
 *   GET  /api/v2/users         - V2 API
 *   GET  /nested/a/b/c/d       - Deeply nested route
 *   GET  /edge/empty           - Empty response
 *   GET  /edge/unicode         - Unicode response
 *   GET  /edge/binary          - Binary-like response
 *   GET  /edge/huge            - 1MB response
 *   GET  /edge/headers-flood   - Many headers
 */
module test_server;

import aurora.web.router;
import aurora.web.context;
import aurora.web.middleware;
import aurora.runtime.connection;
import aurora.runtime.reactor;
import aurora.runtime.config;
import aurora.mem.pool;
import aurora.http : HTTPRequest;

import vibe.core.core : runEventLoop, runTask, exitEventLoop, yield;
import eventcore.core;
import eventcore.driver;
import std.stdio;
import std.conv : to;
import std.array : replicate, join;
import std.algorithm : map;
import std.range : iota;
import std.string : format;
import core.thread;
import core.atomic;

// ============================================================================
// GLOBAL STATE (for testing)
// ============================================================================

shared uint requestCounter = 0;
shared uint errorCounter = 0;

// In-memory "database"
__gshared string[string] usersDb;
shared uint nextUserId = 1;

shared static this()
{
    // Initialize with some users
    usersDb["1"] = `{"id":1,"name":"Alice","email":"alice@example.com"}`;
    usersDb["2"] = `{"id":2,"name":"Bob","email":"bob@example.com"}`;
    usersDb["3"] = `{"id":3,"name":"Charlie","email":"charlie@example.com"}`;
    nextUserId = 4;
}

// ============================================================================
// MIDDLEWARE
// ============================================================================

/// Request counting middleware
void countingMiddleware(ref Context ctx, NextFunction next)
{
    atomicOp!"+="(requestCounter, 1);
    next();
}

/// Error handling middleware
void errorMiddleware(ref Context ctx, NextFunction next)
{
    try
    {
        next();
    }
    catch (Exception e)
    {
        atomicOp!"+="(errorCounter, 1);
        ctx.status(500);
        ctx.send(`{"error":"Internal Server Error","message":"` ~ e.msg ~ `"}`);
    }
}

/// CORS middleware
void corsMiddleware(ref Context ctx, NextFunction next)
{
    ctx.header("Access-Control-Allow-Origin", "*");
    ctx.header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
    ctx.header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Custom-Header");
    
    if (ctx.request.method == "OPTIONS")
    {
        ctx.status(204);
        return;
    }
    next();
}

/// Response time header middleware
void timingMiddleware(ref Context ctx, NextFunction next)
{
    import std.datetime.stopwatch : StopWatch, AutoStart;
    auto sw = StopWatch(AutoStart.yes);
    
    next();
    
    sw.stop();
    ctx.header("X-Response-Time", sw.peek.total!"usecs".to!string ~ "us");
}

// ============================================================================
// HANDLERS
// ============================================================================

// --- Basic Routes ---

void homeHandler(ref Context ctx)
{
    ctx.send("Aurora Test Server - Running!");
}

void healthHandler(ref Context ctx)
{
    auto reqs = atomicLoad(requestCounter);
    auto errs = atomicLoad(errorCounter);
    ctx.header("Content-Type", "application/json");
    ctx.send(format(`{"status":"healthy","requests":%d,"errors":%d}`, reqs, errs));
}

void echoGetHandler(ref Context ctx)
{
    // Parse query string manually (simplified)
    auto path = ctx.request.path;
    import std.string : indexOf;
    auto qIdx = indexOf(path, '?');
    if (qIdx >= 0 && qIdx + 1 < path.length)
    {
        auto query = path[qIdx + 1 .. $];
        ctx.send("Echo: " ~ query);
    }
    else
    {
        ctx.send("Echo: (no message)");
    }
}

void echoPostHandler(ref Context ctx)
{
    ctx.header("Content-Type", "text/plain");
    ctx.send("Echo: " ~ ctx.request.body);
}

void delayHandler(ref Context ctx)
{
    auto msStr = ctx.params.get("ms", "0");
    int ms = 0;
    try { ms = msStr.to!int; } catch (Exception) {}
    
    if (ms > 0 && ms <= 5000)  // Max 5 seconds
    {
        import core.time : msecs;
        Thread.sleep(ms.msecs);
    }
    
    ctx.send(format(`{"delayed":%d}`, ms));
}

void statusHandler(ref Context ctx)
{
    auto codeStr = ctx.params.get("code", "200");
    int code = 200;
    try { code = codeStr.to!int; } catch (Exception) {}
    
    if (code < 100 || code > 599) code = 200;
    
    ctx.status(code);
    ctx.send(format(`{"status":%d}`, code));
}

void sizeHandler(ref Context ctx)
{
    auto bytesStr = ctx.params.get("bytes", "0");
    size_t bytes = 0;
    try { bytes = bytesStr.to!size_t; } catch (Exception) {}
    
    // Limit to 10MB
    if (bytes > 10 * 1024 * 1024) bytes = 10 * 1024 * 1024;
    
    ctx.header("Content-Type", "application/octet-stream");
    ctx.send(replicate("X", bytes));
}

void headersHandler(ref Context ctx)
{
    // Return request info
    ctx.header("Content-Type", "application/json");
    ctx.send(format(`{"method":"%s","path":"%s","version":"%s"}`,
        ctx.request.method,
        ctx.request.path,
        ctx.request.httpVersion));
}

void jsonHandler(ref Context ctx)
{
    ctx.header("Content-Type", "application/json");
    auto body_ = ctx.request.body;
    if (body_.length > 0)
    {
        // Echo back with wrapper
        ctx.send(`{"received":` ~ body_ ~ `}`);
    }
    else
    {
        ctx.send(`{"received":null}`);
    }
}

// --- API v1 Routes ---

void listUsersV1(ref Context ctx)
{
    ctx.header("Content-Type", "application/json");
    
    string[] users;
    foreach (id, userData; usersDb)
    {
        users ~= userData;
    }
    
    ctx.send("[" ~ users.join(",") ~ "]");
}

void getUserV1(ref Context ctx)
{
    auto id = ctx.params.get("id", "");
    ctx.header("Content-Type", "application/json");
    
    if (auto userData = id in usersDb)
    {
        ctx.send(*userData);
    }
    else
    {
        ctx.status(404);
        ctx.send(`{"error":"User not found","id":"` ~ id ~ `"}`);
    }
}

void createUserV1(ref Context ctx)
{
    ctx.header("Content-Type", "application/json");
    
    auto body_ = ctx.request.body;
    auto id = atomicOp!"+="(nextUserId, 1U) - 1;
    auto idStr = id.to!string;
    
    // Store (in real app, would parse and validate)
    usersDb[idStr] = format(`{"id":%d,"data":%s}`, id, body_.length > 0 ? body_ : "null");
    
    ctx.status(201);
    ctx.header("Location", "/api/v1/users/" ~ idStr);
    ctx.send(format(`{"id":%d,"created":true}`, id));
}

void updateUserV1(ref Context ctx)
{
    auto id = ctx.params.get("id", "");
    ctx.header("Content-Type", "application/json");
    
    if (id in usersDb)
    {
        auto body_ = ctx.request.body;
        usersDb[id] = format(`{"id":%s,"data":%s,"updated":true}`, id, body_.length > 0 ? body_ : "null");
        ctx.send(`{"updated":true,"id":"` ~ id ~ `"}`);
    }
    else
    {
        ctx.status(404);
        ctx.send(`{"error":"User not found"}`);
    }
}

void deleteUserV1(ref Context ctx)
{
    auto id = ctx.params.get("id", "");
    ctx.header("Content-Type", "application/json");
    
    if (id in usersDb)
    {
        usersDb.remove(id);
        ctx.status(204);
    }
    else
    {
        ctx.status(404);
        ctx.send(`{"error":"User not found"}`);
    }
}

// --- API v2 Routes ---

void listUsersV2(ref Context ctx)
{
    ctx.header("Content-Type", "application/json");
    ctx.header("X-API-Version", "2");
    
    string[] users;
    foreach (id, userData; usersDb)
    {
        users ~= userData;
    }
    
    ctx.send(`{"version":2,"data":[` ~ users.join(",") ~ `],"count":` ~ users.length.to!string ~ `}`);
}

// --- Nested Routes ---

void deeplyNestedHandler(ref Context ctx)
{
    ctx.send("You found the deeply nested route!");
}

// --- Edge Case Routes ---

void emptyHandler(ref Context ctx)
{
    // Empty response body
    ctx.status(204);
}

void unicodeHandler(ref Context ctx)
{
    ctx.header("Content-Type", "text/plain; charset=utf-8");
    ctx.send("Unicode: 你好世界 🌍 مرحبا Привет こんにちは 🚀✨🎉");
}

void binaryLikeHandler(ref Context ctx)
{
    ctx.header("Content-Type", "application/octet-stream");
    // Binary-like content with null bytes and special chars
    char[] data;
    foreach (i; 0 .. 256)
    {
        data ~= cast(char)i;
    }
    ctx.send(cast(string)data);
}

void hugeHandler(ref Context ctx)
{
    ctx.header("Content-Type", "text/plain");
    // 1MB response
    ctx.send(replicate("A", 1024 * 1024));
}

void headersFloodHandler(ref Context ctx)
{
    // Add many headers
    foreach (i; 0 .. 50)
    {
        ctx.header("X-Custom-Header-" ~ i.to!string, "value-" ~ i.to!string);
    }
    ctx.send("Check the response headers!");
}

// ============================================================================
// SERVER
// ============================================================================

class TestServer
{
    private Router router;
    private MiddlewarePipeline pipeline;
    private ushort port;
    private uint numWorkers;
    private shared bool running;

    this(ushort port = 8080, uint workers = 4)
    {
        this.port = port;
        this.numWorkers = workers;
        this.running = false;
        
        setupRoutes();
        setupMiddleware();
    }

    private void setupMiddleware()
    {
        pipeline = new MiddlewarePipeline();
        pipeline.use((ref Context ctx, NextFunction next) { countingMiddleware(ctx, next); });
        pipeline.use((ref Context ctx, NextFunction next) { errorMiddleware(ctx, next); });
        pipeline.use((ref Context ctx, NextFunction next) { corsMiddleware(ctx, next); });
        pipeline.use((ref Context ctx, NextFunction next) { timingMiddleware(ctx, next); });
    }

    private void setupRoutes()
    {
        router = new Router();
        
        // Basic routes
        router.get("/", (ref Context ctx) { homeHandler(ctx); });
        router.get("/health", (ref Context ctx) { healthHandler(ctx); });
        router.get("/echo", (ref Context ctx) { echoGetHandler(ctx); });
        router.post("/echo", (ref Context ctx) { echoPostHandler(ctx); });
        router.get("/delay/:ms", (ref Context ctx) { delayHandler(ctx); });
        router.get("/status/:code", (ref Context ctx) { statusHandler(ctx); });
        router.get("/size/:bytes", (ref Context ctx) { sizeHandler(ctx); });
        router.get("/headers", (ref Context ctx) { headersHandler(ctx); });
        router.post("/json", (ref Context ctx) { jsonHandler(ctx); });
        
        // API v1 router
        auto apiV1 = new Router("/api/v1");
        apiV1.get("/users", (ref Context ctx) { listUsersV1(ctx); });
        apiV1.get("/users/:id", (ref Context ctx) { getUserV1(ctx); });
        apiV1.post("/users", (ref Context ctx) { createUserV1(ctx); });
        apiV1.put("/users/:id", (ref Context ctx) { updateUserV1(ctx); });
        apiV1.delete_("/users/:id", (ref Context ctx) { deleteUserV1(ctx); });
        router.includeRouter(apiV1);
        
        // API v2 router
        auto apiV2 = new Router("/api/v2");
        apiV2.get("/users", (ref Context ctx) { listUsersV2(ctx); });
        router.includeRouter(apiV2);
        
        // Deeply nested
        router.get("/nested/a/b/c/d", (ref Context ctx) { deeplyNestedHandler(ctx); });
        
        // Edge cases
        router.get("/edge/empty", (ref Context ctx) { emptyHandler(ctx); });
        router.get("/edge/unicode", (ref Context ctx) { unicodeHandler(ctx); });
        router.get("/edge/binary", (ref Context ctx) { binaryLikeHandler(ctx); });
        router.get("/edge/huge", (ref Context ctx) { hugeHandler(ctx); });
        router.get("/edge/headers-flood", (ref Context ctx) { headersFloodHandler(ctx); });
    }

    void start()
    {
        writeln("╔════════════════════════════════════════════╗");
        writeln("║     Aurora Test Server                     ║");
        writeln("╠════════════════════════════════════════════╣");
        writefln("║  Port:    %d                            ║", port);
        writefln("║  Workers: %d (fiber-based)               ║", numWorkers);
        writeln("╚════════════════════════════════════════════╝");
        writeln();
        
        atomicStore(running, true);

        writeln("Server ready! Endpoints available:");
        writeln("  http://localhost:", port, "/");
        writeln("  http://localhost:", port, "/health");
        writeln("  http://localhost:", port, "/api/v1/users");
        writeln();
        
        // Multi-fiber event loop - each connection runs in its own fiber
        runServer();
    }

    private void runServer()
    {
        auto reactor = new Reactor();
        auto bufferPool = new BufferPool();
        auto config = ConnectionConfig.defaults();
        
        scope(exit)
        {
            bufferPool.cleanup();
            reactor.shutdown();
        }
        
        auto driver = eventDriver;
        
        import std.socket : InternetAddress;
        auto addr = new InternetAddress("0.0.0.0", port);
        
        auto listenResult = driver.sockets.listenStream(
            addr,
            (StreamListenSocketFD listenSock, StreamSocketFD clientSock, scope RefAddress remoteAddr) @safe nothrow {
                (() @trusted {
                    try {
                        handleConnection(clientSock, reactor, &bufferPool, &config);
                    } catch (Exception e) {}
                })();
            }
        );
        
        if (listenResult == StreamListenSocketFD.invalid)
        {
            writeln("ERROR: Failed to listen on port ", port);
            return;
        }
        
        runEventLoop();
    }

    private void handleConnection(StreamSocketFD sock, Reactor reactor, BufferPool* pool, ConnectionConfig* cfg) @trusted
    {
        auto conn = new Connection();
        conn.initialize(sock, pool, reactor, cfg);
        
        runTask({
            try {
                connectionLoop(conn);
            } catch (Throwable t) {
            } finally {
                conn.close();
            }
        });
    }

    private void connectionLoop(Connection* conn)
    {
        while (!conn.isClosed && atomicLoad(running))
        {
            // Read request
            conn.transition(aurora.runtime.connection.ConnectionState.READING_HEADERS);
            
            while (!conn.request.isComplete() && !conn.isClosed)
            {
                if (conn.readBuffer.length == 0)
                    conn.readBuffer = conn.bufferPool.acquire(BufferSize.SMALL);
                
                auto res = conn.reactor.socketRead(conn.socket, conn.readBuffer[conn.readPos .. $]);
                
                if (res.bytesRead > 0)
                {
                    conn.readPos += res.bytesRead;
                    conn.request = HTTPRequest.parse(conn.readBuffer[0 .. conn.readPos]);
                    if (conn.request.isComplete()) break;
                }
                else if (res.status == IOStatus.wouldBlock)
                {
                    yield();
                }
                else
                {
                    conn.close();
                    return;
                }
            }
            
            if (conn.isClosed) return;
            
            // Process request
            conn.transition(aurora.runtime.connection.ConnectionState.PROCESSING);
            
            auto ctx = Context(&conn.request, &conn.response);
            auto match = router.match(conn.request.method, conn.request.path);
            
            if (match.found)
            {
                ctx.params = match.params;
                pipeline.execute(ctx, match.handler);
            }
            else
            {
                ctx.status(404);
                ctx.header("Content-Type", "application/json");
                ctx.send(`{"error":"Not Found","path":"` ~ conn.request.path ~ `"}`);
            }
            
            // Write response
            conn.transition(aurora.runtime.connection.ConnectionState.WRITING_RESPONSE);
            conn.processRequest();
            
            while (conn.writePos < conn.writeBuffer.length && !conn.isClosed)
            {
                auto res = conn.reactor.socketWrite(conn.socket, conn.writeBuffer[conn.writePos .. $]);
                if (res.bytesWritten > 0)
                {
                    conn.writePos += res.bytesWritten;
                }
                else if (res.status == IOStatus.wouldBlock)
                {
                    yield();
                }
                else
                {
                    conn.close();
                    return;
                }
            }
            
            // Keep-alive
            if (conn.request.shouldKeepAlive())
            {
                conn.resetConnection();
            }
            else
            {
                conn.close();
            }
        }
    }
}

void main(string[] args)
{
    ushort port = 8080;
    uint workers = 4;
    
    if (args.length > 1)
    {
        try { port = args[1].to!ushort; } catch (Exception) {}
    }
    if (args.length > 2)
    {
        try { workers = args[2].to!uint; } catch (Exception) {}
    }
    
    auto server = new TestServer(port, workers);
    server.start();
}
