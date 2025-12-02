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
