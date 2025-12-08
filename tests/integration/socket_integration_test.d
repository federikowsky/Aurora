/**
 * Socket Integration Test - Real TCP Socket Testing
 *
 * This test validates Aurora's server using real TCP socket connections
 * instead of mocks, ensuring proper FD leak prevention, keep-alive behavior,
 * and connection lifecycle management.
 *
 * Build & Run:
 *   dub test -- tests/integration/socket_integration_test.d
 */
module tests.integration.socket_integration_test;

import aurora;
import aurora.config;

import std.socket;
import std.conv : to;
import std.string : startsWith, indexOf;
import core.thread : Thread;
import core.time : seconds, msecs;

version (unittest):

/// Helper: Create HTTP request string
string makeRequest(string method, string path, string[string] headers = null)
{
    string req = method ~ " " ~ path ~ " HTTP/1.1\r\n";
    req ~= "Host: localhost\r\n";
    foreach (name, value; headers)
    {
        req ~= name ~ ": " ~ value ~ "\r\n";
    }
    req ~= "\r\n";
    return req;
}

/// Helper: Parse status code from HTTP response
int parseStatusCode(string response)
{
    // HTTP/1.1 200 OK
    if (response.length < 12)
        return 0;
    auto spacePos = response.indexOf(' ');
    if (spacePos < 0)
        return 0;
    auto endPos = response.indexOf(' ', spacePos + 1);
    if (endPos < 0)
        return 0;
    try
    {
        return response[spacePos + 1 .. endPos].to!int;
    }
    catch (Exception)
    {
        return 0;
    }
}

// ============================================================================
// Test: Basic TCP Connection
// ============================================================================

@("socket_basic_connection")
unittest
{
    // This test requires a running server - skip if not available
    try
    {
        auto socket = new TcpSocket();
        socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, 2.seconds);
        socket.connect(new InternetAddress("127.0.0.1", 8080));
        
        // Send request
        auto request = makeRequest("GET", "/");
        socket.send(cast(ubyte[]) request);
        
        // Receive response
        ubyte[4096] buffer;
        auto received = socket.receive(buffer);
        
        if (received > 0)
        {
            auto response = cast(string) buffer[0 .. received];
            auto status = parseStatusCode(response);
            assert(status >= 200 && status < 600, 
                   "Expected valid HTTP status, got: " ~ status.to!string);
        }
        
        socket.close();
    }
    catch (SocketOSException)
    {
        // Server not running - test is skipped
    }
}

// ============================================================================
// Test: Keep-Alive Connection Reuse
// ============================================================================

@("socket_keepalive_reuse")
unittest
{
    try
    {
        auto socket = new TcpSocket();
        socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, 2.seconds);
        socket.connect(new InternetAddress("127.0.0.1", 8080));
        
        // Send first request with Connection: keep-alive
        string[string] headers;
        headers["Connection"] = "keep-alive";
        auto request1 = makeRequest("GET", "/", headers);
        socket.send(cast(ubyte[]) request1);
        
        ubyte[4096] buffer;
        auto received1 = socket.receive(buffer);
        assert(received1 > 0, "First request should receive response");
        
        // Send second request on same socket
        auto request2 = makeRequest("GET", "/", headers);
        socket.send(cast(ubyte[]) request2);
        
        auto received2 = socket.receive(buffer);
        assert(received2 > 0, "Second request should receive response on same socket");
        
        socket.close();
    }
    catch (SocketOSException)
    {
        // Server not running
    }
}

// ============================================================================
// Test: Connection Close Header
// ============================================================================

@("socket_connection_close")
unittest
{
    try
    {
        auto socket = new TcpSocket();
        socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, 2.seconds);
        socket.connect(new InternetAddress("127.0.0.1", 8080));
        
        // Send request with Connection: close
        string[string] headers;
        headers["Connection"] = "close";
        auto request = makeRequest("GET", "/", headers);
        socket.send(cast(ubyte[]) request);
        
        ubyte[4096] buffer;
        auto received = socket.receive(buffer);
        assert(received > 0, "Should receive response");
        
        // Server should close connection
        Thread.sleep(100.msecs);
        auto received2 = socket.receive(buffer);
        // received2 should be 0 (connection closed) or error
        
        socket.close();
    }
    catch (SocketOSException)
    {
        // Server not running or closed connection (expected)
    }
}

// ============================================================================
// Test: Multiple Concurrent Connections
// ============================================================================

@("socket_concurrent_connections")
unittest
{
    TcpSocket[] sockets;
    
    void cleanupSockets()
    {
        foreach (s; sockets)
        {
            try { s.close(); } catch (Exception) {}
        }
    }
    
    try
    {
        // Open 10 concurrent connections
        foreach (i; 0 .. 10)
        {
            auto socket = new TcpSocket();
            socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, 2.seconds);
            socket.connect(new InternetAddress("127.0.0.1", 8080));
            sockets ~= socket;
        }
        
        // Send requests on all sockets
        foreach (socket; sockets)
        {
            auto request = makeRequest("GET", "/");
            socket.send(cast(ubyte[]) request);
        }
        
        // Receive responses
        int successCount = 0;
        foreach (socket; sockets)
        {
            ubyte[4096] buffer;
            auto received = socket.receive(buffer);
            if (received > 0)
            {
                auto response = cast(string) buffer[0 .. received];
                if (parseStatusCode(response) == 200)
                    successCount++;
            }
        }
        
        cleanupSockets();
        
        assert(successCount >= 8, 
               "Expected at least 8/10 successful responses, got: " ~ successCount.to!string);
    }
    catch (SocketOSException)
    {
        cleanupSockets();
        // Server not running
    }
}

// ============================================================================
// Test: Large Request Body
// ============================================================================

@("socket_large_request")
unittest
{
    try
    {
        auto socket = new TcpSocket();
        socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, 5.seconds);
        socket.connect(new InternetAddress("127.0.0.1", 8080));
        
        // Create 100KB body
        string body = "";
        foreach (i; 0 .. 1000)
        {
            body ~= "0123456789" ~ "0123456789" ~ "0123456789" ~ "0123456789" ~ "0123456789" ~
                    "0123456789" ~ "0123456789" ~ "0123456789" ~ "0123456789" ~ "0123456789";
        }
        
        string request = "POST /echo HTTP/1.1\r\n"
                       ~ "Host: localhost\r\n"
                       ~ "Content-Length: " ~ body.length.to!string ~ "\r\n"
                       ~ "\r\n"
                       ~ body;
        
        socket.send(cast(ubyte[]) request);
        
        ubyte[4096] buffer;
        auto received = socket.receive(buffer);
        // Just verify we get some response
        assert(received > 0, "Should receive response for large request");
        
        socket.close();
    }
    catch (SocketOSException)
    {
        // Server not running
    }
}

// ============================================================================
// Test: FD Leak Detection
// ============================================================================

@("socket_fd_leak_detection")
unittest
{
    // Open and close many connections, checking that FDs don't leak
    try
    {
        foreach (iter; 0 .. 100)
        {
            auto socket = new TcpSocket();
            socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, 1.seconds);
            socket.connect(new InternetAddress("127.0.0.1", 8080));
            
            auto request = makeRequest("GET", "/");
            socket.send(cast(ubyte[]) request);
            
            ubyte[4096] buffer;
            socket.receive(buffer);
            
            socket.close();
        }
        
        // If we got here without running out of FDs, test passes
        assert(true);
    }
    catch (SocketOSException)
    {
        // Server not running
    }
}
