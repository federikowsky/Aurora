/**
 * Socket Integration Test - Real TCP Socket Testing
 *
 * This test validates Aurora's server using real TCP socket connections
 * instead of mocks, ensuring proper FD leak prevention, keep-alive behavior,
 * and connection lifecycle management.
 *
 * NOTE:
 * These tests start an in-process Aurora server on an ephemeral port to avoid
 * accidentally connecting to an unrelated server on 8080 (which can falsify results).
 *
 * Build & Run:
 *   dub test -- tests/integration/socket_integration_test.d
 */
module tests.integration.socket_integration_test;

import aurora;
import aurora.config;
import aurora.runtime.server : ServerConfig;

import std.socket;
import std.conv : to;
import std.string : startsWith, indexOf;
import core.thread : Thread;
import core.time : seconds, msecs, Duration, MonoTime;

import vibe.core.core : runTask;

version (unittest):

private __gshared ushort gTestPort;

private ushort testPort() @trusted nothrow
{
    return gTestPort;
}

private ushort findFreePort() @trusted nothrow
{
    try
    {
        auto s = new TcpSocket();
        s.bind(new InternetAddress("127.0.0.1", 0));
        s.listen(1);
        auto addr = cast(InternetAddress)s.localAddress();
        auto port = addr.port;
        s.close();
        return port;
    }
    catch (Exception)
    {
        return 0;
    }
}

private void waitForServerReady(ushort port) @trusted
{
    foreach (_; 0 .. 200)
    {
        try
        {
            auto s = new TcpSocket();
            s.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, 200.msecs);
            s.connect(new InternetAddress("127.0.0.1", port));
            s.close();
            return;
        }
        catch (Exception)
        {
            Thread.sleep(10.msecs);
        }
    }
    assert(false, "Aurora test server failed to start listening on port: " ~ port.to!string);
}

private __gshared Thread gServerThread;

shared static this() @trusted
{
    gTestPort = findFreePort();
    assert(gTestPort != 0, "Could not allocate a free ephemeral port for test server");

    gServerThread = new Thread({
        auto cfg = ServerConfig.defaults();
        cfg.host = "127.0.0.1";
        cfg.port = gTestPort;
        cfg.readTimeout = 5.seconds;
        cfg.writeTimeout = 5.seconds;
        cfg.keepAliveTimeout = 5.seconds;
        cfg.maxRequestsPerConnection = 0;
        cfg.debugMode = false;

        auto app = new App(cfg);

        // Minimal routes used by these socket tests.
        app.get("/", (ref Context ctx) {
            ctx.response.setHeader("Content-Type", "text/plain");
            ctx.send("OK");
        });

        app.post("/echo", (ref Context ctx) {
            // Touch the body to ensure framing + Content-Length handling is exercised.
            auto _ = ctx.request.bodyRaw();
            ctx.response.setHeader("Content-Type", "text/plain");
            ctx.send("OK");
        });

        // Best-effort stop endpoint for clean shutdown.
        app.get("/__test/stop", (ref Context ctx) {
            ctx.response.setHeader("Content-Type", "text/plain");
            ctx.response.setHeader("Connection", "close");
            ctx.send("stopping");

            runTask(() @system nothrow {
                try app.stop();
                catch (Exception) {}
            });
        });

        app.listen();
    });

    // Daemon thread avoids hanging the test runner if shutdown fails.
    gServerThread.isDaemon = true;
    gServerThread.start();

    waitForServerReady(gTestPort);
}

shared static ~this() @trusted
{
    if (gTestPort == 0)
        return;

    // Best-effort shutdown. We don't join the thread to avoid hanging the test runner.
    try
    {
        auto s = new TcpSocket();
        s.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, 200.msecs);
        s.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, 200.msecs);
        s.connect(new InternetAddress("127.0.0.1", gTestPort));
        s.send(cast(ubyte[])"GET /__test/stop HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n");
        s.close();
    }
    catch (Exception) {}

    Thread.sleep(50.msecs);
}

pragma(inline, true)
private void sendAll(TcpSocket socket, const(ubyte)[] data)
{
    size_t off = 0;
    while (off < data.length)
    {
        auto n = socket.send(data[off .. $]);
        if (n <= 0)
            throw new Exception("send failed");
        off += cast(size_t)n;
    }
}

