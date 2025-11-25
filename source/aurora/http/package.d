/**
 * Aurora HTTP Module
 * 
 * Features:
 * - HTTPRequest (wraps Wire parser)
 * - HTTPResponse (response builder)
 * - Zero-copy parsing via Wire
 * - Fast (< 5μs parse time)
 * 
 * Usage:
 * ---
 * auto req = HTTPRequest.parse(data);
 * auto resp = HTTPResponse(200, "OK");
 * resp.setBody("Hello!");
 * ---
 */
module aurora.http;

public import aurora.http.util;

import wire;
import std.string : toLower;
import std.conv : to;
import std.array : appender;

/**
 * HTTP Request - wraps Wire parser
 *
 * Note on @nogc:
 * - parse() uses Wire's @nogc parser ✅
 * - Accessor methods (method(), path(), etc.) allocate strings via .toString()
 * - This is acceptable for user-facing API (convenience over @nogc)
 * - Future: Add *View() methods if critical path requires @nogc
 */
struct HTTPRequest
{
    private ParserWrapper wrapper;
    private bool valid;
    
    /**
     * Parse HTTP request from raw bytes
     */
    static HTTPRequest parse(scope ubyte[] data)
    {
        HTTPRequest req;
        req.wrapper = parseHTTP(data);
        req.valid = cast(bool)req.wrapper;  // Uses opCast
        return req;
    }
    
    /**
     * Get HTTP method
     */
    string method()
    {
        if (!valid) return "";
        return wrapper.getMethod().toString();
    }
    
    /**
     * Get request path (without query string)
     * 
     * Note: Wire stores full URL in path. We split off the query string
     * to match standard HTTP semantics where path and query are separate.
     */
    string path()
    {
        if (!valid) return "";
        string fullPath = wrapper.getPath().toString();
        
        // Find query string separator
        import std.string : indexOf;
        auto queryPos = fullPath.indexOf('?');
        
        if (queryPos >= 0)
            return fullPath[0 .. queryPos];
        else
            return fullPath;
    }
    
    /**
     * Get query string (without leading '?')
     * 
     * Note: Wire may return empty/null query. We parse from the path as fallback.
     */
    string query()
    {
        if (!valid) return "";
        
        // First try Wire's query field (check for null StringView)
        auto wireQuery = wrapper.getQuery();
        if (!wireQuery.empty)
            return wireQuery.toString();
        
        // Fallback: parse from path
        string fullPath = wrapper.getPath().toString();
        import std.string : indexOf;
        auto queryPos = fullPath.indexOf('?');
        
        if (queryPos >= 0 && queryPos + 1 < fullPath.length)
            return fullPath[queryPos + 1 .. $];
        else
            return "";
    }
    
    /**
     * Get request body
     */
    string body()
    {
        if (!valid) return "";
        return wrapper.getBody().toString();
    }
    
    /**
     * Get HTTP version
     */
    string httpVersion()
    {
        if (!valid) return "";
        return wrapper.getVersion().toString();
    }
    
    /**
     * Get header by name (case-insensitive)
     */
    string getHeader(string name)
    {
        if (!valid) return "";
        return wrapper.getHeader(name).toString();
    }
    
    /**
     * Check if header exists
     */
    bool hasHeader(string name)
    {
        if (!valid) return false;
        return wrapper.hasHeader(name);
    }
    
    /**
     * Should keep alive connection
     */
    bool shouldKeepAlive()
    {
        if (!valid) return false;
        return wrapper.request.routing.flags & 0x01;
    }
    
    /**
     * Check if request parsing is complete
     *
     * Returns:
     *   true if HTTP request is fully parsed (headers + body complete)
     *   false if more data needed
     *
     * Now uses REAL messageComplete flag from Wire parser (not heuristic!)
     */
    bool isComplete()
    {
        if (!valid) return false;
        
        // Use Wire parser's messageComplete flag set by llhttp on_message_complete callback
        // This is the REAL completion indicator, not a heuristic
        return wrapper.request.routing.messageComplete;
    }
    
    /**
     * Check if parse error occurred
     */
    bool hasError()
    {
        return !valid;
    }
}

/**
 * HTTP Response - response builder
 */
struct HTTPResponse
{
    private int statusCode = 200;
    private string statusMessage = "OK";
    private string[string] headers;
    private string bodyContent;
    
    /**
     * Create response with status
     */
    this(int code, string message)
    {
        statusCode = code;
        statusMessage = message;
        
        // Set default headers
        headers["Server"] = "Aurora/0.1";
        headers["Connection"] = "keep-alive";
    }
    
    /**
     * Set response header
     */
    void setHeader(string name, string value)
    {
        headers[name] = value;
    }
    
    /**
     * Set response status code
     * Uses O(1) lookup from util.d for status text
     */
    void setStatus(int code, string message = "")
    {
        statusCode = code;
        statusMessage = (message.length > 0) ? message : getStatusText(code);
    }
    
    /**
     * Get current status code
     */
    int getStatus() const
    {
        return statusCode;
    }
    
    /// Property alias for statusCode (for test compatibility)
    @property int status() const
    {
        return statusCode;
    }
    
    /// Get response body content
    @property string getBody() const
    {
        return bodyContent;
    }
    
