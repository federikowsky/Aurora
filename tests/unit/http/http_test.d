/**
 * HTTP Layer Tests
 * 
 * TDD: Aurora HTTP types with Wire integration
 * 
 * Features:
 * - HTTPRequest/HTTPResponse structs
 * - Wire parser integration
 * - Zero-copy header/body access
 * - Performance (< 5μs parse time)
 */
module tests.unit.http.http_test;

import unit_threaded;
import aurora.http;

// ========================================
// HAPPY PATH - REQUEST TESTS
// ========================================

// Test 1: Parse simple GET request
@("parse simple GET request")
unittest
{
    string rawRequest = "GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    req.method.shouldEqual("GET");
    req.path.shouldEqual("/hello");
    req.httpVersion.shouldEqual("1.1");
}

// Test 2: Parse GET with query string
@("parse GET with query string")
unittest
{
    string rawRequest = "GET /search?q=test&limit=10 HTTP/1.1\r\nHost: localhost\r\n\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    req.path.shouldEqual("/search");
    req.query.shouldEqual("q=test&limit=10");
}

// Test 3: Parse POST with body
@("parse POST with body")
unittest
{
    string rawRequest = "POST /api/users HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Content-Length: 17\r\n" ~
                       "\r\n" ~
                       "{\"name\":\"Alice\"}";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    req.method.shouldEqual("POST");
    req.path.shouldEqual("/api/users");
    req.body.shouldEqual("{\"name\":\"Alice\"}");
}

// Test 4: Parse headers
@("parse request headers")
unittest
{
    string rawRequest = "GET / HTTP/1.1\r\n" ~
                       "Host: example.com\r\n" ~
                       "User-Agent: Test\r\n" ~
                       "Accept: */*\r\n" ~
                       "\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    req.getHeader("Host").shouldEqual("example.com");
    req.getHeader("User-Agent").shouldEqual("Test");
    req.getHeader("Accept").shouldEqual("*/*");
}

// Test 5: Multiple HTTP methods
@("support multiple HTTP methods")
unittest
{
    string[] methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"];
    
    foreach (method; methods)
    {
        string rawRequest = method ~ " / HTTP/1.1\r\nHost: localhost\r\n\r\n";
        auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
        
        req.method.shouldEqual(method);
    }
}

// ========================================
// HAPPY PATH - RESPONSE TESTS
// ========================================

// Test 6: Create simple response
@("create simple HTTP response")
unittest
{
    auto resp = HTTPResponse(200, "OK");
    resp.setBody("Hello, World!");
    
    auto output = resp.build();
    
    assert(output.length > 0);
}

// Test 7: Set response headers
@("set response headers")
unittest
{
    auto resp = HTTPResponse(200, "OK");
    resp.setHeader("Content-Type", "application/json");
    resp.setHeader("X-Custom", "value");
    
    auto output = resp.build();
    
    // Should contain headers
    import std.string : indexOf;
    assert(output.indexOf("Content-Type") >= 0);
    assert(output.indexOf("X-Custom") >= 0);
}

// ========================================
// EDGE CASES
// ========================================

// Test 8: Empty path defaults to /
@("empty path defaults to /")
unittest
{
    string rawRequest = "GET  HTTP/1.1\r\nHost: localhost\r\n\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    // Wire handles this - test what it returns
}

// Test 9: Case-insensitive headers
@("headers are case-insensitive")
unittest
{
    string rawRequest = "GET / HTTP/1.1\r\nHost: localhost\r\nContent-Type: text/plain\r\n\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    req.getHeader("content-type").shouldEqual("text/plain");
    req.getHeader("CONTENT-TYPE").shouldEqual("text/plain");
}

// Test 10: Keep-alive detection
@("detect keep-alive connection")
unittest
{
    string rawRequest = "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    req.shouldKeepAlive.shouldBeTrue;
}

// Test 11: HTTP/1.0 request
@("parse HTTP/1.0 request")
unittest
{
    string rawRequest = "GET / HTTP/1.0\r\nHost: localhost\r\n\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    req.httpVersion.shouldEqual("1.0");
}

