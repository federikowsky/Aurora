/+ dub.sdl:
name "auth_jwt"
dependency "aurora" path=".."
dependency "jwtlited:phobos" version="~>1.4.0"
+/
/**
 * Aurora JWT Authentication Example
 *
 * This example demonstrates production-ready JWT (JSON Web Token) authentication
 * using the jwtlited library for secure HS256 signing/verification.
 *
 * Features demonstrated:
 * - Real JWT implementation using jwtlited:phobos library
 * - HS256 HMAC signature generation and verification
 * - Token expiration validation
 * - Claims extraction and validation
 * - Public/protected route patterns
 * - Role-based access control
 * - User context propagation through middleware
 * - Error handling with proper HTTP status codes
 *
 * Dependencies:
 * - jwtlited:phobos - Fast, lightweight JWT library for D (HS256/384/512)
 *
 * Security considerations for production:
 * - Store secrets in environment variables or vault
 * - Consider using asymmetric keys (RS256, ES256) with jwtlited:openssl
 * - Implement token refresh mechanisms
 * - Add token revocation (blacklists/whitelists)
 * - Use HTTPS in production
 * - Set appropriate token expiration times
 *
 * To run:
 *   cd examples
 *   dub run --single auth_jwt.d
 *
 * Test with curl:
 *   # Get a token (login)
 *   curl -X POST http://localhost:8080/login \
 *        -H "Content-Type: application/json" \
 *        -d '{"username":"admin","password":"secret"}'
 *
 *   # Access protected route
 *   curl http://localhost:8080/api/protected \
 *        -H "Authorization: Bearer <token_from_login>"
 *
 *   # Access public route (no token needed)
 *   curl http://localhost:8080/api/public
 */
module examples.auth_jwt;

import aurora;
import aurora.web.middleware : Middleware, NextFunction;
import jwtlited.phobos : HS256Handler;
import std.datetime;
import std.conv : to;
import std.algorithm : canFind, splitter;
import std.json;
import std.format : format;
import std.string : representation;
import std.array : array;

// ============================================================================
// JWT CONFIGURATION
// ============================================================================

/**
 * JWT Configuration
 * 
 * In production:
 * - Use environment variables for secrets
 * - Consider using asymmetric keys (RS256, ES256) with jwtlited:openssl
 * - Store issuer/audience in config files
 */
struct JWTConfig
{
    /// Secret key for HMAC signing (use env var in production!)
    /// Minimum 32 bytes recommended for HS256
    string secret = "your-256-bit-secret-key-change-me-in-production";
    
    /// Token issuer (usually your service URL)
    string issuer = "aurora-example";
    
    /// Token audience (who the token is intended for)
    string audience = "aurora-api";
    
    /// Token expiration time in seconds (default: 1 hour)
    uint expirationSeconds = 3600;
    
    /// HTTP header to check for token
    string authHeader = "Authorization";
    
    /// Token prefix in header
    string tokenPrefix = "Bearer ";
    
    /// Paths that don't require authentication
    string[] publicPaths = ["/", "/health", "/login", "/api/public"];
    
    /// Clock skew tolerance in seconds for expiration check
    uint clockSkewSeconds = 60;
}

// ============================================================================
// JWT CLAIMS / PAYLOAD
// ============================================================================

/**
 * JWT Claims Structure
 * 
 * Standard claims (RFC 7519):
 * - iss (issuer): Who issued the token
 * - sub (subject): Who the token is about (usually user ID)
 * - aud (audience): Who the token is intended for
 * - exp (expiration): When the token expires (Unix timestamp)
 * - iat (issued at): When the token was issued
 * - nbf (not before): Token not valid before this time
 *
 * Custom claims:
 * - username, email, roles, etc.
 */
struct JWTClaims
{
    // Standard claims
    string iss;      // Issuer
    string sub;      // Subject (user ID)
    string aud;      // Audience
    long exp;        // Expiration time
    long iat;        // Issued at
    
