/+ dub.sdl:
name "auth_apikey"
dependency "aurora" path=".."
+/
/**
 * Aurora API Key Authentication Example
 *
 * This example demonstrates how to implement API Key authentication
 * as middleware in an Aurora application. API Key authentication is
 * simpler than JWT and suitable for service-to-service communication
 * or simple client authentication.
 *
 * Common API Key patterns demonstrated:
 * 1. Header-based: X-API-Key header
 * 2. Query parameter: ?api_key=xxx
 * 3. Key scopes/permissions
 * 4. Rate limiting per key
 * 5. Key validation and lookup
 *
 * IMPORTANT: This is an EXAMPLE implementation for educational purposes.
 * For production use, consider:
 * - Store keys in a secure database (hashed)
 * - Implement key rotation
 * - Use rate limiting per key
 * - Log key usage for auditing
 * - Use HTTPS only
 * - Implement key revocation
 *
 * To run:
 *   cd examples
 *   dub run --single auth_apikey.d
 *
 * Test with curl:
 *   # Using header (preferred)
 *   curl http://localhost:8080/api/data \
 *        -H "X-API-Key: demo-key-123"
 *
 *   # Using query parameter (less secure)
 *   curl "http://localhost:8080/api/data?api_key=demo-key-123"
 *
 *   # Admin endpoint (requires admin scope)
 *   curl http://localhost:8080/admin/stats \
 *        -H "X-API-Key: admin-key-456"
 */
module examples.auth_apikey;

import aurora;
import aurora.web.middleware : Middleware, NextFunction;
import std.datetime;
import std.conv : to;
import std.algorithm : canFind;
import std.format : format;

// ============================================================================
// API KEY CONFIGURATION
// ============================================================================

/**
 * API Key Configuration
 * 
 * Configure where to look for API keys and validation behavior.
 */
struct APIKeyConfig
{
    /// Header name for API key (standard: X-API-Key)
    string headerName = "X-API-Key";
    
    /// Query parameter name (alternative to header)
    string queryParamName = "api_key";
    
    /// Allow key in query parameter (less secure, disable in production)
    bool allowQueryParam = true;
    
    /// Paths that don't require API key
    string[] publicPaths = ["/", "/health", "/docs"];
    
    /// Custom error message
    string unauthorizedMessage = "Invalid or missing API key";
    
    /// Whether to include WWW-Authenticate header on 401
    bool includeWWWAuthenticate = true;
}

// ============================================================================
// API KEY DATA STRUCTURES
// ============================================================================

/**
 * API Key Information
 * 
 * Represents a valid API key with its metadata and permissions.
 */
struct APIKeyInfo
{
    /// Unique key identifier (not the key itself)
    string keyId;
    
    /// Display name for the key
    string name;
    
    /// Owner/client name
    string owner;
    
    /// Scopes/permissions granted
    string[] scopes;
    
    /// Rate limit (requests per minute, 0 = unlimited)
    uint rateLimit;
    
    /// When the key was created
    long createdAt;
    
    /// When the key expires (0 = never)
    long expiresAt;
    
    /// Whether the key is active
    bool active = true;
    
    /**
     * Check if key has a specific scope
     */
    bool hasScope(string scope_) const
    {
        return scopes.canFind(scope_) || scopes.canFind("*");
    }
    
    /**
     * Check if key is expired
     */
    bool isExpired() const
    {
        if (expiresAt == 0) return false;
        return Clock.currTime(UTC()).toUnixTime() > expiresAt;
    }
}

// ============================================================================
// API KEY STORE (SIMULATED)
// ============================================================================

/**
 * Simple API Key Store
 * 
 * In production, replace with:
 * - Database lookup (Redis, PostgreSQL, etc.)
 * - Key hashing (store hash, not plaintext)
 * - Caching layer for performance
 */
struct APIKeyStore
{
    private static APIKeyInfo[string] keys;
    