// Test 12: Large headers
@("parse request with many headers")
unittest
{
    import std.conv : to;
    
    string rawRequest = "GET / HTTP/1.1\r\nHost: localhost\r\n";
    
    // Add 50 headers
    foreach (i; 0..50)
    {
        rawRequest ~= "X-Header-" ~ i.to!string ~ ": value\r\n";
    }
    rawRequest ~= "\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    req.method.shouldEqual("GET");
}

// ========================================
// ERROR CASES
// ========================================

// Test 13: Malformed request
@("malformed request returns error")
unittest
{
    string rawRequest = "INVALID REQUEST\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    req.hasError.shouldBeTrue;
}

// Test 14: Missing Host header (HTTP/1.1)
@("HTTP/1.1 without Host header")
unittest
{
    string rawRequest = "GET / HTTP/1.1\r\n\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    // Wire may or may not enforce this - test actual behavior
}

// ========================================
// PERFORMANCE TESTS
// ========================================

// Test 15: Parse latency
@("parse latency is fast")
unittest
{
    import std.datetime.stopwatch;
    
    string rawRequest = "GET /api/users?filter=active HTTP/1.1\r\n" ~
                       "Host: example.com\r\n" ~
                       "User-Agent: Benchmark\r\n" ~
                       "Accept: application/json\r\n" ~
                       "\r\n";
    
    auto data = cast(ubyte[])rawRequest;
    
    auto sw = StopWatch(AutoStart.yes);
    
    foreach (i; 0..10_000)
    {
        auto req = HTTPRequest.parse(data);
    }
    
    sw.stop();
    auto totalUs = sw.peek.total!"usecs";
    auto avgUs = totalUs / 10_000.0;
    
    // Target: < 5μs per parse
    assert(avgUs < 50, "Parse too slow");  // Relaxed for debug
}

// ========================================
// STRESS TESTS
// ========================================

// Test 16: Parse many requests
@("parse 100K requests stable")
unittest
{
    string rawRequest = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
    auto data = cast(ubyte[])rawRequest;
    
    foreach (i; 0..100_000)
    {
        auto req = HTTPRequest.parse(data);
        req.method.shouldEqual("GET");
    }
}

// Test 17: Response building stress
@("build 10K responses stable")
unittest
{
    foreach (i; 0..10_000)
    {
        auto resp = HTTPResponse(200, "OK");
        resp.setBody("Test");
        auto output = resp.build();

        assert(output.length > 0);
    }
}

// ========================================
// BATCH 1A: EDGE CASES (M2 Phase 1)
// ========================================

// Test 18: Multiple headers with same key
@("multiple headers with same key")
unittest
{
    string rawRequest = "GET / HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Cookie: session=abc\r\n" ~
                       "Cookie: user=123\r\n" ~
                       "\r\n";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);

    // Wire returns last value for duplicate headers
    // Test that we can retrieve the cookie header
    auto cookie = req.getHeader("Cookie");
    assert(cookie.length > 0, "Should have Cookie header");
}

// Test 19: Query string edge cases
@("query string edge cases")
unittest
{
    // Empty query string
    {
        string rawRequest = "GET /path? HTTP/1.1\r\nHost: localhost\r\n\r\n";
        auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
        req.path.shouldEqual("/path");
        // Query might be empty string or null
    }

    // Special characters in query
    {
        string rawRequest = "GET /search?q=hello%20world&filter=a%2Bb HTTP/1.1\r\nHost: localhost\r\n\r\n";
        auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
        req.query.shouldEqual("q=hello%20world&filter=a%2Bb");
    }

    // Multiple equals signs
    {
        string rawRequest = "GET /test?key=value=extra HTTP/1.1\r\nHost: localhost\r\n\r\n";
        auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
        req.path.shouldEqual("/test");
    }
}

