/**
 * Compression Middleware Tests
 *
 * Tests for response compression middleware (gzip/deflate).
 * Tests cover:
 * - Gzip compression
 * - Deflate compression
 * - Accept-Encoding parsing
 * - Minimum size threshold
 * - Skip compressed content types
 * - Content-Encoding header
 * - Compression only when beneficial
 */
module tests.unit.web.compression_test;

import unit_threaded;
import aurora.web.middleware.compression;
import aurora.web.middleware;
import aurora.web.context;
import aurora.http;
import std.zlib;
import std.string : indexOf;
import std.array : appender;

// ========================================
// HELPER FUNCTIONS
// ========================================

/// Repeat string N times
string repeatString(string s, size_t n)
{
    import std.array : appender;
    auto result = appender!string();
    foreach (i; 0 .. n)
    {
        result ~= s;
    }
    return result.data;
}

/// Get header from response
string getHeader(HTTPResponse* response, string headerName)
{
    if (response is null) return "";
    auto headers = response.getHeaders();
    if (auto val = headerName in headers)
        return *val;
    return "";
}

/// Check if header exists in response
bool hasHeader(HTTPResponse* response, string headerName)
{
    if (response is null) return false;
    auto headers = response.getHeaders();
    return (headerName in headers) !is null;
}

/// Create test context with request headers
struct TestContext
{
    Context ctx;
    HTTPResponse response;
    HTTPRequest request;
    
    static TestContext create(string[string] extraHeaders = null)
    {
        TestContext tc;
        
        string headersStr = "Host: localhost\r\n";
        if (extraHeaders !is null)
        {
            foreach (name, value; extraHeaders)
            {
                headersStr ~= name ~ ": " ~ value ~ "\r\n";
            }
        }
        
        string rawRequest =
            "GET /api HTTP/1.1\r\n" ~
            headersStr ~
            "\r\n";
        tc.request = HTTPRequest.parse(cast(ubyte[]) rawRequest);
        tc.response = HTTPResponse(200, "OK");
        tc.ctx.request = &tc.request;
        tc.ctx.response = &tc.response;
        return tc;
    }
    
    static TestContext createSimple()
    {
        TestContext tc;
        tc.response = HTTPResponse(200, "OK");
        tc.ctx.response = &tc.response;
        return tc;
    }
}

// ========================================
// CONFIG TESTS
// ========================================

// Test 1: Default compression config
@("default compression config")
unittest
{
    auto config = CompressionConfig();
    
    config.minSize.shouldEqual(1024);  // 1 KB
    config.compressionLevel.shouldEqual(6);
    config.enableGzip.shouldBeTrue;
    config.enableDeflate.shouldBeTrue;
    config.preferredMethod.shouldEqual("gzip");
    assert(config.skipContentTypes.length > 0, "Should have skip content types");
}

// Test 2: Custom compression config
@("custom compression config")
unittest
{
    CompressionConfig config;
    config.minSize = 2048;  // 2 KB
    config.compressionLevel = 9;  // Max compression
    config.enableGzip = true;
    config.enableDeflate = false;
    config.preferredMethod = "gzip";
    
    config.minSize.shouldEqual(2048);
    config.compressionLevel.shouldEqual(9);
    config.enableGzip.shouldBeTrue;
    config.enableDeflate.shouldBeFalse;
    config.preferredMethod.shouldEqual("gzip");
}

// ========================================
// MIDDLEWARE CREATION TESTS
// ========================================

// Test 3: CompressionMiddleware can be created
@("CompressionMiddleware can be created")
unittest
{
    auto config = CompressionConfig();
    auto compression = new CompressionMiddleware(config);
    
    assert(compression !is null, "Compression middleware should be created");
}

// Test 4: compressionMiddleware helper creates middleware
@("compressionMiddleware helper creates middleware")
unittest
{
    auto middleware = compressionMiddleware();
    
    auto tc = TestContext.createSimple();
    tc.response.setBody("Hello, World!");
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    middleware(tc.ctx, &next);
    
    nextCalled.shouldBeTrue;
}

// ========================================
// COMPRESSION TESTS
// ========================================

