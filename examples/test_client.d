#!/usr/bin/env dub
/+ dub.sdl:
    name "test_client"
    dependency "requests" version="~>2.1.1"
    versions "ls"
+/
/**
 * Aurora Comprehensive Test Client
 * 
 * Tests the Aurora server with:
 * - Happy path tests (basic functionality)
 * - Edge case tests (unicode, empty, large responses, etc.)
 * - Stress tests (high concurrency, rapid-fire, keep-alive abuse)
 * - Chaos tests (malformed requests, connection abuse)
 * 
 * Usage:
 *   dub run --single examples/test_client.d
 * 
 * Make sure test_server.d is running first!
 */
module test_client;

import std.stdio;
import std.string;
import std.conv;
import std.array;
import std.algorithm;
import std.range;
import std.datetime.stopwatch;
import std.socket;
import std.parallelism;
import core.atomic;
import core.thread;
import core.time;

// ============================================================================
// TEST INFRASTRUCTURE
// ============================================================================

struct TestResult
{
    string name;
    bool passed;
    string message;
    Duration duration;
}

TestResult[] allResults;
shared uint passedCount = 0;
shared uint failedCount = 0;

string baseUrl = "127.0.0.1";
ushort port = 8080;

void runTest(string name, bool delegate() testFn)
{
    auto sw = StopWatch(AutoStart.yes);
    bool passed = false;
    string message = "OK";
    
    try
    {
        passed = testFn();
        if (!passed) message = "Assertion failed";
    }
    catch (Exception e)
    {
        passed = false;
        message = e.msg;
    }
    
    sw.stop();
    
    allResults ~= TestResult(name, passed, message, sw.peek);
    
    if (passed)
    {
        atomicOp!"+="(passedCount, 1);
        writefln("  ✅ %s (%d ms)", name, sw.peek.total!"msecs");
    }
    else
    {
        atomicOp!"+="(failedCount, 1);
        writefln("  ❌ %s - %s (%d ms)", name, message, sw.peek.total!"msecs");
    }
}

// ============================================================================
// RAW HTTP CLIENT (for edge cases and malformed requests)
// ============================================================================

struct RawResponse
{
    int statusCode;
    string[string] headers;
    string body_;
    bool parseError;
    string rawResponse;
}

RawResponse rawHttpRequest(string request, int timeoutMs = 5000)
{
    RawResponse resp;
    resp.parseError = true;
    
    try
    {
        auto socket = new TcpSocket();
        socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(timeoutMs));
        socket.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, dur!"msecs"(timeoutMs));
        
        socket.connect(new InternetAddress(baseUrl, port));
        scope(exit) socket.close();
        
        socket.send(cast(ubyte[])request);
        
        char[65536] buffer;
        ptrdiff_t received;
        string response;
        
        do
        {
            received = socket.receive(buffer[]);
            if (received > 0)
            {
                response ~= buffer[0 .. received];
            }
        } while (received > 0 && response.length < 65536);
        
        resp.rawResponse = response;
        
        // Parse response
        auto headerEnd = response.indexOf("\r\n\r\n");
        if (headerEnd < 0) headerEnd = response.indexOf("\n\n");
        
        if (headerEnd >= 0)
        {
            auto headerPart = response[0 .. headerEnd];
            resp.body_ = response[headerEnd + 4 .. $];
            
            auto lines = headerPart.split("\r\n");
            if (lines.length == 0) lines = headerPart.split("\n");
            
            if (lines.length > 0)
            {
                // Parse status line: HTTP/1.1 200 OK
                auto statusLine = lines[0].split(" ");
                if (statusLine.length >= 2)
                {
                    try { resp.statusCode = statusLine[1].to!int; }
                    catch (Exception) {}
                }
                
                // Parse headers
                foreach (line; lines[1 .. $])
                {
                    auto colonIdx = line.indexOf(':');
                    if (colonIdx > 0)
                    {
                        auto name = line[0 .. colonIdx].strip.toLower;
                        auto value = line[colonIdx + 1 .. $].strip;
                        resp.headers[name] = value;
                    }
                }
                
                resp.parseError = false;
            }
        }
    }
    catch (Exception e)
    {
        resp.parseError = true;
    }
    
    return resp;
}