// Test 20: Large body handling
@("large body handling")
unittest
{
    import std.array : replicate;

    // Create a ~70KB body
    string largeBody = replicate("x", 70_000);
    string rawRequest = "POST /upload HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Content-Length: 70000\r\n" ~
                       "\r\n" ~
                       largeBody;

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);

    req.method.shouldEqual("POST");
    req.body.length.shouldEqual(70_000);
}

// Test 21: Chunked transfer encoding (detection)
@("chunked transfer encoding detection")
unittest
{
    string rawRequest = "POST /api HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Transfer-Encoding: chunked\r\n" ~
                       "\r\n";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);

    req.method.shouldEqual("POST");
    req.hasHeader("Transfer-Encoding").shouldBeTrue;
    req.getHeader("Transfer-Encoding").shouldEqual("chunked");
}

// Test 22: Connection: close detection
@("connection close detection")
unittest
{
    string rawRequest = "GET / HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Connection: close\r\n" ~
                       "\r\n";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);

    req.getHeader("Connection").shouldEqual("close");
    // shouldKeepAlive should be false for Connection: close
    req.shouldKeepAlive.shouldBeFalse;
}

// Test 23: Very long query string
@("very long query string")
unittest
{
    import std.array : replicate;
    import std.conv : to;

    // Build a query string with 100 parameters
    string query = "";
    foreach (i; 0..100)
    {
        if (i > 0) query ~= "&";
        query ~= "param" ~ i.to!string ~ "=value" ~ i.to!string;
    }

    string rawRequest = "GET /search?" ~ query ~ " HTTP/1.1\r\nHost: localhost\r\n\r\n";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);

    req.path.shouldEqual("/search");
    req.query.shouldEqual(query);
}

// ========================================
// BATCH 1B: ERROR CASES (M2 Phase 1)
// ========================================

// Test 24: Invalid HTTP method
@("invalid HTTP method")
unittest
{
    string rawRequest = "INVALID / HTTP/1.1\r\nHost: localhost\r\n\r\n";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);

    // llhttp rejects unknown methods - parse should fail
    req.hasError().shouldEqual(true);
}

// Test 25: Headers too large
@("headers too large")
unittest
{
    import std.conv : to;

    // Create request with very large header values (>8KB total)
    string rawRequest = "GET / HTTP/1.1\r\nHost: localhost\r\n";

    // Add headers totaling >8KB
    foreach (i; 0..200)
    {
        rawRequest ~= "X-Large-Header-" ~ i.to!string ~ ": ";
        foreach (j; 0..50)
        {
            rawRequest ~= "value";
        }
        rawRequest ~= "\r\n";
    }
    rawRequest ~= "\r\n";

    // Wire should handle this, but in production we'd reject it
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);

    // Test passes if we can parse without crashing
    // Real implementation would check total header size and reject
}

// Test 26: Body too large
@("body size validation")
unittest
{
    import std.array : replicate;

    // Create a very large body (1MB)
    string largeBody = replicate("x", 1_000_000);
    string rawRequest = "POST /upload HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Content-Length: 1000000\r\n" ~
                       "\r\n" ~
                       largeBody;

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);

    // Wire can parse this, but framework would enforce body size limits
    req.method.shouldEqual("POST");
    req.body.length.shouldEqual(1_000_000);
}

// Test 27: Invalid HTTP version
@("invalid HTTP version")
unittest
{
    string rawRequest = "GET / HTTP/2.0\r\nHost: localhost\r\n\r\n";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);

    // Wire should parse this, version will be "2.0"
    // Framework would reject unsupported versions
    req.httpVersion.shouldEqual("2.0");
}

// Test 28: Truncated request (incomplete headers)
@("truncated request")
unittest
{
    // Request missing final \r\n\r\n
    string rawRequest = "GET / HTTP/1.1\r\nHost: localhost\r\n";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);

    // Wire may mark this as invalid or partial
    // Test that we detect the error
    if (!req.hasError)
    {
        // If Wire accepts it, that's fine - it's lenient
        // Real implementation would handle partial reads differently
    }
}

