/**
 * CORS Middleware
 *
 * Package: aurora.web.middleware.cors
 *
 * Features:
 * - Preflight OPTIONS handling
 * - CORS headers (Origin, Methods, Headers, Credentials)
 * - Origin validation
 * - Configurable allowed origins/methods/headers
 */
module aurora.web.middleware.cors;

import aurora.web.middleware;
import aurora.web.context;
import aurora.http;

/**
 * CORSConfig - CORS configuration
 */
struct CORSConfig
{
    string[] allowedOrigins = [];  // Empty by default - requires explicit configuration for security
    string[] allowedMethods = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"];
    string[] allowedHeaders = ["*"];
    string[] exposedHeaders = [];
    bool allowCredentials = false;
    uint maxAge = 86400;  // 24 hours
}

/**
 * CORSMiddleware - Cross-Origin Resource Sharing
 */
class CORSMiddleware
{
    private CORSConfig config;
    
    /**
     * Constructor with config
     */
    this(CORSConfig config)
    {
        this.config = config;
    }
    
    /**
     * Handle request (middleware interface)
     */
    void handle(Context ctx, NextFunction next)
    {
        // Get origin from request
        string requestOrigin = ctx.request && ctx.request.hasHeader("Origin")
            ? ctx.request.getHeader("Origin")
            : "";
        
        // Determine allowed origin
        string allowedOrigin = getAllowedOrigin(requestOrigin);
        
        // Handle preflight OPTIONS request
        if (ctx.request && ctx.request.method == "OPTIONS")
        {
            handlePreflight(ctx, allowedOrigin);
            return;  // Don't call next()
        }
        
        // Add CORS headers to normal request
        addCORSHeaders(ctx, allowedOrigin);
        
        // Call next middleware/handler
        next();
    }
    
    private:
    
    /**
     * Get allowed origin for request
     */
    string getAllowedOrigin(string requestOrigin)
    {
        // If no allowed origins configured, return empty
        if (config.allowedOrigins.length == 0)
        {
            return "";
        }
        
        // If wildcard, return wildcard
        if (config.allowedOrigins[0] == "*")
        {
            return "*";
        }
        
        // Check if request origin is in allowed list
        import std.algorithm : canFind;
        import std.uni : toLower;
        
        foreach (allowed; config.allowedOrigins)
        {
            if (toLower(allowed) == toLower(requestOrigin))
            {
                return requestOrigin;  // Return exact match
            }
        }
        
        // Origin not allowed, return first allowed origin
        return config.allowedOrigins[0];
    }
    
    /**
     * Handle preflight OPTIONS request
     */
    void handlePreflight(Context ctx, string allowedOrigin)
    {
        if (!ctx.response) return;
        
        // Set Allow-Origin
        if (allowedOrigin.length > 0)
        {
            ctx.response.setHeader("Access-Control-Allow-Origin", allowedOrigin);
        }
        
        // Set Allow-Methods
        if (config.allowedMethods.length > 0)
        {
            import std.array : join;
            ctx.response.setHeader("Access-Control-Allow-Methods", config.allowedMethods.join(","));
        }
        
        // Set Allow-Headers
        if (config.allowedHeaders.length > 0)
        {
            import std.array : join;
            ctx.response.setHeader("Access-Control-Allow-Headers", config.allowedHeaders.join(","));
        }
        
        // Set Max-Age
        import std.conv : to;
        ctx.response.setHeader("Access-Control-Max-Age", config.maxAge.to!string);
        
        // Set credentials if enabled
        if (config.allowCredentials)
        {
            ctx.response.setHeader("Access-Control-Allow-Credentials", "true");
        }
        
        // Return 204 No Content
        ctx.response.setStatus(204);
    }
    
    /**
     * Add CORS headers to response
     */
    void addCORSHeaders(Context ctx, string allowedOrigin)
    {
        if (!ctx.response) return;
        
        // Set Allow-Origin
        if (allowedOrigin.length > 0)
        {
            ctx.response.setHeader("Access-Control-Allow-Origin", allowedOrigin);
        }
        
        // Set credentials if enabled
        if (config.allowCredentials)
        {
            ctx.response.setHeader("Access-Control-Allow-Credentials", "true");
        }
        
        // Set exposed headers
        if (config.exposedHeaders.length > 0)
        {
            import std.array : join;
            ctx.response.setHeader("Access-Control-Expose-Headers", config.exposedHeaders.join(","));
        }
    }
}

/**
 * Helper function to create CORS middleware
 */
Middleware corsMiddleware(CORSConfig config = CORSConfig())
{
    auto cors = new CORSMiddleware(config);
    
    return (ref Context ctx, NextFunction next) {
        cors.handle(ctx, next);
    };
}
