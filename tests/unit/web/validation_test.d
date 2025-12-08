/**
 * Schema Validation Middleware Tests
 *
 * TDD: Aurora Schema Validation Middleware
 *
 * Features:
 * - Request body validation using Schema system
 * - Returns 400 on validation error
 * - Supports JSON
 * - Custom error messages
 */
module tests.unit.web.validation_test;

import unit_threaded;
import aurora.web.middleware.validation;
import aurora.web.middleware;
import aurora.web.context;
import aurora.http;
import std.json : parseJSON, JSONValue;

// ========================================
// TEST SCHEMAS
// ========================================

struct SimpleSchema
{
    string name;
    int age;
}

struct SchemaWithDefaults
{
    string name = "Unknown";
    int count = 0;
}

struct NestedSchema
{
    string title;
    SimpleSchema author;
}

struct SchemaWithBool
{
    string name;
    bool active;
}

struct SchemaWithArray
{
    string name;
    string[] tags;
}

// ========================================
// HELPER FUNCTIONS
// ========================================

/// Get header from response
string getHeader(HTTPResponse* response, string headerName)
{
    if (response is null) return "";
    auto headers = response.getHeaders();
    if (auto val = headerName in headers)
        return *val;
    return "";
}

/// Create test context with parsed request
struct TestContext
{
    Context ctx;
    HTTPResponse response;
    HTTPRequest request;
    
    static TestContext createWithBody(string body)
    {
        TestContext tc;
        string rawRequest = 
            "POST /api HTTP/1.1\r\n" ~
            "Host: localhost\r\n" ~
            "Content-Type: application/json\r\n" ~
            "Content-Length: " ~ (cast(int)body.length).stringof ~ "\r\n" ~
            "\r\n" ~
            body;
        tc.request = HTTPRequest.parse(cast(ubyte[])rawRequest);
        tc.response = HTTPResponse(200, "OK");
        tc.ctx.request = &tc.request;
        tc.ctx.response = &tc.response;
        return tc;
    }
    
    static TestContext createEmpty()
    {
        TestContext tc;
        string rawRequest = 
            "POST /api HTTP/1.1\r\n" ~
            "Host: localhost\r\n" ~
            "Content-Length: 0\r\n" ~
            "\r\n";
        tc.request = HTTPRequest.parse(cast(ubyte[])rawRequest);
        tc.response = HTTPResponse(200, "OK");
        tc.ctx.request = &tc.request;
        tc.ctx.response = &tc.response;
        return tc;
    }
}

// ========================================
// VALIDATION FUNCTION TESTS
// ========================================

// Test 1: validateJSON with valid simple schema
@("validateJSON parses valid simple schema")
unittest
{
    auto json = parseJSON(`{"name":"Alice","age":30}`);
    auto result = validateJSON!SimpleSchema(json);
    
    result.name.shouldEqual("Alice");
    result.age.shouldEqual(30);
}

// Test 2: validateJSON with missing field uses default
// NOTE: In D, all types have a default .init value, so missing fields
// get default values (0 for int, "" for string, etc.)
// To enforce required fields, use Nullable!T in the schema
@("validateJSON uses default for missing field")
unittest
{
    auto json = parseJSON(`{"name":"Bob"}`);  // Missing 'age'
    
    // Since int.init = 0, missing 'age' gets 0
    auto result = validateJSON!SimpleSchema(json);
    
    result.name.shouldEqual("Bob");
    result.age.shouldEqual(0);  // Default value
}

// Test 3: validateJSON with wrong type throws
@("validateJSON throws on wrong type")
unittest
{
    auto json = parseJSON(`{"name":"Charlie","age":"thirty"}`);  // age is string, should be int
    
    bool threw = false;
    try {
        validateJSON!SimpleSchema(json);
    } catch (ValidationException e) {
        threw = true;
    }
    
    threw.shouldBeTrue;
}

// Test 4: validateJSON with nested struct
@("validateJSON handles nested structs")
unittest
{
    auto json = parseJSON(`{"title":"Book","author":{"name":"Dave","age":40}}`);
    auto result = validateJSON!NestedSchema(json);
    
    result.title.shouldEqual("Book");
    result.author.name.shouldEqual("Dave");
    result.author.age.shouldEqual(40);
}

// Test 5: validateJSON with boolean true
@("validateJSON handles boolean true")
unittest
{
    auto json = parseJSON(`{"name":"Eve","active":true}`);
    auto result = validateJSON!SchemaWithBool(json);
    
    result.name.shouldEqual("Eve");
    result.active.shouldBeTrue;
}

