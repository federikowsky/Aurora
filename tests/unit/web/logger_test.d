/**
 * Logger Middleware Tests
 *
 * TDD: Aurora Logger Middleware
 *
 * Features:
 * - Request/response logging (Gin-style colored output)
 * - Duration measurement
 * - Configurable format (SIMPLE, JSON, COLORED)
 * - Log level filtering
 */
module tests.unit.web.logger_test;

import unit_threaded;
import aurora.web.middleware.logger;
import aurora.web.middleware;
import aurora.web.context;
import aurora.http;

// ========================================
// HELPER FUNCTIONS
// ========================================

/// Create test context with parsed request
struct TestContext
{
    Context ctx;
    HTTPResponse response;
    HTTPRequest request;
    
    static TestContext create(string rawRequest = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
    {
        TestContext tc;
        tc.request = HTTPRequest.parse(cast(ubyte[])rawRequest);
        tc.response = HTTPResponse(200, "OK");
        tc.ctx.request = &tc.request;
        tc.ctx.response = &tc.response;
        return tc;
    }
}

// ========================================
// LOGGER CREATION TESTS
// ========================================

// Test 1: LoggerMiddleware can be created with default log function
@("LoggerMiddleware can be created")
unittest
{
    auto logger = new LoggerMiddleware();
    
    assert(logger !is null, "Logger middleware should be created");
}

// Test 2: LoggerMiddleware can be created with custom log function
@("LoggerMiddleware with custom log function")
unittest
{
    string capturedLog;
    auto logger = new LoggerMiddleware((string msg) {
        capturedLog = msg;
    });
    
    assert(logger !is null, "Logger middleware should be created");
}

// Test 3: loggerMiddleware helper creates middleware
@("loggerMiddleware helper creates middleware")
unittest
{
    auto middleware = loggerMiddleware();
    
    middleware.shouldNotBeNull;
}

// ========================================
// LOGGING BEHAVIOR TESTS
// ========================================

// Test 4: Logger logs something
@("logger logs request")
unittest
{
    string capturedLog;
    auto logger = new LoggerMiddleware((string msg) {
        capturedLog = msg;
    });
    logger.format = LogFormat.SIMPLE;  // Use simple format for predictable output
    
    auto tc = TestContext.create("GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n");
    
    void next() { }
    
    logger.handle(tc.ctx, &next);
    
    capturedLog.length.shouldBeGreaterThan(0);
}

// Test 5: Logger calls next()
@("logger calls next")
unittest
{
    auto logger = new LoggerMiddleware((string msg) { });
    
    auto tc = TestContext.create();
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    logger.handle(tc.ctx, &next);
    
    nextCalled.shouldBeTrue;
}

// Test 6: Logger includes method in SIMPLE format
@("SIMPLE format includes method")
unittest
{
    string capturedLog;
    auto logger = new LoggerMiddleware((string msg) {
        capturedLog = msg;
    });
    logger.format = LogFormat.SIMPLE;
    
    auto tc = TestContext.create("GET /api HTTP/1.1\r\nHost: localhost\r\n\r\n");
    
    void next() { }
    
    logger.handle(tc.ctx, &next);
    
    import std.string : indexOf;
    capturedLog.indexOf("GET").shouldBeGreaterThan(-1);
}

// Test 7: Logger includes path in SIMPLE format
@("SIMPLE format includes path")
unittest
{
    string capturedLog;
    auto logger = new LoggerMiddleware((string msg) {
        capturedLog = msg;
    });
    logger.format = LogFormat.SIMPLE;
    
    auto tc = TestContext.create("GET /api/users HTTP/1.1\r\nHost: localhost\r\n\r\n");
    
    void next() { }
    
    logger.handle(tc.ctx, &next);
    
    import std.string : indexOf;
    capturedLog.indexOf("/api/users").shouldBeGreaterThan(-1);
}

// Test 8: Logger includes status code
@("SIMPLE format includes status code")
unittest
{
    string capturedLog;
    auto logger = new LoggerMiddleware((string msg) {
        capturedLog = msg;
    });
    logger.format = LogFormat.SIMPLE;
    
    auto tc = TestContext.create();
    tc.response.setStatus(201);
    
    void next() { }
    
    logger.handle(tc.ctx, &next);
    
    import std.string : indexOf;
    capturedLog.indexOf("201").shouldBeGreaterThan(-1);
}

// ========================================
// FORMAT TESTS
// ========================================

// Test 9: JSON format produces JSON
@("JSON format produces JSON")
unittest
{
    string capturedLog;
    auto logger = new LoggerMiddleware((string msg) {
        capturedLog = msg;
    });
    logger.format = LogFormat.JSON;
    
    auto tc = TestContext.create("GET /api HTTP/1.1\r\nHost: localhost\r\n\r\n");
    
    void next() { }
    
    logger.handle(tc.ctx, &next);
    
    // Should start with { and end with }
    capturedLog[0].shouldEqual('{');
    capturedLog[$-1].shouldEqual('}');
}

// Test 10: JSON format includes expected fields
@("JSON format includes expected fields")
unittest
{
    string capturedLog;
    auto logger = new LoggerMiddleware((string msg) {
        capturedLog = msg;
    });
    logger.format = LogFormat.JSON;
    
    auto tc = TestContext.create("POST /api HTTP/1.1\r\nHost: localhost\r\n\r\n");
    
    void next() { }
    
    logger.handle(tc.ctx, &next);
    
    import std.string : indexOf;
    capturedLog.indexOf(`"method":"POST"`).shouldBeGreaterThan(-1);
    capturedLog.indexOf(`"path":"/api"`).shouldBeGreaterThan(-1);
    capturedLog.indexOf(`"status":`).shouldBeGreaterThan(-1);
    capturedLog.indexOf(`"duration_us":`).shouldBeGreaterThan(-1);
}

// Test 11: COLORED format has timestamp
@("COLORED format has timestamp")
unittest
{
    string capturedLog;
    auto logger = new LoggerMiddleware((string msg) {
        capturedLog = msg;
    });
    logger.format = LogFormat.COLORED;
    logger.useColors = false;  // Disable ANSI codes for easier testing
    
    auto tc = TestContext.create();
    
    void next() { }
    
    logger.handle(tc.ctx, &next);
    
    import std.string : indexOf;
    // Should have date format YYYY/MM/DD
    capturedLog.indexOf("/").shouldBeGreaterThan(-1);
}

// ========================================
// NULL SAFETY TESTS
// ========================================

// Test 12: Logger handles null request
@("logger handles null request")
unittest
{
    string capturedLog;
    auto logger = new LoggerMiddleware((string msg) {
        capturedLog = msg;
    });
    logger.format = LogFormat.SIMPLE;
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    ctx.request = null;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    // Should not crash
    logger.handle(ctx, &next);
    
    nextCalled.shouldBeTrue;
    // Should log "UNKNOWN" for method
    import std.string : indexOf;
    capturedLog.indexOf("UNKNOWN").shouldBeGreaterThan(-1);
}

// Test 13: Logger handles null response
@("logger handles null response")
unittest
{
    string capturedLog;
    auto logger = new LoggerMiddleware((string msg) {
        capturedLog = msg;
    });
    logger.format = LogFormat.SIMPLE;
    
    auto tc = TestContext.create();
    tc.ctx.response = null;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    // Should not crash
    logger.handle(tc.ctx, &next);
    
    nextCalled.shouldBeTrue;
}

// ========================================
// DURATION MEASUREMENT TESTS
// ========================================

// Test 14: Duration is measured
@("duration is measured")
unittest
{
    string capturedLog;
    auto logger = new LoggerMiddleware((string msg) {
        capturedLog = msg;
    });
    logger.format = LogFormat.SIMPLE;
    
    auto tc = TestContext.create();
    
    void next() {
        // Simulate some work
        import core.thread : Thread;
        import core.time : msecs;
        Thread.sleep(1.msecs);
    }
    
    logger.handle(tc.ctx, &next);
    
    import std.string : indexOf;
    // Should contain duration indicator (μs or ms)
    (capturedLog.indexOf("μs") > -1 || capturedLog.indexOf("ms") > -1).shouldBeTrue;
}

// ========================================
// ERROR HANDLING TESTS
// ========================================

// Test 15: Logger logs errors and re-throws
@("logger logs errors and re-throws")
unittest
{
    string capturedLog;
    auto logger = new LoggerMiddleware((string msg) {
        capturedLog = msg;
    });
    logger.format = LogFormat.SIMPLE;
    
    auto tc = TestContext.create();
    
    void next() {
        throw new Exception("Test error");
    }
    
    bool exceptionCaught = false;
    try {
        logger.handle(tc.ctx, &next);
    } catch (Exception e) {
        exceptionCaught = true;
    }
    
    exceptionCaught.shouldBeTrue;
    // Should have logged with status 500
    import std.string : indexOf;
    capturedLog.indexOf("500").shouldBeGreaterThan(-1);
}

// ========================================
// COLOR SETTING TESTS
// ========================================

// Test 16: Colors can be disabled
@("colors can be disabled")
unittest
{
    auto logger = new LoggerMiddleware();
    logger.useColors = false;
    
    logger.useColors.shouldBeFalse;
}

// Test 17: Colors are enabled by default
@("colors enabled by default")
unittest
{
    auto logger = new LoggerMiddleware();
    
    logger.useColors.shouldBeTrue;
}

// ========================================
// DIFFERENT HTTP METHODS
// ========================================

// Test 18: POST method logged
@("POST method logged")
unittest
{
    string capturedLog;
    auto logger = new LoggerMiddleware((string msg) {
        capturedLog = msg;
    });
    logger.format = LogFormat.SIMPLE;
    
    auto tc = TestContext.create("POST /api HTTP/1.1\r\nHost: localhost\r\n\r\n");
    
    void next() { }
    
    logger.handle(tc.ctx, &next);
    
    import std.string : indexOf;
    capturedLog.indexOf("POST").shouldBeGreaterThan(-1);
}

// Test 19: PUT method logged
@("PUT method logged")
unittest
{
    string capturedLog;
    auto logger = new LoggerMiddleware((string msg) {
        capturedLog = msg;
    });
    logger.format = LogFormat.SIMPLE;
    
    auto tc = TestContext.create("PUT /api HTTP/1.1\r\nHost: localhost\r\n\r\n");
    
    void next() { }
    
    logger.handle(tc.ctx, &next);
    
    import std.string : indexOf;
    capturedLog.indexOf("PUT").shouldBeGreaterThan(-1);
}

// Test 20: DELETE method logged
@("DELETE method logged")
unittest
{
    string capturedLog;
    auto logger = new LoggerMiddleware((string msg) {
        capturedLog = msg;
    });
    logger.format = LogFormat.SIMPLE;
    
    auto tc = TestContext.create("DELETE /api HTTP/1.1\r\nHost: localhost\r\n\r\n");
    
    void next() { }
    
    logger.handle(tc.ctx, &next);
    
    import std.string : indexOf;
    capturedLog.indexOf("DELETE").shouldBeGreaterThan(-1);
}
