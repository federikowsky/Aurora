/**
 * Unit tests for Protocol Upgrade Support (V0.6)
 *
 * Tests:
 * - Upgrade detection (isUpgradeRequest, isWebSocketUpgrade, isSSERequest)
 * - RFC 7230 compliance (comma-separated Connection header)
 * - Hijack state management
 * - Exception handling
 */
module tests.unit.web.upgrade_test;

import unit_threaded;
import aurora.web.context;
import aurora.http;

// ============================================================================
// HIJACK STATE TESTS
// ============================================================================

@("hijack - initial state false")
unittest
{
    Context ctx;
    ctx.isHijacked().shouldBeFalse();
}

@("hijack - throws without connection")
unittest
{
    Context ctx;
    ctx.hijack().shouldThrow();
}

@("streamResponse - throws without connection")
unittest
{
    Context ctx;
    ctx.streamResponse().shouldThrow();
}

// ============================================================================
// UPGRADE DETECTION - NULL REQUEST
// ============================================================================

@("isUpgradeRequest - null request returns false")
unittest
{
    Context ctx;
    ctx.request = null;
    ctx.isUpgradeRequest().shouldBeFalse();
}

@("isWebSocketUpgrade - null request returns false")
unittest
{
    Context ctx;
    ctx.request = null;
    ctx.isWebSocketUpgrade().shouldBeFalse();
}

@("isSSERequest - null request returns false")
unittest
{
    Context ctx;
    ctx.request = null;
    ctx.isSSERequest().shouldBeFalse();
}

// ============================================================================
// UPGRADE DETECTION - BASIC CASES
// ============================================================================

@("isUpgradeRequest - detects upgrade header")
unittest
{
    Context ctx;
    
    string rawRequest = "GET /ws HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Connection: upgrade\r\n" ~
                       "Upgrade: websocket\r\n" ~
                       "\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    ctx.isUpgradeRequest().shouldBeTrue();
}

@("isUpgradeRequest - false when no upgrade token")
unittest
{
    Context ctx;
    
    string rawRequest = "GET /api HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Connection: keep-alive\r\n" ~
                       "\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    ctx.isUpgradeRequest().shouldBeFalse();
}

// ============================================================================
// RFC 7230 COMPLIANCE
// ============================================================================

@("isUpgradeRequest - RFC 7230 comma-separated tokens")
unittest
{
    Context ctx;
    
    string rawRequest = "GET /ws HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Connection: keep-alive, upgrade\r\n" ~
                       "Upgrade: websocket\r\n" ~
                       "\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    ctx.isUpgradeRequest().shouldBeTrue();
}

@("isUpgradeRequest - upgrade in middle of list")
unittest
{
    Context ctx;
    
    string rawRequest = "GET /ws HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Connection: keep-alive, upgrade, close\r\n" ~
                       "Upgrade: websocket\r\n" ~
                       "\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    ctx.isUpgradeRequest().shouldBeTrue();
}

@("isUpgradeRequest - case insensitive")
unittest
{
    Context ctx;
    
    string rawRequest = "GET /ws HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Connection: UPGRADE\r\n" ~
                       "Upgrade: websocket\r\n" ~
                       "\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    ctx.isUpgradeRequest().shouldBeTrue();
}

// ============================================================================
// WEBSOCKET UPGRADE TESTS
// ============================================================================

@("isWebSocketUpgrade - detects websocket")
unittest
{
    Context ctx;
    
    string rawRequest = "GET /ws HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Connection: upgrade\r\n" ~
                       "Upgrade: websocket\r\n" ~
                       "\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    ctx.isWebSocketUpgrade().shouldBeTrue();
}

@("isWebSocketUpgrade - case insensitive upgrade header")
unittest
{
    Context ctx;
    
    string rawRequest = "GET /ws HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Connection: upgrade\r\n" ~
                       "Upgrade: WebSocket\r\n" ~
                       "\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    ctx.isWebSocketUpgrade().shouldBeTrue();
}

@("isWebSocketUpgrade - false for non-websocket upgrade")
unittest
{
    Context ctx;
    
    string rawRequest = "GET /h2 HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Connection: upgrade\r\n" ~
                       "Upgrade: h2c\r\n" ~
                       "\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    ctx.isWebSocketUpgrade().shouldBeFalse();
}

// ============================================================================
// SSE REQUEST TESTS
// ============================================================================

@("isSSERequest - detects event-stream accept")
unittest
{
    Context ctx;
    
    string rawRequest = "GET /events HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Accept: text/event-stream\r\n" ~
                       "\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    ctx.isSSERequest().shouldBeTrue();
}

@("isSSERequest - SSE in accept list")
unittest
{
    Context ctx;
    
    string rawRequest = "GET /events HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Accept: application/json, text/event-stream, text/html\r\n" ~
                       "\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    ctx.isSSERequest().shouldBeTrue();
}

@("isSSERequest - case insensitive")
unittest
{
    Context ctx;
    
    string rawRequest = "GET /events HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Accept: TEXT/EVENT-STREAM\r\n" ~
                       "\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    ctx.isSSERequest().shouldBeTrue();
}

@("isSSERequest - false for non-SSE")
unittest
{
    Context ctx;
    
    string rawRequest = "GET /api HTTP/1.1\r\n" ~
                       "Host: localhost\r\n" ~
                       "Accept: application/json\r\n" ~
                       "\r\n";
    
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    ctx.isSSERequest().shouldBeFalse();
}

// ============================================================================
// SSE FORMAT VALIDATION TESTS
// ============================================================================

@("SSE format - data field")
unittest
{
    // SSE data format: "data: <content>\n\n"
    string data = "Hello World";
    string expected = "data: Hello World\n\n";
    
    // Verify format matches SSE spec
    import std.string : format;
    auto formatted = format!"data: %s\n\n"(data);
    formatted.shouldEqual(expected);
}

@("SSE format - event with type")
unittest
{
    // SSE event with type: "event: <type>\ndata: <content>\n\n"
    string eventType = "update";
    string data = `{"value":42}`;
    
    import std.string : format;
    auto formatted = format!"event: %s\ndata: %s\n\n"(eventType, data);
    formatted.shouldEqual("event: update\ndata: {\"value\":42}\n\n");
}

@("SSE format - comment")
unittest
{
    // SSE comment format: ": <comment>\n"
    string comment = "keep-alive";
    
    import std.string : format;
    auto formatted = format!": %s\n"(comment);
    formatted.shouldEqual(": keep-alive\n");
}

@("SSE format - multiline data")
unittest
{
    // SSE multiline: each line needs "data: " prefix
    string[] lines = ["line1", "line2", "line3"];
    
    import std.array : join;
    import std.algorithm : map;
    auto formatted = lines.map!(l => "data: " ~ l).join("\n") ~ "\n\n";
    formatted.shouldEqual("data: line1\ndata: line2\ndata: line3\n\n");
}

@("SSE format - event with id")
unittest
{
    // SSE with ID for reconnection: "id: <id>\ndata: <content>\n\n"
    string id = "msg-123";
    string data = "hello";
    
    import std.string : format;
    auto formatted = format!"id: %s\ndata: %s\n\n"(id, data);
    formatted.shouldEqual("id: msg-123\ndata: hello\n\n");
}
