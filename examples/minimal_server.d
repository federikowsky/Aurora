/+ dub.sdl:
    name "minimal_server"
    dependency "aurora" path=".."
    dependency "vibe-core" version="~>2.8.6"
    dependency "eventcore" version="~>0.9.0"
+/
/**
 * Minimal Aurora Server - Single-threaded
 * 
 * A simple working server for testing.
 */
module minimal_server;

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
import std.array : replicate, join;
import std.string : format, indexOf;
import core.atomic;

// Global counters
shared uint requestCount = 0;

void main(string[] args)
{
    ushort port = 8080;
    if (args.length > 1)
    {
        try { port = args[1].to!ushort; } catch (Exception) {}
    }
    
    writeln("╔═══════════════════════════════════╗");
    writeln("║  Aurora Minimal Test Server       ║");
    writeln("╠═══════════════════════════════════╣");
    writefln("║  Port: %d                      ║", port);
    writeln("╚═══════════════════════════════════╝");
    writeln();
    
    // Setup router
    auto router = new Router();
    
    // Basic routes
    router.get("/", (ref Context ctx) {
        ctx.send("Aurora Test Server - Running!");
    });
    
    router.get("/health", (ref Context ctx) {
        auto count = atomicLoad(requestCount);
        ctx.header("Content-Type", "application/json");
        ctx.send(format(`{"status":"healthy","requests":%d}`, count));
    });
    
    router.get("/echo", (ref Context ctx) {
        auto path = ctx.request.path;
        auto qIdx = indexOf(path, '?');
        if (qIdx >= 0 && qIdx + 1 < path.length)
        {
            ctx.send("Echo: " ~ path[qIdx + 1 .. $]);
        }
        else
        {
            ctx.send("Echo: (no query)");
        }
    });
    
    router.post("/echo", (ref Context ctx) {
        ctx.send("Echo: " ~ ctx.request.body);
    });
    
    router.get("/status/:code", (ref Context ctx) {
        auto codeStr = ctx.params.get("code", "200");
        int code = 200;
        try { code = codeStr.to!int; } catch (Exception) {}
        if (code < 100 || code > 599) code = 200;
        ctx.status(code);
        ctx.send(format(`{"status":%d}`, code));
    });
    
    router.get("/size/:bytes", (ref Context ctx) {
        auto bytesStr = ctx.params.get("bytes", "0");
        size_t bytes = 0;
        try { bytes = bytesStr.to!size_t; } catch (Exception) {}
        if (bytes > 1024 * 1024) bytes = 1024 * 1024;  // Max 1MB
        ctx.header("Content-Type", "application/octet-stream");
        ctx.send(replicate("X", bytes));
    });
    
    router.post("/json", (ref Context ctx) {
        ctx.header("Content-Type", "application/json");
        auto body_ = ctx.request.body;
        if (body_.length > 0)
            ctx.send(`{"received":` ~ body_ ~ `}`);
        else
            ctx.send(`{"received":null}`);
    });
    
    router.get("/headers", (ref Context ctx) {
        ctx.header("Content-Type", "application/json");
        ctx.send(format(`{"method":"%s","path":"%s"}`,
            ctx.request.method, ctx.request.path));
    });
    
    router.get("/nested/a/b/c/d", (ref Context ctx) {
        ctx.send("You found the deeply nested route!");
    });
    
    // API v1
    auto apiV1 = new Router("/api/v1");
    apiV1.get("/users", (ref Context ctx) {
        ctx.header("Content-Type", "application/json");
        ctx.send(`[{"id":1,"name":"Alice"},{"id":2,"name":"Bob"}]`);
    });
    apiV1.get("/users/:id", (ref Context ctx) {
        auto id = ctx.params.get("id", "0");
        ctx.header("Content-Type", "application/json");
        if (id == "1" || id == "2" || id == "3")
            ctx.send(`{"id":` ~ id ~ `,"name":"User` ~ id ~ `"}`);
        else
        {
            ctx.status(404);
            ctx.send(`{"error":"Not Found"}`);
        }
    });
    apiV1.post("/users", (ref Context ctx) {
        ctx.status(201);
        ctx.header("Content-Type", "application/json");
        ctx.send(`{"id":99,"created":true}`);
    });
    apiV1.put("/users/:id", (ref Context ctx) {
        ctx.header("Content-Type", "application/json");
        ctx.send(`{"updated":true}`);
    });
    apiV1.delete_("/users/:id", (ref Context ctx) {
        ctx.status(204);
    });
    router.includeRouter(apiV1);
    
    // API v2
    auto apiV2 = new Router("/api/v2");
    apiV2.get("/users", (ref Context ctx) {
        ctx.header("Content-Type", "application/json");
        ctx.header("X-API-Version", "2");
        ctx.send(`{"version":2,"data":[],"count":0}`);
    });
    router.includeRouter(apiV2);
    
    // Edge cases
    router.get("/edge/empty", (ref Context ctx) {
        ctx.status(204);
    });
    
    router.get("/edge/unicode", (ref Context ctx) {
        ctx.header("Content-Type", "text/plain; charset=utf-8");
        ctx.send("Unicode: 你好 🌍 مرحبا");
    });
    
    router.get("/edge/huge", (ref Context ctx) {
        ctx.send(replicate("A", 1024 * 1024));
    });
    
    router.get("/edge/headers-flood", (ref Context ctx) {
        foreach (i; 0 .. 50)
            ctx.header("X-Custom-Header-" ~ i.to!string, "value" ~ i.to!string);
        ctx.send("Check headers!");
    });
    
    // Middleware pipeline
    auto pipeline = new MiddlewarePipeline();
    
    // Request counter
    pipeline.use((ref Context ctx, NextFunction next) {
        atomicOp!"+="(requestCount, 1U);
        next();
    });
    
    // CORS
    pipeline.use((ref Context ctx, NextFunction next) {
        ctx.header("Access-Control-Allow-Origin", "*");
        ctx.header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
        
        if (ctx.request.method == "OPTIONS")
        {
            ctx.status(204);
            return;
        }
        next();
    });
    
    // Timing
    pipeline.use((ref Context ctx, NextFunction next) {
        import std.datetime.stopwatch : StopWatch, AutoStart;
        auto sw = StopWatch(AutoStart.yes);
        next();
        sw.stop();
        ctx.header("X-Response-Time", sw.peek.total!"usecs".to!string ~ "us");
    });
    
    // Start server
    auto reactor = new Reactor();
    auto bufferPool = new BufferPool();
    auto config = ConnectionConfig.defaults();
    
    auto driver = eventDriver;
    
    import std.socket : InternetAddress;
    auto addr = new InternetAddress("0.0.0.0", port);
    
    auto listenResult = driver.sockets.listenStream(
        addr,
        (StreamListenSocketFD listenSock, StreamSocketFD clientSock, scope RefAddress remoteAddr) @safe nothrow {
            (() @trusted {
                try
                {
                    handleConnection(clientSock, reactor, &bufferPool, &config, router, pipeline);
                }
                catch (Exception e) {}
            })();
        }
    );
    
    if (listenResult == StreamListenSocketFD.invalid)
    {
        writeln("Failed to listen on port ", port);
        return;
    }
    
    writeln("Server listening on http://0.0.0.0:", port);
    writeln("Press Ctrl+C to stop\n");
    
    runEventLoop();
}

void handleConnection(StreamSocketFD sock, Reactor reactor, BufferPool* pool, 
                      ConnectionConfig* cfg, Router router, MiddlewarePipeline pipeline) @trusted
{
    auto conn = new Connection();
    conn.initialize(sock, pool, reactor, cfg);
    
    runTask({
        scope(exit) conn.close();
        
        try
        {
            while (!conn.isClosed)
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
                        return;
                    }
                }
                
                if (conn.isClosed || !conn.request.isComplete()) return;
                
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
        catch (Exception e) {}
    });
}
