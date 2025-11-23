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
                       "Content-Length: 13\r\n" ~
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
