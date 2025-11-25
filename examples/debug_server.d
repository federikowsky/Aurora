/+ dub.sdl:
    name "debug_server"
    dependency "aurora" path=".."
    dependency "vibe-core" version="~>2.8.6"
    dependency "eventcore" version="~>0.9.0"
+/
/**
 * Debug Server - with extensive logging
 */
module debug_server;

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
import core.atomic;
import core.stdc.stdio : printf;

shared uint requestCount = 0;
shared uint activeConnections = 0;

void log(string msg) @trusted nothrow
{
    try { 
        import std.datetime.systime : Clock;
        auto now = Clock.currTime;
        stderr.writefln("[%02d:%02d:%02d] %s", now.hour, now.minute, now.second, msg);
        stderr.flush();
    } catch (Exception) {}
}

void main()
{
    ushort port = 8080;
    
    log("Starting debug server on port " ~ port.to!string);
    
    // Simple router
    auto router = new Router();
    router.get("/", (ref Context ctx) {
        ctx.send("OK");
    });
    router.get("/health", (ref Context ctx) {
        auto count = atomicLoad(requestCount);
        auto active = atomicLoad(activeConnections);
        ctx.header("Content-Type", "application/json");
        ctx.send(`{"requests":` ~ count.to!string ~ `,"active":` ~ active.to!string ~ `}`);
    });
    
    // No middleware to keep it simple
    auto pipeline = new MiddlewarePipeline();
    
    auto reactor = new Reactor();
    auto bufferPool = new BufferPool();
    auto config = ConnectionConfig.defaults();
    
    auto driver = eventDriver;
    
    import std.socket : InternetAddress;
    auto addr = new InternetAddress("0.0.0.0", port);
    
    log("Calling listenStream...");
    
    auto listenResult = driver.sockets.listenStream(
        addr,
        (StreamListenSocketFD listenSock, StreamSocketFD clientSock, scope RefAddress remoteAddr) @safe nothrow {
            log("New connection accepted");
            atomicOp!"+="(activeConnections, 1);
            
            (() @trusted {
                try
                {
                    handleConnection(clientSock, reactor, &bufferPool, &config, router, pipeline);
                }
                catch (Exception e) 
                {
                    log("handleConnection error: " ~ e.msg);
                }
            })();
        }
    );
    
    if (listenResult == StreamListenSocketFD.invalid)
    {
        log("Failed to listen!");
        return;
    }
    
    log("Server listening, entering event loop...");
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
            log("Connection closing");
            atomicOp!"-="(activeConnections, 1);
            conn.close();
        }
        
        try
        {
            while (!conn.isClosed)
            {
                log("Starting request read...");
                
                // Read request
                conn.transition(aurora.runtime.connection.ConnectionState.READING_HEADERS);
                
                int readAttempts = 0;
                while (!conn.request.isComplete() && !conn.isClosed)
                {
                    readAttempts++;
                    if (readAttempts > 1000) 
                    {
                        log("Too many read attempts, closing");
                        return;
                    }
                    
                    if (conn.readBuffer.length == 0)
                    {
                        log("Acquiring buffer...");
                        conn.readBuffer = conn.bufferPool.acquire(BufferSize.SMALL);
                    }
                    
                    log("Calling socketRead... (attempt " ~ readAttempts.to!string ~ ")");
                    auto res = conn.reactor.socketRead(conn.socket, conn.readBuffer[conn.readPos .. $]);
                    log("socketRead returned: status=" ~ (cast(int)res.status).to!string ~ ", bytes=" ~ res.bytesRead.to!string);
                    
                    if (res.bytesRead > 0)
                    {
                        conn.readPos += res.bytesRead;
                        log("Got " ~ res.bytesRead.to!string ~ " bytes, total=" ~ conn.readPos.to!string);
                        log("About to parse...");
                        conn.request = HTTPRequest.parse(conn.readBuffer[0 .. conn.readPos]);
                        log("Parse done, checking complete...");
                        auto complete = conn.request.isComplete();
                        log("isComplete = " ~ complete.to!string);
                        if (complete) 
                        {
                            log("Request complete!");
                            break;
                        }
                        log("Request not complete yet, need more data");
                    }
                    else if (res.status == IOStatus.wouldBlock)
                    {
                        log("wouldBlock, yielding...");
                        yield();
                    }
                    else
                    {
                        log("Read error or disconnect, closing");
                        return;
                    }
                }
                
                if (conn.isClosed || !conn.request.isComplete()) 
                {
                    log("Connection closed or request incomplete");
                    return;
                }
                
                atomicOp!"+="(requestCount, 1);
                log("Processing request: " ~ conn.request.method ~ " " ~ conn.request.path);
                
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
                log("Writing response...");
                conn.transition(aurora.runtime.connection.ConnectionState.WRITING_RESPONSE);
                conn.processRequest();
                
                int writeAttempts = 0;
                while (conn.writePos < conn.writeBuffer.length && !conn.isClosed)
                {
                    writeAttempts++;
                    if (writeAttempts > 1000)
                    {
                        log("Too many write attempts, closing");
                        return;
                    }
                    
                    log("Calling socketWrite... (attempt " ~ writeAttempts.to!string ~ ")");
                    auto res = conn.reactor.socketWrite(conn.socket, conn.writeBuffer[conn.writePos .. $]);
                    log("socketWrite returned: status=" ~ (cast(int)res.status).to!string ~ ", bytes=" ~ res.bytesWritten.to!string);
                    
                    if (res.bytesWritten > 0)
                    {
                        conn.writePos += res.bytesWritten;
                        log("Wrote " ~ res.bytesWritten.to!string ~ " bytes");
                    }
                    else if (res.status == IOStatus.wouldBlock)
                    {
                        log("Write wouldBlock, yielding...");
                        yield();
                    }
                    else
                    {
                        log("Write error, closing");
                        return;
                    }
                }
                
                log("Response sent");
                
                // Keep-alive
                if (conn.request.shouldKeepAlive())
                {
                    log("Keep-alive, resetting for next request");
                    conn.resetConnection();
                }
                else
                {
                    log("No keep-alive, closing");
                    return;
                }
            }
        }
        catch (Exception e) 
        {
            log("Exception: " ~ e.msg);
        }
    });
}
