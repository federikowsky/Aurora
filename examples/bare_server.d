/+ dub.sdl:
    name "bare_server"
    dependency "aurora" path=".."
    dependency "vibe-core" version="~>2.8.6"
    dependency "eventcore" version="~>0.9.0"
+/
/**
 * Bare minimum server to isolate crash
 */
module bare_server;

import vibe.core.core : runEventLoop, runTask, yield;
import eventcore.core : eventDriver;
import eventcore.driver;
import std.stdio;
import std.conv : to;
import core.atomic;

shared int requestCount = 0;

void main()
{
    writeln("Starting bare server on port 8080...");
    
    auto driver = eventDriver;
    
    import std.socket : InternetAddress;
    auto addr = new InternetAddress("0.0.0.0", 8080);
    
    auto listenResult = driver.sockets.listenStream(
        addr,
        (StreamListenSocketFD listenSock, StreamSocketFD clientSock, scope RefAddress remoteAddr) @safe nothrow {
            (() @trusted nothrow {
                try {
                    runTask(() nothrow {
                        try { handleClient(clientSock); } catch (Exception) {}
                    });
                } catch (Exception) {}
            })();
        }
    );
    
    if (listenResult == StreamListenSocketFD.invalid)
    {
        writeln("ERROR: Failed to listen");
        return;
    }
    
    writeln("Listening...");
    runEventLoop();
}

void handleClient(StreamSocketFD sock) @trusted
{
    auto driver = eventDriver;
    scope(exit) {
        writeln("  Releasing socket");
        driver.sockets.releaseRef(sock);
    }
    
    int reqNum = atomicOp!"+="(requestCount, 1);
    writeln("Connection ", reqNum, " accepted");
    
    // Read request
    ubyte[4096] buffer;
    size_t totalRead = 0;
    
    while (totalRead < buffer.length)
    {
        IOStatus status;
        size_t bytesRead;
        
        driver.sockets.read(sock, buffer[totalRead .. $], IOMode.immediate,
            (s, st, bytes) @safe nothrow {
                status = st;
                bytesRead = cast(size_t)bytes;
            });
        
        writeln("  Read: status=", cast(int)status, ", bytes=", bytesRead);
        
        if (bytesRead > 0)
        {
            totalRead += bytesRead;
            
            // Check if we have a complete HTTP request
            import std.string : indexOf;
            auto data = cast(string)buffer[0 .. totalRead];
            if (data.indexOf("\r\n\r\n") >= 0 || data.indexOf("\n\n") >= 0)
            {
                writeln("  Complete request received (", totalRead, " bytes)");
                break;
            }
        }
        else if (status == IOStatus.wouldBlock)
        {
            yield();
        }
        else
        {
            writeln("  Read error/disconnect");
            return;
        }
    }
    
    // Write response
    string response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK";
    
    size_t written = 0;
    while (written < response.length)
    {
        IOStatus status;
        size_t bytesWritten;
        
        driver.sockets.write(sock, cast(ubyte[])response[written .. $], IOMode.immediate,
            (s, st, bytes) @safe nothrow {
                status = st;
                bytesWritten = cast(size_t)bytes;
            });
        
        writeln("  Write: status=", cast(int)status, ", bytes=", bytesWritten);
        
        if (bytesWritten > 0)
        {
            written += bytesWritten;
        }
        else if (status == IOStatus.wouldBlock)
        {
            yield();
        }
        else
        {
            writeln("  Write error");
            return;
        }
    }
    
    writeln("  Response sent");
}