    // Custom claims (example)
    string username;
    string email;
    string[] roles;
    
    /**
     * Check if token is expired
     */
    bool isExpired(uint clockSkewSeconds = 0) const
    {
        auto now = Clock.currTime(UTC()).toUnixTime();
        return exp < (now - clockSkewSeconds);
    }
    
    /**
     * Convert claims to JSON string for JWT payload
     */
    string toJson() const
    {
        JSONValue json;
        json["iss"] = iss;
        json["sub"] = sub;
        json["aud"] = aud;
        json["exp"] = exp;
        json["iat"] = iat;
        json["username"] = username;
        json["email"] = email;
        
        // Convert roles array to JSON
        JSONValue rolesJson;
        rolesJson = JSONValue(cast(string[])roles);
        json["roles"] = rolesJson;
        
        return json.toString();
    }
    
    /**
     * Parse claims from JSON string
     */
    static JWTClaims fromJson(string jsonStr)
    {
        JWTClaims claims;
        try
        {
            auto json = parseJSON(jsonStr);
            
            claims.iss = json["iss"].str;
            claims.sub = json["sub"].str;
            claims.aud = json["aud"].str;
            claims.exp = json["exp"].integer;
            claims.iat = json["iat"].integer;
            claims.username = json["username"].str;
            claims.email = json["email"].str;
            
            // Parse roles array
            string[] parsedRoles;
            if ("roles" in json)
            {
                foreach (role; json["roles"].array)
                {
                    parsedRoles ~= role.str;
                }
            }
            claims.roles = parsedRoles;
        }
        catch (Exception e)
        {
            // Return empty claims on parse error
        }
        return claims;
    }
}

// ============================================================================
// JWT TOKEN HANDLING (using jwtlited)
// ============================================================================

/**
 * JWT Token Result
 * 
 * Used to return validation results with error information
 */
struct JWTResult
{
    bool valid;
    string error;
    JWTClaims claims;
}

/**
 * JWT Helper using jwtlited library
 * 
 * This implementation uses jwtlited:phobos for HS256 signing.
 * For RS256/ES256, use jwtlited:openssl instead.
 */
struct JWT
{
    private static HS256Handler handler;
    private static bool initialized = false;
    
    /**
     * Initialize the JWT handler with secret key
     */
    static bool initialize(string secret)
    {
        if (!handler.loadKey(secret))
            return false;
        initialized = true;
        return true;
    }
    
    /**
     * Create a JWT token using jwtlited
     * 
     * Token structure: base64url(header).base64url(payload).base64url(signature)
     */
    static string createToken(JWTClaims claims, string secret)
    {
        // Ensure handler is initialized
        if (!initialized)
        {
            if (!initialize(secret))
                return "";
        }
        
        // Prepare payload as JSON
        string payload = claims.toJson();
        
        // Encode token using jwtlited
        char[2048] tokenBuffer;
        immutable len = handler.encode(tokenBuffer[], payload);
        
        if (len <= 0)
            return "";
        
        return tokenBuffer[0..len].idup;
    }
    
