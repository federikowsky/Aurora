/**
 * Form Data Parsing Tests — RFC Compliance & Security
 *
 * Test suite for aurora.http.form module covering:
 * - application/x-www-form-urlencoded parsing (RFC 1866 / HTML 4.01)
 * - OWASP security considerations
 * - Edge cases
 *
 * References:
 * - HTML 4.01 Section 17.13.4: Form content types
 * - RFC 1866: Hypertext Markup Language - 2.0
 */
module tests.unit.http.form_test;

import aurora.http.form;

// ════════════════════════════════════════════════════════════════════════════════
// BASIC FUNCTIONALITY TESTS
// ════════════════════════════════════════════════════════════════════════════════

/**
 * Basic field extraction
 */
@("Basic: Single field extraction")
unittest
{
    assert(getFormField("name=John", "name") == "John");
    assert(getFormField("email=test@example.com", "email") == "test@example.com");
    assert(getFormField("value=123", "value") == "123");
}

/**
 * Multiple fields
 */
@("Basic: Multiple field extraction")
unittest
{
    immutable data = "name=John&age=30&city=Rome";
    
    assert(getFormField(data, "name") == "John");
    assert(getFormField(data, "age") == "30");
    assert(getFormField(data, "city") == "Rome");
}

/**
 * Default values
 */
@("Basic: Default value for missing fields")
unittest
{
    assert(getFormField("a=1", "missing") == "");
    assert(getFormField("a=1", "missing", "default") == "default");
    assert(getFormField("a=1", "missing", "N/A") == "N/A");
}

/**
 * URL decoding in form fields
 */
@("Basic: URL decoding of field values")
unittest
{
    // Percent encoding
    assert(getFormField("email=test%40example.com", "email") == "test@example.com");
    assert(getFormField("path=%2Fhome%2Fuser", "path") == "/home/user");
    assert(getFormField("query=a%3D1%26b%3D2", "query") == "a=1&b=2");
    
    // Plus as space (form encoding)
    assert(getFormField("name=John+Doe", "name") == "John Doe");
    assert(getFormField("message=Hello+World%21", "message") == "Hello World!");
}

// ════════════════════════════════════════════════════════════════════════════════
// MULTI-VALUE FIELD TESTS
// ════════════════════════════════════════════════════════════════════════════════

/**
 * Multi-value fields (same key multiple times)
 */
@("Multi-value: Array of values for same key")
unittest
{
    assert(getFormFieldAll("tag=red&tag=blue&tag=green", "tag") == ["red", "blue", "green"]);
    assert(getFormFieldAll("item=1&item=2&item=3", "item") == ["1", "2", "3"]);
}

/**
 * Multi-value with other fields in between
 */
@("Multi-value: Non-contiguous same keys")
unittest
{
    assert(getFormFieldAll("a=1&b=2&a=3&c=4&a=5", "a") == ["1", "3", "5"]);
}

/**
 * Multi-value empty result
 */
@("Multi-value: Missing key returns empty array")
unittest
{
    assert(getFormFieldAll("x=1&y=2", "z") == []);
    assert(getFormFieldAll("", "anything") == []);
}

/**
 * Multi-value with URL decoding
 */
@("Multi-value: Values are URL decoded")
unittest
{
    auto tags = getFormFieldAll("tag=red%2Forange&tag=blue+sky&tag=green", "tag");
    assert(tags == ["red/orange", "blue sky", "green"]);
}

// ════════════════════════════════════════════════════════════════════════════════
// RAW FIELD ACCESS (@nogc)
// ════════════════════════════════════════════════════════════════════════════════

/**
 * Raw field value without decoding
 */
@("Raw: findFieldValue returns raw encoded value")
unittest
{
    // Should NOT decode
    assert(findFieldValue("email=test%40example.com", "email") == "test%40example.com");
    assert(findFieldValue("name=John+Doe", "name") == "John+Doe");
}

/**
 * Raw field null result
 */
@("Raw: Missing field returns null")
unittest
{
    assert(findFieldValue("a=1&b=2", "missing") is null);
    assert(findFieldValue("", "anything") is null);
}

/**
 * Has field check
 */
@("Raw: hasFormField existence check")
unittest
{
    assert(hasFormField("a=1&b=2&c=3", "a"));
    assert(hasFormField("a=1&b=2&c=3", "b"));
    assert(hasFormField("a=1&b=2&c=3", "c"));
    assert(!hasFormField("a=1&b=2&c=3", "d"));
    assert(!hasFormField("", "anything"));
}

// ════════════════════════════════════════════════════════════════════════════════
// PARSE ALL FIELDS
// ════════════════════════════════════════════════════════════════════════════════

/**
 * Parse all fields to associative array
 */
@("ParseAll: Basic parsing to AA")
unittest
{
    auto data = parseFormData("name=John&age=30&city=Rome");
    
    assert(data["name"] == "John");
    assert(data["age"] == "30");
    assert(data["city"] == "Rome");
    assert(data.length == 3);
}

/**
 * Parse all with URL decoding
 */
@("ParseAll: Values are URL decoded")
unittest
{
    auto data = parseFormData("email=test%40example.com&name=John+Doe");
    
    assert(data["email"] == "test@example.com");
    assert(data["name"] == "John Doe");
}

/**
 * Parse all: duplicate keys (first value wins)
 */
@("ParseAll: First value wins for duplicate keys")
unittest
{
    auto data = parseFormData("key=first&key=second&key=third");
    
    assert(data["key"] == "first");
    assert(data.length == 1);
}

// ════════════════════════════════════════════════════════════════════════════════
// EDGE CASES
// ════════════════════════════════════════════════════════════════════════════════