    static this()
    {
        // Pre-populate with demo keys
        auto now = Clock.currTime(UTC()).toUnixTime();
        
        // Demo key with basic access
        keys["demo-key-123"] = APIKeyInfo(
            "key_001",
            "Demo Key",
            "Demo Client",
            ["read", "write"],
            100,  // 100 requests/minute
            now,
            0,    // Never expires
            true
        );
        
        // Admin key with full access
        keys["admin-key-456"] = APIKeyInfo(
            "key_002",
            "Admin Key",
            "System Administrator",
            ["*"],  // All scopes
            0,      // Unlimited
            now,
            0,
            true
        );
        
        // Read-only key
        keys["readonly-key-789"] = APIKeyInfo(
            "key_003",
            "Read-Only Key",
            "Analytics Service",
            ["read"],
            1000,
            now,
            0,
            true
        );
        
        // Expired key (for testing)
        keys["expired-key-000"] = APIKeyInfo(
            "key_004",
            "Expired Key",
            "Old Client",
            ["read"],
            100,
            now - 86400 * 30,  // Created 30 days ago
            now - 86400,       // Expired yesterday
            true
        );
        
        // Disabled key (for testing)
        keys["disabled-key-999"] = APIKeyInfo(
            "key_005",
            "Disabled Key",
            "Banned Client",
            ["read"],
            100,
            now,
            0,
            false  // Disabled
        );
    }
    
    /**
     * Validate an API key
     * 
     * Returns: APIKeyInfo if valid, null otherwise
     */
    static const(APIKeyInfo)* validate(string apiKey)
    {
        if (auto info = apiKey in keys)
        {
            // Check if active
            if (!info.active)
                return null;
            
            // Check if expired
            if (info.isExpired())
                return null;
            
            return info;
        }
        return null;
    }
}

// ============================================================================
// API KEY MIDDLEWARE
// ============================================================================

/**
 * API Key Authentication Middleware
 * 
 * This middleware:
 * 1. Checks if the path is public (skip authentication)
 * 2. Extracts API key from header or query parameter
 * 3. Validates the key against the store
 * 4. Stores key info in context for route handlers
 * 5. Returns 401 Unauthorized if validation fails
 */
class APIKeyMiddleware
{
    private APIKeyConfig config;
    
    this(APIKeyConfig config = APIKeyConfig())
    {
        this.config = config;
    }
    
    /**
     * Middleware handler function
     */
    void handle(ref Context ctx, NextFunction next)
    {
        // Get request path
        string path = ctx.request ? ctx.request.path : "/";
        
        // Check if path is public
        if (isPublicPath(path))
        {
            next();
            return;
        }
        
        // Extract API key
        string apiKey = extractAPIKey(ctx);
        if (apiKey.length == 0)
        {
            unauthorized(ctx, "Missing API key");
            return;
        }
        
        // Validate key
        auto keyInfo = APIKeyStore.validate(apiKey);
        if (keyInfo is null)
        {
            unauthorized(ctx, config.unauthorizedMessage);
            return;
        }
        
        // Store key info in context
        auto holder = new APIKeyHolder(*keyInfo);
        ctx.storage.set("api_key_info", holder);
        ctx.storage.set("authenticated", cast(void*)1);
        
        // Continue to next middleware/handler
        next();
    }
    
    /**
     * Get middleware as delegate for Aurora
     */
    Middleware middleware()
    {
        return (ref Context ctx, NextFunction next) {
            this.handle(ctx, next);
        };
    }
    
    private:
    
    /**
     * Check if path is in public paths list
     */
    bool isPublicPath(string path)
    {
        foreach (publicPath; config.publicPaths)
        {
            if (path == publicPath)
                return true;
            // Check path prefix
            if (publicPath.length > 0 && path.length > publicPath.length)
            {
                if (path[0..publicPath.length] == publicPath && 
                    (publicPath[$-1] == '/' || path[publicPath.length] == '/'))
                    return true;
            }
        }
        return false;
    }
    
    /**
     * Extract API key from header or query parameter
     */
    string extractAPIKey(ref Context ctx)
    {
        if (ctx.request is null)
            return "";
        
        // First try header (preferred)
        string headerKey = ctx.request.getHeader(config.headerName);
        if (headerKey.length > 0)
            return headerKey;
        
        // Then try query parameter (if allowed)
        if (config.allowQueryParam)
        {
            string query = ctx.request.query();
            if (query.length > 0)
            {
                // Simple query string parsing
                import std.string : indexOf;
                import std.algorithm : splitter;
                
                foreach (param; query.splitter('&'))
                {
                    auto eqPos = param.indexOf('=');
                    if (eqPos > 0)
                    {
                        string key = param[0..eqPos];
                        string value = param[eqPos+1..$];
                        if (key == config.queryParamName)
                            return value;
                    }
                }
            }
        }
        
        return "";
    }
    
