/+ dub.sdl:
    name "micro_server"
    dependency "aurora" path=".."
    dependency "vibe-core" version="~>2.8.6"
    dependency "eventcore" version="~>0.9.0"
+/
/**
 * Micro debug server - most minimal possible with network
 */
module micro_server;

import vibe.core.core : runEventLoop, runTask, yield;
import eventcore.core;
import eventcore.driver;
import std.stdio;
import std.conv : to;
import core.stdc.stdio : printf;

// Import Wire directly for more control
import wire;

void log(string msg) @trusted nothrow
{
    try { 
        import std.datetime.systime : Clock;
        auto now = Clock.currTime;
        stderr.writefln("[%02d:%02d:%02d] %s", now.hour, now.minute, now.second, msg);
        stderr.flush();
    } catch (Exception) {}
}

void main()
{
    ushort port = 8080;
    log("Starting micro server on port " ~ port.to!string);
    
    auto driver = eventDriver;
    
    import std.socket : InternetAddress;
    auto addr = new InternetAddress("0.0.0.0", port);
    
    auto listenResult = driver.sockets.listenStream(
        addr,
        (StreamListenSocketFD listenSock, StreamSocketFD clientSock, scope RefAddress remoteAddr) @safe nothrow {
            log("New connection accepted, socket=" ~ (cast(int)clientSock).to!string);
            
            (() @trusted {
                runTask(() nothrow @trusted {
                    handleClient(clientSock, driver);
                });
            })();
        }
    );
    
    if (listenResult == StreamListenSocketFD.invalid) {
        log("Failed to listen!");
        return;
    }
    
    log("Server listening, entering event loop...");
    runEventLoop();
}

void handleClient(StreamSocketFD sock, EventDriver driver) @trusted nothrow
{
    ubyte[4096] buffer;
    int requestNum = 0;
    
    scope(exit) {
        log("Closing connection");
        driver.sockets.shutdown(sock, true, true);
    }
    
    while (true) {
        requestNum++;
        log("=== Request #" ~ requestNum.to!string ~ " ===");
        
        // Read data
        size_t totalRead = 0;
        while (true) {
            log("Calling read...");
            
            IOStatus status;
            size_t bytesRead = 0;
            bool done = false;
            
            driver.sockets.read(sock, 
                buffer[totalRead .. $],
                IOMode.immediate,
                (StreamSocketFD, IOStatus s, size_t b) @safe nothrow {
                    status = s;
                    bytesRead = b;
                    done = true;
                }
            );
            
            // Wait for completion
            while (!done) {
                try { yield(); } catch(Exception) {}
            }
            
            log("Read returned: status=" ~ (cast(int)status).to!string ~ ", bytes=" ~ bytesRead.to!string);
            
            if (bytesRead > 0) {
                totalRead += bytesRead;
                log("Total read: " ~ totalRead.to!string ~ " bytes");
                
                // Try to see if we have a complete request
                auto dataSlice = buffer[0 .. totalRead];
                
                // Check for end of headers
                bool hasEndOfHeaders = false;
                if (totalRead >= 4) {
                    for (size_t i = 0; i <= totalRead - 4; i++) {
                        if (dataSlice[i .. i+4] == cast(ubyte[])"\r\n\r\n") {
                            hasEndOfHeaders = true;
                            break;
                        }
                    }
                }
                
                if (hasEndOfHeaders) {
                    log("Found end of headers, parsing...");
                    
                    // Parse with Wire directly
                    log("Calling parseHTTP with " ~ totalRead.to!string ~ " bytes...");
                    auto parsed = parseHTTP(dataSlice);
                    log("parseHTTP returned!");
                    
                    if (cast(bool)parsed) {
                        try {
                            log("Parse SUCCESS: method=" ~ parsed.getMethod().toString() ~ 
                                ", path=" ~ parsed.getPath().toString() ~
                                ", complete=" ~ parsed.request.routing.messageComplete.to!string);
                        } catch(Exception) {
                            log("Parse SUCCESS but toString failed");
                        }
                    } else {
                        log("Parse FAILED: error=" ~ parsed.request.content.errorCode.to!string);
                    }
                    break;  // Got a complete request
                }
            } else if (status == IOStatus.wouldBlock) {
                log("wouldBlock, yielding...");
                try { yield(); } catch(Exception) {}
            } else {
                log("Read failed or EOF, closing");
                return;
            }
        }
        
        // Send response
        auto response = cast(ubyte[])"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: keep-alive\r\n\r\nOK";
        size_t written = 0;
        
        while (written < response.length) {
            log("Calling write...");
            
            IOStatus status;
            size_t bytesWritten = 0;
            bool done = false;
            
            driver.sockets.write(sock,
                response[written .. $],
                IOMode.immediate,
                (StreamSocketFD, IOStatus s, size_t b) @safe nothrow {
                    status = s;
                    bytesWritten = b;
                    done = true;
                }
            );
            
            while (!done) {
                try { yield(); } catch(Exception) {}
            }
            
            log("Write returned: status=" ~ (cast(int)status).to!string ~ ", bytes=" ~ bytesWritten.to!string);
            
            if (bytesWritten > 0) {
                written += bytesWritten;
            } else if (status == IOStatus.wouldBlock) {
                try { yield(); } catch(Exception) {}
            } else {
                log("Write failed");
                return;
            }
        }
        
        log("Response sent, ready for next request");
        // Note: ParserWrapper goes out of scope here and releases back to pool
    }
}