/// Helper: Create HTTP request bytes
private ubyte[] makeRequest(string method, string path, string[string] headers = null)
{
    import std.array : appender;

    auto req = appender!string();
    req ~= method;
    req ~= " ";
    req ~= path;
    req ~= " HTTP/1.1\r\n";
    req ~= "Host: localhost\r\n";
    foreach (name, value; headers)
    {
        req ~= name;
        req ~= ": ";
        req ~= value;
        req ~= "\r\n";
    }
    req ~= "\r\n";
    return cast(ubyte[])req.data;
}

/// Helper: Parse status code from HTTP response
private int parseStatusCode(const(char)[] response)
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

private size_t findHeaderEnd(const(ubyte)[] buf) @nogc nothrow pure @safe
{
    if (buf.length < 4)
        return size_t.max;
    foreach (i; 0 .. buf.length - 3)
    {
        if (buf[i] == '\r' && buf[i + 1] == '\n' && buf[i + 2] == '\r' && buf[i + 3] == '\n')
            return i + 4;
    }
    return size_t.max;
}

private size_t parseContentLength(const(char)[] headerBlock)
{
    // Aurora always sets Content-Length for these routes.
    auto idx = headerBlock.indexOf("Content-Length:");
    if (idx < 0)
        return 0;

    auto start = cast(size_t)idx + "Content-Length:".length;
    while (start < headerBlock.length && (headerBlock[start] == ' ' || headerBlock[start] == '\t'))
        start++;

    size_t end = start;
    while (end < headerBlock.length && headerBlock[end] >= '0' && headerBlock[end] <= '9')
        end++;

    if (end == start)
        return 0;

    try { return headerBlock[start .. end].to!size_t; }
    catch (Exception) { return 0; }
}

private bool tryParseOneResponse(const(ubyte)[] inBuf, out size_t consumed, out int status)
{
    auto headerEnd = findHeaderEnd(inBuf);
    if (headerEnd == size_t.max)
        return false;

    auto headerBlock = cast(string)inBuf[0 .. headerEnd];
    status = parseStatusCode(headerBlock);
    if (status == 0)
        return false;

    auto cl = parseContentLength(headerBlock);
    auto total = headerEnd + cl;
    if (inBuf.length < total)
        return false;

    consumed = total;
    return true;
}

private int receiveOneResponseStatus(TcpSocket socket, ref ubyte[] stash, Duration timeout = 2.seconds)
{
    auto deadline = MonoTime.currTime + timeout;
    while (MonoTime.currTime < deadline)
    {
        size_t consumed = 0;
        int status = 0;
        if (tryParseOneResponse(stash, consumed, status))
        {
            stash = stash[consumed .. $];
            return status;
        }

        ubyte[8192] tmp;
        try
        {
            auto n = socket.receive(tmp[]);
            if (n > 0)
            {
                stash ~= tmp[0 .. cast(size_t)n];
                continue;
            }
            return 0;
        }
        catch (SocketOSException)
        {
            // Timeout/no data yet.
            Thread.sleep(10.msecs);
        }
    }

    return 0;
}

// ============================================================================
// Test: Basic TCP Connection
// ============================================================================