    /**
     * Validate and parse a JWT token using jwtlited
     */
    static JWTResult validateToken(string token, JWTConfig config)
    {
        JWTResult result;
        result.valid = false;
        
        // Ensure handler is initialized
        if (!initialized)
        {
            if (!initialize(config.secret))
            {
                result.error = "Failed to initialize JWT handler";
                return result;
            }
        }
        
        // First validate signature using jwtlited
        if (!handler.validate(token))
        {
            result.error = "Invalid signature";
            return result;
        }
        
        // Decode payload
        char[2048] payloadBuffer;
        if (!handler.decode(token, payloadBuffer[]))
        {
            result.error = "Failed to decode token";
            return result;
        }
        
        // Find actual payload length (null-terminated or full buffer)
        size_t payloadLen = 0;
        foreach (i, c; payloadBuffer)
        {
            if (c == '\0' || c == char.init)
                break;
            payloadLen = i + 1;
        }
        
        if (payloadLen == 0)
        {
            result.error = "Empty payload";
            return result;
        }
        
        try
        {
            string payload = cast(string)payloadBuffer[0..payloadLen];
            result.claims = JWTClaims.fromJson(payload);
        }
        catch (Exception e)
        {
            result.error = "Failed to parse payload: " ~ e.msg;
            return result;
        }
        
        // Validate expiration
        if (result.claims.isExpired(config.clockSkewSeconds))
        {
            result.error = "Token expired";
            return result;
        }
        
        // Validate issuer (optional but recommended)
        if (config.issuer.length > 0 && result.claims.iss != config.issuer)
        {
            result.error = "Invalid issuer";
            return result;
        }
        
        // Validate audience (optional but recommended)
        if (config.audience.length > 0 && result.claims.aud != config.audience)
        {
            result.error = "Invalid audience";
            return result;
        }
        
        result.valid = true;
        return result;
    }
}

// ============================================================================
// JWT MIDDLEWARE
// ============================================================================

/**
 * JWT Authentication Middleware
 * 
 * This middleware:
 * 1. Checks if the path is public (skip authentication)
 * 2. Extracts the JWT from Authorization header
 * 3. Validates the token signature and claims using jwtlited
 * 4. Stores user claims in context for route handlers
 * 5. Returns 401 Unauthorized if validation fails
 */
class JWTMiddleware
{
    private JWTConfig config;
    
    this(JWTConfig config = JWTConfig())
    {
        this.config = config;
        // Initialize JWT handler with secret
        JWT.initialize(config.secret);
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
        
        // Extract token from header
        string token = extractToken(ctx);
        if (token.length == 0)
        {
            unauthorized(ctx, "Missing or invalid Authorization header");
            return;
        }
        
        // Validate token using jwtlited
        auto result = JWT.validateToken(token, config);
        if (!result.valid)
        {
            unauthorized(ctx, result.error);
            return;
        }
        
        // Store claims in context for route handlers
        auto claimsHolder = new ClaimsHolder(result.claims);
        ctx.storage.set("jwt_claims", claimsHolder);
        ctx.storage.set("user_id", cast(void*)(result.claims.sub.ptr));
        ctx.storage.set("authenticated", cast(void*)1);
        
        // Continue to next middleware/handler
        next();
    }
    
    /**
     * Get middleware as delegate for Aurora router
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
            // Also check path prefix for API routes like /api/public/...
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
     * Extract JWT token from Authorization header
     */
    string extractToken(ref Context ctx)
    {
        if (ctx.request is null)
            return "";
        
        string authHeader = ctx.request.getHeader(config.authHeader);
        if (authHeader.length == 0)
            return "";
        
        // Check for Bearer prefix
        if (authHeader.length > config.tokenPrefix.length &&
            authHeader[0..config.tokenPrefix.length] == config.tokenPrefix)
        {
            return authHeader[config.tokenPrefix.length..$];
        }
        
        return "";
    }
    
    /**
     * Send 401 Unauthorized response
     */
    void unauthorized(ref Context ctx, string message)
    {
        ctx.status(401)
           .header("WWW-Authenticate", "Bearer")
           .header("Content-Type", "application/json")
           .send(format!`{"error":"Unauthorized","message":"%s"}`(message));
    }
}

/**
 * Claims holder class for context storage
 */
private class ClaimsHolder
{
    JWTClaims claims;
    this(JWTClaims c) { claims = c; }
}

/**
 * Helper function to get JWT claims from context
 * 
 * Usage in route handlers:
 *   auto claims = getJWTClaims(ctx);
 *   if (claims !is null) {
 *       writeln("User: ", claims.username);
 *   }
 */
JWTClaims* getJWTClaims(ref Context ctx)
{
    auto holder = ctx.storage.get!ClaimsHolder("jwt_claims");
    if (holder !is null)
        return &holder.claims;
    return null;
}

