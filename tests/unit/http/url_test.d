/**
 * URL Encoding/Decoding Tests — RFC 3986 & OWASP Compliance
 *
 * Test suite for aurora.http.url module covering:
 * - RFC 3986 percent-encoding specification
 * - OWASP security test cases (injection prevention)
 * - Edge cases and boundary conditions
 *
 * References:
 * - RFC 3986: https://tools.ietf.org/html/rfc3986
 * - OWASP Testing Guide: https://owasp.org/www-project-web-security-testing-guide/
 */
module tests.unit.http.url_test;

import aurora.http.url;

// ════════════════════════════════════════════════════════════════════════════════
// RFC 3986 COMPLIANCE TESTS
// ════════════════════════════════════════════════════════════════════════════════

/**
 * RFC 3986 Section 2.1: Percent-Encoding
 *
 * "A percent-encoding mechanism is used to represent a data octet in a
 * component when that octet's corresponding character is outside the
 * allowed set or is being used as a delimiter"
 */
@("RFC 3986 2.1: Basic percent decoding")
unittest
{
    // Standard percent-encoded characters
    assert(urlDecode("%20") == " ");   // Space
    assert(urlDecode("%21") == "!");   // Exclamation mark
    assert(urlDecode("%2F") == "/");   // Slash
    assert(urlDecode("%3A") == ":");   // Colon
    assert(urlDecode("%3F") == "?");   // Question mark
    assert(urlDecode("%40") == "@");   // At sign
    assert(urlDecode("%23") == "#");   // Hash
    assert(urlDecode("%26") == "&");   // Ampersand
    assert(urlDecode("%3D") == "=");   // Equals
    assert(urlDecode("%25") == "%");   // Percent sign itself
}

/**
 * RFC 3986 Section 2.1: Case-insensitive hex digits
 *
 * "The uppercase hexadecimal digits 'A' through 'F' are equivalent to
 * the lowercase digits 'a' through 'f', respectively"
 */
@("RFC 3986 2.1: Case-insensitive hex digits")
unittest
{
    // Uppercase
    assert(urlDecode("%2F") == "/");
    assert(urlDecode("%2A") == "*");
    assert(urlDecode("%7E") == "~");
    
    // Lowercase
    assert(urlDecode("%2f") == "/");
    assert(urlDecode("%2a") == "*");
    assert(urlDecode("%7e") == "~");
    
    // Mixed case
    assert(urlDecode("%2F%2f") == "//");
    assert(urlDecode("%Ab%aB%AB%ab") == "\xAB\xAB\xAB\xAB");
}

/**
 * RFC 3986 Section 2.3: Unreserved Characters
 *
 * "URIs that differ in the replacement of an unreserved character with
 * its corresponding percent-encoded US-ASCII octet are equivalent"
 */
@("RFC 3986 2.3: Unreserved characters")
unittest
{
    // Unreserved: ALPHA / DIGIT / "-" / "." / "_" / "~"
    assert(urlDecode("abcdefghijklmnopqrstuvwxyz") == "abcdefghijklmnopqrstuvwxyz");
    assert(urlDecode("ABCDEFGHIJKLMNOPQRSTUVWXYZ") == "ABCDEFGHIJKLMNOPQRSTUVWXYZ");
    assert(urlDecode("0123456789") == "0123456789");
    assert(urlDecode("-._~") == "-._~");
    
    // Percent-encoded unreserved should decode to same
    assert(urlDecode("%41") == "A");
    assert(urlDecode("%7A") == "z");
    assert(urlDecode("%30") == "0");
    assert(urlDecode("%2D") == "-");
    assert(urlDecode("%2E") == ".");
    assert(urlDecode("%5F") == "_");
    assert(urlDecode("%7E") == "~");
}

/**
 * RFC 3986: UTF-8 encoding for international characters
 *
 * Non-ASCII characters should be encoded as UTF-8 byte sequences
 */