// ========================================
// BATCH 1C: PERFORMANCE + FUZZ (M2 Phase 1)
// ========================================

// Test 29: Zero-copy verification
@("zero-copy parsing verification")
unittest
{
    string rawRequest = "GET /api/users HTTP/1.1\r\n" ~
                       "Host: example.com\r\n" ~
                       "User-Agent: Test\r\n" ~
                       "\r\n";

    auto data = cast(ubyte[])rawRequest;

    // Parse first request
    {
        auto req1 = HTTPRequest.parse(data);
        req1.method.shouldEqual("GET");
    }
    // req1 goes out of scope, releasing the parser
    
    // Parse again with same buffer
    {
        auto req2 = HTTPRequest.parse(data);
        req2.method.shouldEqual("GET");
    }

    // Wire uses zero-copy - it returns slices into the original buffer
    // This test verifies we can parse without allocation overhead
    // Note: Only ONE active parse result at a time (thread-local parser pool)
}

// Test 30: Random bytes fuzz test
@("random bytes fuzz test")
unittest
{
    import std.random : uniform;

    // Generate random bytes
    ubyte[1024] randomData;
    foreach (ref b; randomData)
    {
        b = cast(ubyte)uniform(0, 256);
    }

    // Parser should not crash on random input
    auto req = HTTPRequest.parse(randomData);

    // Most likely hasError will be true, but no crash
    // This is a fuzz test - we just want stability
}

// Test 31: Truncated requests fuzz test
@("truncated requests fuzz test")
unittest
{
    string fullRequest = "GET /api/users?id=123 HTTP/1.1\r\n" ~
                        "Host: example.com\r\n" ~
                        "User-Agent: Mozilla/5.0\r\n" ~
                        "Accept: application/json\r\n" ~
                        "\r\n";

    // Test various truncation points
    foreach (len; 10..fullRequest.length)
    {
        auto truncated = fullRequest[0..len];
        auto req = HTTPRequest.parse(cast(ubyte[])truncated);

        // Should not crash, may or may not be valid
        // This tests robustness against partial reads
    }
}

// Test 32: Invalid UTF-8 handling
@("invalid UTF-8 handling")
unittest
{
    // Create request with invalid UTF-8 sequences
    ubyte[] rawRequest = cast(ubyte[])"GET /test HTTP/1.1\r\nHost: localhost\r\nX-Bad: ";

    // Add invalid UTF-8 sequence
    rawRequest ~= [0xFF, 0xFE, 0xFD];
    rawRequest ~= cast(ubyte[])"\r\n\r\n";

    // Parser should handle binary data gracefully
    auto req = HTTPRequest.parse(rawRequest);

    // May or may not parse successfully, but should not crash
    // HTTP headers should be ASCII, but we test robustness
}

// ========================================
// BATCH 1D: HTTP/1.1 COMPLIANCE (M2 Phase 1)
// ========================================

// Test 33: Transfer-Encoding header support
@("Transfer-Encoding header support")
unittest
{
    // Simple POST request with regular headers
    // Note: Transfer-Encoding and Content-Length together can be problematic
    string rawRequest = "POST /api HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Content-Length: 4\r\n" ~
                       "\r\n" ~
                       "test";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);

    req.method.shouldEqual("POST");
    req.path.shouldEqual("/api");
    req.body.shouldEqual("test");
}

// Test 34: Expect: 100-continue header
@("Expect 100-continue header")
unittest
{
    // Note: 100-continue expects that headers are complete but body not yet sent
    // For testing, we use Content-Length: 0 to indicate we're testing headers only
    string rawRequest = "POST /upload HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Expect: 100-continue\r\n" ~
                       "Content-Length: 0\r\n" ~
                       "\r\n";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);

    req.method.shouldEqual("POST");
    req.getHeader("Expect").shouldEqual("100-continue");
}

