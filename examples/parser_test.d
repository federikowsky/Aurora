/**
 * Aurora Parser Test
 * 
 * Tests the HTTP parser (Wire) directly.
 * Useful for debugging parse issues.
 */
module examples.parser_test;

import aurora.http;
import std.stdio;

void main()
{
    writeln("═══ Aurora HTTP Parser Test ═══\n");
    
    // Test 1: Simple GET
    testParse("Simple GET", 
        "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n");
    
    // Test 2: GET with path params
    testParse("GET with path", 
        "GET /users/123/posts HTTP/1.1\r\nHost: localhost\r\n\r\n");
    
    // Test 3: POST with body
    testParse("POST with body",
        "POST /api/data HTTP/1.1\r\n" ~
        "Host: localhost\r\n" ~
        "Content-Type: application/json\r\n" ~
        "Content-Length: 13\r\n" ~
        "\r\n" ~
        `{"key":"val"}`);
    
    // Test 4: Multiple headers
    testParse("Multiple headers",
        "GET /test HTTP/1.1\r\n" ~
        "Host: localhost\r\n" ~
        "Accept: application/json\r\n" ~
        "Authorization: Bearer token123\r\n" ~
        "X-Custom: value\r\n" ~
        "\r\n");
    
    writeln("\n═══ All tests complete ═══");
}

void testParse(string name, string raw)
{
    writefln("─── %s ───", name);
    
    auto req = HTTPRequest.parse(cast(ubyte[])raw);
    
    if (req.method.length > 0)
    {
        writefln("  Method:  %s", req.method);
        writefln("  Path:    %s", req.path);
        writefln("  Version: %s", req.httpVersion);
        
        if (req.body.length > 0)
            writefln("  Body:    %s", req.body);
        
        writeln("  ✓ Parsed OK");
    }
    else
    {
        writeln("  ✗ Parse FAILED");
    }
    writeln();
}
