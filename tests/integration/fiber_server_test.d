/**
 * Aurora Fiber Server Test
 * 
 * Simple test server for the new fiber-based architecture.
 */
module tests.integration.fiber_server_test;

import aurora.runtime.server;
import aurora.web.router;
import aurora.web.context;
import std.stdio;

void main()
{
    writeln("=== Aurora Fiber Server Test ===\n");
    
    auto router = new Router();
    
    router.get("/", (ref Context ctx) {
        ctx.response.setStatus(200);
        ctx.response.setBody(`{"status":"ok","architecture":"fiber"}`);
    });
    
    router.get("/health", (ref Context ctx) {
        ctx.response.setStatus(200);
        ctx.response.setBody(`{"health":"good"}`);
    });
    
    router.get("/echo/:msg", (ref Context ctx) {
        auto msg = ctx.params.get("msg", "none");
        ctx.response.setStatus(200);
        ctx.response.setBody(`{"echo":"` ~ msg ~ `"}`);
    });
    
    auto config = ServerConfig();
    config.port = 18888;
    config.host = "0.0.0.0";  // Listen on all interfaces for Docker
    config.debugMode = true;
    
    writeln("Configuration:");
    writefln("  Port: %d", config.port);
    writefln("  Workers: %d", config.effectiveWorkers());
    writefln("  MaxHeaderSize: %d bytes", config.maxHeaderSize);
    writefln("  MaxBodySize: %d bytes", config.maxBodySize);
    writefln("  ReadTimeout: %s", config.readTimeout);
    writeln();
    
    auto server = new Server(router, config);
    
    writeln("Server starting...");
    writeln("Test endpoints:");
    writeln("  curl http://localhost:18888/");
    writeln("  curl http://localhost:18888/health");
    writeln("  curl http://localhost:18888/echo/hello");
    writeln("\nPress Ctrl+C to stop.\n");
    
    server.run();
}