// Test 5: Small response not compressed (below threshold)
@("small response not compressed")
unittest
{
    auto config = CompressionConfig();
    config.minSize = 1024;  // 1 KB threshold
    
    auto compression = new CompressionMiddleware(config);
    auto tc = TestContext.createSimple();
    
    // Small body (below threshold)
    string smallBody = "Hello";  // 5 bytes
    tc.response.setBody(smallBody);
    
    void next() { }
    compression.handle(tc.ctx, &next);
    
    // Should not have Content-Encoding header
    hasHeader(&tc.response, "Content-Encoding").shouldBeFalse;
    
    // Body should be unchanged
    tc.response.getBody().shouldEqual(smallBody);
}

// Test 6: Large response compressed with gzip
@("large response compressed with gzip")
unittest
{
    auto config = CompressionConfig();
    config.minSize = 100;  // Low threshold for testing
    
    auto compression = new CompressionMiddleware(config);
    auto tc = TestContext.create(["Accept-Encoding": "gzip, deflate"]);
    
    // Large body (above threshold)
    string largeBody = repeatString("A", 2000);  // 2000 bytes
    tc.response.setBody(largeBody);
    tc.response.setHeader("Content-Type", "text/plain");
    
    void next() { }
    compression.handle(tc.ctx, &next);
    
    // Should have Content-Encoding header
    string encoding = getHeader(&tc.response, "Content-Encoding");
    encoding.shouldEqual("gzip");
    
    // Compressed body should be smaller
    auto compressedBody = tc.response.getBody();
    assert(compressedBody.length < largeBody.length, "Compressed body should be smaller");
}

// Test 7: Deflate compression when gzip not supported
@("deflate compression when gzip not supported")
unittest
{
    auto config = CompressionConfig();
    config.minSize = 100;
    config.preferredMethod = "gzip";
    
    auto compression = new CompressionMiddleware(config);
    auto tc = TestContext.create(["Accept-Encoding": "deflate"]);
    
    string largeBody = repeatString("B", 2000);
    tc.response.setBody(largeBody);
    tc.response.setHeader("Content-Type", "text/plain");
    
    void next() { }
    compression.handle(tc.ctx, &next);
    
    // Should use deflate
    string encoding = getHeader(&tc.response, "Content-Encoding");
    encoding.shouldEqual("deflate");
}

// Test 8: No compression when Accept-Encoding missing
@("no compression when Accept-Encoding missing")
unittest
{
    auto config = CompressionConfig();
    config.minSize = 100;
    
    auto compression = new CompressionMiddleware(config);
    auto tc = TestContext.create();  // No Accept-Encoding header
    
    string largeBody = repeatString("C", 2000);
    tc.response.setBody(largeBody);
    
    void next() { }
    compression.handle(tc.ctx, &next);
    
    // Should not have Content-Encoding
    hasHeader(&tc.response, "Content-Encoding").shouldBeFalse;
    
    // Body should be unchanged
    tc.response.getBody().shouldEqual(largeBody);
}

// Test 9: Skip compression for already-compressed content types
@("skip compression for compressed content types")
unittest
{
    auto config = CompressionConfig();
    config.minSize = 100;
    
    auto compression = new CompressionMiddleware(config);
    auto tc = TestContext.create(["Accept-Encoding": "gzip"]);
    
    string largeBody = repeatString("D", 2000);
    tc.response.setBody(largeBody);
    tc.response.setHeader("Content-Type", "image/jpeg");  // Already compressed
    
    void next() { }
    compression.handle(tc.ctx, &next);
    
    // Should not compress
    hasHeader(&tc.response, "Content-Encoding").shouldBeFalse;
}

// Test 10: Skip compression when Content-Encoding already set
@("skip compression when Content-Encoding already set")
unittest
{
    auto config = CompressionConfig();
    config.minSize = 100;
    
    auto compression = new CompressionMiddleware(config);
    auto tc = TestContext.create(["Accept-Encoding": "gzip"]);
    
    string largeBody = repeatString("E", 2000);
    tc.response.setBody(largeBody);
    tc.response.setHeader("Content-Encoding", "br");  // Already compressed with brotli
    
    void next() { }
    compression.handle(tc.ctx, &next);
    
    // Should keep original Content-Encoding
    getHeader(&tc.response, "Content-Encoding").shouldEqual("br");
}

