/**
 * Server Integration Tests - Unit Tests Only
 * 
 * These tests verify ServerConfig and Server creation WITHOUT network I/O.
 * Network tests are in a separate standalone executable.
 * 
 * Coverage:
 * - ServerConfig defaults and custom values
 * - Server creation and initial state
 * - Stats initialization
 */
module tests.integration.server_integration_test;

import unit_threaded;
import aurora.runtime.server;
import aurora.web.router : Router;
import aurora.web.context : Context;

import core.time;

// ========================================
// SERVERCONFIG UNIT TESTS
// ========================================

// Test 1: Default security limits are sensible
@("ServerConfig has sensible default security limits")
unittest
{
    auto config = ServerConfig.defaults();
    
    config.maxHeaderSize.shouldEqual(64 * 1024);
    config.maxBodySize.shouldEqual(10 * 1024 * 1024);
    config.readTimeout.shouldEqual(30.seconds);
    config.writeTimeout.shouldEqual(30.seconds);
    config.keepAliveTimeout.shouldEqual(120.seconds);
    config.maxRequestsPerConnection.shouldEqual(1000);
}

// Test 2: Custom security config
@("ServerConfig accepts custom security limits")
unittest
{
    ServerConfig config;
    config.maxHeaderSize = 8 * 1024;
    config.maxBodySize = 1024 * 1024;
    config.readTimeout = 5.seconds;
    
    config.maxHeaderSize.shouldEqual(8 * 1024);
    config.maxBodySize.shouldEqual(1024 * 1024);
    config.readTimeout.shouldEqual(5.seconds);
}

// Test 3: effectiveWorkers returns CPU count or explicit
@("effectiveWorkers returns proper value")
unittest
{
    ServerConfig config;
    
    // Auto-detect
    config.numWorkers = 0;
    auto workers = config.effectiveWorkers();
    workers.shouldBeGreaterThan(0);
    
    // Explicit
    config.numWorkers = 8;
    config.effectiveWorkers().shouldEqual(8);
}

// ========================================
// SERVER INSTANCE TESTS (no network)
// ========================================

// Test 4: Server can be created with router
@("Server can be created with router")
unittest
{
    auto router = new Router();
    router.get("/", (ref Context ctx) { ctx.send("OK"); });
    
    auto config = ServerConfig.defaults();
    auto server = new Server(router, config);
    
    server.isRunning().shouldBeFalse;
    server.isShuttingDown().shouldBeFalse;
}

// Test 5: Server stats start at zero
@("Server stats start at zero")
unittest
{
    auto router = new Router();
    auto config = ServerConfig.defaults();
    auto server = new Server(router, config);
    
    server.getConnections().shouldEqual(0);
    server.getRequests().shouldEqual(0);
    server.getErrors().shouldEqual(0);
    server.getRejectedHeadersTooLarge().shouldEqual(0);
    server.getRejectedBodyTooLarge().shouldEqual(0);
    server.getRejectedTimeout().shouldEqual(0);
    server.getRejectedDuringShutdown().shouldEqual(0);
}

// Test 6: Server can be created with middleware pipeline
@("Server can be created with router and middleware pipeline")
unittest
{
    import aurora.web.middleware : MiddlewarePipeline;
    
    auto router = new Router();
    router.get("/", (ref Context ctx) { ctx.send("OK"); });
    
    auto pipeline = new MiddlewarePipeline();
    
    auto config = ServerConfig.defaults();
    auto server = new Server(router, pipeline, config);
    
    server.isRunning().shouldBeFalse;
    server.isShuttingDown().shouldBeFalse;
}

// Test 7: Server can be created with request handler
@("Server can be created with simple request handler")
unittest
{
    import aurora.http : HTTPRequest;
    
    void handler(scope HTTPRequest* req, scope ResponseBuffer writer) @trusted
    {
        writer.write(200, "text/plain", "OK");
    }
    
    auto config = ServerConfig.defaults();
    auto server = new Server(&handler, config);
    
    server.isRunning().shouldBeFalse;
}

// Test 8: Server respects custom config
@("Server respects custom configuration")
unittest
{
    auto router = new Router();
    
    ServerConfig config;
    config.port = 9999;
    config.host = "127.0.0.1";
    config.debugMode = true;
    config.maxHeaderSize = 32 * 1024;
    
    auto server = new Server(router, config);
    
    // Server should be created without error
    server.isRunning().shouldBeFalse;
}

// ========================================
// RESPONSE BUFFER TESTS
// ========================================

// Test 9: ResponseBuffer writes data
@("ResponseBuffer writes response data")
unittest
{
    aurora.runtime.server.ResponseBuffer buffer;
    
    buffer.write(200, "text/plain", "Hello World");
    
    auto data = buffer.getData();
    data.shouldNotBeNull;
    assert(data.length > 0, "Response buffer should have data");
    
    // Check response starts with HTTP
    auto str = cast(string)data;
    assert(str.length >= 4);
    str[0..4].shouldEqual("HTTP");
}