// Test 6: validateJSON with boolean false
@("validateJSON handles boolean false")
unittest
{
    auto json = parseJSON(`{"name":"Frank","active":false}`);
    auto result = validateJSON!SchemaWithBool(json);
    
    result.name.shouldEqual("Frank");
    result.active.shouldBeFalse;
}

// Test 7: validateJSON with string array
@("validateJSON handles string arrays")
unittest
{
    auto json = parseJSON(`{"name":"Grace","tags":["a","b","c"]}`);
    auto result = validateJSON!SchemaWithArray(json);
    
    result.name.shouldEqual("Grace");
    result.tags.shouldEqual(["a", "b", "c"]);
}

// Test 8: validateJSON with non-object throws
@("validateJSON throws on non-object")
unittest
{
    auto json = parseJSON(`"just a string"`);
    
    bool threw = false;
    try {
        validateJSON!SimpleSchema(json);
    } catch (ValidationException e) {
        threw = true;
    }
    
    threw.shouldBeTrue;
}

// ========================================
// MIDDLEWARE CREATION TESTS
// ========================================

// Test 9: ValidationMiddleware can be created
@("ValidationMiddleware can be created")
unittest
{
    auto validator = new ValidationMiddleware!SimpleSchema();
    
    assert(validator !is null, "Validator middleware should be created");
}

// Test 10: validateRequest helper creates middleware
@("validateRequest helper creates middleware")
unittest
{
    auto middleware = validateRequest!SimpleSchema();
    
    middleware.shouldNotBeNull;
}

// ========================================
// VALIDATION EXCEPTION TESTS
// ========================================

// Test 11: ValidationException can be created
@("ValidationException can be created")
unittest
{
    auto ex = new ValidationException("Test error");
    
    ex.msg.shouldEqual("Test error");
}

// ========================================
// MIDDLEWARE BEHAVIOR TESTS (without real body parsing)
// ========================================

// Test 12: Custom error message
@("custom error message can be set")
unittest
{
    auto validator = new ValidationMiddleware!SimpleSchema();
    validator.errorMessage = "Custom validation error";
    
    validator.errorMessage.shouldEqual("Custom validation error");
}

// Test 13: validateRequest middleware type
@("validateRequest returns correct type")
unittest
{
    Middleware mw = validateRequest!SimpleSchema();
    
    // Should be callable
    mw.shouldNotBeNull;
}

// ========================================
// ARRAY VALIDATION TESTS
// ========================================

// Test 14: Empty array validates
@("empty array validates")
unittest
{
    auto json = parseJSON(`{"name":"Harry","tags":[]}`);
    auto result = validateJSON!SchemaWithArray(json);
    
    result.tags.length.shouldEqual(0);
}

// Test 15: Array with wrong element type throws
@("array with wrong element type throws")
unittest
{
    auto json = parseJSON(`{"name":"Ivy","tags":[1,2,3]}`);  // Numbers instead of strings
    
    bool threw = false;
    try {
        validateJSON!SchemaWithArray(json);
    } catch (ValidationException e) {
        threw = true;
    }
    
    threw.shouldBeTrue;
}

// ========================================
// EDGE CASES
// ========================================

// Test 16: Extra fields in JSON are ignored
@("extra fields in JSON are ignored")
unittest
{
    auto json = parseJSON(`{"name":"Jack","age":25,"extra":"ignored"}`);
    auto result = validateJSON!SimpleSchema(json);
    
    result.name.shouldEqual("Jack");
    result.age.shouldEqual(25);
}

// Test 17: Null context response doesn't crash
@("null context response doesn't crash")
unittest
{
    auto validator = new ValidationMiddleware!SimpleSchema();
    
    Context ctx;
    ctx.response = null;
    ctx.request = null;
    
    // Should not crash even with null pointers
    // (will return early due to null response)
    void next() { }
    
    // This will throw or return early, but shouldn't crash
    try {
        validator.handle(ctx, &next);
    } catch (Exception) {
        // Expected
    }
}

// Test 18: Integer field with zero
@("integer field with zero validates")
unittest
{
    auto json = parseJSON(`{"name":"Kate","age":0}`);
    auto result = validateJSON!SimpleSchema(json);
    
    result.age.shouldEqual(0);
}

// Test 19: Negative integer validates
@("negative integer validates")
unittest
{
    auto json = parseJSON(`{"name":"Leo","age":-5}`);
    auto result = validateJSON!SimpleSchema(json);
    
    result.age.shouldEqual(-5);
}

// Test 20: Unicode in string field
@("unicode in string field validates")
unittest
{
    auto json = parseJSON(`{"name":"日本語","age":20}`);
    auto result = validateJSON!SimpleSchema(json);
    
    result.name.shouldEqual("日本語");
}
