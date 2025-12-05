/**
 * Connection Limits & Statistics Tests
 *
 * Tests for Aurora's connection management:
 * - Active connection tracking
 * - Total connection counting
 * - Request counting per connection
 * - Rejection counter accuracy
 * - Statistics consistency
 *
 * Note: Aurora (V0.5) relies on vibe-core for actual connection limiting.
 * These tests verify the statistics APIs and document current behavior.
 */
module tests.integration.connection_limits_test;

import unit_threaded;
import aurora.runtime.server;
import aurora.runtime.server : OverloadBehavior;
import aurora.web.router;
import aurora.web.context;
import core.atomic;
import core.time;

// ============================================================================
// CONNECTION STATISTICS API TESTS
// ============================================================================

// Test 1: Server has active connections API
@("server has active connections API")
unittest
{
    auto server = createTestServer();
    
    static assert(__traits(compiles, server.getActiveConnections()));
    server.getActiveConnections().shouldEqual(0);
}

// Test 2: Server has total connections API
@("server has total connections API")
unittest
{
    auto server = createTestServer();
    
    static assert(__traits(compiles, server.getConnections()));
    server.getConnections().shouldEqual(0);
}

// Test 3: Server has total requests API
@("server has total requests API")
unittest
{
    auto server = createTestServer();
    
    static assert(__traits(compiles, server.getRequests()));
    server.getRequests().shouldEqual(0);
}

// Test 4: Server has error counter API
@("server has error counter API")
unittest
{
    auto server = createTestServer();
    
    static assert(__traits(compiles, server.getErrors()));
    server.getErrors().shouldEqual(0);
}

// ============================================================================
// REJECTION COUNTER TESTS
// ============================================================================

// Test 5: Header rejection counter exists
@("header rejection counter exists")
unittest
{
    auto server = createTestServer();
    
    static assert(__traits(compiles, server.getRejectedHeadersTooLarge()));
    server.getRejectedHeadersTooLarge().shouldEqual(0);
}

// Test 6: Body rejection counter exists
@("body rejection counter exists")
unittest
{
    auto server = createTestServer();
    
    static assert(__traits(compiles, server.getRejectedBodyTooLarge()));
    server.getRejectedBodyTooLarge().shouldEqual(0);
}

// Test 7: Timeout rejection counter exists
@("timeout rejection counter exists")
unittest
{
    auto server = createTestServer();
    
    static assert(__traits(compiles, server.getRejectedTimeout()));
    server.getRejectedTimeout().shouldEqual(0);
}

// Test 8: Shutdown rejection counter exists
@("shutdown rejection counter exists")
unittest
{
    auto server = createTestServer();
    
    static assert(__traits(compiles, server.getRejectedDuringShutdown()));
    server.getRejectedDuringShutdown().shouldEqual(0);
}

// ============================================================================
// SERVER CONFIG LIMITS TESTS
// ============================================================================

// Test 9: ServerConfig has maxRequestsPerConnection
@("ServerConfig has maxRequestsPerConnection")
unittest
{
    ServerConfig config;
    
    // Default should allow many requests per connection
    config.maxRequestsPerConnection.shouldBeGreaterThan(0);
}

// Test 10: maxRequestsPerConnection can be configured
@("maxRequestsPerConnection can be configured")
unittest
{
    ServerConfig config;
    
    config.maxRequestsPerConnection = 100;
    config.maxRequestsPerConnection.shouldEqual(100);
    
    config.maxRequestsPerConnection = 0;  // 0 = unlimited
    config.maxRequestsPerConnection.shouldEqual(0);
}

// Test 11: ServerConfig has connectionQueueSize
@("ServerConfig has connectionQueueSize")
unittest
{
    ServerConfig config;
    
    config.connectionQueueSize.shouldEqual(4096);  // Default
}

// Test 12: connectionQueueSize can be configured
@("connectionQueueSize can be configured")
unittest
{
    ServerConfig config;
    
    config.connectionQueueSize = 8192;
    config.connectionQueueSize.shouldEqual(8192);
}

// Test 13: ServerConfig has listenBacklog
@("ServerConfig has listenBacklog")
unittest
{
    ServerConfig config;
    
    config.listenBacklog.shouldBeGreaterThan(0);
}

// ============================================================================
// TIMEOUT CONFIGURATION TESTS
// ============================================================================

// Test 14: readTimeout is configurable
@("readTimeout is configurable")
unittest
{
    ServerConfig config;
    
    config.readTimeout = 10.seconds;
    config.readTimeout.total!"seconds".shouldEqual(10);
}

// Test 15: writeTimeout is configurable
@("writeTimeout is configurable")
unittest
{
    ServerConfig config;
    
    config.writeTimeout = 15.seconds;
    config.writeTimeout.total!"seconds".shouldEqual(15);
}

// Test 16: keepAliveTimeout is configurable
@("keepAliveTimeout is configurable")
unittest
{
    ServerConfig config;
    
    config.keepAliveTimeout = 60.seconds;
    config.keepAliveTimeout.total!"seconds".shouldEqual(60);
}

// ============================================================================
// SIZE LIMIT CONFIGURATION TESTS
// ============================================================================

// Test 17: maxHeaderSize is configurable
@("maxHeaderSize is configurable")
unittest
{
    ServerConfig config;
    
    config.maxHeaderSize = 32 * 1024;  // 32KB
    config.maxHeaderSize.shouldEqual(32 * 1024);
}

