/+ dub.sdl:
name "vibed_benchmark"
dependency "vibe-d" version="~>0.10.0"
+/
/**
 * vibe.d HTTP Benchmark Server (Extended Suite)
 *
 * Comprehensive benchmark server for comparison with Aurora.
 * Same endpoints as Aurora's profiling_server.d for fair comparison.
 *
 * Endpoints:
 *   GET  /                  - Plaintext "Hello, World!" (13 bytes)
 *   GET  /json              - JSON small (~50 bytes)
 *   GET  /json/medium       - JSON array ~1KB (20 items)
 *   GET  /body/4k           - 4KB text response
 *   GET  /body/16k          - 16KB text response
 *   GET  /api/users/:id     - REST with path param + custom headers
 *   POST /api/users         - POST with body parsing + JSON response
 *
 * Build & Run:
 *   dub run --single benchmarks/comparison/vibed_server.d --build=release
 *
 * Benchmark:
 *   ./benchmarks/run_full_benchmark.sh --vibed
 */
module benchmarks.comparison.vibed_server;

import vibe.vibe;
import std.array : appender;
import std.conv : to;
import std.format : format;

// Pre-generated response bodies (same as Aurora)
private immutable string BODY_4K;
private immutable string BODY_16K;
private immutable string JSON_MEDIUM;

shared static this()
{
    // Generate 4KB body
    auto buf4k = appender!string();
    foreach (i; 0 .. 100)
    {
        buf4k ~= "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";
    }
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
        jsonBuf ~= (1000 + i).to!string;
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
    auto settings = new HTTPServerSettings;
    settings.port = 8081;  // Different port from Aurora (8080)
    settings.bindAddresses = ["0.0.0.0"];

    auto router = new URLRouter;

    // ════════════════════════════════════════════════════════════════════
    // SCENARIO 1: Plaintext (13 bytes)
    // ════════════════════════════════════════════════════════════════════
    router.get("/", (req, res) {
        res.contentType = "text/plain";
        res.writeBody("Hello, World!");
    });

    // ════════════════════════════════════════════════════════════════════
    // SCENARIO 2: JSON small (~50 bytes)
    // ════════════════════════════════════════════════════════════════════
    router.get("/json", (req, res) {
        res.contentType = "application/json";
        res.writeBody(`{"message":"Hello, World!","status":"ok"}`);
    });

    // ════════════════════════════════════════════════════════════════════
    // SCENARIO 3: JSON medium (~1KB)
    // ════════════════════════════════════════════════════════════════════
    router.get("/json/medium", (req, res) {
        res.contentType = "application/json";
        res.writeBody(JSON_MEDIUM);
    });

    // ════════════════════════════════════════════════════════════════════
    // SCENARIO 4: Large body (4KB)
    // ════════════════════════════════════════════════════════════════════
    router.get("/body/4k", (req, res) {
        res.contentType = "text/plain";
        res.writeBody(BODY_4K);
    });

    // ════════════════════════════════════════════════════════════════════
    // SCENARIO 5: Large body (16KB)
    // ════════════════════════════════════════════════════════════════════
    router.get("/body/16k", (req, res) {
        res.contentType = "text/plain";
        res.writeBody(BODY_16K);
    });

    // ════════════════════════════════════════════════════════════════════
    // SCENARIO 6: REST endpoint with path param + custom headers
    // ════════════════════════════════════════════════════════════════════
    router.get("/api/users/:id", (req, res) {
        auto userId = req.params["id"];

        // Set multiple custom headers (realistic REST scenario)
        res.headers["X-Request-Id"] = "req-12345-abcde";
        res.headers["X-RateLimit-Remaining"] = "99";
        res.headers["X-RateLimit-Reset"] = "1234567890";
        res.headers["Cache-Control"] = "private, max-age=60";
        res.headers["ETag"] = "\"abc123def456\"";

        // JSON response with user data
        auto json = format(
            `{"id":%s,"name":"User %s","email":"user%s@example.com","role":"member","created_at":"2024-01-15T10:30:00Z"}`,
            userId, userId, userId
        );
        res.contentType = "application/json";
        res.writeBody(json);
    });

    // ════════════════════════════════════════════════════════════════════
    // SCENARIO 7: POST with body parsing
    // ════════════════════════════════════════════════════════════════════
    router.post("/api/users", (req, res) {
        // Parse request body (simulates real work)
        auto body = req.bodyReader.readAll();

        // Set response headers
        res.headers["X-Request-Id"] = "req-67890-fghij";
        res.headers["Location"] = "/api/users/12345";

        // Return created response
        res.statusCode = 201;
        res.contentType = "application/json";
        res.writeBody(`{"id":"12345","status":"created","message":"User created successfully"}`);
    });

    listenHTTP(settings, router);

    logInfo("═══════════════════════════════════════════════════════════════");
    logInfo("   vibe.d Benchmark Server (Extended Suite) - Port 8081");
    logInfo("═══════════════════════════════════════════════════════════════");
    logInfo("");
    logInfo("Endpoints:");
    logInfo("  GET  /                  - Plaintext 13 bytes");
    logInfo("  GET  /json              - JSON small ~50 bytes");
    logInfo("  GET  /json/medium       - JSON array ~1KB");
    logInfo("  GET  /body/4k           - Text 4KB");
    logInfo("  GET  /body/16k          - Text 16KB");
    logInfo("  GET  /api/users/:id     - REST + path param + 5 headers");
    logInfo("  POST /api/users         - POST + body parsing + JSON response");
    logInfo("");
    logInfo("Response sizes: JSON_MEDIUM=%d bytes, BODY_4K=%d bytes, BODY_16K=%d bytes",
            JSON_MEDIUM.length, BODY_4K.length, BODY_16K.length);
    logInfo("");
    logInfo("Run benchmark: ./benchmarks/run_full_benchmark.sh --vibed");

    runApplication();
}
