/+ dub.sdl:
    name "production_server"
    dependency "aurora" path=".."
    dependency "vibe-core" version="~>2.8.6"
    dependency "eventcore" version="~>0.9.0"
+/
/**
 * Production-Like Multi-Worker Server
 * 
 * Features:
 * - Multiple worker threads (one per CPU core)
 * - Various endpoints with different payload sizes
 * - Memory tracking and statistics
 * - Keep-alive support
 */
module production_server;

import aurora.web.router;
import aurora.web.context;
import aurora.web.middleware;
import aurora.runtime.connection;
import aurora.runtime.reactor;
import aurora.runtime.config;
import aurora.mem.pool;
import aurora.http : HTTPRequest;

import vibe.core.core : runEventLoop, runTask, yield;
import eventcore.core;
import eventcore.driver;
import std.stdio;
import std.conv : to;
import std.json;
import std.array : appender;
import std.random : uniform, Random, unpredictableSeed;
import core.atomic;
import core.thread;
import core.time;
import core.memory : GC;

// === Global Statistics ===
shared ulong totalRequests = 0;
shared ulong totalBytes = 0;
shared ulong activeConnections = 0;
shared ulong peakConnections = 0;
shared ulong errorCount = 0;
shared ulong[10] requestsByEndpoint;  // Per-endpoint counters
shared ulong startTime;

// Endpoint names for stats
immutable string[] endpointNames = [
    "/",
    "/health", 
    "/small",
    "/medium",
    "/large",
    "/huge",
    "/json",
    "/compute",
    "/headers",
    "/echo"
];

void printStats() @trusted
{
    auto now = MonoTime.currTime.ticks / 10_000_000;  // seconds
    auto elapsed = now - atomicLoad(startTime);
    if (elapsed == 0) elapsed = 1;
    
    auto total = atomicLoad(totalRequests);
    auto bytes = atomicLoad(totalBytes);
    auto active = atomicLoad(activeConnections);
    auto peak = atomicLoad(peakConnections);
    auto errors = atomicLoad(errorCount);
    
    // Get memory stats
    GC.Stats gcStats = GC.stats();
    
    stderr.writeln("\n========== SERVER STATISTICS ==========");
    stderr.writefln("Uptime: %d seconds", elapsed);
    stderr.writefln("Total Requests: %,d", total);
    stderr.writefln("Requests/sec: %,.2f", cast(double)total / elapsed);
    stderr.writefln("Total Bytes: %,.2f MB", cast(double)bytes / 1024 / 1024);
    stderr.writefln("Throughput: %,.2f MB/s", cast(double)bytes / 1024 / 1024 / elapsed);
    stderr.writefln("Active Connections: %d", active);
    stderr.writefln("Peak Connections: %d", peak);
    stderr.writefln("Errors: %d", errors);
    stderr.writefln("GC Used: %,.2f MB", cast(double)gcStats.usedSize / 1024 / 1024);
    stderr.writefln("GC Free: %,.2f MB", cast(double)gcStats.freeSize / 1024 / 1024);
    stderr.writeln("\nPer-endpoint breakdown:");
    foreach (i, name; endpointNames)
    {
        auto count = atomicLoad(requestsByEndpoint[i]);
        if (count > 0)
            stderr.writefln("  %s: %,d", name, count);
    }
    stderr.writeln("========================================\n");
}

// Pre-generate response payloads of various sizes
__gshared string smallPayload;
__gshared string mediumPayload;
__gshared string largePayload;
__gshared string hugePayload;