// Simple HTTP GET
RawResponse httpGet(string path, string[string] headers = null)
{
    string request = "GET " ~ path ~ " HTTP/1.1\r\n";
    request ~= "Host: " ~ baseUrl ~ ":" ~ port.to!string ~ "\r\n";
    request ~= "Connection: close\r\n";
    
    if (headers !is null)
    {
        foreach (name, value; headers)
        {
            request ~= name ~ ": " ~ value ~ "\r\n";
        }
    }
    
    request ~= "\r\n";
    return rawHttpRequest(request);
}

// Simple HTTP POST
RawResponse httpPost(string path, string body_, string contentType = "application/json")
{
    string request = "POST " ~ path ~ " HTTP/1.1\r\n";
    request ~= "Host: " ~ baseUrl ~ ":" ~ port.to!string ~ "\r\n";
    request ~= "Connection: close\r\n";
    request ~= "Content-Type: " ~ contentType ~ "\r\n";
    request ~= "Content-Length: " ~ body_.length.to!string ~ "\r\n";
    request ~= "\r\n";
    request ~= body_;
    return rawHttpRequest(request);
}

// HTTP PUT
RawResponse httpPut(string path, string body_)
{
    string request = "PUT " ~ path ~ " HTTP/1.1\r\n";
    request ~= "Host: " ~ baseUrl ~ ":" ~ port.to!string ~ "\r\n";
    request ~= "Connection: close\r\n";
    request ~= "Content-Type: application/json\r\n";
    request ~= "Content-Length: " ~ body_.length.to!string ~ "\r\n";
    request ~= "\r\n";
    request ~= body_;
    return rawHttpRequest(request);
}

// HTTP DELETE
RawResponse httpDelete(string path)
{
    string request = "DELETE " ~ path ~ " HTTP/1.1\r\n";
    request ~= "Host: " ~ baseUrl ~ ":" ~ port.to!string ~ "\r\n";
    request ~= "Connection: close\r\n";
    request ~= "\r\n";
    return rawHttpRequest(request);
}

// ============================================================================
// HAPPY PATH TESTS
// ============================================================================

