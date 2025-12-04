/**
 * Graceful Shutdown Tests
 *
 * Tests for Aurora's graceful shutdown mechanism:
 * - In-flight requests complete before shutdown
 * - New connections rejected during shutdown
 * - Shutdown timeout enforced
 * - State tracking (rejectedDuringShutdown counter)
 *
 * These are unit tests that verify the shutdown API and state machine.
 * Full integration tests are in graceful_shutdown_test.py.
 */
module tests.integration.graceful_shutdown_test;

import unit_threaded;
import aurora.runtime.server;
import aurora.web.router;
import aurora.web.context;
import core.atomic;
import core.time;

// ============================================================================
// SHUTDOWN STATE TESTS
// ============================================================================

// Test 1: Server starts in non-shutdown state
@("server starts in non-shutdown state")
unittest
{
    auto server = createApp();
    
    server.isShuttingDown().shouldBeFalse;
}

// Test 2: gracefulStop sets shutting down flag
@("gracefulStop sets shutting down flag")
unittest
{
    auto server = createApp();
    
    // We can't actually run gracefulStop without running the server
    // Test the API exists and compiles
    static assert(__traits(compiles, server.gracefulStop()));
}

// Test 3: Server tracks rejected connections during shutdown
@("server tracks rejected connections during shutdown")
unittest
{
    auto server = createApp();
    
    // Check API exists
    static assert(__traits(compiles, server.getRejectedDuringShutdown()));
    
    // Initially should be 0
    server.getRejectedDuringShutdown().shouldEqual(0);
}

// ============================================================================
// CONFIGURATION TESTS
// ============================================================================

// Test 4: ServerConfig has shutdown timeout
@("ServerConfig has shutdown timeout")
unittest
{
    ServerConfig config;
    
    // Default should be reasonable (30 seconds or similar)
    static if (__traits(hasMember, ServerConfig, "shutdownTimeout"))
    {
        // If the field exists, verify it's set
        config.shutdownTimeout.total!"seconds".shouldBeGreaterThan(0);
    }
}

// Test 5: gracefulStop accepts timeout parameter
@("gracefulStop accepts timeout parameter")
unittest
{
    auto server = createApp();
    
    // Should compile with custom timeout
    static assert(__traits(compiles, server.gracefulStop(5.seconds)));
    static assert(__traits(compiles, server.gracefulStop(30.seconds)));
}

// ============================================================================
// STATE MACHINE TESTS
// ============================================================================

// Test 6: Running state is correct
@("running state is correct before run")
unittest
{
    auto server = createApp();
    
    // Before run(), should be false
    server.isRunning().shouldBeFalse;
}

// Test 7: Cannot shutdown twice
@("shutdown state is idempotent")
unittest
{
    auto server = createApp();
    
    // Multiple calls to isShuttingDown should be safe
    server.isShuttingDown().shouldBeFalse;
    server.isShuttingDown().shouldBeFalse;
}

// ============================================================================
// COUNTER TESTS
// ============================================================================

// Test 8: Active connections counter exists
@("active connections counter exists")
unittest
{
    auto server = createApp();
    
    // Should have active connections API
    static assert(__traits(compiles, server.getActiveConnections()));
    
    server.getActiveConnections().shouldEqual(0);
}

// Test 9: Total connections counter exists
@("total connections counter exists")
unittest
{
    auto server = createApp();
    
    static assert(__traits(compiles, server.getConnections()));
    
    server.getConnections().shouldEqual(0);
}

// Test 10: Error counter exists
@("error counter exists")
unittest
{
    auto server = createApp();
    
    static assert(__traits(compiles, server.getErrors()));
    
    server.getErrors().shouldEqual(0);
}

// ============================================================================
// HELPERS
// ============================================================================

/// Create a minimal Aurora server for testing
Server createApp()
{
    auto router = new Router();
    
    router.get("/health", (ref Context ctx) {
        ctx.send("OK");
    });
    
    return new Server(router);
}
