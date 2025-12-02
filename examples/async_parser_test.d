/**
 * Aurora Async Parser Test
 * 
 * Tests incremental/streaming HTTP parsing.
 * Simulates receiving data in chunks.
 */
module examples.async_parser_test;

import aurora.http;
import std.stdio;
import std.conv : to;

void main()
{
    writeln("═══ Aurora Async Parser Test ═══\n");
    
    // Complete request split into chunks
    string[] chunks = [
        "GET /api/us",
        "ers/123 HTTP/1.1\r\n",
        "Host: local",
        "host\r\n",
        "Accept: applic",
        "ation/json\r\n",
        "\r\n"
    ];
    
    writeln("Simulating chunked receive:");
    
    // Accumulate chunks
    ubyte[] buffer;
    foreach (i, chunk; chunks)
    {
        writefln("  Chunk %d: %d bytes", i+1, chunk.length);
        buffer ~= cast(ubyte[])chunk;
        
        // Try parsing after each chunk
        auto req = HTTPRequest.parse(buffer);
        if (req.method.length > 0)
        {
            writeln("\n✓ Complete request received!");
            writefln("  Method: %s", req.method);
            writefln("  Path:   %s", req.path);
            break;
        }
        else
        {
            writeln("    (incomplete, waiting for more data)");
        }
    }
    
    // Test with body
    writeln("\n─── POST with chunked body ───");
    
    string[] postChunks = [
        "POST /data HTTP/1.1\r\n",
        "Content-Length: 20\r\n",
        "\r\n",
        `{"message":`,
        `"hello"}`,
    ];
    
    buffer.length = 0;
    foreach (i, chunk; postChunks)
    {
        buffer ~= cast(ubyte[])chunk;
        writefln("  After chunk %d: %d total bytes", i+1, buffer.length);
    }
    
    auto postReq = HTTPRequest.parse(buffer);
    if (postReq.method.length > 0)
    {
        writefln("  ✓ Parsed: %s %s", postReq.method, postReq.path);
        writefln("  Body: %s", postReq.body);
    }
    
    writeln("\n═══ Test complete ═══");
}
