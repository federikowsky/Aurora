/**
 * Error Handling - HTTPException hierarchy and error middleware
 *
 * Package: aurora.web.error
 *
 * Features:
 * - HTTPException base class
 * - 5 specific exception types
 * - Error middleware pattern
 * - Standard JSON error format
 */
module aurora.web.error;

import aurora.web.context;

/**
 * HTTPException - Base exception for HTTP errors
 *
 * All HTTP exceptions have a status code and optional headers
 */
class HTTPException : Exception
{
    int statusCode;
    string[string] headers;
    
    this(int statusCode, string message, string file = __FILE__, size_t line = __LINE__)
    {
        super(message, file, line);
        this.statusCode = statusCode;
    }
}

/**
 * NotFoundException - 404 Not Found
 */
class NotFoundException : HTTPException
{
    this(string message = "Not Found", string file = __FILE__, size_t line = __LINE__)
    {
        super(404, message, file, line);
    }
}

/**
 * ValidationException - 400 Bad Request
 */
class ValidationException : HTTPException
{
    this(string message, string file = __FILE__, size_t line = __LINE__)
    {
        super(400, message, file, line);
    }
}

/**
 * UnauthorizedException - 401 Unauthorized
 *
 * Automatically sets WWW-Authenticate: Bearer header
 */
class UnauthorizedException : HTTPException
{
    this(string message = "Unauthorized", string file = __FILE__, size_t line = __LINE__)
    {
        super(401, message, file, line);
        headers["WWW-Authenticate"] = "Bearer";
    }
}

/**
 * ForbiddenException - 403 Forbidden
 */
class ForbiddenException : HTTPException
{
    this(string message = "Forbidden", string file = __FILE__, size_t line = __LINE__)
    {
        super(403, message, file, line);
    }
}

/**
 * InternalServerException - 500 Internal Server Error
 */
class InternalServerException : HTTPException
{
    this(string message = "Internal Server Error", string file = __FILE__, size_t line = __LINE__)
    {
        super(500, message, file, line);
    }
}

/**
 * Error middleware - Catches exceptions and formats error responses
 *
 * Usage:
 *   errorMiddleware(ctx, &next);
 *
 * Catches:
 * - HTTPException → formats with status code and message
 * - Exception → returns 500 Internal Server Error
 */
void errorMiddleware(Context ctx, void delegate() next)
{
    try
    {
        next();  // Call next middleware/handler
    }
    catch (HTTPException e)
    {
        // Known HTTP exception
        ctx.status(e.statusCode);
        
        // Set custom headers
        foreach (key, value; e.headers)
        {
            if (ctx.response !is null)
            {
                ctx.response.setHeader(key, value);
            }
        }
        
        // Format error response as JSON
        import std.conv : to;
        string errorJson = "{" ~
            "\"error\":\"" ~ e.msg ~ "\"," ~
            "\"status\":" ~ e.statusCode.to!string;
        
        // Add path if available
        if (ctx.request !is null)
        {
            errorJson ~= ",\"path\":\"" ~ ctx.request.path.to!string ~ "\"";
        }
        
        errorJson ~= "}";
        
        ctx.send(errorJson);
    }
    catch (Exception e)
    {
        // Unknown exception → 500
        ctx.status(500);
        ctx.send("{\"error\":\"Internal Server Error\",\"status\":500}");
    }
}
