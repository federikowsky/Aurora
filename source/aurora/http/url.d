/**
 * URL Encoding/Decoding — Production-Grade Implementation
 *
 * Package: aurora.http.url
 *
 * RFC 3986 compliant URL encoding/decoding with security features:
 * - Null byte injection prevention (default)
 * - Control character filtering (optional)
 * - UTF-8 validation (optional)
 * - Form vs URI mode support
 *
 * Security: rejectNullBytes=true by default to prevent path traversal attacks.
 */
module aurora.http.url;

// ════════════════════════════════════════════════════════════════════════════
// TYPES
// ════════════════════════════════════════════════════════════════════════════

/**
 * Decoding mode.
 *
 * URI mode follows RFC 3986 strictly.
 * Form mode follows HTML form encoding (application/x-www-form-urlencoded).
 */
enum DecodeMode : ubyte
{
    /// RFC 3986: + stays as +
    URI = 0,
    
    /// HTML form encoding: + becomes space
    Form = 1,
}

/**
 * Decoding options for security and behavior control.
 */
struct DecodeOptions
{
    /// Decoding mode (Form by default for web applications)
    DecodeMode mode = DecodeMode.Form;
    
    /// Reject %00 null bytes (security: prevents path traversal)
    bool rejectNullBytes = true;
    
    /// Reject control characters %00-%1F except tab, LF, CR
    bool rejectControlChars = false;
    
    /// Validate output is valid UTF-8
    bool validateUtf8 = false;
    
    /// Standard options for form data
    static DecodeOptions form() pure nothrow @safe @nogc
    {
        return DecodeOptions(DecodeMode.Form, true, false, false);
    }
    
    /// Standard options for URI components
    static DecodeOptions uri() pure nothrow @safe @nogc
    {
        return DecodeOptions(DecodeMode.URI, true, false, false);
    }
    
    /// Strict security options
    static DecodeOptions strict() pure nothrow @safe @nogc
    {
        return DecodeOptions(DecodeMode.Form, true, true, true);
    }
}

/**
 * Result of strict decoding operation.
 */
struct DecodeResult
{
    /// Decoded value (empty on error)
    string value;
    
    /// True if decoding succeeded
    bool ok;
    
    /// Error message (null if ok)
    string error;
    
    /// Check if result is valid
    bool opCast(T : bool)() const pure nothrow @safe @nogc
    {
        return ok;
    }
}

// ════════════════════════════════════════════════════════════════════════════
// PUBLIC API - DECODING
// ════════════════════════════════════════════════════════════════════════════

/**
 * URL decode with lenient error handling.
 *
 * On malformed input, returns input unchanged or partially decoded.
 * Use urlDecodeStrict() for strict validation.
 *
 * Params:
 *   input = URL-encoded string
 *   opts = Decoding options
 *
 * Returns:
 *   Decoded string. On security violation (null byte), returns empty string.
 */
pragma(inline, true)
string urlDecode(const(char)[] input, DecodeOptions opts = DecodeOptions.init) pure @trusted
{
    auto result = urlDecodeImpl(input, opts);
    return result.ok ? result.value : "";
}

/**
 * URL decode with strict validation.
 *
 * Returns detailed error on malformed or dangerous input.
 *
 * Params:
 *   input = URL-encoded string
 *   opts = Decoding options
 *
 * Returns:
 *   DecodeResult with decoded value or error message.
 */
DecodeResult urlDecodeStrict(const(char)[] input, DecodeOptions opts = DecodeOptions.init) pure @safe
{
    return urlDecodeImpl(input, opts);
}

/**
 * Decode form field value (convenience).
 *
 * Uses Form mode with security defaults.
 */
pragma(inline, true)
string formDecode(const(char)[] input) pure @trusted
{
    return urlDecode(input, DecodeOptions.form());
}

/**
 * Decode URI component (convenience).
 *
 * Uses URI mode (+ stays as +) with security defaults.
 */
pragma(inline, true)
string uriDecode(const(char)[] input) pure @trusted
{
    return urlDecode(input, DecodeOptions.uri());
}

// ════════════════════════════════════════════════════════════════════════════
// PUBLIC API - ENCODING
// ════════════════════════════════════════════════════════════════════════════

/**
 * URL encode for URI component.
 *
 * Encodes all characters except unreserved: A-Za-z0-9 - . _ ~
 */
