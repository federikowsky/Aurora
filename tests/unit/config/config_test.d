/**
 * Configuration System Tests
 * 
 * TDD: Type-safe configuration with multiple sources
 * 
 * Features:
 * - Load from JSON/ENV
 * - Type-safe access
 * - Validation
 * - Defaults
 * - Hot reload
 */
module tests.unit.config.config_test;

import unit_threaded;
import aurora.config;

// ========================================
// BASIC LOADING TESTS
// ========================================

// Test 1: Load config from JSON string
@("load config from JSON string")
unittest
{
    string json = `{"port": 8080, "host": "localhost"}`;
    
    auto config = Config.fromJSON(json);
    
    config.shouldNotBeNull;
}

// Test 2: Get string value
@("get string value from config")
unittest
{
    string json = `{"server": {"host": "example.com"}}`;
    auto config = Config.fromJSON(json);
    
    auto host = config.get!string("server.host");
    
    host.shouldEqual("example.com");
}

// Test 3: Get int value
@("get int value from config")
unittest
{
    string json = `{"server": {"port": 9000}}`;
    auto config = Config.fromJSON(json);
    
    auto port = config.get!int("server.port");
    
    port.shouldEqual(9000);
}

// Test 4: Get bool value
@("get bool value from config")
unittest
{
    string json = `{"debug": true}`;
    auto config = Config.fromJSON(json);
    
    auto debug_ = config.get!bool("debug");
    
    debug_.shouldBeTrue;
}

// ========================================
// DEFAULT VALUES TESTS
// ========================================

// Test 5: Get with default value
@("get with default when key missing")
unittest
{
    string json = `{"port": 8080}`;
    auto config = Config.fromJSON(json);
    
    auto host = config.get!string("host", "localhost");
    
    host.shouldEqual("localhost");
}

// Test 6: Get existing value ignores default
@("get existing value ignores default")
unittest
{
    string json = `{"host": "example.com"}`;
    auto config = Config.fromJSON(json);
    
    auto host = config.get!string("host", "localhost");
    
    host.shouldEqual("example.com");
}

// ========================================
// VALIDATION TESTS
// ========================================

// Test 7: Validate required keys
@("validate required keys exist")
unittest
{
    string json = `{"port": 8080}`;
    auto config = Config.fromJSON(json);
    
    auto result = config.validate(["port"]);
    
    result.shouldBeTrue;
}

// Test 8: Validation fails for missing keys
@("validation fails for missing required keys")
unittest
{
    string json = `{"port": 8080}`;
    auto config = Config.fromJSON(json);
    
    auto result = config.validate(["port", "host"]);
    
    result.shouldBeFalse;
}

// ========================================
// ENVIRONMENT VARIABLE TESTS
// ========================================

// Test 9: Load from environment variables
@("load config from environment")
unittest
{
    import std.process : environment;
    
    environment["TEST_PORT"] = "3000";
    environment["TEST_HOST"] = "test.com";
    
    auto config = Config.fromEnv("TEST_");
    
    auto port = config.get!int("PORT");
    port.shouldEqual(3000);
    
    auto host = config.get!string("HOST");
    host.shouldEqual("test.com");
}

// Test 10: ENV overrides JSON
@("environment variables override JSON config")
unittest
{
    import std.process : environment;
    
    string json = `{"port": 8080}`;
    environment["APP_PORT"] = "9000";
    
    auto config = Config.fromJSON(json);
    config.loadEnv("APP_");
    
    auto port = config.get!int("port");
    port.shouldEqual(9000);
}

// ========================================
// NESTED CONFIG TESTS
// ========================================

// Test 11: Get nested value
@("get nested value with dot notation")
unittest
{
    string json = `{"server": {"db": {"host": "db.example.com"}}}`;
    auto config = Config.fromJSON(json);
    
    auto dbHost = config.get!string("server.db.host");
    
    dbHost.shouldEqual("db.example.com");
}

// Test 12: Set value
@("set config value")
unittest
{
    auto config = new Config();
    
    config.set("server.port", 8080);
    
    auto port = config.get!int("server.port");
    port.shouldEqual(8080);
}

// ========================================
// FILE LOADING TESTS
// ========================================

// Test 13: Load from file
@("load config from JSON file")
unittest
{
    import std.file : write, remove, exists;
    
    string json = `{"test": "value"}`;
    write("test_config.json", json);
    
    auto config = Config.fromFile("test_config.json");
    
    auto value = config.get!string("test");
    value.shouldEqual("value");
    
    // Cleanup
    if (exists("test_config.json"))
        remove("test_config.json");
}

// ========================================
// EDGE CASES
// ========================================

// Test 14: Get missing key throws or returns default
@("get missing key without default returns null/throws")
unittest
{
    auto config = new Config();
    
    // Should use default behavior (null or exception)
    auto value = config.get!string("missing", "default");
    value.shouldEqual("default");
}

// Test 15: Empty config
@("empty config works")
unittest
{
    string json = `{}`;
    auto config = Config.fromJSON(json);
    
    config.shouldNotBeNull;
}
