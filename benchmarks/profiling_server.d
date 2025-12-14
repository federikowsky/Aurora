#!/usr/bin/env dub
/+ dub.sdl:
    name "aurora_profiling_benchmark"
    dependency "aurora" path=".."
    
    buildType "profiling" {
        dflags-ldc2 "-O3" "-release" "-boundscheck=off" "-mcpu=native" "-enable-inlining"
        dflags-dmd "-O" "-release" "-inline" "-g" "-vgc" "-profile=gc"
    }
+/
/**
 * Aurora Profiling Benchmark Server
 *
 * Comprehensive benchmark suite for realistic performance profiling.
 * Tests multiple scenarios: plaintext, JSON, large bodies, REST with headers.
 *
 * Endpoints:
 *   GET  /                  - Plaintext "Hello, World!" (13 bytes)
 *   GET  /json              - JSON small (~50 bytes)
 *   GET  /json/medium       - JSON array ~1KB (20 items)
 *   GET  /body/4k           - 4KB text response
 *   GET  /body/16k          - 16KB text response
 *   GET  /api/users/:id     - REST with path param + custom headers
 *   POST /api/users         - POST with body parsing + JSON response
 *   GET  /stats             - Server statistics
 *
 * Usage:
 *   dub run --single benchmarks/profiling_server.d --build=release
 *
 * Benchmark:
 *   ./benchmarks/run_full_benchmark.sh
 */
module benchmarks.profiling_server;

import aurora;
import aurora.runtime.server : Server, ServerConfig;
import aurora.mem.pool : BufferPool;
import core.time : seconds, msecs;
import core.thread : Thread;
import std.stdio : writeln, writefln;
import std.datetime.stopwatch : StopWatch, AutoStart;

// Pre-generated response bodies (avoid allocation during benchmark)
private immutable string BODY_4K;
private immutable string BODY_16K;
private immutable string JSON_MEDIUM;

shared static this()
{
    import std.array : appender;

    // Generate 4KB body
    auto buf4k = appender!string();
    foreach (i; 0 .. 100)
    {
        buf4k ~= "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";
    }
    // Pad to exactly 4096 bytes
    while (buf4k.data.length < 4096)
        buf4k ~= "X";
    BODY_4K = buf4k.data[0 .. 4096].idup;

    // Generate 16KB body
    auto buf16k = appender!string();
    foreach (i; 0 .. 400)
    {
        buf16k ~= "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";
    }
    while (buf16k.data.length < 16384)
        buf16k ~= "X";
    BODY_16K = buf16k.data[0 .. 16384].idup;

    // Generate JSON medium (~1KB array of 20 items)
    auto jsonBuf = appender!string();
    jsonBuf ~= `{"users":[`;
    foreach (i; 0 .. 20)
    {
        if (i > 0) jsonBuf ~= ",";
        jsonBuf ~= `{"id":`;
        jsonBuf ~= (1000 + i).stringof;
        import std.conv : to;
        jsonBuf ~= (1000 + i).to!string;
        jsonBuf ~= `,"name":"User `;
        jsonBuf ~= (i + 1).to!string;
        jsonBuf ~= `","email":"user`;
        jsonBuf ~= (i + 1).to!string;
        jsonBuf ~= `@example.com","active":true,"score":`;
        jsonBuf ~= ((i * 17) % 100).to!string;
        jsonBuf ~= `}`;
    }
    jsonBuf ~= `]}`;
    JSON_MEDIUM = jsonBuf.data.idup;
}

