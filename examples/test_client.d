/**
 * Aurora Test Client
 * 
 * Simple HTTP client for testing Aurora servers.
 * Not a server - sends requests to test endpoints.
 */
module examples.test_client;

import std.socket;
import std.stdio;
import std.string;
import std.conv : to;

void main(string[] args)
{
    string host = "127.0.0.1";
    ushort port = 8080;
    string path = "/";
    string method = "GET";
    
    // Parse args
    foreach (i, arg; args[1..$])
    {
        if (arg.startsWith("--port="))
            port = arg[7..$].to!ushort;
        else if (arg.startsWith("--host="))
            host = arg[7..$];
        else if (arg.startsWith("--path="))
            path = arg[7..$];
        else if (arg.startsWith("--method="))
            method = arg[9..$].toUpper;
    }
    
    writefln("Connecting to %s:%d...", host, port);
    
    try
    {
        auto socket = new TcpSocket();
        socket.connect(new InternetAddress(host, port));
        
        // Send HTTP request
        string request = method ~ " " ~ path ~ " HTTP/1.1\r\n" ~
                        "Host: " ~ host ~ "\r\n" ~
                        "Connection: close\r\n" ~
                        "\r\n";
        
        socket.send(cast(ubyte[])request);
        writefln("Sent %s %s", method, path);
        
        // Read response
        ubyte[4096] buffer;
        string response;
        
        while (true)
        {
            auto received = socket.receive(buffer);
            if (received <= 0) break;
            response ~= cast(string)buffer[0..received];
        }
        
        socket.close();
        
        writeln("\n─── Response ───");
        writeln(response);
        writeln("────────────────");
    }
    catch (Exception e)
    {
        writefln("Error: %s", e.msg);
    }
}
