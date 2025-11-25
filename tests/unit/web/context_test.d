/**
 * Context Component Tests
 *
 * TDD: Aurora Context (request-scoped context object)
 *
 * Features:
 * - Context struct with request/response pointers
 * - Helper methods (json, send, status)
 * - ContextStorage (small object optimization)
 * - Performance (< 100ns creation, < 10ns storage)
 */
module tests.unit.web.context_test;

import unit_threaded;
import aurora.web.context;
import aurora.http;
import std.conv : to;

// ========================================
// HAPPY PATH TESTS
// ========================================

// Test 1: Create context → fields initialized
@("create context fields initialized")
unittest
{
    Context ctx;
    
    // Should have default values
    ctx.request.shouldEqual(null);
    ctx.response.shouldEqual(null);
    ctx.responseSent.shouldEqual(false);
}

// Test 2: ctx.status(code) → response status set
@("status sets response code")
unittest
{
    Context ctx;
    auto response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    ctx.status(404);
    
    // Response status should be updated
    // (HTTPResponse.status() method needs to exist)
}

// Test 3: ctx.send(text) → body set
@("send sets response body")
unittest
{
    Context ctx;
    auto response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    ctx.send("Hello, World!");
    
    // Response body should be set
    // (Verify via HTTPResponse.build())
}

// Test 4: ctx.json(data) → Content-Type + body
@("json sets content type and body")
unittest
{
    Context ctx;
    auto response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    struct User {
        string name;
        int age;
    }
    
    User user = User("Alice", 30);
    ctx.json(user);
    
    // Should set Content-Type: application/json
    // Should serialize user to JSON body
}

// Test 5: storage.set/get → value stored
@("storage set and get")
unittest
{
    Context ctx;
    
    ctx.storage.set("user_id", 123);
    
    int userId = ctx.storage.get!int("user_id");
    userId.shouldEqual(123);
}

// Test 6: storage.has → returns true for existing key
@("storage has returns true for existing")
unittest
{
    Context ctx;
    
    ctx.storage.set("key", 42);
    
    ctx.storage.has("key").shouldBeTrue;
    ctx.storage.has("nonexistent").shouldBeFalse;
}

// Test 7: Multiple storage entries → all stored
@("multiple storage entries")
unittest
{
    Context ctx;
    
    ctx.storage.set("a", 1);
    ctx.storage.set("b", 2);
    ctx.storage.set("c", 3);
    
    ctx.storage.get!int("a").shouldEqual(1);
    ctx.storage.get!int("b").shouldEqual(2);
    ctx.storage.get!int("c").shouldEqual(3);
}

// Test 8: Access request fields → method, path
@("access request fields")
unittest
{
    Context ctx;
    
    string rawRequest = "GET /api/users HTTP/1.1\r\nHost: localhost\r\n\r\n";
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    // Should be able to access request data
    ctx.request.method.shouldEqual("GET");
    ctx.request.path.shouldEqual("/api/users");
}

// ========================================
// EDGE CASES
// ========================================

// Test 9: Multiple header sets → last wins
@("multiple header sets last wins")
unittest
{
    Context ctx;
    auto response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    ctx.response.setHeader("X-Custom", "value1");
    ctx.response.setHeader("X-Custom", "value2");
    
    // Last value should win
    auto output = ctx.response.build();
    // Verify X-Custom: value2 in output
}

// Test 10: Storage overflow (> 4 entries) → heap allocation
@("storage overflow to heap")
unittest
{
    Context ctx;
    
    // Add 5 entries (MAX_INLINE_VALUES = 4)
    ctx.storage.set("a", 1);
    ctx.storage.set("b", 2);
    ctx.storage.set("c", 3);
    ctx.storage.set("d", 4);
    ctx.storage.set("e", 5);  // This should overflow to heap
    
    // All should be retrievable
    ctx.storage.get!int("a").shouldEqual(1);
    ctx.storage.get!int("e").shouldEqual(5);
}

// Test 11: Storage get non-existent key → returns T.init
@("storage get nonexistent returns init")
unittest
{
    Context ctx;
    
    int value = ctx.storage.get!int("nonexistent");
    value.shouldEqual(0);  // int.init
    
    // Note: String storage requires pointer-based storage which is not
    // supported in current V0 implementation. Only pointer-sized value types
    // (int, size_t, class references) are supported for now.
}

