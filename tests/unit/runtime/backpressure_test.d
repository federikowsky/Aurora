/**
 * Backpressure Tests
 * 
 * Tests for connection limiting and backpressure configuration
 * 
 * Coverage:
 * - ServerConfig backpressure fields
 * - OverloadBehavior enum
 * - Connection water marks
 * - In-flight request limits
 */
module tests.unit.runtime.backpressure_test;

import unit_threaded;
import aurora.runtime.server : ServerConfig, OverloadBehavior;

// ========================================
// CONFIG DEFAULT VALUES
// ========================================

@("default maxConnections is 10000")
unittest
{
    auto config = ServerConfig.defaults();
    config.maxConnections.shouldEqual(10_000);
}

@("default connectionHighWater is 0.8")
unittest
{
    auto config = ServerConfig.defaults();
    config.connectionHighWater.shouldBeGreaterThan(0.79f);
    config.connectionHighWater.shouldBeSmallerThan(0.81f);
}

@("default connectionLowWater is 0.6")
unittest
{
    auto config = ServerConfig.defaults();
    config.connectionLowWater.shouldBeGreaterThan(0.59f);
    config.connectionLowWater.shouldBeSmallerThan(0.61f);
}

@("default maxInFlightRequests is 1000")
unittest
{
    auto config = ServerConfig.defaults();
    config.maxInFlightRequests.shouldEqual(1000);
}

@("default overloadBehavior is reject503")
unittest
{
    auto config = ServerConfig.defaults();
    config.overloadBehavior.shouldEqual(OverloadBehavior.reject503);
}

@("default retryAfterSeconds is 5")
unittest
{
    auto config = ServerConfig.defaults();
    config.retryAfterSeconds.shouldEqual(5);
}

// ========================================
// CUSTOM CONFIGURATION
// ========================================

@("custom maxConnections can be set")
unittest
{
    ServerConfig config;
    config.maxConnections = 50_000;
    config.maxConnections.shouldEqual(50_000);
}

@("maxConnections 0 means unlimited")
unittest
{
    ServerConfig config;
    config.maxConnections = 0;
    config.maxConnections.shouldEqual(0);
}

@("custom water marks can be set")
unittest
{
    ServerConfig config;
    config.connectionHighWater = 0.9f;
    config.connectionLowWater = 0.7f;
    
    config.connectionHighWater.shouldBeGreaterThan(0.89f);
    config.connectionLowWater.shouldBeGreaterThan(0.69f);
}

@("overloadBehavior can be set to closeConnection")
unittest
{
    ServerConfig config;
    config.overloadBehavior = OverloadBehavior.closeConnection;
    config.overloadBehavior.shouldEqual(OverloadBehavior.closeConnection);
}

@("overloadBehavior can be set to queueRequest")
unittest
{
    ServerConfig config;
    config.overloadBehavior = OverloadBehavior.queueRequest;
    config.overloadBehavior.shouldEqual(OverloadBehavior.queueRequest);
}

@("custom retryAfterSeconds can be set")
unittest
{
    ServerConfig config;
    config.retryAfterSeconds = 30;
    config.retryAfterSeconds.shouldEqual(30);
}

// ========================================
// EDGE CASES
// ========================================

@("water marks: low should be less than high")
unittest
{
    auto config = ServerConfig.defaults();
    config.connectionLowWater.shouldBeSmallerThan(config.connectionHighWater);
}

@("maxInFlightRequests 0 means unlimited")
unittest
{
    ServerConfig config;
    config.maxInFlightRequests = 0;
    config.maxInFlightRequests.shouldEqual(0);
}

// ========================================
// OVERLOAD BEHAVIOR ENUM
// ========================================

@("OverloadBehavior has three values")
unittest
{
    // Verify all enum values exist
    auto b1 = OverloadBehavior.reject503;
    auto b2 = OverloadBehavior.closeConnection;
    auto b3 = OverloadBehavior.queueRequest;
    
    // They should be distinct
    b1.shouldNotEqual(b2);
    b2.shouldNotEqual(b3);
    b1.shouldNotEqual(b3);
}
