/+ dub.sdl:
    name "simple_server"
    dependency "aurora" path=".."
    dependency "vibe-core" version="~>2.8.6"
    dependency "eventcore" version="~>0.9.0"
+/
module simple_server;

import aurora.web.router;
import aurora.web.context;
import aurora.runtime.connection;
import aurora.runtime.reactor;
import aurora.runtime.config;
import aurora.mem.pool;
import aurora.mem.arena;
import aurora.http : HTTPRequest;

import vibe.core.core : runEventLoop, runTask, exitEventLoop;
import eventcore.core; // Import core for eventDriver
import eventcore.driver;
import std.stdio;
import core.thread;
import std.conv : to;
import core.atomic;

// Embedded Server implementation since we can't modify source/
class Server
{
    private Router router;
    private ushort port;
    private int threads;
    private Thread[] workerThreads;
    private shared bool running;

    this(Router router, ushort port = 8080, int threads = 4)
    {
        this.router = router;
        this.port = port;
        this.threads = threads;
        this.running = false;
    }

    void start()
    {
        writeln("Starting Aurora Server on port ", port, " with ", threads, " threads...");
        atomicStore(running, true);

        // Create worker threads
        foreach (i; 0 .. threads)
        {
            uint id = cast(uint)i;
            auto t = new Thread({
                workerLoop(id);
            });
            t.start();
            workerThreads ~= t;
        }

        // Wait for workers (in a real app, we might want to handle signals here)
        foreach (t; workerThreads)
        {
            t.join();
        }
    }

    private void workerLoop(uint id)
    {
        writeln("Worker ", id, " starting...");
        try
        {
            // Thread-local resources
            writeln("Worker ", id, " creating Reactor...");
            auto reactor = new Reactor();
            writeln("Worker ", id, " creating BufferPool...");
            auto bufferPool = new BufferPool();
            auto config = ConnectionConfig.defaults();
            
            try
            {
                // Get event driver
                auto driver = eventcore.core.eventDriver;
                
                // Listen
                import std.socket : InternetAddress;
                auto addr = new InternetAddress("0.0.0.0", port);
                
                driver.sockets.listenStream(addr, (StreamListenSocketFD listenSock, StreamSocketFD clientSock, scope RefAddress remoteAddr) @safe nothrow {
                    (() @trusted {
                        try {
                            // Handle new connection
                            handleConnection(clientSock, reactor, &bufferPool, &config);
                        } catch (Exception e) {
                            import core.stdc.stdio : printf;
                            printf("Accept error\n");
                        }
                    })();
                });

                writeln("Worker ", id, " listening on port ", port);

                // Run event loop
                runEventLoop();
            }
            catch (Exception e)
            {
                writeln("Worker ", id, " failed: ", e.msg);
            }
            finally
            {
                // Cleanup
                if (bufferPool) bufferPool.cleanup();
                if (reactor) reactor.shutdown();
            }
        }
        catch (Throwable t)
        {
            writeln("Worker ", id, " CRASHED: ", t.msg);
            // Print stack trace if possible, or just msg
            import std.stdio : stderr;
            stderr.writeln(t);
        }
    }

    private void handleConnection(StreamSocketFD sock, Reactor reactor, BufferPool* pool, ConnectionConfig* cfg) @trusted
    {
        auto conn = new Connection();
        conn.initialize(sock, pool, reactor, cfg);
        
        runTask({
            try {
                import core.stdc.stdio : printf;
                // printf("Task started\n");
                customConnectionLoop(conn, router);
            } catch (Throwable t) {
                import core.stdc.stdio : printf;
                printf("Connection loop CRASH: %s\n", t.msg.ptr);
            }
        });
    }

    private void customConnectionLoop(Connection* conn, Router router)
    {
        import core.stdc.stdio : printf;
        try
        {
            while (!conn.isClosed)
            {
                // 1. Read Request
                conn.transition(aurora.runtime.connection.ConnectionState.READING_HEADERS);
                
                // READ LOOP
                while (!conn.request.isComplete() && !conn.isClosed)
                {
                    if (conn.readBuffer.length == 0) {
                        // printf("Acquiring buffer...\n");
                        conn.readBuffer = conn.bufferPool.acquire(BufferSize.SMALL);
                    }
                    
                    auto res = conn.reactor.socketRead(conn.socket, conn.readBuffer[conn.readPos .. $]);
                    
                    if (res[1] > 0)
                    {
                        conn.readPos += res[1];
                        conn.request = HTTPRequest.parse(conn.readBuffer[0 .. conn.readPos]);
                        
                        if (conn.request.isComplete()) break;
                    }
                    else if (res[0] == eventcore.driver.IOStatus.wouldBlock)
                    {
                        import vibe.core.core : yield;
                        yield();
                    }
                    else
                    {
                        conn.close();
                        return;
                    }
                }
                
                if (conn.isClosed) return;
                
                // 2. Handle Request
                conn.transition(aurora.runtime.connection.ConnectionState.PROCESSING);
                
                // Route
                auto match = router.match(conn.request.method, conn.request.path);
                if (match.found)
                {
                    // Create context (pass pointers)
                    auto ctx = Context(&conn.request, &conn.response);
                    match.handler(ctx);
                }
                else
                {
                    conn.response.setStatus(404);
                    conn.response.setBody("Not Found");
                }
                
                // 3. Write Response
                conn.transition(aurora.runtime.connection.ConnectionState.WRITING_RESPONSE);
                
                conn.processRequest();
                
                // Write loop
                while (conn.writePos < conn.writeBuffer.length && !conn.isClosed)
                {
                    auto res = conn.reactor.socketWrite(conn.socket, conn.writeBuffer[conn.writePos .. $]);
                    if (res[1] > 0)
                    {
                        conn.writePos += res[1];
                    }
                    else if (res[0] == eventcore.driver.IOStatus.wouldBlock)
                    {
                        import vibe.core.core : yield;
                        yield();
                    }
                    else
                    {
                        conn.close();
                        return;
                    }
                }
                
                // 4. Keep-Alive logic
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
        catch (Exception e)
        {
            printf("Connection error: %s\n", e.msg.ptr);
            conn.close();
        }
    }
}

void main()
{
    // Define routes
    auto router = new Router();
    router.get("/", (Context ctx) {
        ctx.response.setStatus(200);
        ctx.response.setBody("Hello from Aurora!");
    });
    
    router.get("/health", (Context ctx) {
        ctx.response.setStatus(200);
        ctx.response.setBody("OK");
    });

    // Start server
    auto server = new Server(router, 8080, 4);
    server.start();
}