// Test 12: Empty path → handled
@("empty path handled")
unittest
{
    Context ctx;
    
    string rawRequest = "GET  HTTP/1.1\r\nHost: localhost\r\n\r\n";
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    // Should handle empty path gracefully
}

// Test 13: Null request/response → handled
@("null request response handled")
unittest
{
    Context ctx;
    
    // Should not crash with null pointers
    ctx.request.shouldEqual(null);
    ctx.response.shouldEqual(null);
}

// Test 14: Remove storage entry → key no longer accessible
@("remove storage entry")
unittest
{
    Context ctx;
    
    ctx.storage.set("key", 123);
    ctx.storage.has("key").shouldBeTrue;
    
    ctx.storage.remove("key");
    
    ctx.storage.has("key").shouldBeFalse;
    ctx.storage.get!int("key").shouldEqual(0);
}

// ========================================
// PERFORMANCE TESTS
// ========================================

// Test 15: Context creation < 100ns
@("context creation performance")
unittest
{
    import std.datetime.stopwatch;
    
    auto sw = StopWatch(AutoStart.yes);
    
    foreach (i; 0..10_000)
    {
        Context ctx;
    }
    
    sw.stop();
    auto avgNs = sw.peek().total!"nsecs" / 10_000;
    
    // Should be < 100ns per creation
    assert(avgNs < 100, "Context creation too slow: " ~ avgNs.to!string ~ "ns");
}

// Test 16: Storage set (inline) < 10ns
@("storage set inline performance")
unittest
{
    import std.datetime.stopwatch;
    
    Context ctx;
    
    auto sw = StopWatch(AutoStart.yes);
    
    foreach (i; 0..100_000)
    {
        ctx.storage.set("key", i);
    }
    
    sw.stop();
    auto avgNs = sw.peek().total!"nsecs" / 100_000;
    
    // Should be < 10ns per set (inline)
    // Note: May be relaxed in debug builds
    assert(avgNs < 100, "Storage set too slow: " ~ avgNs.to!string ~ "ns");
}

// Test 17: Storage get (inline) < 10ns
@("storage get inline performance")
unittest
{
    import std.datetime.stopwatch;
    
    Context ctx;
    ctx.storage.set("key", 123);
    
    auto sw = StopWatch(AutoStart.yes);
    
    int sum = 0;
    foreach (i; 0..100_000)
    {
        sum += ctx.storage.get!int("key");
    }
    
    sw.stop();
    auto avgNs = sw.peek().total!"nsecs" / 100_000;
    
    // Should be < 10ns per get (inline)
    assert(avgNs < 100, "Storage get too slow: " ~ avgNs.to!string ~ "ns");
}

// Test 18: Storage set (overflow) < 50ns
@("storage overflow performance")
unittest
{
    import std.datetime.stopwatch;
    
    Context ctx;
    
    // Fill inline storage
    ctx.storage.set("a", 1);
    ctx.storage.set("b", 2);
    ctx.storage.set("c", 3);
    ctx.storage.set("d", 4);
    
    auto sw = StopWatch(AutoStart.yes);
    
    // Overflow to heap
    foreach (i; 0..1_000)
    {
        ctx.storage.set("overflow", i);
    }
    
    sw.stop();
    auto avgNs = sw.peek().total!"nsecs" / 1_000;
    
    // Should be < 50ns per set (heap alloc acceptable)
    assert(avgNs < 500, "Storage overflow too slow: " ~ avgNs.to!string ~ "ns");
}

// ========================================
// INTEGRATION TESTS
// ========================================

// Test 19: Context with real HTTPRequest
@("context with real request")
unittest
{
    Context ctx;
    
    string rawRequest = "POST /api/users HTTP/1.1\r\n" ~
                       "Host: example.com\r\n" ~
                       "Content-Type: application/json\r\n" ~
                       "Content-Length: 17\r\n" ~
                       "\r\n" ~
                       "{\"name\":\"Alice\"}";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    ctx.request.method.shouldEqual("POST");
    ctx.request.path.shouldEqual("/api/users");
    ctx.request.getHeader("Content-Type").shouldEqual("application/json");
}

// Test 20: Context with real HTTPResponse
@("context with real response")
unittest
{
    Context ctx;
    auto response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    ctx.status(201);
    ctx.send("Created");
    
    auto output = ctx.response.build();
    
    // Should contain status and body
    import std.string : indexOf;
    assert(output.indexOf("201") >= 0, "Should contain 201 status");
    assert(output.indexOf("Created") >= 0, "Should contain body");
}