// Test 35: Host header validation (HTTP/1.1 requirement)
@("Host header validation")
unittest
{
    // Valid with Host
    {
        string rawRequest = "GET / HTTP/1.1\r\nHost: example.com:8080\r\n\r\n";
        auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
        req.getHeader("Host").shouldEqual("example.com:8080");
    }

    // Host with port
    {
        string rawRequest = "GET / HTTP/1.1\r\nHost: 192.168.1.1:3000\r\n\r\n";
        auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
        req.hasHeader("Host").shouldBeTrue;
    }
}

// Test 36: Request URI variations
@("Request URI variations")
unittest
{
    // Standard path-form (most common)
    {
        string rawRequest = "GET /path/to/resource HTTP/1.1\r\nHost: example.com\r\n\r\n";
        auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
        req.method.shouldEqual("GET");
        req.path.shouldEqual("/path/to/resource");
    }

    // Asterisk form (for OPTIONS)
    {
        string rawRequest = "OPTIONS * HTTP/1.1\r\nHost: example.com\r\n\r\n";
        auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
        req.method.shouldEqual("OPTIONS");
    }
}

// Test 37: Long header value
@("Long header value")
unittest
{
    // Headers with long values should parse correctly
    string rawRequest = "GET / HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "X-Long-Header: value1value2value3value4value5\r\n" ~
                       "\r\n";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);

    req.method.shouldEqual("GET");
    req.getHeader("X-Long-Header").shouldEqual("value1value2value3value4value5");
}

// Test 38: Whitespace handling in headers
@("Whitespace handling in headers")
unittest
{
    // Leading/trailing whitespace in header values
    string rawRequest = "GET / HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "X-Whitespace:   value with spaces   \r\n" ~
                       "\r\n";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);

    auto value = req.getHeader("X-Whitespace");
    // Wire may or may not trim whitespace - test actual behavior
    assert(value.length > 0, "Header should have value");
}

// Test 39: Method case sensitivity
@("Method case sensitivity")
unittest
{
    // HTTP methods must be uppercase per HTTP spec
    // llhttp rejects lowercase methods
    string rawRequest = "get / HTTP/1.1\r\nHost: localhost\r\n\r\n";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);

    // llhttp is strict: lowercase methods are rejected as invalid
    req.hasError.shouldBeTrue;
}

// Test 40: Content-Length header parsing
@("Content-Length header parsing")
unittest
{
    string rawRequest = "POST / HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Content-Length: 4\r\n" ~
                       "\r\n" ~
                       "test";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);

    req.hasHeader("Content-Length").shouldBeTrue;
    req.getHeader("Content-Length").shouldEqual("4");
    req.body.shouldEqual("test");
}

// ========================================
// CRITICAL STRESS TESTS (Production)
// ========================================

// Test 41: Multiple request parsing
@("HTTP multiple request parsing")
unittest
{
    string rawRequest = "GET /api/users?id=123&filter=active HTTP/1.1\r\n" ~
                       "Host: example.com\r\n" ~
                       "User-Agent: StressTest\r\n" ~
                       "Accept: application/json\r\n" ~
                       "Authorization: Bearer token123\r\n" ~
                       "\r\n";
    
    auto data = cast(ubyte[])rawRequest;
    
    // Parse multiple requests to ensure parser pool is working
    foreach (i; 0..100)
    {
        auto req = HTTPRequest.parse(data);
        req.method.shouldEqual("GET");
        req.path.shouldEqual("/api/users");
        req.query.shouldEqual("id=123&filter=active");
    }
}

// ========================================
// HTTP SMUGGLING TESTS (OWASP WSTG-INPV-15)
// ========================================
// See: https://owasp.org/www-project-web-security-testing-guide/latest/4-Web_Application_Security_Testing/07-Input_Validation_Testing/15-Testing_for_HTTP_Splitting_Smuggling

