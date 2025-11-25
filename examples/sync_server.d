/+ dub.sdl:
    name "sync_server"
    dependency "aurora" path=".."
+/
/**
 * Synchronous Aurora Server - No async, just blocking I/O
 * For testing the core HTTP handling without event loop complexity
 */
module sync_server;

import std.socket;
import std.stdio;
import std.string;
import std.conv : to;
import std.array : replicate;
import std.algorithm : canFind;
import core.thread;
import core.time : dur;

void main(string[] args)
{
    ushort port = 8080;
    if (args.length > 1)
        try { port = args[1].to!ushort; } catch (Exception) {}
    
    writeln("╔═══════════════════════════════════╗");
    writeln("║  Aurora Sync Test Server          ║");
    writefln("║  Port: %d                      ║", port);
    writeln("╚═══════════════════════════════════╝");
    
    auto listener = new TcpSocket();
    listener.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
    listener.bind(new InternetAddress("0.0.0.0", port));
    listener.listen(128);
    
    writeln("Listening on port ", port);
    writeln("Press Ctrl+C to stop\n");
    
    uint requestCount = 0;
    
    while (true)
    {
        auto client = listener.accept();
        
        // Handle in new thread for concurrency
        new Thread({
            scope(exit) client.close();
            
            try
            {
                handleClient(client, requestCount);
            }
            catch (Exception e)
            {
                writeln("Error: ", e.msg);
            }
        }).start();
        
        requestCount++;
    }
}

void handleClient(Socket client, uint reqNum)
{
    client.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(30));
    client.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, dur!"seconds"(30));
    
    char[8192] buffer;
    ptrdiff_t received = client.receive(buffer[]);
    
    if (received <= 0) return;
    
    string request = cast(string)buffer[0 .. received];
    
    // Parse simple HTTP
    auto lines = request.split("\r\n");
    if (lines.length == 0) return;
    
    auto requestLine = lines[0].split(" ");
    if (requestLine.length < 2) return;
    
    string method = requestLine[0];
    string path = requestLine[1];
    
    // Check Connection header
    bool keepAlive = true;
    foreach (line; lines[1 .. $])
    {
        if (line.toLower.startsWith("connection:"))
        {
            if (line.toLower.canFind("close"))
                keepAlive = false;
            break;
        }
    }
    
    // Route and build response
    string responseBody;
    int statusCode = 200;
    string contentType = "text/plain";
    string[string] extraHeaders;
    
    if (path == "/")
    {
        responseBody = "Aurora Sync Server - Running!";
    }
    else if (path == "/health")
    {
        contentType = "application/json";
        responseBody = `{"status":"healthy","requests":` ~ reqNum.to!string ~ `}`;
    }
    else if (path.startsWith("/status/"))
    {
        auto codeStr = path[8 .. $];
        try { statusCode = codeStr.to!int; } catch (Exception) { statusCode = 200; }
        contentType = "application/json";
        responseBody = `{"status":` ~ statusCode.to!string ~ `}`;
    }
    else if (path.startsWith("/size/"))
    {
        auto sizeStr = path[6 .. $];
        size_t size = 0;
        try { size = sizeStr.to!size_t; } catch (Exception) {}
        if (size > 1024 * 1024) size = 1024 * 1024;
        contentType = "application/octet-stream";
        responseBody = replicate("X", size);
    }
    else if (path == "/api/v1/users")
    {
        contentType = "application/json";
        responseBody = `[{"id":1,"name":"Alice"},{"id":2,"name":"Bob"}]`;
    }
    else if (path.startsWith("/api/v1/users/"))
    {
        auto id = path[14 .. $];
        contentType = "application/json";
        if (id == "1" || id == "2")
            responseBody = `{"id":` ~ id ~ `,"name":"User` ~ id ~ `"}`;
        else
        {
            statusCode = 404;
            responseBody = `{"error":"Not Found"}`;
        }
    }
    else if (path == "/edge/empty")
    {
        statusCode = 204;
        responseBody = "";
    }
    else if (path == "/edge/unicode")
    {
        contentType = "text/plain; charset=utf-8";
        responseBody = "Unicode: 你好 🌍 مرحبا Привет";
    }
    else if (path == "/edge/huge")
    {
        responseBody = replicate("A", 1024 * 1024);
    }
    else if (path == "/edge/headers-flood")
    {
        foreach (i; 0 .. 50)
            extraHeaders["X-Custom-Header-" ~ i.to!string] = "value" ~ i.to!string;
        responseBody = "Check headers!";
    }
    else if (path == "/nested/a/b/c/d")
    {
        responseBody = "Deeply nested route!";
    }
    else
    {
        statusCode = 404;
        contentType = "application/json";
        responseBody = `{"error":"Not Found","path":"` ~ path ~ `"}`;
    }
    
    // Build HTTP response
    string statusMsg = getStatusMessage(statusCode);
    string response = "HTTP/1.1 " ~ statusCode.to!string ~ " " ~ statusMsg ~ "\r\n";
    response ~= "Content-Type: " ~ contentType ~ "\r\n";
    response ~= "Content-Length: " ~ responseBody.length.to!string ~ "\r\n";
    response ~= "Connection: " ~ (keepAlive ? "keep-alive" : "close") ~ "\r\n";
    response ~= "Access-Control-Allow-Origin: *\r\n";
    response ~= "X-Response-Time: 1us\r\n";
    
    foreach (name, value; extraHeaders)
        response ~= name ~ ": " ~ value ~ "\r\n";
    
    response ~= "\r\n";
    response ~= responseBody;
    
    client.send(cast(ubyte[])response);
}

string getStatusMessage(int code)
{
    switch (code)
    {
        case 200: return "OK";
        case 201: return "Created";
        case 204: return "No Content";
        case 400: return "Bad Request";
        case 404: return "Not Found";
        case 500: return "Internal Server Error";
        default: return "Unknown";
    }
}
