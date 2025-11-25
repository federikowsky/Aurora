/**
 * Schema Validation Middleware Tests
 *
 * TDD: Aurora Schema Validation Middleware
 *
 * Features:
 * - Request body validation using Schema system
 * - Returns 400 on validation error
 * - Supports JSON and form data
 * - Custom error messages
 */
module tests.unit.web.middleware.validation_test;

import unit_threaded;
import aurora.web.middleware.validation;
import aurora.web.middleware;
import aurora.web.context;
import aurora.http;
// TODO: Complete schema implementation
// import aurora.core.schema;

// Test schema
struct UserSchema
{
    string name;
    int age;
    string email;
}

// ========================================
// VALID BODY PASSES TESTS
// ========================================

// Test 1: Valid JSON body passes
@("valid JSON body passes")
unittest
{
    auto validator = new ValidationMiddleware!UserSchema();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])`{"name":"Alice","age":30,"email":"alice@example.com"}`;
    ctx.request = &req;
    ctx.response = &res;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    validator.handle(ctx, &next);
    
    nextCalled.shouldBeTrue;
}

// Test 2: Validated data stored in context
@("validated data stored in context")
unittest
{
    auto validator = new ValidationMiddleware!UserSchema();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])`{"name":"Bob","age":25,"email":"bob@example.com"}`;
    ctx.request = &req;
    ctx.response = &res;
    
    void next() {
        // Check validated data in context
        auto user = ctx.storage.get!UserSchema("validated");
        user.name.shouldEqual("Bob");
        user.age.shouldEqual(25);
    }
    
    validator.handle(ctx, &next);
}

// Test 3: Nested objects validated
@("nested objects validated")
unittest
{
    struct Address {
        string city;
        string country;
    }
    
    struct UserWithAddress {
        string name;
        Address address;
    }
    
    auto validator = new ValidationMiddleware!UserWithAddress();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])`{"name":"Charlie","address":{"city":"NYC","country":"USA"}}`;
    ctx.request = &req;
    ctx.response = &res;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    validator.handle(ctx, &next);
    
    nextCalled.shouldBeTrue;
}

// Test 4: Arrays validated
@("arrays validated")
unittest
{
    struct UserList {
        string[] names;
    }
    
    auto validator = new ValidationMiddleware!UserList();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])`{"names":["Alice","Bob","Charlie"]}`;
    ctx.request = &req;
    ctx.response = &res;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    validator.handle(ctx, &next);
    
    nextCalled.shouldBeTrue;
}

// Test 5: Optional fields handled
@("optional fields handled")
unittest
{
    struct UserOptional {
        string name;
        int age;
        string email = "";  // Optional with default
    }
    
    auto validator = new ValidationMiddleware!UserOptional();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])`{"name":"Dave","age":35}`;  // No email
    ctx.request = &req;
    ctx.response = &res;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    validator.handle(ctx, &next);
    
    nextCalled.shouldBeTrue;
}

// ========================================
// INVALID BODY REJECTED TESTS
// ========================================

// Test 6: Missing required field
@("missing required field rejected")
unittest
{
    auto validator = new ValidationMiddleware!UserSchema();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])`{"name":"Eve"}`;  // Missing age, email
    ctx.request = &req;
    ctx.response = &res;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    validator.handle(ctx, &next);
    
    nextCalled.shouldBeFalse;
    res.statusCode.shouldEqual(400);
}

// Test 7: Wrong type rejected
@("wrong type rejected")
unittest
{
    auto validator = new ValidationMiddleware!UserSchema();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])`{"name":"Frank","age":"not a number","email":"frank@example.com"}`;
    ctx.request = &req;
    ctx.response = &res;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    validator.handle(ctx, &next);
    
    nextCalled.shouldBeFalse;
    res.statusCode.shouldEqual(400);
}

// Test 8: Extra fields ignored or rejected
@("extra fields handled")
unittest
{
    auto validator = new ValidationMiddleware!UserSchema();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])`{"name":"Grace","age":28,"email":"grace@example.com","extra":"field"}`;
    ctx.request = &req;
    ctx.response = &res;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    validator.handle(ctx, &next);
    
    // Should pass (extra fields ignored)
    nextCalled.shouldBeTrue;
}

