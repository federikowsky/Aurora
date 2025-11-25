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
 */
module tests.unit.web.middleware.security_test;

import unit_threaded;
import aurora.web.middleware.security;
import aurora.web.middleware;
import aurora.web.context;
import aurora.http;

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
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    res.headers["X-Content-Type-Options"].shouldEqual("nosniff");
}

// Test 2: X-Frame-Options header
@("sets X-Frame-Options")
unittest
{
    auto config = SecurityConfig();
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    res.headers["X-Frame-Options"].shouldEqual("DENY");
}

// Test 3: X-XSS-Protection header
@("sets X-XSS-Protection")
unittest
{
    auto config = SecurityConfig();
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    res.headers["X-XSS-Protection"].shouldEqual("1; mode=block");
}

// Test 4: Strict-Transport-Security header
@("sets HSTS header")
unittest
{
    auto config = SecurityConfig();
    config.enableHSTS = true;
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    res.headers["Strict-Transport-Security"].shouldEqual("max-age=31536000; includeSubDomains");
}

// Test 5: Content-Security-Policy header
@("sets CSP header")
unittest
{
    auto config = SecurityConfig();
    config.enableCSP = true;
    config.cspDirective = "default-src 'self'";
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    res.headers["Content-Security-Policy"].shouldEqual("default-src 'self'");
}

// Test 6: All headers together
@("sets all security headers")
unittest
{
    auto config = SecurityConfig();
    config.enableHSTS = true;
    config.enableCSP = true;
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    assert("X-Content-Type-Options" in res.headers);
    assert("X-Frame-Options" in res.headers);
    assert("X-XSS-Protection" in res.headers);
    assert("Strict-Transport-Security" in res.headers);
    assert("Content-Security-Policy" in res.headers);
}

// Test 7: Referrer-Policy header
@("sets Referrer-Policy")
unittest
{
    auto config = SecurityConfig();
    config.referrerPolicy = "no-referrer";
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    res.headers["Referrer-Policy"].shouldEqual("no-referrer");
}

// Test 8: Permissions-Policy header
@("sets Permissions-Policy")
unittest
{
    auto config = SecurityConfig();
    config.permissionsPolicy = "geolocation=(), microphone=()";
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    res.headers["Permissions-Policy"].shouldEqual("geolocation=(), microphone=()");
}

// Test 9: X-Download-Options header
@("sets X-Download-Options")
unittest
{
    auto config = SecurityConfig();
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    res.headers["X-Download-Options"].shouldEqual("noopen");
}

// Test 10: X-Permitted-Cross-Domain-Policies header
@("sets X-Permitted-Cross-Domain-Policies")
unittest
{
    auto config = SecurityConfig();
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    res.headers["X-Permitted-Cross-Domain-Policies"].shouldEqual("none");
}

// ========================================
// CONFIGURABLE TESTS
// ========================================

// Test 11: Disable X-Frame-Options
@("can disable X-Frame-Options")
unittest
{
    auto config = SecurityConfig();
    config.enableFrameOptions = false;
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    assert("X-Frame-Options" !in res.headers);
}

// Test 12: Custom X-Frame-Options value
@("custom X-Frame-Options value")
unittest
{
    auto config = SecurityConfig();
    config.frameOptions = "SAMEORIGIN";
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    res.headers["X-Frame-Options"].shouldEqual("SAMEORIGIN");
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
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    res.headers["Strict-Transport-Security"].shouldEqual("max-age=86400; includeSubDomains");
}

// Test 14: HSTS without includeSubDomains
@("HSTS without includeSubDomains")
unittest
{
    auto config = SecurityConfig();
    config.enableHSTS = true;
    config.hstsIncludeSubDomains = false;
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    res.headers["Strict-Transport-Security"].shouldEqual("max-age=31536000");
}

// Test 15: Custom CSP directive
@("custom CSP directive")
unittest
{
    auto config = SecurityConfig();
    config.enableCSP = true;
    config.cspDirective = "default-src 'self'; script-src 'unsafe-inline'";
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    res.headers["Content-Security-Policy"].shouldEqual("default-src 'self'; script-src 'unsafe-inline'");
}

// ========================================
// EDGE CASES
// ========================================

// Test 16: Missing response
@("handles missing response")
unittest
{
    auto config = SecurityConfig();
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPRequest req;
    req.method = "GET";
    ctx.request = &req;
    // No response
    
    void next() { }
    
    // Should not throw
    security.handle(ctx, &next);
}

// Test 17: Calls next
@("calls next middleware")
unittest
{
    auto config = SecurityConfig();
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    ctx.request = &req;
    ctx.response = &res;
    
    bool nextCalled = false;
    void next() { nextCalled = true; }
    
    security.handle(ctx, &next);
    
    nextCalled.shouldBeTrue;
}

// Test 18: Headers not overwritten
@("does not overwrite existing headers")
unittest
{
    auto config = SecurityConfig();
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    res.headers["X-Frame-Options"] = "ALLOW-FROM https://example.com";
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    // Should keep existing value
    res.headers["X-Frame-Options"].shouldEqual("ALLOW-FROM https://example.com");
}

// ========================================
// INTEGRATION TESTS
// ========================================

// Test 19: Works with other middleware
@("works with other middleware")
unittest
{
    auto config = SecurityConfig();
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    ctx.request = &req;
    ctx.response = &res;
    
    bool otherMiddlewareCalled = false;
    void next() { otherMiddlewareCalled = true; }
    
    security.handle(ctx, &next);
    
    otherMiddlewareCalled.shouldBeTrue;
    assert("X-Content-Type-Options" in res.headers);
}

// Test 20: Default config
@("default config works")
unittest
{
    auto config = SecurityConfig();
    auto security = new SecurityMiddleware(config);
    
    Context ctx;
    HTTPRequest req;
    HTTPResponse res;
    req.method = "GET";
    ctx.request = &req;
    ctx.response = &res;
    
    void next() { }
    
    security.handle(ctx, &next);
    
    // Should have default security headers
    assert("X-Content-Type-Options" in res.headers);
    assert("X-Frame-Options" in res.headers);
    assert("X-XSS-Protection" in res.headers);
}