/**
 * Empty input
 */
@("Edge: Empty input")
unittest
{
    assert(getFormField("", "name") == "");
    assert(getFormFieldAll("", "name") == []);
    assert(findFieldValue("", "name") is null);
    assert(!hasFormField("", "name"));
    assert(parseFormData("").length == 0);
}

/**
 * Empty values
 */
@("Edge: Empty field values")
unittest
{
    assert(getFormField("name=", "name") == "");
    assert(getFormField("a=&b=value", "a") == "");
    assert(findFieldValue("name=", "name") == "");
}

/**
 * Key without equals sign
 */
@("Edge: Key without value (no = sign)")
unittest
{
    // "flag" without = should still be found
    assert(hasFormField("a=1&flag&b=2", "flag"));
    assert(getFormField("a=1&flag&b=2", "flag") == "");
}

/**
 * Consecutive ampersands
 */
@("Edge: Empty pairs from consecutive &&")
unittest
{
    assert(getFormField("a=1&&b=2", "b") == "2");
    assert(getFormField("&&a=1&&", "a") == "1");
}

/**
 * Special characters in keys
 */
@("Edge: Keys with encoded characters")
unittest
{
    // Encoded key names (less common but valid)
    auto data = parseFormData("user%5Bname%5D=John&user%5Bage%5D=30");
    assert(data["user[name]"] == "John");
    assert(data["user[age]"] == "30");
}

/**
 * Very long values
 */
@("Edge: Long field values")
unittest
{
    // Create 10KB value
    char[] longValue;
    longValue.length = 10_000;
    longValue[] = 'x';
    
    string data = "field=" ~ cast(string)longValue;
    string result = getFormField(data, "field");
    
    assert(result.length == 10_000);
}

/**
 * Binary data in values
 */
@("Edge: Binary data in percent-encoded values")
unittest
{
    // All bytes 0x01-0xFF (skip 0x00 null which is rejected)
    string encoded = "data=";
    foreach (ubyte b; 1 .. 256)
    {
        encoded ~= '%';
        encoded ~= "0123456789ABCDEF"[b >> 4];
        encoded ~= "0123456789ABCDEF"[b & 0x0F];
    }
    
    string value = getFormField(encoded, "data");
    assert(value.length == 255);
}

// ════════════════════════════════════════════════════════════════════════════════
// SECURITY TESTS
// ════════════════════════════════════════════════════════════════════════════════

/**
 * Null byte in form values
 */
@("Security: Null byte rejection in form values")
unittest
{
    // Null bytes should be rejected
    assert(getFormField("file=test%00.jpg", "file") == "");
    assert(getFormField("path=/etc/passwd%00", "path") == "");
}

/**
 * SQL injection characters in form values
 */
@("Security: SQL injection chars decode correctly")
unittest
{
    // These should decode correctly - application must sanitize
    assert(getFormField("input=%27+OR+1%3D1+--", "input") == "' OR 1=1 --");
    assert(getFormField("query=%22%3BUNION+SELECT+*", "query") == "\";UNION SELECT *");
}

/**
 * XSS in form values
 */
@("Security: XSS characters decode correctly")
unittest
{
    // These should decode correctly - application must escape for HTML
    assert(getFormField("comment=%3Cscript%3Ealert(1)%3C%2Fscript%3E", "comment") 
           == "<script>alert(1)</script>");
}

/**
 * Path traversal in form values
 */
@("Security: Path traversal sequences decode correctly")
unittest
{
    // These should decode correctly - application must validate paths
    assert(getFormField("file=..%2F..%2F..%2Fetc%2Fpasswd", "file") 
           == "../../../etc/passwd");
}

// ════════════════════════════════════════════════════════════════════════════════
// REAL-WORLD EXAMPLES
// ════════════════════════════════════════════════════════════════════════════════

/**
 * Login form
 */
@("Real-world: Login form parsing")
unittest
{
    immutable loginForm = "email=user%40example.com&password=secret%21123&remember=on";
    
    assert(getFormField(loginForm, "email") == "user@example.com");
    assert(getFormField(loginForm, "password") == "secret!123");
    assert(getFormField(loginForm, "remember") == "on");
}

/**
 * Search form with complex query
 */
@("Real-world: Search form with special chars")
unittest
{
    immutable searchForm = "q=C%2B%2B+programming&category=tech&sort=relevance";
    
    assert(getFormField(searchForm, "q") == "C++ programming");
    assert(getFormField(searchForm, "category") == "tech");
    assert(getFormField(searchForm, "sort") == "relevance");
}

/**
 * Multi-select form
 */
@("Real-world: Multi-select form")
unittest
{
    immutable filterForm = "brand=Apple&brand=Samsung&brand=Google&minPrice=100&maxPrice=1000";
    
    auto brands = getFormFieldAll(filterForm, "brand");
    assert(brands == ["Apple", "Samsung", "Google"]);
    assert(getFormField(filterForm, "minPrice") == "100");
    assert(getFormField(filterForm, "maxPrice") == "1000");
}

/**
 * Checkout form with unicode
 */
@("Real-world: International checkout form")
unittest
{
    immutable checkoutForm = 
        "name=Jos%C3%A9+Garc%C3%ADa" ~
        "&address=Calle+Mayor+123" ~
        "&city=Espa%C3%B1a" ~
        "&amount=%E2%82%AC50.00";
    
    assert(getFormField(checkoutForm, "name") == "José García");
    assert(getFormField(checkoutForm, "city") == "España");
    assert(getFormField(checkoutForm, "amount") == "€50.00");
}
