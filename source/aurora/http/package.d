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
     * Get request path
     */
    string path()
    {
        if (!valid) return "";
        return wrapper.getPath().toString();
    }
    
    /**
     * Get query string
     */
    string query()
    {
        if (!valid) return "";
        return wrapper.getQuery().toString();
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
    private int statusCode;
    private string statusMessage;
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
}