    /**
     * Send 401 Unauthorized response
     */
    void unauthorized(ref Context ctx, string message)
    {
        auto response = ctx.status(401);
        
        if (config.includeWWWAuthenticate)
        {
            response = response.header("WWW-Authenticate", 
                `API-Key realm="api", charset="UTF-8"`);
        }
        
        response.header("Content-Type", "application/json")
                .send(format!`{"error":"Unauthorized","message":"%s"}`(message));
    }
}

/**
 * API Key info holder class for context storage
 */
private class APIKeyHolder
{
    APIKeyInfo info;
    this(const APIKeyInfo i) { 
        info = cast()i;  // Copy to mutable
    }
}

/**
 * Helper function to get API key info from context
 * 
 * Usage in route handlers:
 *   auto keyInfo = getAPIKeyInfo(ctx);
 *   if (keyInfo !is null && keyInfo.hasScope("admin")) {
 *       // Admin access
 *   }
 */
const(APIKeyInfo)* getAPIKeyInfo(ref Context ctx)
{
    auto holder = ctx.storage.get!APIKeyHolder("api_key_info");
    if (holder !is null)
        return &holder.info;
    return null;
}

/**
 * Require scope middleware factory
 * 
 * Creates a middleware that checks if the authenticated API key
 * has a specific scope. Use this for route-level authorization.
 * 
 * Usage:
 *   app.get("/admin/stats", requireScope("admin"), (ref ctx) { ... });
 */
Middleware requireScope(string requiredScope)
{
    return (ref Context ctx, NextFunction next) {
        auto keyInfo = getAPIKeyInfo(ctx);
        
        if (keyInfo is null)
        {
            ctx.status(401)
               .json(`{"error":"Unauthorized","message":"Authentication required"}`);
            return;
        }
        
        if (!keyInfo.hasScope(requiredScope))
        {
            ctx.status(403)
               .json(format!`{"error":"Forbidden","message":"Scope '%s' required"}`(requiredScope));
            return;
        }
        
        next();
    };
}

// ============================================================================
// EXAMPLE SERVER
// ============================================================================