string urlEncode(const(char)[] input) pure @trusted
{
    if (input.length == 0) return "";
    
    // Fast path: check if encoding needed
    bool needsEncode = false;
    foreach (c; input)
    {
        if (!isUnreserved(c))
        {
            needsEncode = true;
            break;
        }
    }
    
    if (!needsEncode)
        return input.idup;
    
    // Encode (worst case = 3x length for all encoded)
    char[] result;
    result.reserve(input.length * 3);
    
    foreach (c; input)
    {
        if (isUnreserved(c))
        {
            result ~= c;
        }
        else
        {
            result ~= '%';
            result ~= hexCharUpper((cast(ubyte)c >> 4) & 0x0F);
            result ~= hexCharUpper(cast(ubyte)c & 0x0F);
        }
    }
    
    return cast(string)result;
}

/**
 * URL encode for form data.
 *
 * Like urlEncode but encodes space as + (HTML form standard).
 */
string formEncode(const(char)[] input) pure @trusted
{
    if (input.length == 0) return "";
    
    bool needsEncode = false;
    foreach (c; input)
    {
        if (!isUnreserved(c) && c != ' ')
        {
            needsEncode = true;
            break;
        }
        if (c == ' ')
        {
            needsEncode = true;
            break;
        }
    }
    
    if (!needsEncode)
        return input.idup;
    
    char[] result;
    result.reserve(input.length * 3);
    
    foreach (c; input)
    {
        if (c == ' ')
        {
            result ~= '+';
        }
        else if (isUnreserved(c))
        {
            result ~= c;
        }
        else
        {
            result ~= '%';
            result ~= hexCharUpper((cast(ubyte)c >> 4) & 0x0F);
            result ~= hexCharUpper(cast(ubyte)c & 0x0F);
        }
    }
    
    return cast(string)result;
}

// ════════════════════════════════════════════════════════════════════════════
// IMPLEMENTATION
// ════════════════════════════════════════════════════════════════════════════