// Test 10: ResponseBuffer writeJson
@("ResponseBuffer writes JSON response")
unittest
{
    aurora.runtime.server.ResponseBuffer buffer;
    
    buffer.writeJson(200, `{"status":"ok"}`);
    
    auto data = buffer.getData();
    data.shouldNotBeNull;
    
    auto str = cast(string)data;
    import std.algorithm : canFind;
    assert(str.canFind("application/json"), "Should have JSON content type");
}

// Test 11: ResponseBuffer prevents double write
@("ResponseBuffer prevents double write")
unittest
{
    aurora.runtime.server.ResponseBuffer buffer;
    
    buffer.write(200, "text/plain", "First");
    buffer.write(500, "text/plain", "Second");  // Should be ignored
    
    auto data = buffer.getData();
    auto str = cast(string)data;
    
    // Should contain "First", not "Second"
    import std.algorithm : canFind;
    assert(str.canFind("First"), "Should contain first response");
    assert(!str.canFind("Second"), "Should not contain second response");
}

// ========================================
// SERVER STATE TESTS
// ========================================

// Test 12: Multiple server instances
@("Multiple server instances can coexist")
unittest
{
    auto router1 = new Router();
    auto router2 = new Router();
    
    ServerConfig config1;
    config1.port = 8081;
    
    ServerConfig config2;
    config2.port = 8082;
    
    auto server1 = new Server(router1, config1);
    auto server2 = new Server(router2, config2);
    
    // Both should be created successfully
    server1.isRunning().shouldBeFalse;
    server2.isRunning().shouldBeFalse;
}

// Test 13: Server active connections starts at zero
@("Server active connections starts at zero")
unittest
{
    auto router = new Router();
    auto server = new Server(router);
    
    server.getActiveConnections().shouldEqual(0);
}

// ========================================
// GRACEFUL SHUTDOWN TESTS (Unit Level)
// ========================================
// Note: Full graceful shutdown requires running server + network I/O
// These tests verify the API and state transitions without network

// Test 14: Server has gracefulStop method
@("Server has gracefulStop method")
unittest
{
    auto router = new Router();
    auto server = new Server(router);
    
    // Method should exist and be callable
    // Cannot actually stop a non-running server, but method should exist
    assert(&server.gracefulStop !is null, "gracefulStop method should exist");
}

// Test 15: Server shutdown flag is initially false
@("Server shutdown flag is initially false")
unittest
{
    auto router = new Router();
    auto server = new Server(router);
    
    server.isShuttingDown().shouldBeFalse;
}

// Test 16: Server state after creation
@("Server state after creation")
unittest
{
    auto router = new Router();
    auto server = new Server(router);
    
    // Server should not be running after creation
    server.isRunning().shouldBeFalse;
    server.isShuttingDown().shouldBeFalse;
    
    // Note: Cannot call stop() on non-running server without event loop
    // Full lifecycle test requires integration test with actual server run
}

// Test 17: Server tracks rejected during shutdown count
@("Server tracks rejected during shutdown count")
unittest
{
    auto router = new Router();
    auto server = new Server(router);
    
    // Initial count should be zero
    server.getRejectedDuringShutdown().shouldEqual(0);
}

// Test 18: ServerConfig timeout values
@("ServerConfig has timeout configuration")
unittest
{
    import core.time : seconds;
    
    ServerConfig config;
    
    // Default timeouts
    config.readTimeout.shouldEqual(30.seconds);
    config.writeTimeout.shouldEqual(30.seconds);
    config.keepAliveTimeout.shouldEqual(120.seconds);
    
    // Custom timeouts for graceful shutdown
    config.readTimeout = 5.seconds;
    config.writeTimeout = 5.seconds;
    
    config.readTimeout.shouldEqual(5.seconds);
    config.writeTimeout.shouldEqual(5.seconds);
}

// Test 19: Server stats all start at zero
@("All server stats start at zero")
unittest
{
    auto router = new Router();
    auto server = new Server(router);
    
    server.getConnections().shouldEqual(0);
    server.getActiveConnections().shouldEqual(0);
    server.getRequests().shouldEqual(0);
    server.getErrors().shouldEqual(0);
    server.getRejectedHeadersTooLarge().shouldEqual(0);
    server.getRejectedBodyTooLarge().shouldEqual(0);
    server.getRejectedTimeout().shouldEqual(0);
    server.getRejectedDuringShutdown().shouldEqual(0);
}

// Test 20: Server max requests per connection configuration
@("Server max requests per connection configuration")
unittest
{
    ServerConfig config;
    
    // Default value
    config.maxRequestsPerConnection.shouldEqual(1000);
    
    // Unlimited
    config.maxRequestsPerConnection = 0;
    config.maxRequestsPerConnection.shouldEqual(0);
    
    // High load API server
    config.maxRequestsPerConnection = 100000;
    config.maxRequestsPerConnection.shouldEqual(100000);
}