// ============================================================================
// SIMULATED USER DATABASE
// ============================================================================

/**
 * Simple user store (for demo purposes only!)
 * 
 * In production:
 * - Use a proper database
 * - Hash passwords with bcrypt/argon2
 * - Implement proper user management
 */
struct UserStore
{
    struct User
    {
        string id;
        string username;
        string password; // Plain text for demo - NEVER do this in production!
        string email;
        string[] roles;
    }
    
    static User[string] users;
    
    static this()
    {
        // Pre-populate with demo users
        users["admin"] = User("1", "admin", "secret", "admin@example.com", ["admin", "user"]);
        users["user1"] = User("2", "user1", "password123", "user1@example.com", ["user"]);
        users["guest"] = User("3", "guest", "guest", "guest@example.com", ["guest"]);
    }
    
    static User* authenticate(string username, string password)
    {
        if (auto user = username in users)
        {
            if (user.password == password)  // In production: use bcrypt!
                return user;
        }
        return null;
    }
}

// ============================================================================
// EXAMPLE SERVER
// ============================================================================

/// Global config for use in route handlers
__gshared JWTConfig jwtConfig;

void main()
{
    import std.stdio : writeln;
    
    writeln("===========================================");
    writeln("   Aurora JWT Authentication Example");
    writeln("   (using jwtlited:phobos for HS256)");
    writeln("===========================================");
    writeln();
    
    // Create JWT configuration
    jwtConfig.secret = "my-super-secret-key-for-demo-only-32bytes!";  // At least 32 bytes for HS256
    jwtConfig.expirationSeconds = 3600;  // 1 hour
    jwtConfig.publicPaths = ["/", "/health", "/login", "/api/public"];
    
    // Create middleware
    auto jwtMiddleware = new JWTMiddleware(jwtConfig);
    
    // Create app with default config
    auto app = new App();
    
    // Add JWT middleware globally
    app.use(jwtMiddleware.middleware());
    
    // ======================
    // PUBLIC ROUTES
    // ======================
    
    // Health check (public)
    app.get("/health", (ref ctx) {
        ctx.json(`{"status":"healthy","service":"aurora-jwt-example","jwt_library":"jwtlited:phobos"}`);
    });
    
    // Home (public)
    app.get("/", (ref ctx) {
        ctx.header("Content-Type", "text/html")
           .send(`
            <html>
            <head><title>Aurora JWT Example</title></head>
            <body>
                <h1>Aurora JWT Authentication Example</h1>
                <p><em>Using jwtlited:phobos for HS256 signing</em></p>
                <h2>Available Endpoints:</h2>
                <ul>
                    <li><code>POST /login</code> - Get JWT token (public)</li>
                    <li><code>GET /api/public</code> - Public API (no auth)</li>
                    <li><code>GET /api/protected</code> - Protected API (requires token)</li>
                    <li><code>GET /api/admin</code> - Admin only (requires admin role)</li>
                    <li><code>GET /api/me</code> - Get current user info</li>
                </ul>
                <h2>Demo Users:</h2>
                <ul>
                    <li>admin / secret (roles: admin, user)</li>
                    <li>user1 / password123 (roles: user)</li>
                    <li>guest / guest (roles: guest)</li>
                </ul>
            </body>
            </html>
           `);
    });
    
    // Login endpoint (public)
    app.post("/login", &handleLogin);
    
    // Public API (no auth required)
    app.get("/api/public", (ref ctx) {
        ctx.json(`{"message":"This is a public endpoint, no authentication required"}`);
    });
    
    // ======================
    // PROTECTED ROUTES
    // ======================
    
    // Protected API (requires valid token)
    app.get("/api/protected", (ref ctx) {
        auto claims = getJWTClaims(ctx);
        if (claims is null)
        {
            ctx.status(500).json(`{"error":"Internal error"}`);
            return;
        }
        
        ctx.json(format!`{
            "message": "Welcome to the protected area!",
            "user": "%s",
            "roles": ["%s"]
        }`(claims.username, claims.roles.length > 0 ? claims.roles[0] : "none"));
    });
    
    // Admin-only endpoint (requires admin role)
    app.get("/api/admin", (ref ctx) {
        auto claims = getJWTClaims(ctx);
        if (claims is null)
        {
            ctx.status(500).json(`{"error":"Internal error"}`);
            return;
        }
        
        // Check for admin role
        if (!claims.roles.canFind("admin"))
        {
            ctx.status(403)
               .json(`{"error":"Forbidden","message":"Admin role required"}`);
            return;
        }
        
        ctx.json(`{"message":"Welcome, administrator!","access_level":"full"}`);
    });
    
    // Get current user info
    app.get("/api/me", (ref ctx) {
        auto claims = getJWTClaims(ctx);
        if (claims is null)
        {
            ctx.status(500).json(`{"error":"Internal error"}`);
            return;
        }
        
        import std.array : join;
        ctx.json(format!`{
            "id": "%s",
            "username": "%s",
            "email": "%s",
            "roles": [%s],
            "token_issued_at": %d,
            "token_expires_at": %d
        }`(
            claims.sub,
            claims.username,
            claims.email,
            `"` ~ claims.roles.join(`","`) ~ `"`,
            claims.iat,
            claims.exp
        ));
    });
    
    // ======================
    // START SERVER
    // ======================
    
    writeln("Test commands:");
    writeln();
    writeln("  # Login to get token:");
    writeln(`  curl -X POST http://localhost:8080/login \`);
    writeln(`       -H "Content-Type: application/json" \`);
    writeln(`       -d '{"username":"admin","password":"secret"}'`);
    writeln();
    writeln("  # Access protected endpoint:");
    writeln(`  curl http://localhost:8080/api/protected \`);
    writeln(`       -H "Authorization: Bearer <token>"`);
    writeln();
    writeln("  # Access admin endpoint:");
    writeln(`  curl http://localhost:8080/api/admin \`);
    writeln(`       -H "Authorization: Bearer <token>"`);
    writeln();
    writeln("Starting server on http://localhost:8080");
    writeln("-------------------------------------------");
    
    // Start server
    app.listen(8080);
}

/**
 * Handle login requests
 */
void handleLogin(ref Context ctx)
{
    // Parse request body
    string username, password;
    
    try
    {
        auto bodyStr = ctx.request.body();
        if (bodyStr.length > 0)
        {
            auto json = parseJSON(bodyStr);
            username = json["username"].str;
            password = json["password"].str;
        }
    }
    catch (Exception e)
    {
        ctx.status(400)
           .json(`{"error":"Bad Request","message":"Invalid JSON body"}`);
        return;
    }
    
    // Authenticate user
    auto user = UserStore.authenticate(username, password);
    if (user is null)
    {
        ctx.status(401)
           .json(`{"error":"Unauthorized","message":"Invalid credentials"}`);
        return;
    }
    
    // Create JWT claims
    auto now = Clock.currTime(UTC()).toUnixTime();
    JWTClaims claims;
    claims.iss = jwtConfig.issuer;
    claims.sub = user.id;
    claims.aud = jwtConfig.audience;
    claims.iat = now;
    claims.exp = now + jwtConfig.expirationSeconds;
    claims.username = user.username;
    claims.email = user.email;
    claims.roles = user.roles;
    
    // Generate token using jwtlited
    string token = JWT.createToken(claims, jwtConfig.secret);
    
    if (token.length == 0)
    {
        ctx.status(500)
           .json(`{"error":"Internal Server Error","message":"Failed to generate token"}`);
        return;
    }
    
    // Return token
    ctx.json(format!`{
        "token": "%s",
        "type": "Bearer",
        "expires_in": %d,
        "user": {
            "id": "%s",
            "username": "%s",
            "email": "%s"
        }
    }`(token, jwtConfig.expirationSeconds, user.id, user.username, user.email));
}