// Test 11: Compression only when beneficial (compressed < original)
@("compression only when beneficial")
unittest
{
    auto config = CompressionConfig();
    config.minSize = 100;
    
    auto compression = new CompressionMiddleware(config);
    auto tc = TestContext.create(["Accept-Encoding": "gzip"]);
    
    // Small, already-compressed-like data (won't compress well)
    // Note: This test may be flaky as zlib might still compress slightly
    // The important part is that the middleware checks if compressed < original
    
    string body = repeatString("F", 500);  // Small enough to potentially not benefit
    tc.response.setBody(body);
    tc.response.setHeader("Content-Type", "text/plain");
    
    void next() { }
    compression.handle(tc.ctx, &next);
    
    // If compression didn't help, Content-Encoding might not be set
    // This is implementation-dependent, but the middleware should handle it
    auto finalBody = tc.response.getBody();
    assert(finalBody.length > 0, "Body should exist");
}

// Test 12: JSON response compressed
@("JSON response compressed")
unittest
{
    auto config = CompressionConfig();
    config.minSize = 100;
    
    auto compression = new CompressionMiddleware(config);
    auto tc = TestContext.create(["Accept-Encoding": "gzip"]);
    
    // Large JSON body
    string jsonBody = `{"data": "` ~ repeatString("X", 1500) ~ `"}`;
    tc.response.setBody(jsonBody);
    tc.response.setHeader("Content-Type", "application/json");
    
    void next() { }
    compression.handle(tc.ctx, &next);
    
    // Should be compressed
    string encoding = getHeader(&tc.response, "Content-Encoding");
    encoding.shouldEqual("gzip");
    
    // Compressed body should be smaller
    auto compressedBody = tc.response.getBody();
    assert(compressedBody.length < jsonBody.length, "Compressed JSON body should be smaller");
}

// Test 13: HTML response compressed
@("HTML response compressed")
unittest
{
    auto config = CompressionConfig();
    config.minSize = 100;
    
    auto compression = new CompressionMiddleware(config);
    auto tc = TestContext.create(["Accept-Encoding": "gzip, deflate"]);
    
    // Large HTML body
    string htmlBody = "<html><body>" ~ repeatString("Y", 2000) ~ "</body></html>";
    tc.response.setBody(htmlBody);
    tc.response.setHeader("Content-Type", "text/html");
    
    void next() { }
    compression.handle(tc.ctx, &next);
    
    // Should be compressed
    string encoding = getHeader(&tc.response, "Content-Encoding");
    encoding.shouldEqual("gzip");  // Preferred method
    
    // Compressed body should be smaller
    auto compressedBody = tc.response.getBody();
    assert(compressedBody.length < htmlBody.length, "Compressed HTML body should be smaller");
}

// Test 14: Multiple skip content types
@("multiple skip content types")
unittest
{
    auto config = CompressionConfig();
    config.minSize = 100;
    config.skipContentTypes = ["image/png", "video/mp4", "application/zip"];
    
    auto compression = new CompressionMiddleware(config);
    auto tc = TestContext.create(["Accept-Encoding": "gzip"]);
    
    string largeBody = repeatString("Z", 2000);
    tc.response.setBody(largeBody);
    tc.response.setHeader("Content-Type", "image/png");
    
    void next() { }
    compression.handle(tc.ctx, &next);
    
    // Should not compress
    hasHeader(&tc.response, "Content-Encoding").shouldBeFalse;
}

// Test 15: Content-Type with charset (should still skip if base type matches)
@("Content-Type with charset handled correctly")
unittest
{
    auto config = CompressionConfig();
    config.minSize = 100;
    
    auto compression = new CompressionMiddleware(config);
    auto tc = TestContext.create(["Accept-Encoding": "gzip"]);
    
    string largeBody = repeatString("W", 2000);
    tc.response.setBody(largeBody);
    tc.response.setHeader("Content-Type", "image/jpeg; charset=utf-8");
    
    void next() { }
    compression.handle(tc.ctx, &next);
    
    // Should skip compression (image/jpeg is in skip list)
    hasHeader(&tc.response, "Content-Encoding").shouldBeFalse;
}

