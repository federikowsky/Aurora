/**
 * Aurora Minimal Server
 * 
 * The absolute simplest Aurora server - just one route.
 * Perfect for testing and learning.
 */
module examples.minimal_server;

import aurora;

void main()
{
    auto app = new App();
    
    app.get("/", (ref Context ctx) {
        ctx.send("Hello from Aurora!");
    });
    
    import std.stdio : writeln;
    writeln("Minimal server on http://localhost:8080");
    app.listen(8080);
}
