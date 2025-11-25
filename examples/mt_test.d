/**
 * Multi-threaded server test
 * 
 * Tests the thread pool server architecture
 */
module mt_test;

import aurora.runtime.server;
import aurora.web.router;
import aurora.web.context;
import aurora.http : HTTPRequest;

import core.stdc.signal;
import core.stdc.stdlib : exit;
import std.stdio;
import std.conv : to;

__gshared Server server;

extern(C) void handleSignal(int sig) nothrow @nogc @system
{
    // Simple exit - server cleanup happens via OS
    exit(0);
}

void main(string[] args)
{
    // Parse args
    uint numWorkers = 4;
    foreach (arg; args[1..$])
    {
        import std.algorithm : startsWith;
        if (arg.startsWith("--workers="))
        {
            try { numWorkers = arg[10..$].to!uint; } catch (Exception) {}
        }
    }
    
    writefln("Starting with %d workers...", numWorkers);
    
    // Signal handling - cross-platform
    version(Posix)
    {
        signal(SIGINT, &handleSignal);
        signal(SIGTERM, &handleSignal);
    }
    version(Windows)
    {
        // Windows uses Ctrl+C handler via SetConsoleCtrlHandler
        // For simplicity, we just rely on process termination
        signal(SIGINT, &handleSignal);
    }
    
    // Create router
    auto router = new Router();
    
    router.get("/", (ref Context ctx) {
        ctx.send("Hello from Aurora MT server!");
    });
    
    router.get("/health", (ref Context ctx) {
        import std.conv : to;
        ctx.json(`{"status":"ok","workers":` ~ numWorkers.to!string ~ `,"mode":"multi-threaded"}`);
    });
    
    router.get("/echo/:msg", (ref Context ctx) {
        ctx.send("Echo: " ~ ctx.params.get("msg", ""));
    });
    
    // Config
    ServerConfig config;
    config.port = 8080;
    config.numWorkers = numWorkers;
    config.debugMode = true;
    
    // Start
    server = new Server(router, config);
    server.run();
}