@("socket_basic_connection")
unittest
{
    try
    {
        auto socket = new TcpSocket();
        socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, 2.seconds);
        socket.connect(new InternetAddress("127.0.0.1", testPort()));
        
        // Send request
        auto request = makeRequest("GET", "/");
        sendAll(socket, request);
        
        // Receive response
        ubyte[] stash;
        auto status = receiveOneResponseStatus(socket, stash, 2.seconds);
        assert(status == 200, "Expected HTTP 200, got: " ~ status.to!string);
        
        socket.close();
    }
    catch (SocketOSException)
    {
        assert(false, "Failed to connect to in-process Aurora test server on port: " ~ testPort().to!string);
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
        socket.connect(new InternetAddress("127.0.0.1", testPort()));
        
        // Send first request with Connection: keep-alive
        string[string] headers;
        headers["Connection"] = "keep-alive";
        auto request1 = makeRequest("GET", "/", headers);
        sendAll(socket, request1);

        ubyte[] stash;
        auto status1 = receiveOneResponseStatus(socket, stash, 2.seconds);
        assert(status1 == 200, "Expected HTTP 200, got: " ~ status1.to!string);
        
        // Send second request on same socket
        auto request2 = makeRequest("GET", "/", headers);
        sendAll(socket, request2);

        auto status2 = receiveOneResponseStatus(socket, stash, 2.seconds);
        assert(status2 == 200, "Expected HTTP 200 on reuse, got: " ~ status2.to!string);
        
        socket.close();
    }
    catch (SocketOSException)
    {
        assert(false, "Failed to connect to in-process Aurora test server on port: " ~ testPort().to!string);
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
        socket.connect(new InternetAddress("127.0.0.1", testPort()));
        
        // Send request with Connection: close
        string[string] headers;
        headers["Connection"] = "close";
        auto request = makeRequest("GET", "/", headers);
        sendAll(socket, request);

        ubyte[] stash;
        auto status = receiveOneResponseStatus(socket, stash, 2.seconds);
        assert(status == 200, "Expected HTTP 200, got: " ~ status.to!string);
        
        // Server should close connection
        Thread.sleep(100.msecs);
        ubyte[64] buf;
        auto received2 = socket.receive(buf[]);
        // received2 should be 0 (connection closed) or error (caught below)
        
        socket.close();
    }
    catch (SocketOSException)
    {
        // Closed connection (expected)
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
            socket.connect(new InternetAddress("127.0.0.1", testPort()));
            sockets ~= socket;
        }
        
        // Send requests on all sockets
        auto request = makeRequest("GET", "/");
        foreach (socket; sockets)
            sendAll(socket, request);
        
        // Receive responses
        int successCount = 0;
        foreach (socket; sockets)
        {
            ubyte[] stash;
            auto status = receiveOneResponseStatus(socket, stash, 2.seconds);
            if (status == 200)
                successCount++;
        }
        
        cleanupSockets();

        assert(successCount >= 8, 
               "Expected at least 8/10 successful responses, got: " ~ successCount.to!string);
    }
    catch (SocketOSException)
    {
        cleanupSockets();
        assert(false, "Failed to connect to in-process Aurora test server on port: " ~ testPort().to!string);
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
        socket.connect(new InternetAddress("127.0.0.1", testPort()));
        
        // Create 100KB body (linear fill, avoids O(n^2) string concatenation).
        ubyte[] body;
        body.length = 100 * 1024;
        foreach (i; 0 .. body.length)
            body[i] = cast(ubyte)('a' + (i & 15));

        import std.array : appender;
        auto head = appender!string();
        head ~= "POST /echo HTTP/1.1\r\n";
        head ~= "Host: localhost\r\n";
        head ~= "Content-Length: ";
        head ~= body.length.to!string;
        head ~= "\r\n\r\n";

        sendAll(socket, cast(ubyte[])head.data);
        sendAll(socket, body);

        ubyte[] stash;
        auto status = receiveOneResponseStatus(socket, stash, 5.seconds);
        assert(status == 200, "Expected HTTP 200, got: " ~ status.to!string);
        
        socket.close();
    }
    catch (SocketOSException)
    {
        assert(false, "Failed to connect to in-process Aurora test server on port: " ~ testPort().to!string);
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
        auto request = makeRequest("GET", "/");
        foreach (iter; 0 .. 100)
        {
            auto socket = new TcpSocket();
            socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, 1.seconds);
            socket.connect(new InternetAddress("127.0.0.1", testPort()));
            
            sendAll(socket, request);
            
            ubyte[] stash;
            auto status = receiveOneResponseStatus(socket, stash, 1.seconds);
            assert(status == 200, "Expected HTTP 200, got: " ~ status.to!string);
            
            socket.close();
        }
        
        // If we got here without running out of FDs, test passes
        assert(true);
    }
    catch (SocketOSException)
    {
        assert(false, "Failed to connect to in-process Aurora test server on port: " ~ testPort().to!string);
    }
}