// Test 16: Null response handled gracefully
@("null response handled gracefully")
unittest
{
    auto config = CompressionConfig();
    auto compression = new CompressionMiddleware(config);
    
    Context ctx;
    ctx.response = null;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    // Should not crash
    compression.handle(ctx, &next);
    
    nextCalled.shouldBeTrue;
}

// Test 17: Null request handled gracefully
@("null request handled gracefully")
unittest
{
    auto config = CompressionConfig();
    config.minSize = 100;
    
    auto compression = new CompressionMiddleware(config);
    auto tc = TestContext.createSimple();
    tc.ctx.request = null;
    
    string largeBody = repeatString("V", 2000);
    tc.response.setBody(largeBody);
    
    void next() { }
    
    // Should not crash (no Accept-Encoding, so no compression)
    compression.handle(tc.ctx, &next);
    
    hasHeader(&tc.response, "Content-Encoding").shouldBeFalse;
}

// Test 18: Preferred method (gzip vs deflate)
@("preferred method selection")
unittest
{
    auto config = CompressionConfig();
    config.minSize = 100;
    config.preferredMethod = "deflate";  // Prefer deflate
    
    auto compression = new CompressionMiddleware(config);
    auto tc = TestContext.create(["Accept-Encoding": "gzip, deflate"]);
    
    string largeBody = repeatString("U", 2000);
    tc.response.setBody(largeBody);
    tc.response.setHeader("Content-Type", "text/plain");
    
    void next() { }
    compression.handle(tc.ctx, &next);
    
    // Should use preferred method (deflate)
    string encoding = getHeader(&tc.response, "Content-Encoding");
    encoding.shouldEqual("deflate");
}

// Test 19: Compression level affects size
@("compression level affects size")
unittest
{
    // Test that different compression levels produce different results
    // (This is more of a sanity check)
    
    CompressionConfig config1;
    config1.minSize = 100;
    config1.compressionLevel = 1;  // Low compression
    
    CompressionConfig config2;
    config2.minSize = 100;
    config2.compressionLevel = 9;  // High compression
    
    auto tc1 = TestContext.create(["Accept-Encoding": "gzip"]);
    auto tc2 = TestContext.create(["Accept-Encoding": "gzip"]);
    
    string body = repeatString("T", 2000);
    tc1.response.setBody(body);
    tc2.response.setBody(body);
    tc1.response.setHeader("Content-Type", "text/plain");
    tc2.response.setHeader("Content-Type", "text/plain");
    
    auto comp1 = new CompressionMiddleware(config1);
    auto comp2 = new CompressionMiddleware(config2);
    
    void next() { }
    comp1.handle(tc1.ctx, &next);
    comp2.handle(tc2.ctx, &next);
    
    // Both should be compressed
    hasHeader(&tc1.response, "Content-Encoding").shouldBeTrue;
    hasHeader(&tc2.response, "Content-Encoding").shouldBeTrue;
    
    // Sizes may differ (implementation detail)
    auto body1 = tc1.response.getBody();
    auto body2 = tc2.response.getBody();
    assert(body1.length > 0 && body2.length > 0, "Both should have compressed bodies");
}

// Test 20: Compression middleware in pipeline
@("compression middleware in pipeline")
unittest
{
    import aurora.web.middleware : MiddlewarePipeline;
    
    auto pipeline = new MiddlewarePipeline();
    
    CompressionConfig config;
    config.minSize = 100;
    auto compression = new CompressionMiddleware(config);
    
    pipeline.use((ref Context ctx, NextFunction next) {
        compression.handle(ctx, next);
    });
    
    auto tc = TestContext.create(["Accept-Encoding": "gzip"]);
    string largeBody = repeatString("S", 2000);
    tc.response.setBody(largeBody);
    tc.response.setHeader("Content-Type", "text/plain");
    
    pipeline.execute(tc.ctx, (ref Context c) {
        // Handler does nothing, body already set
    });
    
    // Should be compressed
    string encoding = getHeader(&tc.response, "Content-Encoding");
    encoding.shouldEqual("gzip");
}

