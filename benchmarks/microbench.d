#!/usr/bin/env dub
/+ dub.sdl:
    name "aurora_microbench"
    dependency "aurora" path=".."
+/
/**
 * Aurora Micro-Benchmarks
 * 
 * Isolate individual component costs to find the bottleneck.
 * Run from benchmarks/ directory.
 */
module benchmarks.microbench;

import std.stdio : writeln, writefln;
import std.datetime.stopwatch : StopWatch, AutoStart;
import core.time : Duration, nsecs, usecs, msecs;

// Aurora components
import aurora.web.router : Router, PathParams;
import aurora.web.context : Context;
import aurora.http : HTTPResponse, HTTPRequest;
import aurora.http.util : buildResponseInto;

enum ITERATIONS = 1_000_000;
enum WARMUP = 10_000;

void main()
{
    writeln("╔══════════════════════════════════════════════════════════════╗");
    writeln("║         Aurora Micro-Benchmarks                              ║");
    writeln("╚══════════════════════════════════════════════════════════════╝");
    writeln();
    
    // 1. Router.match() benchmark
    benchRouterMatch();
    
    // 2. Context creation
    benchContextCreation();
    
    // 3. HTTPResponse creation
    benchResponseCreation();
    
    // 4. buildResponseInto
    benchBuildResponse();
    
    // 5. PathParams operations
    benchPathParams();
    
    // 6. Full request simulation (no I/O)
    benchFullRequest();
    
    writeln();
    writeln("═══════════════════════════════════════════════════════════════");
    writeln("  Benchmark complete. Look for the slowest component.");
    writeln("═══════════════════════════════════════════════════════════════");
}

void benchRouterMatch()
{
    writeln("─── Router.match() ───────────────────────────────────────────");
    
    auto router = new Router();
    
    // Add routes like a typical app
    router.get("/", (ref Context ctx) { });
    router.get("/json", (ref Context ctx) { });
    router.get("/users", (ref Context ctx) { });
    router.get("/users/:id", (ref Context ctx) { });
    router.get("/users/:id/posts", (ref Context ctx) { });
    router.get("/api/v1/products", (ref Context ctx) { });
    router.get("/api/v1/products/:id", (ref Context ctx) { });
    router.post("/api/v1/products", (ref Context ctx) { });
    
    // Warmup
    foreach (_; 0 .. WARMUP)
    {
        auto result = router.match("GET", "/");
    }
    
    // Benchmark static route "/"
    auto sw1 = StopWatch(AutoStart.yes);
    foreach (_; 0 .. ITERATIONS)
    {
        auto result = router.match("GET", "/");
    }
    sw1.stop();
    
    // Benchmark param route "/users/:id"
    auto sw2 = StopWatch(AutoStart.yes);
    foreach (_; 0 .. ITERATIONS)
    {
        auto result = router.match("GET", "/users/123");
    }
    sw2.stop();
    
    // Benchmark deep route
    auto sw3 = StopWatch(AutoStart.yes);
    foreach (_; 0 .. ITERATIONS)
    {
        auto result = router.match("GET", "/api/v1/products/456");
    }
    sw3.stop();
    
    printResult("  Static route '/'", sw1.peek, ITERATIONS);
    printResult("  Param route '/users/:id'", sw2.peek, ITERATIONS);
    printResult("  Deep route '/api/v1/products/:id'", sw3.peek, ITERATIONS);
    writeln();
}

void benchContextCreation()
{
    writeln("─── Context Creation ─────────────────────────────────────────");
    
    HTTPRequest req;
    HTTPResponse resp = HTTPResponse(200, "OK");
    
    // Warmup
    foreach (_; 0 .. WARMUP)
    {
        Context ctx;
        ctx.request = &req;
        ctx.response = &resp;
    }
    
    auto sw = StopWatch(AutoStart.yes);
    foreach (_; 0 .. ITERATIONS)
    {
        Context ctx;
        ctx.request = &req;
        ctx.response = &resp;
    }
    sw.stop();
    
    printResult("  Context struct init", sw.peek, ITERATIONS);
    writeln();
}