@("RFC 3986: UTF-8 multi-byte sequences")
unittest
{
    // 2-byte UTF-8 sequences
    assert(urlDecode("%C3%A9") == "é");      // U+00E9 LATIN SMALL LETTER E WITH ACUTE
    assert(urlDecode("%C3%BC") == "ü");      // U+00FC LATIN SMALL LETTER U WITH DIAERESIS
    assert(urlDecode("%C2%A9") == "©");      // U+00A9 COPYRIGHT SIGN
    
    // 3-byte UTF-8 sequences
    assert(urlDecode("%E2%9C%93") == "✓");   // U+2713 CHECK MARK
    assert(urlDecode("%E2%82%AC") == "€");   // U+20AC EURO SIGN
    assert(urlDecode("%E4%B8%AD") == "中");  // U+4E2D CJK character
    
    // 4-byte UTF-8 sequences (emoji)
    assert(urlDecode("%F0%9F%98%80") == "😀"); // U+1F600 GRINNING FACE
}

/**
 * RFC 3986 Section 2.4: Encoding consistency
 *
 * Encoders should produce uppercase hex; decoders accept both
 */
@("RFC 3986 2.4: Encoding produces uppercase hex")
unittest
{
    // Encoding should produce uppercase
    assert(urlEncode(" ") == "%20");
    assert(urlEncode("/") == "%2F");
    assert(urlEncode("@") == "%40");
    
    // Verify no lowercase hex digits (only check chars after %)
    string encoded = urlEncode("Special: @#$%");
    for (size_t i = 0; i < encoded.length; i++)
    {
        if (encoded[i] == '%' && i + 2 < encoded.length)
        {
            // Check hex digit 1
            char h1 = encoded[i + 1];
            if (h1 >= 'a' && h1 <= 'f')
                assert(false, "Encoder produced lowercase hex digit");
            
            // Check hex digit 2
            char h2 = encoded[i + 2];
            if (h2 >= 'a' && h2 <= 'f')
                assert(false, "Encoder produced lowercase hex digit");
        }
    }
}

// ════════════════════════════════════════════════════════════════════════════════
// OWASP SECURITY TESTS
// ════════════════════════════════════════════════════════════════════════════════

/**
 * OWASP: Null Byte Injection Prevention
 *
 * %00 (null byte) can be used to bypass file extension checks
 * and truncate strings in C-based backends.
 *
 * Reference: OWASP Testing Guide - WSTG-INPV-003
 */
@("OWASP: Null byte injection prevention")
unittest
{
    // By default, null bytes are rejected
    assert(urlDecode("%00") == "");
    assert(urlDecode("file.txt%00.jpg") == "");
    assert(urlDecode("/etc/passwd%00") == "");
    
    // Strict mode with detailed error
    auto result1 = urlDecodeStrict("%00");
    assert(!result1.ok);
    assert(result1.error == "Null byte (%00) not allowed");
    
    auto result2 = urlDecodeStrict("malicious%00payload");
    assert(!result2.ok);
    
    // Embedded null bytes
    auto result3 = urlDecodeStrict("before%00after");
    assert(!result3.ok);
}

/**
 * OWASP: Double Encoding Prevention
 *
 * %25XX (double encoding) should decode to %XX, not to the final character.
 * We only decode once to prevent bypass attacks.
 *
 * Reference: OWASP Testing Guide - WSTG-INPV-001
 */
@("OWASP: Double encoding - single decode only")
unittest
{
    // %25 = %, so %252F should decode to %2F, not /
    assert(urlDecode("%252F") == "%2F");
    assert(urlDecode("%2520") == "%20");
    
    // Multiple levels of encoding
    assert(urlDecode("%25252F") == "%252F");  // Triple encoded /
    
    // Path traversal attempt via double encoding
    assert(urlDecode("%252e%252e%252f") == "%2e%2e%2f");  // Not ../
    
    // Don't recursively decode
    string result = urlDecode("%252F");
    assert(result != "/", "Double decoding vulnerability!");
}

/**
 * OWASP: Path Traversal Patterns
 *
 * Common path traversal sequences that should be detected by applications
 * after URL decoding. Our decoder should decode them correctly.
 */
@("OWASP: Path traversal sequences decode correctly")
unittest
{
    // Standard path traversal (decoded as-is, application should validate)
    assert(urlDecode("%2e%2e%2f") == "../");
    assert(urlDecode("%2e%2e/") == "../");
    assert(urlDecode("..%2f") == "../");
    assert(urlDecode("..%5c") == "..\\");  // Windows
    
    // URL encoded path traversal
    assert(urlDecode("%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd") == "../../../etc/passwd");
}

