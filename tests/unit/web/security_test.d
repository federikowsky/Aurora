/**
 * Security Headers Middleware Tests
 *
 * TDD: Aurora Security Headers Middleware
 *
 * Features:
 * - X-Content-Type-Options: nosniff
 * - X-Frame-Options: DENY
 * - X-XSS-Protection: 1; mode=block
 * - Strict-Transport-Security (HSTS)
 * - Content-Security-Policy (CSP)
 * - Referrer-Policy
 * - Permissions-Policy
 */
module tests.unit.web.security_test;

import unit_threaded;
import aurora.web.middleware.security;
import aurora.web.middleware;
import aurora.web.context;
import aurora.http;

// ========================================
// HELPER FUNCTIONS
// ========================================

/// Get header from response
string getHeader(HTTPResponse* response, string headerName)
{
    if (response is null) return "";
    auto headers = response.getHeaders();
    if (auto val = headerName in headers)
        return *val;
    return "";
}

/// Check if header exists in response
bool hasHeader(HTTPResponse* response, string headerName)
{
    if (response is null) return false;
    auto headers = response.getHeaders();
    return (headerName in headers) !is null;
}

// ========================================
// HEADERS ADDED TESTS
// ========================================

// Test 1: X-Content-Type-Options header
@("sets X-Content-Type-Options")
unittest
{
    auto config = SecurityConfig();
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    security.handle(ctx, &next);
    
    nextCalled.shouldBeTrue;
    getHeader(&response, "X-Content-Type-Options").shouldEqual("nosniff");
}

// Test 2: X-Frame-Options header
@("sets X-Frame-Options")
unittest
{
    auto config = SecurityConfig();
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    getHeader(&response, "X-Frame-Options").shouldEqual("DENY");
}

// Test 3: X-XSS-Protection header
@("sets X-XSS-Protection")
unittest
{
    auto config = SecurityConfig();
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    getHeader(&response, "X-XSS-Protection").shouldEqual("1; mode=block");
}

// Test 4: Strict-Transport-Security header
@("sets HSTS header when enabled")
unittest
{
    auto config = SecurityConfig();
    config.enableHSTS = true;
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    getHeader(&response, "Strict-Transport-Security").shouldEqual("max-age=31536000; includeSubDomains");
}

// Test 5: Content-Security-Policy header
@("sets CSP header when enabled")
unittest
{
    auto config = SecurityConfig();
    config.enableCSP = true;
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    getHeader(&response, "Content-Security-Policy").shouldEqual("default-src 'self'");
}

// Test 6: All default headers set
@("sets all default security headers")
unittest
{
    auto config = SecurityConfig();
    config.enableHSTS = true;
    config.enableCSP = true;
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    hasHeader(&response, "X-Content-Type-Options").shouldBeTrue;
    hasHeader(&response, "X-Frame-Options").shouldBeTrue;
    hasHeader(&response, "X-XSS-Protection").shouldBeTrue;
    hasHeader(&response, "Strict-Transport-Security").shouldBeTrue;
    hasHeader(&response, "Content-Security-Policy").shouldBeTrue;
}

// Test 7: Referrer-Policy header
@("sets Referrer-Policy header")
unittest
{
    auto config = SecurityConfig();
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    getHeader(&response, "Referrer-Policy").shouldEqual("no-referrer");
}

// Test 8: Permissions-Policy header
@("sets Permissions-Policy when configured")
unittest
{
    auto config = SecurityConfig();
    config.permissionsPolicy = "geolocation=(), microphone=()";
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    getHeader(&response, "Permissions-Policy").shouldEqual("geolocation=(), microphone=()");
}

// ========================================
// CONFIGURATION TESTS
// ========================================

// Test 9: Disable X-Content-Type-Options
@("disables X-Content-Type-Options when configured")
unittest
{
    auto config = SecurityConfig();
    config.enableContentTypeOptions = false;
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    hasHeader(&response, "X-Content-Type-Options").shouldBeFalse;
}

