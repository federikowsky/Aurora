/**
 * Aurora Sync Server
 * 
 * Synchronous/blocking style server example.
 * Single-threaded, simple request handling.
 */
module examples.sync_server;

import aurora;

void main()
{
    auto config = ServerConfig.defaults();
    config.numWorkers = 1;  // Single worker = synchronous handling
    
    auto app = new App(config);
    
    app.get("/", (ref Context ctx) {
        ctx.send("Sync server - single threaded");
    });
    
    // Simulate slow operation
    app.get("/slow", (ref Context ctx) {
        import core.thread : Thread;
        import core.time : dur;
        
        Thread.sleep(dur!"msecs"(100));
        ctx.send("Done after 100ms");
    });
    
    // Sequential processing demo
    app.get("/sequence/:n", (ref Context ctx) {
        import std.conv : to;
        int n = 10;
        try {
            n = ctx.params.get("n", "10").to!int;
        } catch (Exception) {}
        
        string result = "Sequence: ";
        foreach (i; 1..n+1)
            result ~= i.to!string ~ " ";
        
        ctx.send(result);
    });
    
    import std.stdio : writeln;
    writeln("Sync server on http://localhost:8080 (single worker)");
    
    app.listen(8080);
}
