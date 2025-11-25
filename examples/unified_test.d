/**
 * Test server for unified multi-worker architecture
 * 
 * Tests:
 * - N=1 worker (single-threaded)
 * - N=4 workers (multi-threaded)
 * - Cross-platform compatibility (macOS shared socket, Linux SO_REUSEPORT)
 */
module unified_test;

import aurora.runtime.server;
import aurora.web.router;
import aurora.web.context;
import aurora.web.middleware;

import core.thread;
import core.stdc.signal;
import std.stdio;

__gshared Server server;
__gshared bool shouldStop = false;

extern(C) void handleSignal(int sig) nothrow @nogc @system
{
    shouldStop = true;
}

void main(string[] args)
{
    // Parse command line for worker count
    uint numWorkers = 4;  // Default
    foreach (arg; args[1..$])
    {
        import std.algorithm : startsWith;
        import std.conv : to;
        if (arg.startsWith("--workers="))
        {
            try { numWorkers = arg[10..$].to!uint; } catch (Exception) {}
        }
    }
    
    writefln("Starting with %d workers...", numWorkers);
    
    // Setup signal handler
    signal(SIGINT, &handleSignal);
    signal(SIGTERM, &handleSignal);
    
    // Create router
    auto router = new Router();
    
    // Simple routes for testing
    router.get("/", (ref Context ctx) {
        ctx.send("Hello from Aurora unified server!");
    });
    
    router.get("/health", (ref Context ctx) {
        import std.conv : to;
        ctx.json(`{"status":"ok","workers":` ~ numWorkers.to!string ~ `}`);
    });
    
    router.get("/echo/:msg", (ref Context ctx) {
        ctx.send("Echo: " ~ ctx.params.get("msg", ""));
    });
    
    // Create config
    ServerConfig config;
    config.port = 8080;
    config.numWorkers = numWorkers;
    config.debugMode = true;
    
    // Create and run server
    server = new Server(router, null, config);
    
    scope(exit)
    {
        if (server !is null)
        {
            writefln("\nStats: %d requests, %d connections, %d errors",
                server.getRequests(), server.getConnections(), server.getErrors());
        }
    }
    
    server.run();
}
