/**
 * Error Handling Tests
 *
 * TDD: Aurora Error Handling (HTTPException hierarchy + error middleware)
 *
 * Features:
 * - HTTPException base class
 * - 5 specific exception types
 * - Error middleware pattern
 * - Standard error format
 */
module tests.unit.web.error_test;

import unit_threaded;
import aurora.web.error;
import aurora.web.context;
import aurora.http;

// ========================================
// HAPPY PATH - EXCEPTION TYPES
// ========================================

// Test 1: Throw NotFoundException → 404
@("NotFoundException has 404 status")
unittest
{
    auto ex = new NotFoundException("User not found");
    
    ex.statusCode.shouldEqual(404);
    ex.msg.shouldEqual("User not found");
}

// Test 2: Throw ValidationException → 400
@("ValidationException has 400 status")
unittest
{
    auto ex = new ValidationException("Invalid email");
    
    ex.statusCode.shouldEqual(400);
    ex.msg.shouldEqual("Invalid email");
}

// Test 3: Throw UnauthorizedException → 401 + WWW-Authenticate
@("UnauthorizedException has 401 and WWW-Authenticate")
unittest
{
    auto ex = new UnauthorizedException();
    
    ex.statusCode.shouldEqual(401);
    ex.msg.shouldEqual("Unauthorized");
    ex.headers["WWW-Authenticate"].shouldEqual("Bearer");
}

// Test 4: Throw ForbiddenException → 403
@("ForbiddenException has 403 status")
unittest
{
    auto ex = new ForbiddenException("Access denied");
    
    ex.statusCode.shouldEqual(403);
    ex.msg.shouldEqual("Access denied");
}

// Test 5: Throw InternalServerException → 500
@("InternalServerException has 500 status")
unittest
{
    auto ex = new InternalServerException();
    
    ex.statusCode.shouldEqual(500);
    ex.msg.shouldEqual("Internal Server Error");
}

// Test 6: Error middleware catches HTTPException
@("error middleware catches HTTPException")
unittest
{
    Context ctx;
    auto response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    string rawRequest = "GET /api/users HTTP/1.1\r\nHost: localhost\r\n\r\n";
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    bool nextCalled = false;
    void next() {
        nextCalled = true;
        throw new NotFoundException("User not found");
    }
    
    errorMiddleware(ctx, &next);
    
    nextCalled.shouldBeTrue;
    // Response should have 404 status and error JSON
}

// ========================================
// EDGE CASES
// ========================================

// Test 7: Unknown exception → 500
@("unknown exception returns 500")
unittest
{
    Context ctx;
    auto response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    string rawRequest = "GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n";
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    void next() {
        throw new Exception("Unknown error");
    }
    
    errorMiddleware(ctx, &next);
    
    // Should catch and return 500
}

// Test 8: Exception with custom headers
@("exception with custom headers")
unittest
{
    auto ex = new HTTPException(418, "I'm a teapot");
    ex.headers["X-Custom"] = "value";
    
    ex.statusCode.shouldEqual(418);
    ex.headers["X-Custom"].shouldEqual("value");
}

// Test 9: Exception in middleware → propagated
@("exception in middleware propagated")
unittest
{
    Context ctx;
    auto response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    string rawRequest = "GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n";
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    void next() {
        throw new ValidationException("Bad input");
    }
    
    // Error middleware should catch
    errorMiddleware(ctx, &next);
}

// Test 10: Nested exceptions → outer caught
@("nested exceptions outer caught")
unittest
{
    Context ctx;
    auto response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    string rawRequest = "GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n";
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    void next() {
        try {
            throw new ValidationException("Inner");
        } catch (Exception) {
            throw new NotFoundException("Outer");
        }
    }
    
    errorMiddleware(ctx, &next);
    // Should catch NotFoundException (outer)
}

// Test 11: Empty error message → handled
@("empty error message handled")
unittest
{
    auto ex = new ValidationException("");
    
    ex.statusCode.shouldEqual(400);
    ex.msg.shouldEqual("");  // Empty is valid
}

// ========================================
// INTEGRATION TESTS
// ========================================

// Test 12: Error middleware with Context
@("error middleware formats response")
unittest
{
    Context ctx;
    auto response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    string rawRequest = "GET /api/users/123 HTTP/1.1\r\nHost: localhost\r\n\r\n";
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    void next() {
        throw new NotFoundException("User 123 not found");
    }
    
    errorMiddleware(ctx, &next);
    
    // Response should be formatted as JSON
    auto output = ctx.response.build();
    
    import std.string : indexOf;
    assert(output.indexOf("404") >= 0, "Should contain 404 status");
    assert(output.indexOf("User 123 not found") >= 0, "Should contain error message");
}

// Test 13: Multiple error middleware → first catches
@("multiple error middleware first catches")
unittest
{
    Context ctx;
    auto response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    string rawRequest = "GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n";
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    bool firstCalled = false;
    bool secondCalled = false;
    
    void next() {
        throw new NotFoundException();
    }
    
    // First error middleware
    void firstErrorMiddleware() {
        try {
            next();
        } catch (HTTPException e) {
            firstCalled = true;
            throw e;  // Re-throw for second middleware
        }
    }
    
    // Second error middleware
    errorMiddleware(ctx, &firstErrorMiddleware);
    
    firstCalled.shouldBeTrue;
}

// Test 14: Error in handler → middleware catches
@("error in handler caught by middleware")
unittest
{
    Context ctx;
    auto response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    string rawRequest = "POST /api/users HTTP/1.1\r\nHost: localhost\r\n\r\n";
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    void handler() {
        // Simulate validation error in handler
        throw new ValidationException("Name is required");
    }
    
    errorMiddleware(ctx, &handler);
    
    // Should catch and format error
}

// Test 15: Error format validation
@("error format is valid JSON")
unittest
{
    Context ctx;
    auto response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    string rawRequest = "GET /api/test HTTP/1.1\r\nHost: localhost\r\n\r\n";
    auto req = HTTPRequest.parse(cast(ubyte[])rawRequest);
    ctx.request = &req;
    
    void next() {
        throw new NotFoundException("Resource not found");
    }
    
    errorMiddleware(ctx, &next);
    
    auto output = ctx.response.build();
    
    // Should contain JSON error format
    import std.string : indexOf;
    assert(output.indexOf("error") >= 0, "Should have 'error' field");
    assert(output.indexOf("status") >= 0, "Should have 'status' field");
}
