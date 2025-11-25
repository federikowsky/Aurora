/**
 * HTTP Utilities - Shared utilities for HTTP response building
 * 
 * Features:
 * - Static status text lookup table (no switch overhead)
 * - Pre-computed status line cache
 * - Zero-allocation response building into buffers
 * - Thread-safe, immutable data structures
 */
module aurora.http.util;

import core.stdc.string : memcpy;

// ============================================================================
// STATUS CODE LOOKUP TABLE
// ============================================================================

/**
 * HTTP status text lookup table.
 * Covers ALL standard HTTP status codes with O(1) lookup.
 * For codes outside 0-511 range or unknown codes, returns "Unknown".
 */
private immutable string[512] STATUS_TEXT_TABLE = () {
    string[512] table;
    
    // Initialize all to "Unknown" - safe default for any unmapped code
    foreach (ref s; table)
        s = "Unknown";
    
    // 1xx Informational
    table[100] = "Continue";
    table[101] = "Switching Protocols";
    table[102] = "Processing";
    table[103] = "Early Hints";
    
    // 2xx Success
    table[200] = "OK";
    table[201] = "Created";
    table[202] = "Accepted";
    table[203] = "Non-Authoritative Information";
    table[204] = "No Content";
    table[205] = "Reset Content";
    table[206] = "Partial Content";
    table[207] = "Multi-Status";
    table[208] = "Already Reported";
    table[226] = "IM Used";
    
    // 3xx Redirection
    table[300] = "Multiple Choices";
    table[301] = "Moved Permanently";
    table[302] = "Found";
    table[303] = "See Other";
    table[304] = "Not Modified";
    table[305] = "Use Proxy";
    table[306] = "Switch Proxy";  // Deprecated but still valid
    table[307] = "Temporary Redirect";
    table[308] = "Permanent Redirect";
    
    // 4xx Client Error
    table[400] = "Bad Request";
    table[401] = "Unauthorized";
    table[402] = "Payment Required";
    table[403] = "Forbidden";
    table[404] = "Not Found";
    table[405] = "Method Not Allowed";
    table[406] = "Not Acceptable";
    table[407] = "Proxy Authentication Required";
    table[408] = "Request Timeout";
    table[409] = "Conflict";
    table[410] = "Gone";
    table[411] = "Length Required";
    table[412] = "Precondition Failed";
    table[413] = "Payload Too Large";
    table[414] = "URI Too Long";
    table[415] = "Unsupported Media Type";
    table[416] = "Range Not Satisfiable";
    table[417] = "Expectation Failed";
    table[418] = "I'm a teapot";
    table[421] = "Misdirected Request";
    table[422] = "Unprocessable Entity";
    table[423] = "Locked";
    table[424] = "Failed Dependency";
    table[425] = "Too Early";
    table[426] = "Upgrade Required";
    table[428] = "Precondition Required";
    table[429] = "Too Many Requests";
    table[431] = "Request Header Fields Too Large";
    table[451] = "Unavailable For Legal Reasons";
    
    // 5xx Server Error
    table[500] = "Internal Server Error";
    table[501] = "Not Implemented";
    table[502] = "Bad Gateway";
    table[503] = "Service Unavailable";
    table[504] = "Gateway Timeout";
    table[505] = "HTTP Version Not Supported";
    table[506] = "Variant Also Negotiates";
    table[507] = "Insufficient Storage";
    table[508] = "Loop Detected";
    table[510] = "Not Extended";
    table[511] = "Network Authentication Required";
    
    return table;
}();

/**
 * Get HTTP status text for a status code.
 * O(1) lookup via static table.
 */
string getStatusText(int code) @safe @nogc nothrow pure
{
    if (code >= 0 && code < 512)
        return STATUS_TEXT_TABLE[code];
    return "Unknown";
}

// ============================================================================
// PRE-COMPUTED STATUS LINES
// ============================================================================

/**
 * Pre-computed status lines for common codes.
 * Avoids string formatting on hot path.
 * For uncommon codes, buildResponseInto() constructs the line dynamically.
 */
