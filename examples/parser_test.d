/+ dub.sdl:
    name "parser_test"
    dependency "aurora" path=".."
    dependency "wire" path="../../Wire"
+/
/**
 * Minimal test to debug Wire parser issue
 */
module parser_test;

import wire;
import std.stdio;

void main()
{
    writeln("=== Wire Parser Test ===");
    
    // First request
    auto data1 = cast(ubyte[])"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
    writeln("Parsing request 1 (", data1.length, " bytes)...");
    
    {
        auto req1 = parseHTTP(data1);
        writeln("Request 1 parsed:");
        writeln("  Method: ", req1.getMethod().toString());
        writeln("  Path: ", req1.getPath().toString());
        writeln("  Complete: ", req1.request.routing.messageComplete);
        writeln("  Valid: ", cast(bool)req1);
    }
    writeln("Request 1 wrapper destroyed (out of scope)");
    
    // Second request
    auto data2 = cast(ubyte[])"GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
    writeln("\nParsing request 2 (", data2.length, " bytes)...");
    
    {
        auto req2 = parseHTTP(data2);
        writeln("Request 2 parsed:");
        writeln("  Method: ", req2.getMethod().toString());
        writeln("  Path: ", req2.getPath().toString());
        writeln("  Complete: ", req2.request.routing.messageComplete);
        writeln("  Valid: ", cast(bool)req2);
    }
    writeln("Request 2 wrapper destroyed (out of scope)");
    
    // Third request - test struct reset pattern
    writeln("\n=== Testing HTTPRequest pattern ===");
    
    import aurora.http : HTTPRequest;
    
    HTTPRequest req;
    
    writeln("Parsing into req...");
    req = HTTPRequest.parse(data1);
    writeln("  Method: ", req.method());
    writeln("  Path: ", req.path());
    writeln("  Complete: ", req.isComplete());
    
    writeln("Resetting req = HTTPRequest.init...");
    req = HTTPRequest.init;
    
    writeln("Parsing second request into req...");
    req = HTTPRequest.parse(data2);
    writeln("  Method: ", req.method());
    writeln("  Path: ", req.path());
    writeln("  Complete: ", req.isComplete());
    
    writeln("\n=== All tests passed ===");
}