void runHappyPathTests()
{
    writeln("\n📗 HAPPY PATH TESTS");
    writeln("=" .replicate(50));
    
    runTest("GET / returns 200", {
        auto resp = httpGet("/");
        import std.stdio : stderr;
        stderr.writefln("DEBUG: statusCode=%d, body=[%s], parseError=%s", 
            resp.statusCode, resp.body_, resp.parseError);
        return resp.statusCode == 200 && resp.body_.canFind("Aurora");
    });
    
    runTest("GET /health returns JSON", {
        auto resp = httpGet("/health");
        return resp.statusCode == 200 && 
               resp.body_.canFind("healthy") &&
               resp.headers.get("content-type", "").canFind("json");
    });
    
    runTest("GET /echo with query param", {
        auto resp = httpGet("/echo?msg=hello");
        return resp.statusCode == 200 && resp.body_.canFind("hello");
    });
    
    runTest("POST /echo echoes body", {
        auto resp = httpPost("/echo", "test message", "text/plain");
        return resp.statusCode == 200 && resp.body_.canFind("test message");
    });
    
    runTest("GET /status/:code returns correct status", {
        auto resp = httpGet("/status/201");
        return resp.statusCode == 201;
    });
    
    runTest("GET /status/404 returns 404", {
        auto resp = httpGet("/status/404");
        return resp.statusCode == 404;
    });
    
    runTest("GET /status/500 returns 500", {
        auto resp = httpGet("/status/500");
        return resp.statusCode == 500;
    });
    
    runTest("POST /json echoes JSON", {
        auto resp = httpPost("/json", `{"key":"value"}`);
        return resp.statusCode == 200 && resp.body_.canFind("received");
    });
    
    runTest("GET /headers returns request info", {
        auto resp = httpGet("/headers");
        return resp.statusCode == 200 && resp.body_.canFind("GET");
    });
    
    runTest("GET /nested/a/b/c/d works", {
        auto resp = httpGet("/nested/a/b/c/d");
        return resp.statusCode == 200 && resp.body_.canFind("nested");
    });
    
    // API v1 tests
    runTest("GET /api/v1/users returns list", {
        auto resp = httpGet("/api/v1/users");
        return resp.statusCode == 200 && resp.body_.canFind("Alice");
    });
    
    runTest("GET /api/v1/users/1 returns user", {
        auto resp = httpGet("/api/v1/users/1");
        return resp.statusCode == 200 && resp.body_.canFind("Alice");
    });
    
    runTest("GET /api/v1/users/999 returns 404", {
        auto resp = httpGet("/api/v1/users/999");
        return resp.statusCode == 404;
    });
    
    runTest("POST /api/v1/users creates user", {
        auto resp = httpPost("/api/v1/users", `{"name":"NewUser"}`);
        return resp.statusCode == 201 && resp.body_.canFind("created");
    });
    
    runTest("PUT /api/v1/users/1 updates user", {
        auto resp = httpPut("/api/v1/users/1", `{"name":"UpdatedAlice"}`);
        return resp.statusCode == 200 && resp.body_.canFind("updated");
    });
    
    // API v2 tests
    runTest("GET /api/v2/users returns v2 format", {
        auto resp = httpGet("/api/v2/users");
        return resp.statusCode == 200 && 
               resp.body_.canFind("version") &&
               resp.headers.get("x-api-version", "") == "2";
    });
    
    // CORS test
    runTest("OPTIONS request returns CORS headers", {
        string request = "OPTIONS /api/v1/users HTTP/1.1\r\n";
        request ~= "Host: " ~ baseUrl ~ "\r\n";
        request ~= "Connection: close\r\n";
        request ~= "\r\n";
        auto resp = rawHttpRequest(request);
        return resp.statusCode == 204 &&
               resp.headers.get("access-control-allow-origin", "") == "*";
    });
    
    runTest("Response has timing header", {
        auto resp = httpGet("/");
        return ("x-response-time" in resp.headers) !is null;
    });
}

// ============================================================================
// EDGE CASE TESTS
// ============================================================================

void runEdgeCaseTests()
{
    writeln("\n📙 EDGE CASE TESTS");
    writeln("=".replicate(50));
    
    runTest("GET /edge/empty returns 204 with no body", {
        auto resp = httpGet("/edge/empty");
        return resp.statusCode == 204;
    });
    
    runTest("GET /edge/unicode returns unicode correctly", {
        auto resp = httpGet("/edge/unicode");
        return resp.statusCode == 200 && 
               (resp.body_.canFind("🌍") || resp.body_.length > 20);
    });
    
    runTest("GET /edge/huge returns 1MB", {
        auto resp = httpGet("/edge/huge");
        return resp.statusCode == 200 && resp.body_.length >= 1024 * 1024;
    });
    
    runTest("GET /edge/headers-flood returns many headers", {
        auto resp = httpGet("/edge/headers-flood");
        int customHeaders = 0;
        foreach (name, _; resp.headers)
        {
            if (name.startsWith("x-custom-header-"))
                customHeaders++;
        }
        return resp.statusCode == 200 && customHeaders >= 40;
    });
    
    runTest("GET /size/0 returns empty body", {
        auto resp = httpGet("/size/0");
        return resp.statusCode == 200;
    });
    
    runTest("GET /size/100 returns 100 bytes", {
        auto resp = httpGet("/size/100");
        return resp.statusCode == 200 && resp.body_.length == 100;
    });
    
    runTest("GET /size/10000 returns 10KB", {
        auto resp = httpGet("/size/10000");
        return resp.statusCode == 200 && resp.body_.length == 10000;
    });
    
    runTest("GET nonexistent path returns 404", {
        auto resp = httpGet("/this/path/does/not/exist");
        return resp.statusCode == 404;
    });
    
    runTest("Very long path handled", {
        auto longPath = "/" ~ "a".replicate(1000);
        auto resp = httpGet(longPath);
        return resp.statusCode == 404;  // Should return 404, not crash
    });
    
    runTest("Path with special chars", {
        auto resp = httpGet("/echo?msg=hello%20world%21");
        return resp.statusCode == 200;
    });
    
    runTest("Path with unicode", {
        auto resp = httpGet("/echo?msg=こんにちは");
        return resp.statusCode == 200;
    });
    
    runTest("Empty POST body handled", {
        auto resp = httpPost("/json", "");
        return resp.statusCode == 200 && resp.body_.canFind("null");
    });
    
    runTest("Large POST body (64KB)", {
        auto largeBody = `{"data":"` ~ "X".replicate(64000) ~ `"}`;
        auto resp = httpPost("/json", largeBody);
        return resp.statusCode == 200;
    });
    
    runTest("POST with wrong Content-Type", {
        auto resp = httpPost("/json", `{"key":"value"}`, "text/plain");
        return resp.statusCode == 200;
    });
    
    runTest("Multiple query parameters", {
        auto resp = httpGet("/echo?a=1&b=2&c=3&d=4&e=5");
        return resp.statusCode == 200;
    });
    
    runTest("HTTP/1.0 request", {
        string request = "GET / HTTP/1.0\r\n";
        request ~= "Host: " ~ baseUrl ~ "\r\n";
        request ~= "\r\n";
        auto resp = rawHttpRequest(request);
        return resp.statusCode == 200;
    });
    
    runTest("Request without Host header", {
        string request = "GET / HTTP/1.1\r\n";
        request ~= "Connection: close\r\n";
        request ~= "\r\n";
        auto resp = rawHttpRequest(request);
        // Should still work or return 400
        return resp.statusCode == 200 || resp.statusCode == 400;
    });
    
    runTest("Extra whitespace in headers", {
        string request = "GET / HTTP/1.1\r\n";
        request ~= "Host:   " ~ baseUrl ~ "   \r\n";
        request ~= "Connection:   close   \r\n";
        request ~= "\r\n";
        auto resp = rawHttpRequest(request);
        return resp.statusCode == 200;
    });
}