immutable string STATUS_LINE_200 = "HTTP/1.1 200 OK\r\n";
immutable string STATUS_LINE_201 = "HTTP/1.1 201 Created\r\n";
immutable string STATUS_LINE_202 = "HTTP/1.1 202 Accepted\r\n";
immutable string STATUS_LINE_204 = "HTTP/1.1 204 No Content\r\n";
immutable string STATUS_LINE_206 = "HTTP/1.1 206 Partial Content\r\n";
immutable string STATUS_LINE_301 = "HTTP/1.1 301 Moved Permanently\r\n";
immutable string STATUS_LINE_302 = "HTTP/1.1 302 Found\r\n";
immutable string STATUS_LINE_303 = "HTTP/1.1 303 See Other\r\n";
immutable string STATUS_LINE_304 = "HTTP/1.1 304 Not Modified\r\n";
immutable string STATUS_LINE_307 = "HTTP/1.1 307 Temporary Redirect\r\n";
immutable string STATUS_LINE_308 = "HTTP/1.1 308 Permanent Redirect\r\n";
immutable string STATUS_LINE_400 = "HTTP/1.1 400 Bad Request\r\n";
immutable string STATUS_LINE_401 = "HTTP/1.1 401 Unauthorized\r\n";
immutable string STATUS_LINE_403 = "HTTP/1.1 403 Forbidden\r\n";
immutable string STATUS_LINE_404 = "HTTP/1.1 404 Not Found\r\n";
immutable string STATUS_LINE_405 = "HTTP/1.1 405 Method Not Allowed\r\n";
immutable string STATUS_LINE_408 = "HTTP/1.1 408 Request Timeout\r\n";
immutable string STATUS_LINE_409 = "HTTP/1.1 409 Conflict\r\n";
immutable string STATUS_LINE_410 = "HTTP/1.1 410 Gone\r\n";
immutable string STATUS_LINE_413 = "HTTP/1.1 413 Payload Too Large\r\n";
immutable string STATUS_LINE_415 = "HTTP/1.1 415 Unsupported Media Type\r\n";
immutable string STATUS_LINE_422 = "HTTP/1.1 422 Unprocessable Entity\r\n";
immutable string STATUS_LINE_429 = "HTTP/1.1 429 Too Many Requests\r\n";
immutable string STATUS_LINE_500 = "HTTP/1.1 500 Internal Server Error\r\n";
immutable string STATUS_LINE_501 = "HTTP/1.1 501 Not Implemented\r\n";
immutable string STATUS_LINE_502 = "HTTP/1.1 502 Bad Gateway\r\n";
immutable string STATUS_LINE_503 = "HTTP/1.1 503 Service Unavailable\r\n";
immutable string STATUS_LINE_504 = "HTTP/1.1 504 Gateway Timeout\r\n";

/**
 * Get pre-computed status line for common codes.
 * Returns null for uncommon codes (caller should format manually).
 * 
 * This is an optimization - for codes not in this list,
 * the caller uses getStatusText() to build the line dynamically.
 */
string getStatusLine(int code) @safe @nogc nothrow pure
{
    switch (code)
    {
        case 200: return STATUS_LINE_200;
        case 201: return STATUS_LINE_201;
        case 202: return STATUS_LINE_202;
        case 204: return STATUS_LINE_204;
        case 206: return STATUS_LINE_206;
        case 301: return STATUS_LINE_301;
        case 302: return STATUS_LINE_302;
        case 303: return STATUS_LINE_303;
        case 304: return STATUS_LINE_304;
        case 307: return STATUS_LINE_307;
        case 308: return STATUS_LINE_308;
        case 400: return STATUS_LINE_400;
        case 401: return STATUS_LINE_401;
        case 403: return STATUS_LINE_403;
        case 404: return STATUS_LINE_404;
        case 405: return STATUS_LINE_405;
        case 408: return STATUS_LINE_408;
        case 409: return STATUS_LINE_409;
        case 410: return STATUS_LINE_410;
        case 413: return STATUS_LINE_413;
        case 415: return STATUS_LINE_415;
        case 422: return STATUS_LINE_422;
        case 429: return STATUS_LINE_429;
        case 500: return STATUS_LINE_500;
        case 501: return STATUS_LINE_501;
        case 502: return STATUS_LINE_502;
        case 503: return STATUS_LINE_503;
        case 504: return STATUS_LINE_504;
        default: return null;  // Caller will build dynamically using getStatusText()
    }
}

