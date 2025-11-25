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
     * Supports ALL HTTP status codes (100-599) per RFC specifications
     */
    void setStatus(int code, string message = "")
    {
        statusCode = code;
        if (message.length > 0)
        {
            statusMessage = message;
        }
        else
        {
            // Set standard message for ALL HTTP status codes
            switch (code)
            {
                // 1xx Informational
                case 100: statusMessage = "Continue"; break;
                case 101: statusMessage = "Switching Protocols"; break;
                case 102: statusMessage = "Processing"; break;
                case 103: statusMessage = "Early Hints"; break;
                
                // 2xx Success
                case 200: statusMessage = "OK"; break;
                case 201: statusMessage = "Created"; break;
                case 202: statusMessage = "Accepted"; break;
                case 203: statusMessage = "Non-Authoritative Information"; break;
                case 204: statusMessage = "No Content"; break;
                case 205: statusMessage = "Reset Content"; break;
                case 206: statusMessage = "Partial Content"; break;
                case 207: statusMessage = "Multi-Status"; break;
                case 208: statusMessage = "Already Reported"; break;
                case 226: statusMessage = "IM Used"; break;
                
                // 3xx Redirection
                case 300: statusMessage = "Multiple Choices"; break;
                case 301: statusMessage = "Moved Permanently"; break;
                case 302: statusMessage = "Found"; break;
                case 303: statusMessage = "See Other"; break;
                case 304: statusMessage = "Not Modified"; break;
                case 305: statusMessage = "Use Proxy"; break;
                case 306: statusMessage = "Switch Proxy"; break;
                case 307: statusMessage = "Temporary Redirect"; break;
                case 308: statusMessage = "Permanent Redirect"; break;
                
                // 4xx Client Error
                case 400: statusMessage = "Bad Request"; break;
                case 401: statusMessage = "Unauthorized"; break;
                case 402: statusMessage = "Payment Required"; break;
                case 403: statusMessage = "Forbidden"; break;
                case 404: statusMessage = "Not Found"; break;
                case 405: statusMessage = "Method Not Allowed"; break;
                case 406: statusMessage = "Not Acceptable"; break;
                case 407: statusMessage = "Proxy Authentication Required"; break;
                case 408: statusMessage = "Request Timeout"; break;
                case 409: statusMessage = "Conflict"; break;
                case 410: statusMessage = "Gone"; break;
                case 411: statusMessage = "Length Required"; break;
                case 412: statusMessage = "Precondition Failed"; break;
                case 413: statusMessage = "Payload Too Large"; break;
                case 414: statusMessage = "URI Too Long"; break;
                case 415: statusMessage = "Unsupported Media Type"; break;
                case 416: statusMessage = "Range Not Satisfiable"; break;
                case 417: statusMessage = "Expectation Failed"; break;
                case 418: statusMessage = "I'm a teapot"; break;
                case 421: statusMessage = "Misdirected Request"; break;
                case 422: statusMessage = "Unprocessable Entity"; break;
                case 423: statusMessage = "Locked"; break;
                case 424: statusMessage = "Failed Dependency"; break;
                case 425: statusMessage = "Too Early"; break;
                case 426: statusMessage = "Upgrade Required"; break;
                case 428: statusMessage = "Precondition Required"; break;
                case 429: statusMessage = "Too Many Requests"; break;
                case 431: statusMessage = "Request Header Fields Too Large"; break;
                case 451: statusMessage = "Unavailable For Legal Reasons"; break;
                
                // 5xx Server Error
                case 500: statusMessage = "Internal Server Error"; break;
                case 501: statusMessage = "Not Implemented"; break;
                case 502: statusMessage = "Bad Gateway"; break;
                case 503: statusMessage = "Service Unavailable"; break;
                case 504: statusMessage = "Gateway Timeout"; break;
                case 505: statusMessage = "HTTP Version Not Supported"; break;
                case 506: statusMessage = "Variant Also Negotiates"; break;
                case 507: statusMessage = "Insufficient Storage"; break;
                case 508: statusMessage = "Loop Detected"; break;
                case 510: statusMessage = "Not Extended"; break;
                case 511: statusMessage = "Network Authentication Required"; break;
                
                // Default for unknown codes
                default: 
                    if (code >= 100 && code < 200)
                        statusMessage = "Informational";
                    else if (code >= 200 && code < 300)
                        statusMessage = "Success";
                    else if (code >= 300 && code < 400)
                        statusMessage = "Redirection";
                    else if (code >= 400 && code < 500)
                        statusMessage = "Client Error";
                    else if (code >= 500 && code < 600)
                        statusMessage = "Server Error";
                    else
                        statusMessage = "Unknown";
                    break;
            }
        }
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