void main()
{
    import std.stdio : writeln;
    
    writeln("===========================================");
    writeln("   Aurora API Key Authentication Example");
    writeln("===========================================");
    writeln();
    
    // Create API Key configuration
    APIKeyConfig apiKeyConfig;
    apiKeyConfig.publicPaths = ["/", "/health", "/docs"];
    apiKeyConfig.allowQueryParam = true;  // For demo (disable in production)
    
    // Create middleware
    auto apiKeyMiddleware = new APIKeyMiddleware(apiKeyConfig);
    
    // Create app
    auto app = new App();
    
    // Add API key middleware globally
    app.use(apiKeyMiddleware.middleware());
    
    // ======================
    // PUBLIC ROUTES
    // ======================
    
    // Health check (public)
    app.get("/health", (ref ctx) {
        ctx.json(`{"status":"healthy","service":"aurora-apikey-example"}`);
    });
    
    // Home page (public)
    app.get("/", (ref ctx) {
        ctx.header("Content-Type", "text/html")
           .send(`
            <html>
            <head><title>Aurora API Key Example</title></head>
            <body>
                <h1>Aurora API Key Authentication Example</h1>
                <h2>Available Endpoints:</h2>
                <ul>
                    <li><code>GET /health</code> - Health check (public)</li>
                    <li><code>GET /docs</code> - API documentation (public)</li>
                    <li><code>GET /api/data</code> - Get data (requires API key)</li>
                    <li><code>POST /api/data</code> - Create data (requires 'write' scope)</li>
                    <li><code>GET /admin/stats</code> - Admin stats (requires 'admin' or '*' scope)</li>
                </ul>
                <h2>Demo API Keys:</h2>
                <table border="1" cellpadding="10">
                    <tr><th>Key</th><th>Scopes</th><th>Rate Limit</th></tr>
                    <tr><td>demo-key-123</td><td>read, write</td><td>100/min</td></tr>
                    <tr><td>admin-key-456</td><td>* (all)</td><td>unlimited</td></tr>
                    <tr><td>readonly-key-789</td><td>read</td><td>1000/min</td></tr>
                    <tr><td>expired-key-000</td><td>read</td><td>expired!</td></tr>
                    <tr><td>disabled-key-999</td><td>read</td><td>disabled!</td></tr>
                </table>
            </body>
            </html>
           `);
    });
    
    // API Documentation (public)
    app.get("/docs", (ref ctx) {
        ctx.json(`{
            "api_version": "1.0",
            "authentication": {
                "type": "API Key",
                "header": "X-API-Key",
                "query_param": "api_key"
            },
            "endpoints": [
                {"method": "GET", "path": "/api/data", "scopes": ["read"]},
                {"method": "POST", "path": "/api/data", "scopes": ["write"]},
                {"method": "GET", "path": "/admin/stats", "scopes": ["admin"]}
            ]
        }`);
    });
    
    // ======================
    // PROTECTED API ROUTES
    // ======================
    
    // Get data (requires valid API key with 'read' scope)
    app.get("/api/data", (ref ctx) {
        auto keyInfo = getAPIKeyInfo(ctx);
        if (keyInfo is null)
        {
            ctx.status(500).json(`{"error":"Internal error"}`);
            return;
        }
        
        // Check read scope
        if (!keyInfo.hasScope("read"))
        {
            ctx.status(403)
               .json(`{"error":"Forbidden","message":"'read' scope required"}`);
            return;
        }
        
        ctx.json(format!`{
            "data": [
                {"id": 1, "name": "Item 1"},
                {"id": 2, "name": "Item 2"},
                {"id": 3, "name": "Item 3"}
            ],
            "meta": {
                "authenticated_as": "%s",
                "key_id": "%s",
                "rate_limit": %d
            }
        }`(keyInfo.owner, keyInfo.keyId, keyInfo.rateLimit));
    });
    
    // Create data (requires 'write' scope)
    app.post("/api/data", (ref ctx) {
        auto keyInfo = getAPIKeyInfo(ctx);
        if (keyInfo is null)
        {
            ctx.status(500).json(`{"error":"Internal error"}`);
            return;
        }
        
        // Check write scope
        if (!keyInfo.hasScope("write"))
        {
            ctx.status(403)
               .json(`{"error":"Forbidden","message":"'write' scope required"}`);
            return;
        }
        
        ctx.status(201)
           .json(`{"created": true, "id": 4, "message": "Data created successfully"}`);
    });
    
    // Admin stats (requires admin scope or wildcard)
    app.get("/admin/stats", (ref ctx) {
        auto keyInfo = getAPIKeyInfo(ctx);
        if (keyInfo is null)
        {
            ctx.status(500).json(`{"error":"Internal error"}`);
            return;
        }
        
        // Check admin scope (or wildcard)
        if (!keyInfo.hasScope("admin") && !keyInfo.hasScope("*"))
        {
            ctx.status(403)
               .json(`{"error":"Forbidden","message":"'admin' scope required"}`);
            return;
        }
        
        ctx.json(`{
            "stats": {
                "total_keys": 5,
                "active_keys": 3,
                "total_requests_today": 12345,
                "top_clients": [
                    {"name": "Analytics Service", "requests": 5000},
                    {"name": "Demo Client", "requests": 2000}
                ]
            }
        }`);
    });
    
    // ======================
    // START SERVER
    // ======================
    
    writeln("Test commands:");
    writeln();
    writeln("  # Using X-API-Key header (recommended):");
    writeln(`  curl http://localhost:8080/api/data -H "X-API-Key: demo-key-123"`);
    writeln();
    writeln("  # Using query parameter:");
    writeln(`  curl "http://localhost:8080/api/data?api_key=demo-key-123"`);
    writeln();
    writeln("  # Admin endpoint:");
    writeln(`  curl http://localhost:8080/admin/stats -H "X-API-Key: admin-key-456"`);
    writeln();
    writeln("  # Try expired key (should fail):");
    writeln(`  curl http://localhost:8080/api/data -H "X-API-Key: expired-key-000"`);
    writeln();
    writeln("  # Try disabled key (should fail):");
    writeln(`  curl http://localhost:8080/api/data -H "X-API-Key: disabled-key-999"`);
    writeln();
    writeln("Starting server on http://localhost:8080");
    writeln("-------------------------------------------");
    
    // Start server
    app.listen(8080);
}