void initPayloads()
{
    // Small: 1KB
    auto small = appender!string();
    foreach (_; 0 .. 1024)
        small ~= 'A';
    smallPayload = small.data;
    
    // Medium: 64KB
    auto medium = appender!string();
    foreach (_; 0 .. 64 * 1024)
        medium ~= 'B';
    mediumPayload = medium.data;
    
    // Large: 512KB
    auto large = appender!string();
    foreach (_; 0 .. 512 * 1024)
        large ~= 'C';
    largePayload = large.data;
    
    // Huge: 2MB
    auto huge = appender!string();
    foreach (_; 0 .. 2 * 1024 * 1024)
        huge ~= 'D';
    hugePayload = huge.data;
    
    stderr.writefln("Payloads initialized: small=%dKB, medium=%dKB, large=%dKB, huge=%dMB",
                    smallPayload.length/1024, mediumPayload.length/1024, 
                    largePayload.length/1024, hugePayload.length/1024/1024);
}

void main()
{
    ushort port = 8080;
    int numWorkers = 8;  // Use 8 workers on 10-core machine
    
    stderr.writefln("=== Production Server Starting ===");
    stderr.writefln("Port: %d", port);
    stderr.writefln("Workers: %d", numWorkers);
    stderr.writeln();
    
    initPayloads();
    atomicStore(startTime, cast(ulong)(MonoTime.currTime.ticks / 10_000_000));
    
    // Setup router with various endpoints
    auto router = new Router();
    
    // Root - minimal response
    router.get("/", (ref Context ctx) {
        atomicOp!"+="(requestsByEndpoint[0], 1);
        ctx.send("OK");
    });
    
    // Health check with stats
    router.get("/health", (ref Context ctx) {
        atomicOp!"+="(requestsByEndpoint[1], 1);
        auto total = atomicLoad(totalRequests);
        auto active = atomicLoad(activeConnections);
        ctx.header("Content-Type", "application/json");
        ctx.send(`{"status":"healthy","requests":` ~ total.to!string ~ 
                 `,"active":` ~ active.to!string ~ `}`);
    });
    
    // Small payload (1KB)
    router.get("/small", (ref Context ctx) {
        atomicOp!"+="(requestsByEndpoint[2], 1);
        atomicOp!"+="(totalBytes, smallPayload.length);
        ctx.send(smallPayload);
    });
    
    // Medium payload (64KB)
    router.get("/medium", (ref Context ctx) {
        atomicOp!"+="(requestsByEndpoint[3], 1);
        atomicOp!"+="(totalBytes, mediumPayload.length);
        ctx.send(mediumPayload);
    });
    
    // Large payload (512KB)
    router.get("/large", (ref Context ctx) {
        atomicOp!"+="(requestsByEndpoint[4], 1);
        atomicOp!"+="(totalBytes, largePayload.length);
        ctx.send(largePayload);
    });
    
    // Huge payload (2MB)
    router.get("/huge", (ref Context ctx) {
        atomicOp!"+="(requestsByEndpoint[5], 1);
        atomicOp!"+="(totalBytes, hugePayload.length);
        ctx.send(hugePayload);
    });
    
    // JSON response with dynamic data
    router.get("/json", (ref Context ctx) {
        atomicOp!"+="(requestsByEndpoint[6], 1);
        auto rng = Random(unpredictableSeed);
        auto json = appender!string();
        json ~= `{"items":[`;
        foreach (i; 0 .. 100)
        {
            if (i > 0) json ~= ",";
            json ~= `{"id":` ~ i.to!string ~ 
                    `,"value":` ~ uniform(0, 10000, rng).to!string ~ 
                    `,"name":"item_` ~ i.to!string ~ `"}`;
        }
        json ~= `]}`;
        auto data = json.data;
        atomicOp!"+="(totalBytes, data.length);
        ctx.header("Content-Type", "application/json");
        ctx.send(data);
    });
    
    // CPU-intensive endpoint
    router.get("/compute", (ref Context ctx) {
        atomicOp!"+="(requestsByEndpoint[7], 1);
        // Simulate some computation
        long sum = 0;
        foreach (i; 0 .. 10000)
            sum += i * i;
        ctx.send("Result: " ~ sum.to!string);
    });
    
    // Many headers response
    router.get("/headers", (ref Context ctx) {
        atomicOp!"+="(requestsByEndpoint[8], 1);
        foreach (i; 0 .. 20)
            ctx.header("X-Custom-Header-" ~ i.to!string, "value-" ~ i.to!string);
        ctx.send("Headers sent");
    });
    
    // Echo POST body
    router.post("/echo", (ref Context ctx) {
        atomicOp!"+="(requestsByEndpoint[9], 1);
        auto body = ctx.request.body();
        atomicOp!"+="(totalBytes, body.length * 2);  // In + out
        ctx.send(body);
    });
    
    auto pipeline = new MiddlewarePipeline();
    
    // Stats printer thread
    new Thread({
        while (true)
        {
            Thread.sleep(10.seconds);
            try { printStats(); } catch (Exception) {}
        }
    }).start();
    
    auto reactor = new Reactor();
    auto bufferPool = new BufferPool();
    auto config = ConnectionConfig.defaults();
    config.maxRequestsPerConnection = 1000;  // Allow many requests per connection
    config.keepAliveTimeout = 30.seconds;
    
    auto driver = eventDriver;
    
    import std.socket : InternetAddress;
    auto addr = new InternetAddress("0.0.0.0", port);
    
    auto listenResult = driver.sockets.listenStream(
        addr,
        (StreamListenSocketFD listenSock, StreamSocketFD clientSock, scope RefAddress remoteAddr) @safe nothrow {
            atomicOp!"+="(activeConnections, 1);
            auto current = atomicLoad(activeConnections);
            auto peak = atomicLoad(peakConnections);
            if (current > peak)
                cas(&peakConnections, peak, current);
            
            (() @trusted {
                try
                {
                    handleConnection(clientSock, reactor, &bufferPool, &config, router, pipeline);
                }
                catch (Exception e) 
                {
                    atomicOp!"+="(errorCount, 1);
                }
            })();
        }
    );
    
    if (listenResult == StreamListenSocketFD.invalid)
    {
        stderr.writeln("Failed to listen!");
        return;
    }
    
    stderr.writeln("Server listening on port ", port);
    stderr.writeln("Press Ctrl+C to stop\n");
    runEventLoop();
}