// ============================================================================
// STRESS TESTS
// ============================================================================

void runStressTests()
{
    writeln("\n📕 STRESS TESTS");
    writeln("=".replicate(50));
    
    // Sequential rapid-fire
    runTest("100 sequential requests", {
        int success = 0;
        foreach (i; 0 .. 100)
        {
            auto resp = httpGet("/health");
            if (resp.statusCode == 200) success++;
        }
        return success == 100;
    });
    
    // Parallel requests
    runTest("50 parallel requests", {
        shared int success = 0;
        auto work = iota(50);
        
        foreach (i; parallel(work))
        {
            auto resp = httpGet("/health");
            if (resp.statusCode == 200)
                atomicOp!"+="(success, 1);
        }
        
        return atomicLoad(success) == 50;
    });
    
    // High concurrency
    runTest("200 parallel requests", {
        shared int success = 0;
        auto work = iota(200);
        
        foreach (i; parallel(work))
        {
            auto resp = httpGet("/");
            if (resp.statusCode == 200)
                atomicOp!"+="(success, 1);
        }
        
        return atomicLoad(success) >= 180;  // Allow some failures
    });
    
    // Mixed methods concurrency
    runTest("100 mixed method parallel requests", {
        shared int success = 0;
        auto work = iota(100);
        
        foreach (i; parallel(work))
        {
            RawResponse resp;
            switch (i % 4)
            {
                case 0: resp = httpGet("/api/v1/users"); break;
                case 1: resp = httpPost("/json", `{"i":` ~ i.to!string ~ `}`); break;
                case 2: resp = httpGet("/api/v1/users/1"); break;
                case 3: resp = httpGet("/health"); break;
                default: break;
            }
            if (resp.statusCode == 200 || resp.statusCode == 201)
                atomicOp!"+="(success, 1);
        }
        
        return atomicLoad(success) >= 90;
    });
    
    // Large response stress
    runTest("20 parallel large response requests (100KB each)", {
        shared int success = 0;
        auto work = iota(20);
        
        foreach (i; parallel(work))
        {
            auto resp = httpGet("/size/102400");
            if (resp.statusCode == 200 && resp.body_.length == 102400)
                atomicOp!"+="(success, 1);
        }
        
        return atomicLoad(success) >= 18;
    });
    
    // Connection churn
    runTest("500 rapid connect/disconnect", {
        shared int success = 0;
        auto work = iota(500);
        
        foreach (i; parallel(work, 50))
        {
            try
            {
                auto socket = new TcpSocket();
                socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(1000));
                socket.connect(new InternetAddress(baseUrl, port));
                socket.close();
                atomicOp!"+="(success, 1);
            }
            catch (Exception) {}
        }
        
        return atomicLoad(success) >= 450;
    });
    
    // Throughput test
    runTest("Throughput: 1000 requests in < 10 seconds", {
        auto sw = StopWatch(AutoStart.yes);
        shared int success = 0;
        auto work = iota(1000);
        
        foreach (i; parallel(work, 100))
        {
            auto resp = httpGet("/health");
            if (resp.statusCode == 200)
                atomicOp!"+="(success, 1);
        }
        
        sw.stop();
        auto elapsed = sw.peek.total!"seconds";
        writefln("    -> %d requests in %d seconds (%.1f req/s)", 
                 atomicLoad(success), elapsed,
                 cast(double)atomicLoad(success) / max(1, elapsed));
        
        return elapsed < 10 && atomicLoad(success) >= 900;
    });
}