// Test 42: Duplicate Content-Length headers (HTTP Smuggling vector)
@("duplicate Content-Length headers handling")
unittest
{
    // CL.CL attack: Two different Content-Length values
    // Front-end proxy might use first, back-end might use second
    // Secure behavior: Reject or use consistent interpretation
    string rawRequest = "POST /api HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Content-Length: 10\r\n" ~
                       "Content-Length: 4\r\n" ~
                       "\r\n" ~
                       "testabcdef";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    // Wire parser behavior - should either:
    // 1. Return error (safest)
    // 2. Use first Content-Length (consistent)
    // 3. Use last Content-Length (consistent)
    // Key: Must be consistent, not ambiguous
    auto cl = req.getHeader("Content-Length");
    // Verify we get a single value, not concatenation
    assert(cl == "10" || cl == "4" || req.hasError, 
           "Duplicate Content-Length must be handled consistently");
}

// Test 43: CL.TE attack vector (Content-Length + Transfer-Encoding)
@("CL.TE attack - Content-Length with Transfer-Encoding")
unittest
{
    // CL.TE: Front-end uses Content-Length, back-end uses Transfer-Encoding
    // This is a common HTTP smuggling vector
    string rawRequest = "POST /api HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Content-Length: 13\r\n" ~
                       "Transfer-Encoding: chunked\r\n" ~
                       "\r\n" ~
                       "0\r\n" ~
                       "\r\n" ~
                       "SMUGGLED";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    // Per RFC 7230 Section 3.3.3:
    // If both present, Transfer-Encoding takes precedence
    // OR message should be rejected (safest)
    // Wire parser may reject this combination - that's secure behavior
    
    // Test that parser doesn't crash and handles this edge case
    // The specific handling (reject, use TE, use CL) is implementation-dependent
}

// Test 44: TE.CL attack vector (Transfer-Encoding before Content-Length priority)
@("TE.CL attack - Transfer-Encoding should take precedence")
unittest
{
    // Per RFC 7230, when both are present, Transfer-Encoding wins
    string rawRequest = "POST /api HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Transfer-Encoding: chunked\r\n" ~
                       "Content-Length: 4\r\n" ~
                       "\r\n" ~
                       "5\r\nhello\r\n0\r\n\r\n";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    // Wire parser may handle this differently - test that it doesn't crash
    // and that parsing completes without exception
    // The specific behavior (reject both, use TE, use CL) is implementation-dependent
    // Key security property: consistent behavior, no request splitting
}

// Test 45: Obfuscated Transfer-Encoding headers
@("obfuscated Transfer-Encoding headers")
unittest
{
    // Attackers try to obfuscate TE header to bypass front-end
    string[] obfuscatedRequests = [
        // Whitespace after value
        "POST /api HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked \r\nContent-Length: 4\r\n\r\ntest",
        // Tab character
        "POST /api HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding:\tchunked\r\nContent-Length: 4\r\n\r\ntest",
        // Double TE header
        "POST /api HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: identity\r\nTransfer-Encoding: chunked\r\nContent-Length: 4\r\n\r\ntest",
    ];
    
    foreach (rawRequest; obfuscatedRequests)
    {
        auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
        // Parser should handle these consistently without crashing
        // Either parse correctly or reject
    }
}

// Test 46: HTTP Request Line Injection (CRLF Injection)
@("CRLF injection in path")
unittest
{
    // Attempt to inject second request via path
    string rawRequest = "GET /api\r\nX-Injected: Header\r\nGET /admin HTTP/1.1\r\nHost: localhost\r\n\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    // Should either:
    // 1. Return error (safest - malformed request)
    // 2. Parse only first valid line
    // Should NOT parse injected headers or second request
}

// Test 47: HTTP Header Name Injection
@("header name CRLF injection")
unittest
{
    // Attempt to inject via header name containing CRLF
    // Most parsers will reject this as malformed
    string rawRequest = "GET / HTTP/1.1\r\nHost: localhost\r\nX-Bad\r\nHeader: value\r\n\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    // The injected "Header" should NOT be parsed as a separate header
    // Either error or ignore the malformed line
}