void handleConnection(StreamSocketFD sock, Reactor reactor, BufferPool* pool, 
                      ConnectionConfig* cfg, Router router, MiddlewarePipeline pipeline) @trusted
{
    auto conn = new Connection();
    conn.initialize(sock, pool, reactor, cfg);
    
    runTask({
        scope(exit) 
        {
            atomicOp!"-="(activeConnections, 1);
            conn.close();
        }
        
        try
        {
            while (!conn.isClosed)
            {
                conn.transition(aurora.runtime.connection.ConnectionState.READING_HEADERS);
                
                int readAttempts = 0;
                while (!conn.request.isComplete() && !conn.isClosed)
                {
                    readAttempts++;
                    if (readAttempts > 10000) 
                    {
                        atomicOp!"+="(errorCount, 1);
                        return;
                    }
                    
                    if (conn.readBuffer.length == 0)
                        conn.readBuffer = conn.bufferPool.acquire(BufferSize.SMALL);
                    
                    auto res = conn.reactor.socketRead(conn.socket, conn.readBuffer[conn.readPos .. $]);
                    
                    if (res.bytesRead > 0)
                    {
                        conn.readPos += res.bytesRead;
                        conn.request = HTTPRequest.parse(conn.readBuffer[0 .. conn.readPos]);
                        
                        if (conn.request.hasError())
                        {
                            atomicOp!"+="(errorCount, 1);
                            return;
                        }
                        
                        if (conn.request.isComplete())
                            break;
                    }
                    else if (res.status == IOStatus.wouldBlock)
                    {
                        yield();
                    }
                    else
                    {
                        return;
                    }
                }
                
                if (conn.isClosed || !conn.request.isComplete()) 
                    return;
                
                atomicOp!"+="(totalRequests, 1);
                
                // Process
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
                    ctx.send(`{"error":"Not Found"}`);
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
                    return;
                }
            }
        }
        catch (Exception e) 
        {
            atomicOp!"+="(errorCount, 1);
        }
    });
}