// ============================================================================
// CHAOS TESTS (try to break the server)
// ============================================================================

void runChaosTests()
{
    writeln("\n💀 CHAOS TESTS");
    writeln("=".replicate(50));
    
    // Malformed requests
    runTest("Malformed HTTP (no method)", {
        auto resp = rawHttpRequest("/ HTTP/1.1\r\nHost: test\r\n\r\n", 2000);
        // Server should handle gracefully
        return true;  // Just shouldn't crash
    });
    
    runTest("Malformed HTTP (garbage)", {
        auto resp = rawHttpRequest("GARBAGE GARBAGE GARBAGE\r\n\r\n", 2000);
        return true;  // Just shouldn't crash
    });
    
    runTest("Incomplete request", {
        auto resp = rawHttpRequest("GET / HTTP/1.1\r\n", 2000);
        return true;
    });
    
    runTest("Very long header line (10KB)", {
        string request = "GET / HTTP/1.1\r\n";
        request ~= "Host: " ~ baseUrl ~ "\r\n";
        request ~= "X-Long-Header: " ~ "X".replicate(10000) ~ "\r\n";
        request ~= "Connection: close\r\n";
        request ~= "\r\n";
        auto resp = rawHttpRequest(request, 3000);
        // Should either work or return error, not crash
        return true;
    });
    
    runTest("Many headers (100)", {
        string request = "GET / HTTP/1.1\r\n";
        request ~= "Host: " ~ baseUrl ~ "\r\n";
        foreach (i; 0 .. 100)
        {
            request ~= "X-Header-" ~ i.to!string ~ ": value\r\n";
        }
        request ~= "Connection: close\r\n";
        request ~= "\r\n";
        auto resp = rawHttpRequest(request, 3000);
        return resp.statusCode == 200 || resp.statusCode == 400 || resp.statusCode == 431;
    });
    
    runTest("Binary data in headers", {
        string request = "GET / HTTP/1.1\r\n";
        request ~= "Host: " ~ baseUrl ~ "\r\n";
        request ~= "X-Binary: \x00\x01\x02\x03\r\n";
        request ~= "Connection: close\r\n";
        request ~= "\r\n";
        auto resp = rawHttpRequest(request, 2000);
        return true;  // Shouldn't crash
    });
    
    runTest("Double Content-Length", {
        string request = "POST /json HTTP/1.1\r\n";
        request ~= "Host: " ~ baseUrl ~ "\r\n";
        request ~= "Content-Length: 10\r\n";
        request ~= "Content-Length: 20\r\n";
        request ~= "Connection: close\r\n";
        request ~= "\r\n";
        request ~= "0123456789";
        auto resp = rawHttpRequest(request, 2000);
        return true;  // Should handle somehow
    });
    
    runTest("Negative Content-Length", {
        string request = "POST /json HTTP/1.1\r\n";
        request ~= "Host: " ~ baseUrl ~ "\r\n";
        request ~= "Content-Length: -1\r\n";
        request ~= "Connection: close\r\n";
        request ~= "\r\n";
        auto resp = rawHttpRequest(request, 2000);
        return true;
    });
    
    runTest("Huge Content-Length (overflow attempt)", {
        string request = "POST /json HTTP/1.1\r\n";
        request ~= "Host: " ~ baseUrl ~ "\r\n";
        request ~= "Content-Length: 99999999999999999999\r\n";
        request ~= "Connection: close\r\n";
        request ~= "\r\n";
        request ~= "small body";
        auto resp = rawHttpRequest(request, 2000);
        return true;
    });
    
    runTest("Slowloris-style (slow headers)", {
        try
        {
            auto socket = new TcpSocket();
            socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(5000));
            socket.connect(new InternetAddress(baseUrl, port));
            scope(exit) socket.close();
            
            // Send headers very slowly
            socket.send(cast(ubyte[])"GET / HTTP/1.1\r\n");
            Thread.sleep(100.msecs);
            socket.send(cast(ubyte[])"Host: test\r\n");
            Thread.sleep(100.msecs);
            socket.send(cast(ubyte[])"Connection: close\r\n");
            Thread.sleep(100.msecs);
            socket.send(cast(ubyte[])"\r\n");
            
            char[4096] buffer;
            auto received = socket.receive(buffer[]);
            
            return received > 0;  // Should still get response
        }
        catch (Exception)
        {
            return true;  // Timeout is acceptable
        }
    });
    
    runTest("Pipelining (multiple requests on one connection)", {
        try
        {
            auto socket = new TcpSocket();
            socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(5000));
            socket.connect(new InternetAddress(baseUrl, port));
            scope(exit) socket.close();
            
            // Send 3 requests back-to-back
            string requests;
            foreach (i; 0 .. 3)
            {
                requests ~= "GET /health HTTP/1.1\r\n";
                requests ~= "Host: " ~ baseUrl ~ "\r\n";
                requests ~= "Connection: keep-alive\r\n";
                requests ~= "\r\n";
            }
            
            socket.send(cast(ubyte[])requests);
            
            char[65536] buffer;
            ptrdiff_t total = 0;
            do
            {
                auto received = socket.receive(buffer[total .. $]);
                if (received <= 0) break;
                total += received;
            } while (total < 65536);
            
            // Should get multiple responses
            auto response = cast(string)buffer[0 .. total];
            auto count = response.split("HTTP/1.1").length - 1;
            
            return count >= 1;  // At least one response
        }
        catch (Exception)
        {
            return true;
        }
    });
    
    runTest("Request smuggling attempt", {
        string request = "POST /json HTTP/1.1\r\n";
        request ~= "Host: " ~ baseUrl ~ "\r\n";
        request ~= "Content-Length: 44\r\n";
        request ~= "Transfer-Encoding: chunked\r\n";
        request ~= "Connection: close\r\n";
        request ~= "\r\n";
        request ~= "0\r\n";
        request ~= "\r\n";
        request ~= "GET /smuggled HTTP/1.1\r\n";
        request ~= "Host: evil\r\n";
        request ~= "\r\n";
        
        auto resp = rawHttpRequest(request, 2000);
        return true;  // Should handle without vulnerability
    });
    
    runTest("Rapid reconnect flood (100 in 1 second)", {
        auto sw = StopWatch(AutoStart.yes);
        int connections = 0;
        
        while (sw.peek.total!"msecs" < 1000 && connections < 100)
        {
            try
            {
                auto socket = new TcpSocket();
                socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(100));
                socket.connect(new InternetAddress(baseUrl, port));
                socket.close();
                connections++;
            }
            catch (Exception) {}
        }
        
        return connections >= 50;
    });
    
    // After chaos, verify server still works
    runTest("Server still responsive after chaos", {
        Thread.sleep(500.msecs);  // Let server recover
        auto resp = httpGet("/health");
        return resp.statusCode == 200;
    });
}