/**
 * OWASP: Control Character Rejection
 *
 * With rejectControlChars=true, control chars (0x00-0x1F) are rejected
 * EXCEPT for common whitespace: TAB (0x09), LF (0x0A), CR (0x0D).
 * 
 * Note: For CRLF injection prevention in HTTP headers, validate at
 * application level or use null byte rejection which is default.
 */
@("OWASP: Control character rejection (except whitespace)")
unittest
{
    auto strictOpts = DecodeOptions.strict();
    
    // Control chars like BEL (0x07), BS (0x08) should be rejected
    auto result1 = urlDecodeStrict("%07", strictOpts);  // BEL
    assert(!result1.ok);
    
    auto result2 = urlDecodeStrict("%08", strictOpts);  // Backspace
    assert(!result2.ok);
    
    auto result3 = urlDecodeStrict("%01", strictOpts);  // SOH
    assert(!result3.ok);
    
    // TAB, LF, CR are allowed even in strict mode (common whitespace)
    auto tab = urlDecodeStrict("%09", strictOpts);
    assert(tab.ok);
    assert(tab.value == "\t");
    
    auto lf = urlDecodeStrict("%0A", strictOpts);
    assert(lf.ok);
    assert(lf.value == "\n");
    
    auto cr = urlDecodeStrict("%0D", strictOpts);
    assert(cr.ok);
    assert(cr.value == "\r");
}

/**
 * OWASP: Unicode Normalization Attacks
 *
 * Different Unicode representations of same character.
 * Decoder should handle UTF-8 correctly.
 */
@("OWASP: Unicode encoding variations")
unittest
{
    // Overlong UTF-8 sequences should be validated when validateUtf8=true
    auto strictOpts = DecodeOptions.strict();
    
    // Valid UTF-8
    auto valid = urlDecodeStrict("%C3%A9", strictOpts);  // é
    assert(valid.ok);
    assert(valid.value == "é");
}

/**
 * OWASP: SQL Injection Characters
 *
 * Common SQL injection characters should decode correctly.
 */
@("OWASP: SQL injection characters decode correctly")
unittest
{
    assert(urlDecode("%27") == "'");    // Single quote
    assert(urlDecode("%22") == "\"");   // Double quote
    assert(urlDecode("%3B") == ";");    // Semicolon
    assert(urlDecode("%2D%2D") == "--"); // Comment
    assert(urlDecode("%2F%2A") == "/*"); // Block comment start
    assert(urlDecode("%2A%2F") == "*/"); // Block comment end
}

/**
 * OWASP: XSS Attack Characters
 *
 * Common XSS attack characters should decode correctly.
 */
@("OWASP: XSS characters decode correctly")
unittest
{
    assert(urlDecode("%3C") == "<");    // Less than
    assert(urlDecode("%3E") == ">");    // Greater than
    assert(urlDecode("%3Cscript%3E") == "<script>");
    assert(urlDecode("%22%3E%3Cscript%3Ealert(1)%3C%2Fscript%3E") == 
           "\"><script>alert(1)</script>");
}

// ════════════════════════════════════════════════════════════════════════════════
// EDGE CASES AND BOUNDARY CONDITIONS
// ════════════════════════════════════════════════════════════════════════════════

/**
 * Edge case: Empty and whitespace input
 */
@("Edge case: Empty and whitespace")
unittest
{
    assert(urlDecode("") == "");
    assert(urlDecode("%20") == " ");
    assert(urlDecode("%20%20%20") == "   ");
    assert(urlDecode("   ") == "   ");  // Literal spaces pass through
}

/**
 * Edge case: Truncated percent encoding
 */
@("Edge case: Truncated percent encoding")
unittest
{
    auto result1 = urlDecodeStrict("%");
    assert(!result1.ok);
    assert(result1.error == "Truncated percent encoding at end of string");
    
    auto result2 = urlDecodeStrict("%2");
    assert(!result2.ok);
    
    auto result3 = urlDecodeStrict("hello%");
    assert(!result3.ok);
    
    auto result4 = urlDecodeStrict("hello%2");
    assert(!result4.ok);
}