// Test 9: Invalid JSON rejected
@("invalid JSON rejected")
unittest
{
    auto validator = new ValidationMiddleware!UserSchema();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])`{invalid json}`;
    ctx.request = &req;
    ctx.response = &res;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    validator.handle(ctx, &next);
    
    nextCalled.shouldBeFalse;
    res.statusCode.shouldEqual(400);
}

// Test 10: Constraint violation rejected
@("constraint violation rejected")
unittest
{
    struct UserWithConstraints {
        string name;
        int age;  // Assume constraint: age > 0
    }
    
    auto validator = new ValidationMiddleware!UserWithConstraints();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])`{"name":"Henry","age":-5}`;
    ctx.request = &req;
    ctx.response = &res;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    validator.handle(ctx, &next);
    
    // Should reject (negative age)
    // Note: This depends on schema constraints implementation
}

// ========================================
// ERROR FORMAT TESTS
// ========================================

// Test 11: Error returns 400 status
@("error returns 400 status")
unittest
{
    auto validator = new ValidationMiddleware!UserSchema();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])`{"invalid":"data"}`;
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    validator.handle(ctx, &next);
    
    res.statusCode.shouldEqual(400);
}

// Test 12: Error message in response
@("error message in response")
unittest
{
    auto validator = new ValidationMiddleware!UserSchema();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])`{}`;
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    validator.handle(ctx, &next);
    
    // Should have error in response body
    assert(res.body.length > 0, "Error message missing");
}

// Test 13: Field errors detailed
@("field errors detailed")
unittest
{
    auto validator = new ValidationMiddleware!UserSchema();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])`{"name":""}`;  // Empty name
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    validator.handle(ctx, &next);
    
    // Error should mention which fields are invalid
    res.statusCode.shouldEqual(400);
}

// Test 14: Custom error messages
@("custom error messages")
unittest
{
    auto validator = new ValidationMiddleware!UserSchema();
    validator.errorMessage = "Invalid user data";
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])`{}`;
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    validator.handle(ctx, &next);
    
    // Should use custom error message
    res.statusCode.shouldEqual(400);
}

// Test 15: JSON error format
@("JSON error format")
unittest
{
    auto validator = new ValidationMiddleware!UserSchema();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])`{}`;
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    validator.handle(ctx, &next);
    
    // Response should be JSON
    import std.string : indexOf;
    auto bodyStr = cast(string)res.body;
    assert(bodyStr.indexOf("error") >= 0 || bodyStr.indexOf("{") >= 0, "Not JSON format");
}

// ========================================
// EDGE CASES
// ========================================

// Test 16: Empty body
@("empty body handled")
unittest
{
    auto validator = new ValidationMiddleware!UserSchema();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])``;
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    // Should not throw
    validator.handle(ctx, &next);
    
    res.statusCode.shouldEqual(400);
}

// Test 17: Null body
@("null body handled")
unittest
{
    auto validator = new ValidationMiddleware!UserSchema();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])`null`;
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    // Should not throw
    validator.handle(ctx, &next);
}

// Test 18: Very large body
@("very large body handled")
unittest
{
    import std.array : replicate;
    
    auto validator = new ValidationMiddleware!UserSchema();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    // Large but valid JSON
    req.body = cast(ubyte[])`{"name":"` ~ replicate("A", 10000) ~ `","age":30,"email":"test@example.com"}`;
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    // Should handle large body
    validator.handle(ctx, &next);
}

// ========================================
// INTEGRATION TESTS
// ========================================

// Test 19: Works with other middleware
@("works with other middleware")
unittest
{
    auto validator = new ValidationMiddleware!UserSchema();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])`{"name":"Ivy","age":32,"email":"ivy@example.com"}`;
    ctx.request = &req;
    ctx.response = &res;
    
    bool otherMiddlewareCalled = false;
    void next() { otherMiddlewareCalled = true; }
    
    validator.handle(ctx, &next);
    
    otherMiddlewareCalled.shouldBeTrue;
}

// Test 20: Validation with Context integration
@("validation with context integration")
unittest
{
    auto validator = new ValidationMiddleware!UserSchema();
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "POST";
    req.body = cast(ubyte[])`{"name":"Jack","age":40,"email":"jack@example.com"}`;
    ctx.request = &req;
    ctx.response = &res;
    
    void next() {
        // Validated data should be in context
        assert(ctx.storage.has("validated"));
    }
    
    validator.handle(ctx, &next);
}