// Test 18: maxBodySize is configurable
@("maxBodySize is configurable")
unittest
{
    ServerConfig config;
    
    config.maxBodySize = 5 * 1024 * 1024;  // 5MB
    config.maxBodySize.shouldEqual(5 * 1024 * 1024);
}

// ============================================================================
// COUNTER TYPE TESTS
// ============================================================================

// Test 19: All counters return ulong
@("all counters return ulong")
unittest
{
    auto server = createTestServer();
    
    static assert(is(typeof(server.getConnections()) == ulong));
    static assert(is(typeof(server.getActiveConnections()) == ulong));
    static assert(is(typeof(server.getRequests()) == ulong));
    static assert(is(typeof(server.getErrors()) == ulong));
    static assert(is(typeof(server.getRejectedHeadersTooLarge()) == ulong));
    static assert(is(typeof(server.getRejectedBodyTooLarge()) == ulong));
    static assert(is(typeof(server.getRejectedTimeout()) == ulong));
    static assert(is(typeof(server.getRejectedDuringShutdown()) == ulong));
}

// Test 20: Server accepts custom config
@("server accepts custom config")
unittest
{
    auto router = new Router();
    router.get("/", (ref Context ctx) { ctx.send("ok"); });
    
    ServerConfig config;
    config.maxRequestsPerConnection = 50;
    config.maxHeaderSize = 16 * 1024;
    config.maxBodySize = 1024 * 1024;
    config.readTimeout = 5.seconds;
    
    auto server = new Server(router, config);
    server.shouldNotBeNull;
}

// ============================================================================
// BACKPRESSURE API TESTS (V0.6)
// ============================================================================

// Test: Server has isInOverload API
@("server has isInOverload API")
unittest
{
    auto server = createTestServer();
    
    static assert(__traits(compiles, server.isInOverload()));
    server.isInOverload().shouldBeFalse;  // Initially not overloaded
}

// Test: Server has rejectedOverload counter
@("server has rejectedOverload counter")
unittest
{
    auto server = createTestServer();
    
    static assert(__traits(compiles, server.getRejectedOverload()));
    server.getRejectedOverload().shouldEqual(0);
}

// Test: Server has rejectedInFlight counter
@("server has rejectedInFlight counter")
unittest
{
    auto server = createTestServer();
    
    static assert(__traits(compiles, server.getRejectedInFlight()));
    server.getRejectedInFlight().shouldEqual(0);
}

// Test: Server has overloadTransitions counter
@("server has overloadTransitions counter")
unittest
{
    auto server = createTestServer();
    
    static assert(__traits(compiles, server.getOverloadTransitions()));
    server.getOverloadTransitions().shouldEqual(0);
}

// Test: Server has currentInFlightRequests counter
@("server has currentInFlightRequests counter")
unittest
{
    auto server = createTestServer();
    
    static assert(__traits(compiles, server.getCurrentInFlightRequests()));
    server.getCurrentInFlightRequests().shouldEqual(0);
}

// Test: Server has connectionUtilization method
@("server has connectionUtilization method")
unittest
{
    auto server = createTestServer();
    
    static assert(__traits(compiles, server.getConnectionUtilization()));
    auto utilization = server.getConnectionUtilization();
    utilization.shouldBeGreaterThan(-0.1f);
    utilization.shouldBeSmallerThan(1.1f);
}

// Test: Server has water mark getters
@("server has water mark getters")
unittest
{
    auto router = new Router();
    router.get("/", (ref Context ctx) { ctx.send("OK"); });
    
    ServerConfig config;
    config.maxConnections = 1000;
    config.connectionHighWater = 0.8f;
    config.connectionLowWater = 0.6f;
    
    auto server = new Server(router, config);
    
    server.getConnectionHighWaterMark().shouldEqual(800);  // 1000 * 0.8
    server.getConnectionLowWaterMark().shouldEqual(600);   // 1000 * 0.6
}

// Test: Connection utilization is 0 with no connections
@("connection utilization is 0 with no connections")
unittest
{
    auto server = createTestServer();
    server.getConnectionUtilization().shouldEqual(0.0f);
}

// Test: Backpressure config can be customized
@("backpressure config can be customized")
unittest
{
    auto router = new Router();
    router.get("/", (ref Context ctx) { ctx.send("OK"); });
    
    ServerConfig config;
    config.maxConnections = 5000;
    config.connectionHighWater = 0.9f;
    config.connectionLowWater = 0.7f;
    config.maxInFlightRequests = 500;
    config.overloadBehavior = OverloadBehavior.closeConnection;
    config.retryAfterSeconds = 10;
    
    auto server = new Server(router, config);
    server.shouldNotBeNull;
    
    // Verify water marks are calculated correctly
    server.getConnectionHighWaterMark().shouldEqual(4500);  // 5000 * 0.9
    server.getConnectionLowWaterMark().shouldEqual(3500);   // 5000 * 0.7
}

// ============================================================================
// HELPERS
// ============================================================================

/// Create a test server
Server createTestServer()
{
    auto router = new Router();
    
    router.get("/", (ref Context ctx) {
        ctx.send("OK");
    });
    
    router.get("/health", (ref Context ctx) {
        ctx.send(`{"status":"healthy"}`);
    });
    
    return new Server(router);
}
