/**
 * ServerConfig Tests
 * 
 * Tests for configurable security limits and server configuration
 * 
 * Coverage:
 * - Default values
 * - Custom configuration
 * - Edge cases for limits
 * - effectiveWorkers() calculation
 */
module tests.unit.runtime.server_config_test;

import unit_threaded;
import aurora.runtime.server : ServerConfig;
import core.time : seconds, msecs;

// ========================================
// DEFAULT VALUES TESTS
// ========================================

// Test 1: Default host and port
@("default host is 0.0.0.0 and port is 8080")
unittest
{
    auto config = ServerConfig.defaults();
    
    config.host.shouldEqual("0.0.0.0");
    config.port.shouldEqual(8080);
}

// Test 2: Default security limits
@("default security limits are set")
unittest
{
    auto config = ServerConfig.defaults();
    
    // Header size: 64KB
    config.maxHeaderSize.shouldEqual(64 * 1024);
    
    // Body size: 10MB
    config.maxBodySize.shouldEqual(10 * 1024 * 1024);
    
    // Timeouts
    config.readTimeout.shouldEqual(30.seconds);
    config.writeTimeout.shouldEqual(30.seconds);
    config.keepAliveTimeout.shouldEqual(120.seconds);
    
    // Max requests per connection
    config.maxRequestsPerConnection.shouldEqual(1000);
}

// Test 3: Default worker settings
@("default worker settings")
unittest
{
    auto config = ServerConfig.defaults();
    
    config.numWorkers.shouldEqual(0);  // Auto-detect
    config.connectionQueueSize.shouldEqual(4096);
    config.listenBacklog.shouldEqual(1024);
    config.debugMode.shouldBeFalse;
}

// ========================================
// CUSTOM CONFIGURATION TESTS
// ========================================

// Test 4: Custom host and port
@("custom host and port can be set")
unittest
{
    ServerConfig config;
    config.host = "127.0.0.1";
    config.port = 9000;
    
    config.host.shouldEqual("127.0.0.1");
    config.port.shouldEqual(9000);
}

// Test 5: Custom security limits
@("custom security limits can be set")
unittest
{
    ServerConfig config;
    config.maxHeaderSize = 32 * 1024;  // 32KB
    config.maxBodySize = 1024 * 1024;  // 1MB
    config.readTimeout = 10.seconds;
    config.writeTimeout = 15.seconds;
    config.keepAliveTimeout = 60.seconds;
    config.maxRequestsPerConnection = 500;
    
    config.maxHeaderSize.shouldEqual(32 * 1024);
    config.maxBodySize.shouldEqual(1024 * 1024);
    config.readTimeout.shouldEqual(10.seconds);
    config.writeTimeout.shouldEqual(15.seconds);
    config.keepAliveTimeout.shouldEqual(60.seconds);
    config.maxRequestsPerConnection.shouldEqual(500);
}

// Test 6: Custom worker count
@("custom worker count can be set")
unittest
{
    ServerConfig config;
    config.numWorkers = 8;
    
    config.numWorkers.shouldEqual(8);
    config.effectiveWorkers().shouldEqual(8);
}

// ========================================
// effectiveWorkers() TESTS
// ========================================

// Test 7: effectiveWorkers with explicit count
@("effectiveWorkers returns explicit count when set")
unittest
{
    ServerConfig config;
    config.numWorkers = 16;
    
    config.effectiveWorkers().shouldEqual(16);
}

// Test 8: effectiveWorkers auto-detects when 0
@("effectiveWorkers auto-detects CPU count when numWorkers is 0")
unittest
{
    ServerConfig config;
    config.numWorkers = 0;
    
    auto workers = config.effectiveWorkers();
    
    // Should return at least 1 worker
    workers.shouldBeGreaterThan(0);
    
    // Should not return an unreasonable number
    assert(workers < 256, "Unreasonably high worker count detected");
}

// ========================================
// EDGE CASES
// ========================================

// Test 9: Zero header size (should still be valid config)
@("zero header size is valid config")
unittest
{
    ServerConfig config;
    config.maxHeaderSize = 0;
    
    config.maxHeaderSize.shouldEqual(0);
}

// Test 10: Very large body size
@("very large body size can be set")
unittest
{
    ServerConfig config;
    config.maxBodySize = 1024 * 1024 * 1024;  // 1GB
    
    config.maxBodySize.shouldEqual(1024 * 1024 * 1024);
}

// Test 11: Zero timeout (no timeout)
@("zero timeout can be set")
unittest
{
    ServerConfig config;
    config.readTimeout = 0.seconds;
    
    config.readTimeout.shouldEqual(0.seconds);
}

// Test 12: Very short timeout
@("millisecond timeout can be set")
unittest
{
    ServerConfig config;
    config.readTimeout = 100.msecs;
    
    config.readTimeout.shouldEqual(100.msecs);
}

// Test 13: Unlimited requests per connection
@("unlimited requests per connection when set to 0")
unittest
{
    ServerConfig config;
    config.maxRequestsPerConnection = 0;
    
    config.maxRequestsPerConnection.shouldEqual(0);
}

// Test 14: Single worker
@("single worker configuration")
unittest
{
    ServerConfig config;
    config.numWorkers = 1;
    
    config.effectiveWorkers().shouldEqual(1);
}

// ========================================
// PRODUCTION-LIKE CONFIGURATIONS
// ========================================

// Test 15: High-security configuration
@("high security configuration")
unittest
{
    ServerConfig config;
    config.maxHeaderSize = 8 * 1024;      // 8KB - minimal headers
    config.maxBodySize = 1024 * 1024;     // 1MB - small payloads
    config.readTimeout = 5.seconds;        // Short timeout
    config.writeTimeout = 5.seconds;
    config.keepAliveTimeout = 30.seconds;
    config.maxRequestsPerConnection = 100;
    
    // All values should be set
    config.maxHeaderSize.shouldEqual(8 * 1024);
    config.maxBodySize.shouldEqual(1024 * 1024);
    config.readTimeout.shouldEqual(5.seconds);
}

// Test 16: File upload server configuration
@("file upload server configuration")
unittest
{
    ServerConfig config;
    config.maxHeaderSize = 64 * 1024;          // Normal headers
    config.maxBodySize = 100 * 1024 * 1024;    // 100MB uploads
    config.readTimeout = 300.seconds;           // 5 min for slow uploads
    config.writeTimeout = 60.seconds;
    
    config.maxBodySize.shouldEqual(100 * 1024 * 1024);
    config.readTimeout.shouldEqual(300.seconds);
}

// Test 17: API gateway configuration
@("API gateway configuration")
unittest
{
    ServerConfig config;
    config.host = "0.0.0.0";
    config.port = 80;
    config.numWorkers = 32;
    config.connectionQueueSize = 8192;
    config.maxHeaderSize = 16 * 1024;
    config.maxBodySize = 5 * 1024 * 1024;
    config.readTimeout = 30.seconds;
    config.keepAliveTimeout = 300.seconds;
    config.maxRequestsPerConnection = 10000;
    
    config.numWorkers.shouldEqual(32);
    config.connectionQueueSize.shouldEqual(8192);
    config.maxRequestsPerConnection.shouldEqual(10000);
}
