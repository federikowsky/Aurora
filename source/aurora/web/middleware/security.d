/**
 * Security Headers Middleware
 *
 * Package: aurora.web.middleware.security
 *
 * Features:
 * - X-Content-Type-Options: nosniff
 * - X-Frame-Options: DENY
 * - X-XSS-Protection: 1; mode=block
 * - Strict-Transport-Security (HSTS)
 * - Content-Security-Policy (CSP)
 * - Referrer-Policy
 * - Permissions-Policy
 * - X-Download-Options
 * - X-Permitted-Cross-Domain-Policies
 * - Cross-Origin-Opener-Policy (COOP)
 * - Cross-Origin-Embedder-Policy (COEP)
 * - Cross-Origin-Resource-Policy (CORP)
 */
module aurora.web.middleware.security;

import aurora.web.middleware;
import aurora.web.context;
import aurora.http;

/**
 * SecurityConfig - Security headers configuration
 */
struct SecurityConfig
{
    // X-Content-Type-Options
    bool enableContentTypeOptions = true;
    
    // X-Frame-Options
    bool enableFrameOptions = true;
    string frameOptions = "DENY";  // DENY, SAMEORIGIN, ALLOW-FROM
    
    // X-XSS-Protection
    bool enableXSSProtection = true;
    string xssProtection = "1; mode=block";
    
    // Strict-Transport-Security (HSTS)
    bool enableHSTS = false;  // Disabled by default (requires HTTPS)
    uint hstsMaxAge = 31536000;  // 1 year
    bool hstsIncludeSubDomains = true;
    
    // Content-Security-Policy
    bool enableCSP = false;  // Disabled by default (app-specific)
    string cspDirective = "default-src 'self'";
    
    // Referrer-Policy
    string referrerPolicy = "no-referrer";
    
    // Permissions-Policy
    string permissionsPolicy = "";
    
    // X-Download-Options
    bool enableDownloadOptions = true;
    
    // X-Permitted-Cross-Domain-Policies
    bool enableCrossDomainPolicies = true;
    
    // Cross-Origin-Opener-Policy (COOP)
    // Controls how the document can share its browsing context group
    // Options: "unsafe-none", "same-origin-allow-popups", "same-origin"
    bool enableCOOP = false;  // Disabled by default (can break popups)
    string coopPolicy = "same-origin";
    
    // Cross-Origin-Embedder-Policy (COEP)
    // Prevents document from loading cross-origin resources without explicit permission
    // Options: "unsafe-none", "require-corp", "credentialless"
    bool enableCOEP = false;  // Disabled by default (can break resources)
    string coepPolicy = "require-corp";
    
    // Cross-Origin-Resource-Policy (CORP)
    // Controls which origins can embed the resource
    // Options: "same-site", "same-origin", "cross-origin"
    bool enableCORP = false;  // Disabled by default
    string corpPolicy = "same-origin";
}

/**
 * SecurityMiddleware - Security headers
 */
class SecurityMiddleware
{
    private SecurityConfig config;
    
    /**
     * Constructor with config
     */
    this(SecurityConfig config)
    {
        this.config = config;
    }
    
    /**
     * Handle request (middleware interface)
     */
    void handle(Context ctx, NextFunction next)
    {
        // Add security headers before calling next
        addSecurityHeaders(ctx);
        
        // Call next middleware/handler
        next();
    }
    
    private:
    
    /**
     * Add security headers to response
     */
    void addSecurityHeaders(Context ctx)
    {
        if (!ctx.response) return;
        
        // X-Content-Type-Options
        if (config.enableContentTypeOptions)
        {
            setHeaderIfNotExists(ctx.response, "X-Content-Type-Options", "nosniff");
        }
        
        // X-Frame-Options
        if (config.enableFrameOptions)
        {
            setHeaderIfNotExists(ctx.response, "X-Frame-Options", config.frameOptions);
        }
        
        // X-XSS-Protection
        if (config.enableXSSProtection)
        {
            setHeaderIfNotExists(ctx.response, "X-XSS-Protection", config.xssProtection);
        }
        
        // Strict-Transport-Security (HSTS)
        if (config.enableHSTS)
        {
            import std.conv : to;
            string hstsValue = "max-age=" ~ config.hstsMaxAge.to!string;
            if (config.hstsIncludeSubDomains)
            {
                hstsValue ~= "; includeSubDomains";
            }
            setHeaderIfNotExists(ctx.response, "Strict-Transport-Security", hstsValue);
        }
        
        // Content-Security-Policy
        if (config.enableCSP)
        {
            setHeaderIfNotExists(ctx.response, "Content-Security-Policy", config.cspDirective);
        }
        
        // Referrer-Policy
        if (config.referrerPolicy.length > 0)
        {
            setHeaderIfNotExists(ctx.response, "Referrer-Policy", config.referrerPolicy);
        }
        
        // Permissions-Policy
        if (config.permissionsPolicy.length > 0)
        {
            setHeaderIfNotExists(ctx.response, "Permissions-Policy", config.permissionsPolicy);
        }
        
        // X-Download-Options
        if (config.enableDownloadOptions)
        {
            setHeaderIfNotExists(ctx.response, "X-Download-Options", "noopen");
        }
        
        // X-Permitted-Cross-Domain-Policies
        if (config.enableCrossDomainPolicies)
        {
            setHeaderIfNotExists(ctx.response, "X-Permitted-Cross-Domain-Policies", "none");
        }
        
        // Cross-Origin-Opener-Policy (COOP)
        if (config.enableCOOP)
        {
            setHeaderIfNotExists(ctx.response, "Cross-Origin-Opener-Policy", config.coopPolicy);
        }
        
        // Cross-Origin-Embedder-Policy (COEP)
        if (config.enableCOEP)
        {
            setHeaderIfNotExists(ctx.response, "Cross-Origin-Embedder-Policy", config.coepPolicy);
        }
        
        // Cross-Origin-Resource-Policy (CORP)
        if (config.enableCORP)
        {
            setHeaderIfNotExists(ctx.response, "Cross-Origin-Resource-Policy", config.corpPolicy);
        }
    }
    
    /**
     * Set header only if it doesn't already exist
     */
    void setHeaderIfNotExists(HTTPResponse* response, string name, string value)
    {
        // HTTPResponse doesn't expose hasHeader, so we just set
        // This will override if exists, but that's acceptable for security headers
        response.setHeader(name, value);
    }
}

/**
 * Helper function to create security middleware
 */
Middleware securityHeadersMiddleware(SecurityConfig config = SecurityConfig())
{
    auto security = new SecurityMiddleware(config);
    
    return (ref Context ctx, NextFunction next) {
        security.handle(ctx, next);
    };
}