// Test 10: Disable X-Frame-Options
@("disables X-Frame-Options when configured")
unittest
{
    auto config = SecurityConfig();
    config.enableFrameOptions = false;
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    hasHeader(&response, "X-Frame-Options").shouldBeFalse;
}

// Test 11: Custom Frame-Options value
@("allows custom X-Frame-Options value")
unittest
{
    auto config = SecurityConfig();
    config.frameOptions = "SAMEORIGIN";
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    getHeader(&response, "X-Frame-Options").shouldEqual("SAMEORIGIN");
}

// Test 12: HSTS without includeSubDomains
@("HSTS without includeSubDomains")
unittest
{
    auto config = SecurityConfig();
    config.enableHSTS = true;
    config.hstsIncludeSubDomains = false;
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    getHeader(&response, "Strict-Transport-Security").shouldEqual("max-age=31536000");
}

// Test 13: Custom HSTS max-age
@("custom HSTS max-age")
unittest
{
    auto config = SecurityConfig();
    config.enableHSTS = true;
    config.hstsMaxAge = 86400;  // 1 day
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    getHeader(&response, "Strict-Transport-Security").shouldEqual("max-age=86400; includeSubDomains");
}

// Test 14: Custom CSP directive
@("custom CSP directive")
unittest
{
    auto config = SecurityConfig();
    config.enableCSP = true;
    config.cspDirective = "default-src 'self'; script-src 'unsafe-inline'";
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    getHeader(&response, "Content-Security-Policy").shouldEqual("default-src 'self'; script-src 'unsafe-inline'");
}

// ========================================
// MIDDLEWARE CHAIN TESTS
// ========================================

// Test 15: Next() is called
@("calls next middleware")
unittest
{
    auto config = SecurityConfig();
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    security.handle(ctx, &next);
    
    nextCalled.shouldBeTrue;
}

// Test 16: Headers set before next()
@("headers set before next is called")
unittest
{
    auto config = SecurityConfig();
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    bool headersSetBeforeNext = false;
    void next() {
        headersSetBeforeNext = hasHeader(&response, "X-Content-Type-Options");
    }
    
    security.handle(ctx, &next);
    
    headersSetBeforeNext.shouldBeTrue;
}

// ========================================
// HELPER FUNCTION TESTS
// ========================================

// Test 17: securityHeadersMiddleware helper
@("securityHeadersMiddleware helper creates middleware")
unittest
{
    auto middleware = securityHeadersMiddleware();
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    middleware(ctx, &next);
    
    nextCalled.shouldBeTrue;
    hasHeader(&response, "X-Content-Type-Options").shouldBeTrue;
}

// Test 18: securityHeadersMiddleware with config
@("securityHeadersMiddleware with custom config")
unittest
{
    auto config = SecurityConfig();
    config.enableHSTS = true;
    
    auto middleware = securityHeadersMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    void next() { }
    
    middleware(ctx, &next);
    
    hasHeader(&response, "Strict-Transport-Security").shouldBeTrue;
}

// ========================================
// EDGE CASES
// ========================================

// Test 19: Null response handling
@("handles null response gracefully")
unittest
{
    auto config = SecurityConfig();
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    ctx.response = null;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    // Should not crash
    security.handle(ctx, &next);
    
    nextCalled.shouldBeTrue;
}

// Test 20: X-Download-Options header
@("sets X-Download-Options header")
unittest
{
    auto config = SecurityConfig();
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    getHeader(&response, "X-Download-Options").shouldEqual("noopen");
}

// Test 21: X-Permitted-Cross-Domain-Policies header
@("sets X-Permitted-Cross-Domain-Policies header")
unittest
{
    auto config = SecurityConfig();
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPResponse response = HTTPResponse(200, "OK");
    ctx.response = &response;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    getHeader(&response, "X-Permitted-Cross-Domain-Policies").shouldEqual("none");
}