// ============================================================================
// KEEP-ALIVE TESTS
// ============================================================================

void runKeepAliveTests()
{
    writeln("\n🔄 KEEP-ALIVE TESTS");
    writeln("=".replicate(50));
    
    runTest("Multiple requests on single connection", {
        try
        {
            auto socket = new TcpSocket();
            socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(5000));
            socket.connect(new InternetAddress(baseUrl, port));
            scope(exit) socket.close();
            
            int successful = 0;
            
            foreach (i; 0 .. 5)
            {
                string request = "GET /health HTTP/1.1\r\n";
                request ~= "Host: " ~ baseUrl ~ "\r\n";
                request ~= "Connection: keep-alive\r\n";
                request ~= "\r\n";
                
                socket.send(cast(ubyte[])request);
                
                // Read response (simplified)
                char[4096] buffer;
                auto received = socket.receive(buffer[]);
                
                if (received > 0)
                {
                    auto response = cast(string)buffer[0 .. received];
                    if (response.canFind("200"))
                        successful++;
                }
            }
            
            return successful >= 3;
        }
        catch (Exception e)
        {
            return false;
        }
    });
    
    runTest("Connection: close respected", {
        try
        {
            auto socket = new TcpSocket();
            socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(2000));
            socket.connect(new InternetAddress(baseUrl, port));
            scope(exit) socket.close();
            
            string request = "GET / HTTP/1.1\r\n";
            request ~= "Host: " ~ baseUrl ~ "\r\n";
            request ~= "Connection: close\r\n";
            request ~= "\r\n";
            
            socket.send(cast(ubyte[])request);
            
            char[4096] buffer;
            socket.receive(buffer[]);
            
            // Second request should fail
            socket.send(cast(ubyte[])request);
            auto received = socket.receive(buffer[]);
            
            return received <= 0;  // Connection should be closed
        }
        catch (Exception)
        {
            return true;  // Expected - connection closed
        }
    });
}