    /// Get content type
    @property string getContentType() const
    {
        if (auto ct = "Content-Type" in headers)
            return *ct;
        return "text/html";  // Default
    }

    /// Get response headers
    @property ref inout(string[string]) getHeaders() inout
    {
        return headers;
    }
    
    /**
     * Set response body
     */
    void setBody(string content)
    {
        bodyContent = content;
        headers["Content-Length"] = content.length.to!string;
    }
    
    /**
     * Build HTTP response string
     */
    string build() const
    {
        auto result = appender!string();

        // Status line
        result ~= "HTTP/1.1 ";
        result ~= statusCode.to!string;
        result ~= " ";
        result ~= statusMessage;
        result ~= "\r\n";

        // Headers
        foreach (name, value; headers)
        {
            result ~= name;
            result ~= ": ";
            result ~= value;
            result ~= "\r\n";
        }

        result ~= "\r\n";

        // Body
        if (bodyContent.length > 0)
        {
            result ~= bodyContent;
        }

        return result.data;
    }

    /**
     * Format integer to buffer without allocation (@nogc)
     *
     * Params:
     *   value = Integer to format
     *   buffer = Buffer to write into (must be at least 12 chars)
     *
     * Returns:
     *   Number of characters written
     */
    private static size_t formatInt(int value, ref char[12] buffer) @nogc nothrow pure
    {
        if (value == 0)
        {
            buffer[0] = '0';
            return 1;
        }

        bool negative = value < 0;
        if (negative)
        {
            // Handle edge case: int.min cannot be negated
            if (value == int.min)
            {
                // -2147483648
                immutable string minStr = "-2147483648";
                buffer[0 .. minStr.length] = minStr[];
                return minStr.length;
            }
            value = -value;
        }

        // Convert to string in reverse
        char[12] temp;
        size_t pos = 0;

        while (value > 0)
        {
            temp[pos++] = cast(char)('0' + (value % 10));
            value /= 10;
        }

        // Write to output buffer
        size_t writePos = 0;
        if (negative)
            buffer[writePos++] = '-';

        // Reverse digits
        while (pos > 0)
        {
            buffer[writePos++] = temp[--pos];
        }

        return writePos;
    }

    /**
     * Estimate required buffer size for buildInto
     *
     * Returns:
     *   Estimated bytes needed (includes 10% safety margin)
     *
     * Performance: O(headers count), < 1μs
     */
    size_t estimateSize() const @nogc pure
    {
        size_t size = 0;

        // Status line: "HTTP/1.1 NNN Message\r\n"
        // "HTTP/1.1 " = 9 bytes
        // status code = max 3 digits
        // " " = 1 byte
        // status message = variable (max ~50 for standard messages)
        // "\r\n" = 2 bytes
        size += 9 + 3 + 1 + statusMessage.length + 2;

        // Headers: "Name: Value\r\n"
        foreach (name, value; headers)
        {
            size += name.length + 2 + value.length + 2;  // ": " + "\r\n"
        }

        // Blank line
        size += 2;

        // Body
        size += bodyContent.length;

        // Add 10% safety margin for any edge cases
        return size + (size / 10);
    }

    /**
     * Build HTTP response into pre-allocated buffer (@nogc hot-path)
     *
     * This is the zero-allocation method for building responses directly into
     * pool-allocated buffers, eliminating GC allocations in the hot path.
     *
     * Params:
     *   buffer = Pre-allocated buffer to write into
     *
     * Returns:
     *   Number of bytes written, or 0 if buffer too small
     *
     * Performance: O(headers + body_size), < 1μs for typical response
     *
     * Example:
     * ---
     * auto buffer = bufferPool.acquire(BufferSize.SMALL);
     * size_t bytesWritten = response.buildInto(buffer);
     * if (bytesWritten == 0) {
     *     // Buffer too small, try larger
     *     bufferPool.release(buffer);
     *     buffer = bufferPool.acquire(BufferSize.MEDIUM);
     *     bytesWritten = response.buildInto(buffer);
     * }
     * ---
     */
    size_t buildInto(ubyte[] buffer) const @trusted
    {
        size_t pos = 0;

        // Helper: Write string to buffer
        bool writeString(const(char)[] s)
        {
            if (pos + s.length > buffer.length)
                return false;
            buffer[pos .. pos + s.length] = cast(ubyte[])s;
            pos += s.length;
            return true;
        }

        // Helper: Write integer
        bool writeInt(int value)
        {
            char[12] buf;
            size_t len = formatInt(value, buf);
            return writeString(buf[0 .. len]);
        }

        // 1. Status line: "HTTP/1.1 200 OK\r\n"
        if (!writeString("HTTP/1.1 ")) return 0;
        if (!writeInt(statusCode)) return 0;
        if (!writeString(" ")) return 0;
        if (!writeString(statusMessage)) return 0;
        if (!writeString("\r\n")) return 0;

        // 2. Headers: "Name: Value\r\n"
        foreach (name, value; headers)
        {
            if (!writeString(name)) return 0;
            if (!writeString(": ")) return 0;
            if (!writeString(value)) return 0;
            if (!writeString("\r\n")) return 0;
        }

        // 3. Blank line
        if (!writeString("\r\n")) return 0;

        // 4. Body
        if (bodyContent.length > 0)
        {
            if (!writeString(bodyContent)) return 0;
        }

        return pos;
    }
}
