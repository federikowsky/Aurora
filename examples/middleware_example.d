/**
 * Aurora Middleware Pipeline Example
 * 
 * Demonstrates middleware patterns:
 * - Authentication middleware
 * - Rate limiting
 * - Request/response logging
 * - Error handling middleware
 * - Custom middleware chaining
 * - Conditional middleware
 */
module examples.middleware_example;

import aurora;
import std.datetime;
import std.conv : to;
import std.algorithm : canFind;
import std.json;
import std.format : format;

// ============================================================================
// Authentication Middleware
// ============================================================================

class AuthMiddleware
{
    private string[] validTokens;
    private string[] publicPaths;
    
    this()
    {
        // Simulated valid API tokens
        validTokens = ["token123", "token456", "admin-token"];
        
        // Paths that don't require authentication
        publicPaths = ["/", "/health", "/api/public", "/login"];
    }
    
    void handle(ref Context ctx, NextFunction next)
    {
        // Check if path is public
        string path = ctx.request ? ctx.request.path : "/";
        
        foreach (publicPath; publicPaths)
        {
            if (path == publicPath || path.canFind(publicPath ~ "/"))
            {
                next();
                return;
            }
        }
        
        // Get Authorization header
        string authHeader = "";
        if (ctx.request && ctx.request.hasHeader("Authorization"))
        {
            authHeader = ctx.request.getHeader("Authorization");
        }
        
        // Validate token
        if (authHeader.length > 7 && authHeader[0..7] == "Bearer ")
        {
            string token = authHeader[7..$];
            
            if (validTokens.canFind(token))
            {
                // Store user info in context
                ctx.storage.set("authenticated", cast(void*)1);
                ctx.storage.set("token", cast(void*)token.ptr);
                next();
                return;
            }
        }
        
        // Unauthorized
        ctx.status(401)
           .header("WWW-Authenticate", "Bearer")
           .json(`{"error":"Unauthorized","message":"Valid Bearer token required"}`);
    }
}

// ============================================================================
// Rate Limiter Middleware
// ============================================================================

class RateLimiter
{
    private uint maxRequests;
    private Duration window;
    private ulong[string] requestCounts;
    private SysTime[string] windowStarts;
    
    this(uint maxRequests = 100, Duration window = 60.seconds)
    {
        this.maxRequests = maxRequests;
        this.window = window;
    }
    
    void handle(ref Context ctx, NextFunction next)
    {
        // Use client IP as key (simplified - would use real IP in production)
        string clientKey = "default-client";
        
        auto now = Clock.currTime();
        
        // Check if window expired
        if (clientKey in windowStarts)
        {
            if (now - windowStarts[clientKey] > window)
            {
                // Reset window
                requestCounts[clientKey] = 0;
                windowStarts[clientKey] = now;
            }
        }
        else
        {
            windowStarts[clientKey] = now;
            requestCounts[clientKey] = 0;
        }
        
        // Check limit
        if (requestCounts[clientKey] >= maxRequests)
        {
            auto resetTime = windowStarts[clientKey] + window;
            auto remaining = (resetTime - now).total!"seconds";
            
            ctx.status(429)
               .header("X-RateLimit-Limit", maxRequests.to!string)
               .header("X-RateLimit-Remaining", "0")
               .header("X-RateLimit-Reset", remaining.to!string)
               .header("Retry-After", remaining.to!string)
               .json(`{"error":"Too Many Requests","retryAfter":` ~ remaining.to!string ~ `}`);
            return;
        }
        
        // Increment counter
        requestCounts[clientKey]++;
        
        // Add rate limit headers
        auto remaining = maxRequests - requestCounts[clientKey];
        ctx.response.setHeader("X-RateLimit-Limit", maxRequests.to!string);
        ctx.response.setHeader("X-RateLimit-Remaining", remaining.to!string);
        
        next();
    }
}

// ============================================================================
// Request Logger Middleware
// ============================================================================

class RequestLogger
{
    import std.stdio : writefln;
    import std.datetime.stopwatch : StopWatch, AutoStart;
    
    void handle(ref Context ctx, NextFunction next)
    {
        auto sw = StopWatch(AutoStart.yes);
        
        string method = ctx.request ? ctx.request.method : "?";
        string path = ctx.request ? ctx.request.path : "?";
        
        // Call next middleware/handler
        next();
        
        sw.stop();
        
        int status = ctx.response ? ctx.response.status : 0;
        auto duration = sw.peek.total!"usecs";
        
        // Log format: [TIME] METHOD PATH STATUS DURATION
        auto timestamp = Clock.currTime().toISOExtString()[0..19];
        writefln("[%s] %s %s %d %dμs", timestamp, method, path, status, duration);
    }
}

// ============================================================================
// Error Handler Middleware
// ============================================================================

class ErrorHandler
{
    void handle(ref Context ctx, NextFunction next)
    {
        try
        {
            next();
            
            // Check for unhandled 404
            if (ctx.response && ctx.response.status == 0)
            {
                ctx.status(404).json(`{"error":"Not Found"}`);
            }
        }
        catch (Exception e)
        {
            // Log error
            import std.stdio : stderr;
            stderr.writefln("[ERROR] %s", e.msg);
            
            // Send error response
            ctx.status(500).json(`{"error":"Internal Server Error"}`);
        }
    }
}