// ============================================================================
// ZERO-ALLOCATION RESPONSE BUILDING
// ============================================================================

/**
 * Integer to string conversion without allocation.
 * Writes digits into provided buffer, returns slice of written portion.
 */
char[] intToBuffer(long value, char[] buffer) @safe @nogc nothrow pure
{
    if (buffer.length == 0)
        return buffer[0..0];
    
    if (value == 0)
    {
        buffer[0] = '0';
        return buffer[0..1];
    }
    
    bool negative = value < 0;
    if (negative)
        value = -value;
    
    // Write digits in reverse
    size_t pos = buffer.length;
    while (value > 0 && pos > 0)
    {
        pos--;
        buffer[pos] = cast(char)('0' + (value % 10));
        value /= 10;
    }
    
    // Add negative sign
    if (negative && pos > 0)
    {
        pos--;
        buffer[pos] = '-';
    }
    
    return buffer[pos .. $];
}

/**
 * Build HTTP response directly into buffer.
 * Returns number of bytes written, or 0 if buffer too small.
 * 
 * @nogc - no garbage collection allocations
 */
size_t buildResponseInto(
    ubyte[] buffer,
    int statusCode,
    const(char)[] contentType,
    const(char)[] body_,
    bool keepAlive = true
) @trusted @nogc nothrow
{
    size_t pos = 0;
    
    // Helper to write string
    void write(const(char)[] s)
    {
        if (pos + s.length > buffer.length)
        {
            pos = size_t.max;  // Mark overflow
            return;
        }
        memcpy(buffer.ptr + pos, s.ptr, s.length);
        pos += s.length;
    }
    
    // Status line
    auto statusLine = getStatusLine(statusCode);
    if (statusLine !is null)
    {
        write(statusLine);
    }
    else
    {
        write("HTTP/1.1 ");
        char[16] numBuf;
        write(intToBuffer(statusCode, numBuf[]));
        write(" ");
        write(getStatusText(statusCode));
        write("\r\n");
    }
    
    if (pos == size_t.max) return 0;
    
    // Content-Type header
    write("Content-Type: ");
    write(contentType);
    write("\r\n");
    
    if (pos == size_t.max) return 0;
    
    // Content-Length header
    write("Content-Length: ");
    char[20] lenBuf;
    write(intToBuffer(body_.length, lenBuf[]));
    write("\r\n");
    
    if (pos == size_t.max) return 0;
    
    // Connection header
    if (keepAlive)
        write("Connection: keep-alive\r\n");
    else
        write("Connection: close\r\n");
    
    // Server header
    write("Server: Aurora/0.2\r\n");
    
    // End headers
    write("\r\n");
    
    if (pos == size_t.max) return 0;
    
    // Body
    write(body_);
    
    if (pos == size_t.max) return 0;
    
    return pos;
}

// ============================================================================
// UNIT TESTS
// ============================================================================

unittest
{
    // Test status text lookup
    assert(getStatusText(200) == "OK");
    assert(getStatusText(404) == "Not Found");
    assert(getStatusText(500) == "Internal Server Error");
    assert(getStatusText(999) == "Unknown");
    
    // Test status line lookup
    assert(getStatusLine(200) == "HTTP/1.1 200 OK\r\n");
    assert(getStatusLine(404) == "HTTP/1.1 404 Not Found\r\n");
    assert(getStatusLine(999) is null);
    
    // Test intToBuffer
    char[20] buf;
    assert(intToBuffer(0, buf[]) == "0");
    assert(intToBuffer(123, buf[]) == "123");
    assert(intToBuffer(42, buf[]) == "42");
    
    // Test buildResponseInto
    ubyte[512] respBuf;
    auto len = buildResponseInto(respBuf[], 200, "text/plain", "Hello");
    assert(len > 0);
    auto response = cast(string)respBuf[0..len];
    assert(response.length > 0);
    import std.algorithm : canFind;
    assert(response.canFind("HTTP/1.1 200 OK"));
    assert(response.canFind("Content-Type: text/plain"));
    assert(response.canFind("Content-Length: 5"));
    assert(response.canFind("Hello"));
}