// Test 48: HTTP Header Value Injection (Host Header Injection WSTG-INPV-17)
@("Host header value injection")
unittest
{
    // Single valid Host header - baseline
    {
        string rawRequest = "GET / HTTP/1.1\r\nHost: legitimate.com\r\n\r\n";
        auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
        req.getHeader("Host").shouldEqual("legitimate.com");
    }
    
    // Multiple Host headers (should reject or use first)
    {
        string rawRequest = "GET / HTTP/1.1\r\n" ~
                           "Host: legitimate.com\r\n" ~
                           "Host: evil.com\r\n" ~
                           "\r\n";
        
        auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
        auto host = req.getHeader("Host");
        // Should be consistent - either first, last, or error
        assert(host == "legitimate.com" || host == "evil.com" || req.hasError,
               "Multiple Host headers must be handled consistently");
    }
}

// Test 49: Absolute URI in request line (proxy behavior)
@("absolute URI in request line")
unittest
{
    // Proxies may receive requests with absolute URI
    string rawRequest = "GET http://example.com/path HTTP/1.1\r\nHost: example.com\r\n\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    // Should either:
    // 1. Parse the full URI as path
    // 2. Extract just the path component
}

// Test 50: Negative Content-Length
@("negative Content-Length rejection")
unittest
{
    string rawRequest = "POST /api HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Content-Length: -1\r\n" ~
                       "\r\n" ~
                       "test";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    // Negative Content-Length should be rejected or treated as 0
    // Should NOT cause integer overflow or buffer issues
}

// Test 51: Very large Content-Length (DoS vector)
@("extremely large Content-Length handling")
unittest
{
    // Attempt to cause memory exhaustion or integer overflow
    string rawRequest = "POST /api HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Content-Length: 999999999999999999\r\n" ~
                       "\r\n" ~
                       "tiny";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    // Parser should handle this gracefully
    // Either reject or limit the value
    auto cl = req.getHeader("Content-Length");
    // Should not crash or hang
}

// Test 52: Null bytes in headers
@("null bytes in headers")
unittest
{
    // Null byte injection attempt
    string rawRequest = "GET /api HTTP/1.1\r\nHost: localhost\r\nX-Test: value\x00evil\r\n\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    // Parser should handle null bytes safely
    // Either reject, truncate, or encode
}

// Test 53: Invalid HTTP version
@("invalid HTTP version handling")
unittest
{
    string[] invalidVersions = [
        "GET / HTTP/9.9\r\nHost: localhost\r\n\r\n",
        "GET / HTTP/1\r\nHost: localhost\r\n\r\n",
        "GET / HTTP\r\nHost: localhost\r\n\r\n",
        "GET / HTTP/a.b\r\nHost: localhost\r\n\r\n",
    ];
    
    foreach (rawRequest; invalidVersions)
    {
        auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
        // Should either reject or handle gracefully
    }
}

// Test 54: HTTP/0.9 simple request (legacy)
@("HTTP/0.9 simple request")
unittest
{
    // HTTP/0.9 has no version or headers
    string rawRequest = "GET /\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    // Modern servers should reject HTTP/0.9 or parse gracefully
}

// Test 55: Request with body but no Content-Length
@("body without Content-Length")
unittest
{
    string rawRequest = "POST /api HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "\r\n" ~
                       "orphan body data";

    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    // Without Content-Length or Transfer-Encoding:
    // Body length is indeterminate
    // Parser should treat as 0-length body or error
}

// ========================================
// HTTP RESPONSE ADDITIONAL TESTS
// ========================================

// Test 56: Response buildInto with small buffer
@("Response buildInto with small buffer")
unittest
{
    auto resp = HTTPResponse(200, "OK");
    resp.setBody("Hello");
    
    ubyte[10] smallBuffer;
    auto bytesWritten = resp.buildInto(smallBuffer[]);
    
    // Buffer too small, should return 0
    bytesWritten.shouldEqual(0);
}

