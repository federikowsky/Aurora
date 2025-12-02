/**
 * Aurora Micro Server
 * 
 * Tiny JSON microservice example.
 * Single endpoint, minimal code.
 */
module examples.micro_server;

import aurora;
import std.json;
import std.conv : to;
import core.atomic;

// Simple counter service
shared long counter = 0;

void main()
{
    auto app = new App();
    
    // GET /count - return current count
    app.get("/count", (ref Context ctx) {
        auto val = atomicLoad(counter);
        ctx.header("Content-Type", "application/json")
           .send(`{"count":` ~ val.to!string ~ `}`);
    });
    
    // POST /count - increment counter
    app.post("/count", (ref Context ctx) {
        auto newVal = atomicOp!"+="(counter, 1L);
        ctx.header("Content-Type", "application/json")
           .send(`{"count":` ~ newVal.to!string ~ `}`);
    });
    
    // DELETE /count - reset counter
    app.delete_("/count", (ref Context ctx) {
        atomicStore(counter, 0L);
        ctx.header("Content-Type", "application/json")
           .send(`{"count":0}`);
    });
    
    import std.stdio : writeln;
    writeln("Micro counter service on http://localhost:8080");
    writeln("  GET  /count  - get counter");
    writeln("  POST /count  - increment");
    writeln("  DELETE /count - reset");
    
    app.listen(8080);
}
