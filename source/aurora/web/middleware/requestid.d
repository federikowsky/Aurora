/**
 * Request ID Middleware
 *
 * Package: aurora.web.middleware.requestid
 *
 * Features:
 * - UUID generation for request tracing
 * - Preserves existing X-Request-ID header
 * - Configurable header name
 * - Stores ID in context for logging
 * - Thread-safe
 */
module aurora.web.middleware.requestid;

import aurora.web.middleware;
import aurora.web.context;
import std.uuid : randomUUID;

/**
 * RequestIdConfig - Configuration for request ID middleware
 */
struct RequestIdConfig
{
    /// Header name to use for request ID
    string headerName = "X-Request-ID";
    
    /// Whether to preserve existing request ID from client
    bool preserveExisting = true;
    
    /// Context storage key for the request ID
    string storageKey = "requestId";
    
    /// Custom ID generator (default: UUID v4)
    string delegate() generator = null;
    
    /// Whether to set the header on response
    bool setResponseHeader = true;
}

/**
 * Request ID storage wrapper
 * 
 * Used to safely store the request ID string in context storage.
 * We use a class to get a stable reference that can be cast to void*.
 */
private class RequestIdHolder
{
    string value;
    
    this(string v) { value = v; }
}

/**
 * RequestIdMiddleware - Generates or preserves request IDs
 *
 * This middleware:
 * 1. Checks for existing X-Request-ID header
 * 2. Generates new UUID if none exists
 * 3. Stores ID in context for logging
 * 4. Sets response header
 */
class RequestIdMiddleware
{
    private RequestIdConfig config;
    
    /**
     * Create middleware with default config
     */
    this()
    {
        this.config = RequestIdConfig();
    }
    
    /**
     * Create middleware with custom config
     */
    this(RequestIdConfig config)
    {
        this.config = config;
    }
    
    /**
     * Get the middleware function
     */
    Middleware middleware()
    {
        return (ref Context ctx, NextFunction next) {
            string requestId;
            
            // Check for existing request ID
            if (config.preserveExisting && ctx.request !is null)
            {
                string existing = ctx.request.getHeader(config.headerName);
                if (existing.length > 0 && isValidRequestId(existing))
                {
                    requestId = existing;
                }
            }
            
            // Generate new ID if needed
            if (requestId.length == 0)
            {
                requestId = generateId();
            }
            
            // Store in context (using holder class for stable reference)
            auto holder = new RequestIdHolder(requestId);
            ctx.storage.set(config.storageKey, holder);
            
            // Set response header
            if (config.setResponseHeader && ctx.response !is null)
            {
                ctx.response.setHeader(config.headerName, requestId);
            }
            
            next();
        };
    }
    
    /**
     * Generate a new request ID
     */
    private string generateId()
    {
        if (config.generator !is null)
        {
            return config.generator();
        }
        return randomUUID().toString();
    }
    
    /**
     * Validate request ID format
     * 
     * Accepts:
     * - UUIDs (with or without dashes)
     * - Alphanumeric strings 8-128 chars
     * - Common ID formats (e.g., "req_abc123")
     */
    private static bool isValidRequestId(string id) @safe pure nothrow
    {
        if (id.length < 8 || id.length > 128)
            return false;
        
        // Allow alphanumeric, dashes, underscores
        foreach (char c; id)
        {
            if (!isAllowedChar(c))
                return false;
        }
        
        return true;
    }
    
    private static bool isAllowedChar(char c) @safe pure nothrow
    {
        return (c >= 'a' && c <= 'z') ||
               (c >= 'A' && c <= 'Z') ||
               (c >= '0' && c <= '9') ||
               c == '-' || c == '_';
    }
}

/**
 * Helper function to get request ID from context
 *
 * Usage:
 * ---
 * auto id = getRequestId(ctx);
 * ---
 */
string getRequestId(ref Context ctx, string storageKey = "requestId")
{
    auto holder = ctx.storage.get!RequestIdHolder(storageKey);
    if (holder !is null)
    {
        return holder.value;
    }
    return "";
}

/**
 * Factory function for simple usage
 *
 * Usage:
 * ---
 * router.use(requestIdMiddleware());
 * ---
 */
Middleware requestIdMiddleware()
{
    return new RequestIdMiddleware().middleware();
}

/**
 * Factory function with custom config
 *
 * Usage:
 * ---
 * auto config = RequestIdConfig();
 * config.headerName = "X-Correlation-ID";
 * router.use(requestIdMiddleware(config));
 * ---
 */
Middleware requestIdMiddleware(RequestIdConfig config)
{
    return new RequestIdMiddleware(config).middleware();
}