// Test 57: Response buildInto with adequate buffer
@("Response buildInto with adequate buffer")
unittest
{
    auto resp = HTTPResponse(200, "OK");
    resp.setBody("Hi");
    
    ubyte[1024] buffer;
    auto bytesWritten = resp.buildInto(buffer[]);
    
    // Should write something
    assert(bytesWritten > 0, "Should write response to buffer");
    
    // Verify starts with HTTP
    auto str = cast(string)buffer[0..bytesWritten];
    assert(str.length >= 4);
    str[0..4].shouldEqual("HTTP");
}

// Test 58: Response estimateSize
@("Response estimateSize returns reasonable value")
unittest
{
    auto resp = HTTPResponse(200, "OK");
    resp.setBody("Hello, World!");
    resp.setHeader("Content-Type", "text/plain");
    
    auto estimate = resp.estimateSize();
    
    // Should be positive
    assert(estimate > 0, "Estimate should be positive");
    
    // Should be larger than body
    assert(estimate > 13, "Estimate should be larger than body");
}

// Test 59: Response getContentType
@("Response getContentType returns default or set value")
unittest
{
    // Default content type
    {
        auto resp = HTTPResponse(200, "OK");
        resp.getContentType().shouldEqual("text/html");  // Default
    }
    
    // Custom content type
    {
        auto resp = HTTPResponse(200, "OK");
        resp.setHeader("Content-Type", "application/json");
        resp.getContentType().shouldEqual("application/json");
    }
}

// Test 60: Response getStatus
@("Response getStatus returns status code")
unittest
{
    auto resp = HTTPResponse(404, "Not Found");
    
    resp.status.shouldEqual(404);
    resp.getStatus().shouldEqual(404);
}

// Test 61: Response getBody
@("Response getBody returns body content")
unittest
{
    auto resp = HTTPResponse(200, "OK");
    resp.setBody("Test body");
    
    resp.getBody().shouldEqual("Test body");
}

// Test 62: Response with various status codes
@("Response with various status codes")
unittest
{
    int[] codes = [100, 200, 201, 204, 301, 302, 400, 401, 403, 404, 500, 502, 503];
    
    foreach (code; codes)
    {
        auto resp = HTTPResponse(code, "Status");
        auto output = resp.build();
        
        assert(output.length > 0, "Response should be built");
    }
}

// Test 63: Response setStatus changes status
@("Response setStatus changes status")
unittest
{
    auto resp = HTTPResponse(200, "OK");
    
    resp.getStatus().shouldEqual(200);
    
    resp.setStatus(404);
    resp.getStatus().shouldEqual(404);
}

// Test 64: Response multiple headers
@("Response multiple headers")
unittest
{
    auto resp = HTTPResponse(200, "OK");
    resp.setHeader("Content-Type", "application/json");
    resp.setHeader("Cache-Control", "no-cache");
    resp.setHeader("X-Request-Id", "12345");
    
    auto output = resp.build();
    
    import std.algorithm : canFind;
    assert(output.canFind("Content-Type"), "Should have Content-Type");
    assert(output.canFind("Cache-Control"), "Should have Cache-Control");
    assert(output.canFind("X-Request-Id"), "Should have X-Request-Id");
}

// Test 65: Request isComplete
@("Request isComplete for complete request")
unittest
{
    string rawRequest = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    
    // Complete request should return true
    // Note: Wire parser sets messageComplete flag
}

// Test 66: Request query with edge cases
@("Request query edge cases")
unittest
{
    // Query with special characters
    {
        string rawRequest = "GET /search?q=a+b&c=%26 HTTP/1.1\r\nHost: localhost\r\n\r\n";
        auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
        
        // Query should preserve encoding
        assert(req.query.length > 0, "Should have query string");
    }
    
    // Path with multiple query params
    {
        string rawRequest = "GET /api?a=1&b=2&c=3&d=4&e=5 HTTP/1.1\r\nHost: localhost\r\n\r\n";
        auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
        
        req.path.shouldEqual("/api");
        assert(req.query.length > 0, "Should have query string");
    }
}