void main()
{
    writeln("╔══════════════════════════════════════════════════════════════╗");
    writeln("║      Aurora Profiling Benchmark Server (Extended Suite)      ║");
    writeln("╚══════════════════════════════════════════════════════════════╝");
    writeln();

    // Config optimized for benchmarking
    auto config = ServerConfig.defaults();
    config.port = 8080;
    config.numWorkers = 0;  // Auto-detect CPU cores
    config.maxConnections = 0;  // Unlimited connections
    config.maxInFlightRequests = 0;  // Unlimited in-flight requests
    config.maxRequestsPerConnection = 0;  // Unlimited requests per connection (keep-alive)
    config.readTimeout = 300.seconds;  // 5 minutes (long benchmarks)
    config.writeTimeout = 300.seconds;  // 5 minutes (long benchmarks)
    config.keepAliveTimeout = 600.seconds;  // 10 minutes (long keep-alive for benchmarks)
    config.debugMode = false;  // Disable debug logging for accurate timing


    auto app = new App(config);

    // ════════════════════════════════════════════════════════════════════
    // SCENARIO 1: Plaintext (13 bytes) - Pure framework overhead
    // ════════════════════════════════════════════════════════════════════
    app.get("/", (ref Context ctx) {
        ctx.response.setHeader("Content-Type", "text/plain");
        ctx.send("Hello, World!");
    });

    // ════════════════════════════════════════════════════════════════════
    // SCENARIO 2: JSON small (~50 bytes) - Typical API response
    // ════════════════════════════════════════════════════════════════════
    app.get("/json", (ref Context ctx) {
        ctx.json(["message": "Hello, World!", "status": "ok"]);
    });

    // ════════════════════════════════════════════════════════════════════
    // SCENARIO 3: JSON medium (~1KB) - Array of items
    // ════════════════════════════════════════════════════════════════════
    app.get("/json/medium", (ref Context ctx) {
        ctx.response.setHeader("Content-Type", "application/json");
        ctx.send(JSON_MEDIUM);
    });

    // ════════════════════════════════════════════════════════════════════
    // SCENARIO 4: Large body (4KB) - Medium response
    // ════════════════════════════════════════════════════════════════════
    app.get("/body/4k", (ref Context ctx) {
        ctx.response.setHeader("Content-Type", "text/plain");
        ctx.send(BODY_4K);
    });

    // ════════════════════════════════════════════════════════════════════
    // SCENARIO 5: Large body (16KB) - Large response
    // ════════════════════════════════════════════════════════════════════
    app.get("/body/16k", (ref Context ctx) {
        ctx.response.setHeader("Content-Type", "text/plain");
        ctx.send(BODY_16K);
    });

    // ════════════════════════════════════════════════════════════════════
    // SCENARIO 6: REST endpoint with path param + custom headers
    // ════════════════════════════════════════════════════════════════════
    app.get("/api/users/:id", (ref Context ctx) {
        auto userId = ctx.params.get("id");

        // Set multiple custom headers (realistic REST scenario)
        ctx.response.setHeader("X-Request-Id", "req-12345-abcde");
        ctx.response.setHeader("X-RateLimit-Remaining", "99");
        ctx.response.setHeader("X-RateLimit-Reset", "1234567890");
        ctx.response.setHeader("Cache-Control", "private, max-age=60");
        ctx.response.setHeader("ETag", "\"abc123def456\"");

        // JSON response with user data
        import std.format : format;
        auto json = format(
            `{"id":%s,"name":"User %s","email":"user%s@example.com","role":"member","created_at":"2024-01-15T10:30:00Z"}`,
            userId, userId, userId
        );
        ctx.response.setHeader("Content-Type", "application/json");
        ctx.send(json);
    });

    // ════════════════════════════════════════════════════════════════════
    // SCENARIO 7: POST with body parsing
    // ════════════════════════════════════════════════════════════════════
    app.post("/api/users", (ref Context ctx) {
        // Parse request body (simulates real work)
        auto body = ctx.request.body();

        // Set response headers
        ctx.response.setHeader("X-Request-Id", "req-67890-fghij");
        ctx.response.setHeader("Location", "/api/users/12345");

        // Return created response
        ctx.response.setStatus(201);
        ctx.json([
            "id": "12345",
            "status": "created",
            "message": "User created successfully"
        ]);
    });

    // ════════════════════════════════════════════════════════════════════
    // STATS: Server statistics for monitoring
    // ════════════════════════════════════════════════════════════════════
    app.get("/stats", (ref Context ctx) {
        import std.format : format;
        auto stats = format(
            `{"requests":%d,"pool_misses":%d,"pool_fallbacks":%d,"pool_drops":%d}`,
            app.totalRequests(),
            BufferPool.getGlobalPoolMisses(),
            BufferPool.getGlobalFallbackAllocs(),
            BufferPool.getGlobalPoolFullDrops()
        );
        ctx.json(stats);
    });

    writeln("Benchmark Endpoints:");
    writeln("  GET  /                  - Plaintext 13 bytes");
    writeln("  GET  /json              - JSON small ~50 bytes");
    writeln("  GET  /json/medium       - JSON array ~1KB (20 items)");
    writeln("  GET  /body/4k           - Text 4KB");
    writeln("  GET  /body/16k          - Text 16KB");
    writeln("  GET  /api/users/:id     - REST + path param + 5 headers");
    writeln("  POST /api/users         - POST + body parsing + JSON response");
    writeln("  GET  /stats             - Server statistics");
    writeln();
    writefln("Response sizes: JSON_MEDIUM=%d bytes, BODY_4K=%d bytes, BODY_16K=%d bytes",
             JSON_MEDIUM.length, BODY_4K.length, BODY_16K.length);
    writeln();
    writefln("Starting server on http://localhost:%d", config.port);
    writeln("Run benchmark: ./benchmarks/run_full_benchmark.sh");
    writeln("Use Ctrl+C to stop");
    writeln();

    app.listen();
}