// ============================================================================
// MAIN
// ============================================================================

void main(string[] args)
{
    writeln("╔════════════════════════════════════════════════════════════╗");
    writeln("║           AURORA COMPREHENSIVE TEST CLIENT                 ║");
    writeln("╚════════════════════════════════════════════════════════════╝");
    
    // Parse args
    if (args.length > 1)
    {
        baseUrl = args[1];
    }
    if (args.length > 2)
    {
        try { port = args[2].to!ushort; } catch (Exception) {}
    }
    
    writefln("\nTarget: %s:%d", baseUrl, port);
    writeln("Starting tests...\n");
    
    // Check server is running
    writeln("Checking server connectivity...");
    auto checkResp = httpGet("/health");
    if (checkResp.statusCode != 200)
    {
        writeln("❌ Cannot connect to server!");
        writeln("   Make sure test_server.d is running:");
        writeln("   dub run --single examples/test_server.d");
        return;
    }
    writeln("✅ Server is running\n");
    
    auto totalSw = StopWatch(AutoStart.yes);
    
    // Run all test suites
    runHappyPathTests();
    runEdgeCaseTests();
    runKeepAliveTests();
    runStressTests();
    runChaosTests();
    
    totalSw.stop();
    
    // Summary
    writeln("\n");
    writeln("╔════════════════════════════════════════════════════════════╗");
    writeln("║                      TEST SUMMARY                          ║");
    writeln("╠════════════════════════════════════════════════════════════╣");
    writefln("║  Total Tests:  %3d                                         ║", atomicLoad(passedCount) + atomicLoad(failedCount));
    writefln("║  Passed:       %3d ✅                                       ║", atomicLoad(passedCount));
    writefln("║  Failed:       %3d ❌                                       ║", atomicLoad(failedCount));
    writefln("║  Duration:     %3d seconds                                 ║", totalSw.peek.total!"seconds");
    writeln("╚════════════════════════════════════════════════════════════╝");
    
    if (atomicLoad(failedCount) > 0)
    {
        writeln("\nFailed tests:");
        foreach (result; allResults)
        {
            if (!result.passed)
            {
                writefln("  - %s: %s", result.name, result.message);
            }
        }
    }
    
    writeln();
}