/**
 * Edge case: Invalid hex characters
 */
@("Edge case: Invalid hex characters")
unittest
{
    auto result1 = urlDecodeStrict("%ZZ");
    assert(!result1.ok);
    assert(result1.error == "Invalid hexadecimal in percent encoding");
    
    auto result2 = urlDecodeStrict("%GH");
    assert(!result2.ok);
    
    auto result3 = urlDecodeStrict("%1G");
    assert(!result3.ok);
    
    auto result4 = urlDecodeStrict("%G1");
    assert(!result4.ok);
}

/**
 * Edge case: Form encoding (+ as space)
 */
@("Edge case: Form vs URI mode for + character")
unittest
{
    // Form mode: + becomes space
    assert(urlDecode("hello+world", DecodeOptions.form()) == "hello world");
    assert(formDecode("hello+world") == "hello world");
    
    // URI mode: + stays as +
    assert(urlDecode("hello+world", DecodeOptions.uri()) == "hello+world");
    assert(uriDecode("hello+world") == "hello+world");
    
    // %2B is + in both modes
    assert(urlDecode("%2B", DecodeOptions.form()) == "+");
    assert(urlDecode("%2B", DecodeOptions.uri()) == "+");
}

/**
 * Edge case: All byte values (0x00-0xFF)
 */
@("Edge case: Full byte range encoding/decoding")
unittest
{
    // Test that all encodable bytes round-trip (except null in default mode)
    foreach (ubyte b; 1 .. 256)  // Skip 0 (null rejected by default)
    {
        string encoded = urlEncode([cast(char)b]);
        
        // Decode with null rejection disabled to test all bytes
        auto opts = DecodeOptions.form();
        opts.rejectNullBytes = false;
        
        string decoded = urlDecode(encoded, opts);
        assert(decoded.length == 1);
        assert(cast(ubyte)decoded[0] == b, 
               "Round-trip failed for byte " ~ cast(char)('0' + b/100) ~ 
               cast(char)('0' + (b/10)%10) ~ cast(char)('0' + b%10));
    }
}

/**
 * Edge case: Long input strings
 */
@("Edge case: Long input strings")
unittest
{
    // 10KB of encoded data
    char[] input;
    input.length = 30_000;  // %XX = 3 chars per byte
    
    for (size_t i = 0; i < input.length; i += 3)
    {
        input[i] = '%';
        input[i+1] = '4';
        input[i+2] = '1';  // %41 = 'A'
    }
    
    string decoded = urlDecode(cast(string)input);
    assert(decoded.length == 10_000);
    
    foreach (c; decoded)
        assert(c == 'A');
}

// ════════════════════════════════════════════════════════════════════════════════
// ENCODING TESTS
// ════════════════════════════════════════════════════════════════════════════════

/**
 * URL encoding basic functionality
 */
@("Encoding: Basic URL encoding")
unittest
{
    // No encoding needed
    assert(urlEncode("hello") == "hello");
    assert(urlEncode("ABC123") == "ABC123");
    assert(urlEncode("-._~") == "-._~");
    
    // Space encoding
    assert(urlEncode("hello world") == "hello%20world");
    
    // Special characters
    assert(urlEncode("/path/to/file") == "%2Fpath%2Fto%2Ffile");
    assert(urlEncode("a=1&b=2") == "a%3D1%26b%3D2");
}

/**
 * Form encoding with + for space
 */
@("Encoding: Form encoding (+ for space)")
unittest
{
    assert(formEncode("hello world") == "hello+world");
    assert(formEncode("a b c") == "a+b+c");
    
    // Actual + must be encoded
    assert(formEncode("1+1=2") == "1%2B1%3D2");
}

/**
 * Encoding round-trip
 */
@("Encoding: Round-trip encode/decode")
unittest
{
    immutable testStrings = [
        "hello world",
        "test@example.com",
        "path/to/file.txt",
        "query?param=value&other=123",
        "unicode: é ñ ü",
        "emoji: 😀",
        "special: !@#$%^&*()",
    ];
    
    foreach (original; testStrings)
    {
        string encoded = urlEncode(original);
        string decoded = uriDecode(encoded);  // URI mode, + stays +
        assert(decoded == original, "Round-trip failed for: " ~ original);
    }
}