// ============================================================================
// JSON Body Parser Middleware
// ============================================================================

class JsonBodyParser
{
    void handle(ref Context ctx, NextFunction next)
    {
        if (ctx.request && ctx.request.body.length > 0)
        {
            string contentType = ctx.request.getHeader("Content-Type");
            
            if (contentType.canFind("application/json"))
            {
                try
                {
                    auto json = parseJSON(cast(string)ctx.request.body);
                    // Store parsed JSON in context for handlers to use
                    // Note: Simplified - real impl would store properly
                }
                catch (JSONException)
                {
                    ctx.status(400).json(`{"error":"Invalid JSON body"}`);
                    return;
                }
            }
        }
        
        next();
    }
}

// ============================================================================
// Response Time Header Middleware
// ============================================================================

Middleware responseTimeMiddleware()
{
    return (ref Context ctx, NextFunction next) {
        import std.datetime.stopwatch : StopWatch, AutoStart;
        
        auto sw = StopWatch(AutoStart.yes);
        
        next();
        
        sw.stop();
        auto ms = sw.peek.total!"usecs" / 1000.0;
        
        if (ctx.response)
        {
            ctx.response.setHeader("X-Response-Time", format("%.2fms", ms));
        }
    };
}

// ============================================================================
// Request ID Middleware
// ============================================================================

Middleware requestIdMiddleware()
{
    return (ref Context ctx, NextFunction next) {
        import std.uuid : randomUUID;
        
        // Generate request ID
        string requestId = randomUUID().toString();
        
        // Add to request headers (for logging)
        ctx.storage.set("requestId", cast(void*)requestId.ptr);
        
        // Add to response headers
        if (ctx.response)
        {
            ctx.response.setHeader("X-Request-ID", requestId);
        }
        
        next();
    };
}

// ============================================================================
// Main Application
// ============================================================================

void main()
{
    auto config = ServerConfig.defaults();
    config.numWorkers = 4;
    
    auto app = new App(config);
    
    // ========================================================================
    // Middleware Stack (order matters!)
    // ========================================================================
    
    // 1. Request ID (first, so all logs have it)
    app.use(requestIdMiddleware());
    
    // 2. Response time header
    app.use(responseTimeMiddleware());
    
    // 3. Error handler (wraps everything)
    app.use(new ErrorHandler());
    
    // 4. Request logger
    app.use(new RequestLogger());
    
    // 5. CORS
    app.use(new CORSMiddleware(CORSConfig()));
    
    // 6. Security headers
    app.use(new SecurityMiddleware(SecurityConfig()));
    
    // 7. Rate limiter (100 requests per minute)
    app.use(new RateLimiter(100, 60.seconds));
    
    // 8. Authentication (checks Bearer token)
    app.use(new AuthMiddleware());
    
    // 9. JSON body parser
    app.use(new JsonBodyParser());
    
    // ========================================================================
    // Routes
    // ========================================================================
    
    // Public routes (no auth required)
    app.get("/", (ref Context ctx) {
        ctx.json(["message": "Welcome to the API", "version": "1.0"]);
    });
    
    app.get("/health", (ref Context ctx) {
        ctx.json(["status": "healthy"]);
    });
    
    app.get("/api/public/info", (ref Context ctx) {
        ctx.json(["info": "This is public information"]);
    });
    
    app.post("/login", (ref Context ctx) {
        // Simplified login - returns a token
        ctx.json(["token": "token123", "message": "Use this token in Authorization header"]);
    });
    
    // Protected routes (require auth)
    app.get("/api/protected", (ref Context ctx) {
        ctx.json(["message": "You are authenticated!", "data": "secret-data"]);
    });
    
    app.get("/api/user/profile", (ref Context ctx) {
        // Check if authenticated (set by AuthMiddleware)
        auto authenticated = ctx.storage.get!(void*)("authenticated");
        
        if (authenticated !is null)
        {
            ctx.json(["username": "demo-user", "email": "demo@example.com"]);
        }
        else
        {
            ctx.status(401).json(`{"error":"Not authenticated"}`);
        }
    });
    
    app.post("/api/data", (ref Context ctx) {
        // Echo back the received data
        auto body = ctx.request ? cast(string)ctx.request.body : "{}";
        ctx.json(`{"received":` ~ body ~ `}`);
    });
    
    // Rate limit test endpoint
    app.get("/api/ratelimit-test", (ref Context ctx) {
        ctx.json(["message": "Request successful. Check X-RateLimit-* headers."]);
    });
    
    // ========================================================================
    // Start Server
    // ========================================================================
    
    import std.stdio : writefln;
    writefln("Middleware Demo starting on http://localhost:8080");
    writefln("\nMiddleware stack:");
    writefln("  1. Request ID");
    writefln("  2. Response Time");
    writefln("  3. Error Handler");
    writefln("  4. Request Logger");
    writefln("  5. CORS");
    writefln("  6. Security Headers");
    writefln("  7. Rate Limiter (100/min)");
    writefln("  8. Authentication");
    writefln("  9. JSON Body Parser");
    writefln("\nTest commands:");
    writefln("  curl http://localhost:8080/                     # Public");
    writefln("  curl http://localhost:8080/api/protected        # 401 Unauthorized");
    writefln("  curl -H 'Authorization: Bearer token123' http://localhost:8080/api/protected");
    
    app.listen(8080);
}