private DecodeResult urlDecodeImpl(const(char)[] input, DecodeOptions opts) pure @trusted
{
    if (input.length == 0)
        return DecodeResult("", true, null);
    
    // ─────────────────────────────────────────────────────────────────────────
    // Phase 1: Pre-scan - validate and check if decoding needed
    // ─────────────────────────────────────────────────────────────────────────
    
    bool needsDecode = false;
    size_t i = 0;
    
    while (i < input.length)
    {
        immutable c = input[i];
        
        if (c == '%')
        {
            // Validate %XX format
            if (i + 2 >= input.length)
                return DecodeResult("", false, "Truncated percent encoding at end of string");
            
            immutable hi = hexDigit(input[i + 1]);
            immutable lo = hexDigit(input[i + 2]);
            
            if (hi < 0 || lo < 0)
                return DecodeResult("", false, "Invalid hexadecimal in percent encoding");
            
            immutable ubyte decoded = cast(ubyte)((hi << 4) | lo);
            
            // Security: null byte check
            if (opts.rejectNullBytes && decoded == 0)
                return DecodeResult("", false, "Null byte (%00) not allowed");
            
            // Security: control character check
            if (opts.rejectControlChars && isControlChar(decoded))
                return DecodeResult("", false, "Control character not allowed");
            
            needsDecode = true;
            i += 3;
        }
        else if (c == '+' && opts.mode == DecodeMode.Form)
        {
            needsDecode = true;
            i++;
        }
        else
        {
            i++;
        }
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // Fast path: no decoding needed
    // ─────────────────────────────────────────────────────────────────────────
    
    if (!needsDecode)
        return DecodeResult(input.idup, true, null);
    
    // ─────────────────────────────────────────────────────────────────────────
    // Phase 2: Decode pass
    // ─────────────────────────────────────────────────────────────────────────
    
    // Pre-allocate buffer (decoded length <= input length)
    char[] result = new char[input.length];
    size_t outIdx = 0;
    i = 0;
    
    while (i < input.length)
    {
        immutable c = input[i];
        
        if (c == '%')
        {
            // Already validated in pre-scan
            immutable hi = hexDigit(input[i + 1]);
            immutable lo = hexDigit(input[i + 2]);
            result[outIdx++] = cast(char)((hi << 4) | lo);
            i += 3;
        }
        else if (c == '+' && opts.mode == DecodeMode.Form)
        {
            result[outIdx++] = ' ';
            i++;
        }
        else
        {
            result[outIdx++] = c;
            i++;
        }
    }
    
    string decoded = cast(string)result[0 .. outIdx];
    
    // ─────────────────────────────────────────────────────────────────────────
    // Phase 3: Optional UTF-8 validation
    // ─────────────────────────────────────────────────────────────────────────
    
    if (opts.validateUtf8 && !isValidUtf8(decoded))
        return DecodeResult("", false, "Invalid UTF-8 sequence after decoding");
    
    return DecodeResult(decoded, true, null);
}

// ════════════════════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════════════════════

/**
 * Convert hex character to value (0-15).
 * Returns -1 for invalid hex character.
 */
pragma(inline, true)
private int hexDigit(char c) pure nothrow @safe @nogc
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/**
 * Convert value (0-15) to uppercase hex character.
 */
pragma(inline, true)
private char hexCharUpper(int n) pure nothrow @safe @nogc
{
    return cast(char)(n < 10 ? '0' + n : 'A' + n - 10);
}

/**
 * Check if character is unreserved per RFC 3986.
 * Unreserved = A-Za-z0-9 - . _ ~
 */
pragma(inline, true)
private bool isUnreserved(char c) pure nothrow @safe @nogc
{
    if (c >= 'a' && c <= 'z') return true;
    if (c >= 'A' && c <= 'Z') return true;
    if (c >= '0' && c <= '9') return true;
    return c == '-' || c == '.' || c == '_' || c == '~';
}

/**
 * Check if byte is a control character (0x00-0x1F) except allowed ones.
 * Allowed: TAB (0x09), LF (0x0A), CR (0x0D)
 */
pragma(inline, true)
private bool isControlChar(ubyte b) pure nothrow @safe @nogc
{
    if (b >= 0x20) return false;
    if (b == 0x09 || b == 0x0A || b == 0x0D) return false;  // TAB, LF, CR allowed
    return true;
}

/**
 * Validate UTF-8 encoding.
 * Returns true if string is valid UTF-8.
 */
private bool isValidUtf8(const(char)[] s) pure nothrow @safe @nogc
{
    size_t i = 0;
    while (i < s.length)
    {
        immutable ubyte b = cast(ubyte)s[i];
        
        if (b <= 0x7F)
        {
            // ASCII
            i++;
        }
        else if ((b & 0xE0) == 0xC0)
        {
            // 2-byte sequence
            if (i + 1 >= s.length) return false;
            if ((cast(ubyte)s[i + 1] & 0xC0) != 0x80) return false;
            // Check for overlong encoding
            if (b < 0xC2) return false;
            i += 2;
        }
        else if ((b & 0xF0) == 0xE0)
        {
            // 3-byte sequence
            if (i + 2 >= s.length) return false;
            if ((cast(ubyte)s[i + 1] & 0xC0) != 0x80) return false;
            if ((cast(ubyte)s[i + 2] & 0xC0) != 0x80) return false;
            // Check for overlong encoding and surrogate range
            uint codepoint = ((b & 0x0F) << 12) | 
                            ((cast(ubyte)s[i + 1] & 0x3F) << 6) |
                            (cast(ubyte)s[i + 2] & 0x3F);
            if (codepoint < 0x800) return false;  // Overlong
            if (codepoint >= 0xD800 && codepoint <= 0xDFFF) return false;  // Surrogate
            i += 3;
        }
        else if ((b & 0xF8) == 0xF0)
        {
            // 4-byte sequence
            if (i + 3 >= s.length) return false;
            if ((cast(ubyte)s[i + 1] & 0xC0) != 0x80) return false;
            if ((cast(ubyte)s[i + 2] & 0xC0) != 0x80) return false;
            if ((cast(ubyte)s[i + 3] & 0xC0) != 0x80) return false;
            // Check for overlong and out of range
            uint codepoint = ((b & 0x07) << 18) |
                            ((cast(ubyte)s[i + 1] & 0x3F) << 12) |
                            ((cast(ubyte)s[i + 2] & 0x3F) << 6) |
                            (cast(ubyte)s[i + 3] & 0x3F);
            if (codepoint < 0x10000) return false;  // Overlong
            if (codepoint > 0x10FFFF) return false;  // Out of Unicode range
            i += 4;
        }
        else
        {
            // Invalid leading byte
            return false;
        }
    }
    return true;
}
