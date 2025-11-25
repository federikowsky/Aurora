/+ dub.sdl:
    name "async_parser_test"
    dependency "aurora" path=".."
    dependency "wire" path="../../Wire"
    dependency "vibe-core" version="~>2.8.6"
+/
/**
 * Test Wire parser in async context similar to server
 */
module async_parser_test;

import aurora.http : HTTPRequest, HTTPResponse;
import aurora.runtime.connection;
import aurora.runtime.reactor;
import aurora.mem.pool;
import vibe.core.core : runTask, runEventLoop, exitEventLoop;
import std.stdio;
import std.conv : to;

void main()
{
    writeln("=== Async Parser Test ===");
    
    runTask(() nothrow @trusted {
        scope(exit) exitEventLoop();
        
        try {
            // Simulate connection pattern
            HTTPRequest request;
            ubyte[] buffer = new ubyte[4096];
            
            // First request
            auto data1 = "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
            buffer[0 .. data1.length] = cast(ubyte[])data1;
            
            writeln("Parsing first request...");
            request = HTTPRequest.parse(buffer[0 .. data1.length]);
            writeln("  Method: ", request.method());
            writeln("  Path: ", request.path());
            writeln("  Complete: ", request.isComplete());
            writeln("  Keep-alive: ", request.shouldKeepAlive());
            
            // Simulate response processing
            auto response = HTTPResponse(200, "OK");
            response.setBody("Hello");
            writeln("Response: ", response.getStatus(), " ", response.getBody());
            
            // Reset for next request (like resetConnection does)
            writeln("\nResetting request = HTTPRequest.init...");
            request = HTTPRequest.init;
            
            // Second request into SAME buffer (simulating reuse)
            auto data2 = "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n";
            buffer[0 .. data2.length] = cast(ubyte[])data2;
            
            writeln("Parsing second request...");
            request = HTTPRequest.parse(buffer[0 .. data2.length]);
            writeln("  Method: ", request.method());
            writeln("  Path: ", request.path());
            writeln("  Complete: ", request.isComplete());
            
            writeln("\n=== Test passed! ===");
        }
        catch (Exception e) {
            try { writeln("ERROR: ", e.msg); } catch (Exception) {}
        }
    });
    
    runEventLoop();
}