void benchResponseCreation()
{
    writeln("─── HTTPResponse Creation ────────────────────────────────────");
    
    // Warmup
    foreach (_; 0 .. WARMUP)
    {
        auto resp = HTTPResponse(200, "OK");
        resp.setHeader("Content-Type", "text/plain");
        resp.setBody("Hello, World!");
    }
    
    auto sw = StopWatch(AutoStart.yes);
    foreach (_; 0 .. ITERATIONS)
    {
        auto resp = HTTPResponse(200, "OK");
        resp.setHeader("Content-Type", "text/plain");
        resp.setBody("Hello, World!");
    }
    sw.stop();
    
    printResult("  HTTPResponse + setHeader + setBody", sw.peek, ITERATIONS);
    writeln();
}

void benchBuildResponse()
{
    writeln("─── buildResponseInto (@nogc) ────────────────────────────────");
    
    ubyte[4096] buffer;
    
    // Warmup
    foreach (_; 0 .. WARMUP)
    {
        auto len = buildResponseInto(buffer[], 200, "text/plain", "Hello, World!", true);
    }
    
    auto sw = StopWatch(AutoStart.yes);
    foreach (_; 0 .. ITERATIONS)
    {
        auto len = buildResponseInto(buffer[], 200, "text/plain", "Hello, World!", true);
    }
    sw.stop();
    
    printResult("  buildResponseInto (stack buffer)", sw.peek, ITERATIONS);
    writeln();
}

void benchPathParams()
{
    writeln("─── PathParams Operations ────────────────────────────────────");
    
    // Warmup
    foreach (_; 0 .. WARMUP)
    {
        PathParams params;
        params["id"] = "123";
        params["name"] = "test";
        auto val = params["id"];
    }
    
    auto sw = StopWatch(AutoStart.yes);
    foreach (_; 0 .. ITERATIONS)
    {
        PathParams params;
        params["id"] = "123";
        params["name"] = "test";
        auto val = params["id"];
    }
    sw.stop();
    
    printResult("  PathParams set + get", sw.peek, ITERATIONS);
    writeln();
}

void benchFullRequest()
{
    writeln("─── Full Request Simulation (no I/O) ─────────────────────────");
    
    auto router = new Router();
    router.get("/", (ref Context ctx) {
        ctx.send("Hello, World!");
    });
    
    HTTPRequest req;
    ubyte[4096] buffer;
    
    // Warmup
    foreach (_; 0 .. WARMUP)
    {
        // 1. Match route
        auto match = router.match("GET", "/");
        
        // 2. Create context
        Context ctx;
        ctx.request = &req;
        auto resp = HTTPResponse(200, "OK");
        ctx.response = &resp;
        
        // 3. Execute handler
        if (match.handler !is null)
        {
            match.handler(ctx);
        }
        
        // 4. Build response
        auto len = buildResponseInto(buffer[], resp.status, 
            resp.getContentType(), resp.getBody(), true);
    }
    
    auto sw = StopWatch(AutoStart.yes);
    foreach (_; 0 .. ITERATIONS)
    {
        // 1. Match route
        auto match = router.match("GET", "/");
        
        // 2. Create context
        Context ctx;
        ctx.request = &req;
        auto resp = HTTPResponse(200, "OK");
        ctx.response = &resp;
        
        // 3. Execute handler (sets body via ctx.send)
        if (match.handler !is null)
        {
            match.handler(ctx);
        }
        
        // 4. Build response 
        auto len = buildResponseInto(buffer[], resp.status, 
            resp.getContentType(), resp.getBody(), true);
    }
    sw.stop();
    
    printResult("  Full request (match+ctx+handler+build)", sw.peek, ITERATIONS);
    
    // Calculate theoretical max RPS
    auto nsPerOp = sw.peek.total!"nsecs" / ITERATIONS;
    auto theoreticalRps = 1_000_000_000 / nsPerOp;
    writefln("  Theoretical max: %,d req/s (single-threaded, no I/O)", theoreticalRps);
    writeln();
}

void printResult(string name, Duration duration, ulong iterations)
{
    auto totalNs = duration.total!"nsecs";
    auto nsPerOp = totalNs / iterations;
    auto opsPerSec = iterations * 1_000_000_000 / totalNs;
    
    writefln("%s: %,d ns/op (%,d ops/sec)", name, nsPerOp, opsPerSec);
}
