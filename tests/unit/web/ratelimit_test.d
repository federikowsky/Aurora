/**
 * Rate Limit Middleware Tests
 *
 * Tests for the token bucket rate limiter implementation.
 * Tests cover:
 * - Basic rate limiting
 * - Burst handling
 * - Per-client limiting
 * - 429 responses
 * - Retry-After header
 * - Token refill mechanics
 * - Custom key extractors
 */
module tests.unit.web.ratelimit_test;

import aurora.web.middleware.ratelimit;
import aurora.web.context;
import aurora.web.middleware;
import aurora.http;
import core.time;
import core.thread;
import std.conv : to;

// ========================================
// HELPER FUNCTIONS
// ========================================

/// Test context struct to hold request/response for testing
struct TestContext
{
    Context ctx;
    HTTPResponse response;
    HTTPRequest request;

    /// Create test context with optional headers
    static TestContext create(string[string] extraHeaders = null)
    {
        TestContext tc;
        
        string headersStr = "Host: localhost\r\n";
        if (extraHeaders !is null)
        {
            foreach (name, value; extraHeaders)
            {
                headersStr ~= name ~ ": " ~ value ~ "\r\n";
            }
        }
        
        string rawRequest =
            "GET /api HTTP/1.1\r\n" ~
            headersStr ~
            "\r\n";
        tc.request = HTTPRequest.parse(cast(ubyte[]) rawRequest);
        tc.response = HTTPResponse(200, "OK");
        tc.ctx.request = &tc.request;
        tc.ctx.response = &tc.response;
        return tc;
    }

    /// Get response status code
    int getStatus()
    {
        return response.getStatus();
    }

    /// Get response body
    string getBody()
    {
        return response.getBody();
    }
}

//
// Test 1-5: Basic Rate Limiting
//

/// Test 1: Request within limit should pass
@("Test 1: Request within limit passes")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 10;
    config.burstSize = 0;
    config.windowSize = 1.seconds;

    auto limiter = new RateLimiter(config);

    // First request should be allowed
    assert(limiter.isAllowed("client1"), "First request should be allowed");
}

/// Test 2: Requests exceeding limit should be blocked
@("Test 2: Requests exceeding limit are blocked")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 3;
    config.burstSize = 0;
    config.windowSize = 1.seconds;

    auto limiter = new RateLimiter(config);

    // Consume all tokens
    assert(limiter.isAllowed("client1"), "Request 1 should pass");
    assert(limiter.isAllowed("client1"), "Request 2 should pass");
    assert(limiter.isAllowed("client1"), "Request 3 should pass");

    // Next request should be blocked
    assert(!limiter.isAllowed("client1"), "Request 4 should be blocked");
}

/// Test 3: Different clients have separate limits
@("Test 3: Separate limits per client")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 2;
    config.burstSize = 0;
    config.windowSize = 1.seconds;

    auto limiter = new RateLimiter(config);

    // Client 1 uses their limit
    assert(limiter.isAllowed("client1"));
    assert(limiter.isAllowed("client1"));
    assert(!limiter.isAllowed("client1"), "Client 1 should be rate limited");

    // Client 2 should have their own limit
    assert(limiter.isAllowed("client2"), "Client 2 should not be affected by client 1");
    assert(limiter.isAllowed("client2"));
    assert(!limiter.isAllowed("client2"), "Client 2 should now be rate limited");
}

/// Test 4: Burst allows temporary spike
@("Test 4: Burst allows temporary spike")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 5;
    config.burstSize = 3;  // Total allowed: 5 + 3 = 8
    config.windowSize = 1.seconds;

    auto limiter = new RateLimiter(config);

    // Should allow up to requestsPerWindow + burstSize
    int allowed = 0;
    for (int i = 0; i < 12; i++)
    {
        if (limiter.isAllowed("burst_client"))
            allowed++;
    }

    assert(allowed == 8, "Should allow exactly requestsPerWindow + burstSize requests");
}

/// Test 5: Zero burst size works correctly
@("Test 5: Zero burst size")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 3;
    config.burstSize = 0;
    config.windowSize = 1.seconds;

    auto limiter = new RateLimiter(config);

    int allowed = 0;
    for (int i = 0; i < 10; i++)
    {
        if (limiter.isAllowed("no_burst"))
            allowed++;
    }

    assert(allowed == 3, "Should allow exactly requestsPerWindow requests with zero burst");
}

//
// Test 6-10: Token Bucket Mechanics
//

/// Test 6: Tokens refill over time
@("Test 6: Tokens refill over time")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 1;
    config.burstSize = 0;
    config.windowSize = 100.msecs;

    auto limiter = new RateLimiter(config);

    // Use the token
    assert(limiter.isAllowed("refill_test"));
    assert(!limiter.isAllowed("refill_test"), "Should be blocked immediately after");

    // Wait for refill
    Thread.sleep(150.msecs);

    // Should have a token again
    assert(limiter.isAllowed("refill_test"), "Should have token after refill period");
}

/// Test 7: Partial token refill
@("Test 7: Partial refill not enough for request")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 1;
    config.burstSize = 0;
    config.windowSize = 200.msecs;

    auto limiter = new RateLimiter(config);

    // Use the token
    assert(limiter.isAllowed("partial"));
    assert(!limiter.isAllowed("partial"));

    // Wait only half the time
    Thread.sleep(50.msecs);

    // Should still be blocked (not enough tokens)
    assert(!limiter.isAllowed("partial"), "Should still be blocked with partial refill");

    // Wait the rest
    Thread.sleep(200.msecs);
    assert(limiter.isAllowed("partial"), "Should be allowed after full refill");
}

/// Test 8: Tokens don't exceed max
@("Test 8: Tokens capped at max")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 3;
    config.burstSize = 2;
    config.windowSize = 50.msecs;

    auto limiter = new RateLimiter(config);

    // Don't use any tokens, wait for potential over-refill
    Thread.sleep(200.msecs);

    // Should still only have max tokens (requestsPerWindow + burstSize = 5)
    int allowed = 0;
    for (int i = 0; i < 10; i++)
    {
        if (limiter.isAllowed("max_tokens"))
            allowed++;
    }

    assert(allowed == 5, "Should not exceed max tokens even after long wait");
}

/// Test 9: New client starts with full tokens
@("Test 9: New client starts with full bucket")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 5;
    config.burstSize = 0;
    config.windowSize = 1.seconds;

    auto limiter = new RateLimiter(config);

    // New client should have full tokens
    int allowed = 0;
    for (int i = 0; i < 10; i++)
    {
        if (limiter.isAllowed("new_client"))
            allowed++;
    }

    assert(allowed == 5, "New client should start with full token bucket");
}

/// Test 10: Retry-After calculation
@("Test 10: Retry-After seconds calculated correctly")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 1;
    config.burstSize = 0;
    config.windowSize = 5.seconds;

    auto limiter = new RateLimiter(config);

    // Use the token
    assert(limiter.isAllowed("retry_test"));
    assert(!limiter.isAllowed("retry_test"));

    // Check Retry-After
    uint retryAfter = limiter.getRetryAfter("retry_test");
    assert(retryAfter > 0 && retryAfter <= 6, "Retry-After should be between 1 and 6 seconds");
}

//
// Test 11-15: Middleware Integration
//

/// Test 11: Middleware allows request within limit
@("Test 11: Middleware allows normal request")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 10;
    config.burstSize = 0;

    auto mw = rateLimitMiddleware(config);
    auto tc = TestContext.create();
    bool nextCalled = false;

    mw(tc.ctx, () { nextCalled = true; });

    assert(nextCalled, "Next should be called for allowed request");
    assert(tc.response.getStatus() != 429, "Status should not be 429");
}

/// Test 12: Middleware blocks rate limited request
@("Test 12: Middleware blocks when rate limited")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 1;
    config.burstSize = 0;
    config.windowSize = 10.seconds;  // Long window to prevent refill

    auto mw = rateLimitMiddleware(config);
    bool nextCalled = false;

    // First request - allowed
    auto tc1 = TestContext.create();
    mw(tc1.ctx, () { nextCalled = true; });
    assert(nextCalled, "First request should be allowed");

    // Second request - blocked
    nextCalled = false;
    auto tc2 = TestContext.create();
    mw(tc2.ctx, () { nextCalled = true; });

    assert(!nextCalled, "Next should NOT be called for rate limited request");
    assert(tc2.response.getStatus() == 429, "Status should be 429 Too Many Requests");
}

/// Test 13: 429 response includes correct headers
@("Test 13: Rate limit response has correct headers")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 1;
    config.burstSize = 0;
    config.windowSize = 10.seconds;
    config.includeRetryAfter = true;

    auto mw = rateLimitMiddleware(config);

    // Use up the limit
    auto tc1 = TestContext.create();
    mw(tc1.ctx, () {});

    // Get blocked request
    auto tc2 = TestContext.create();
    mw(tc2.ctx, () {});

    auto headers = tc2.response.getHeaders();
    assert("Content-Type" in headers, "Should have Content-Type header");
    assert(headers["Content-Type"] == "application/json", "Content-Type should be application/json");
    assert("Retry-After" in headers, "Should have Retry-After header");
}

/// Test 14: 429 response body is valid JSON
@("Test 14: Rate limit response body is valid JSON")
unittest
{
    import std.json : parseJSON, JSONException;

    RateLimitConfig config;
    config.requestsPerWindow = 1;
    config.burstSize = 0;
    config.windowSize = 10.seconds;
    config.limitExceededMessage = "Rate limit exceeded";

    auto mw = rateLimitMiddleware(config);

    // Use up limit
    auto tc1 = TestContext.create();
    mw(tc1.ctx, () {});

    // Get blocked
    auto tc2 = TestContext.create();
    mw(tc2.ctx, () {});

    try
    {
        auto json = parseJSON(tc2.response.getBody());
        assert(json["status"].integer == 429, "JSON should have status 429");
        assert(json["error"].str == "Rate limit exceeded", "JSON should have error message");
    }
    catch (JSONException e)
    {
        assert(false, "Response body should be valid JSON: " ~ e.msg);
    }
}

/// Test 15: Retry-After header can be disabled
@("Test 15: Retry-After can be disabled")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 1;
    config.burstSize = 0;
    config.windowSize = 10.seconds;
    config.includeRetryAfter = false;

    auto mw = rateLimitMiddleware(config);

    auto tc1 = TestContext.create();
    mw(tc1.ctx, () {});

    auto tc2 = TestContext.create();
    mw(tc2.ctx, () {});

    auto headers = tc2.response.getHeaders();
    assert("Retry-After" !in headers, "Retry-After header should not be present when disabled");
}

//
// Test 16-20: Key Extraction
//

/// Test 16: X-Forwarded-For header used for key
@("Test 16: X-Forwarded-For used for client identification")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 1;
    config.burstSize = 0;
    config.windowSize = 10.seconds;

    auto mw = rateLimitMiddleware(config);

    // Client 1 via proxy
    auto tc1 = TestContext.create(["X-Forwarded-For": "192.168.1.100"]);
    bool called1 = false;
    mw(tc1.ctx, () { called1 = true; });
    assert(called1, "Client 1 should be allowed");

    // Same IP - should be blocked
    auto tc2 = TestContext.create(["X-Forwarded-For": "192.168.1.100"]);
    bool called2 = false;
    mw(tc2.ctx, () { called2 = true; });
    assert(!called2, "Same client IP should be blocked");

    // Different IP - should be allowed
    auto tc3 = TestContext.create(["X-Forwarded-For": "192.168.1.200"]);
    bool called3 = false;
    mw(tc3.ctx, () { called3 = true; });
    assert(called3, "Different client IP should be allowed");
}

/// Test 17: First IP in X-Forwarded-For chain used
@("Test 17: First IP in X-Forwarded-For chain used")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 1;
    config.burstSize = 0;
    config.windowSize = 10.seconds;

    auto mw = rateLimitMiddleware(config);

    // Client with proxy chain
    auto tc1 = TestContext.create(["X-Forwarded-For": "10.0.0.1, 10.0.0.2, 10.0.0.3"]);
    bool called1 = false;
    mw(tc1.ctx, () { called1 = true; });
    assert(called1);

    // Same first IP, different chain - should be blocked (same client)
    auto tc2 = TestContext.create(["X-Forwarded-For": "10.0.0.1, 172.16.0.1"]);
    bool called2 = false;
    mw(tc2.ctx, () { called2 = true; });
    assert(!called2, "Should identify same client by first IP in chain");
}

/// Test 18: X-Real-IP fallback when no X-Forwarded-For
@("Test 18: X-Real-IP fallback")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 1;
    config.burstSize = 0;
    config.windowSize = 10.seconds;

    auto mw = rateLimitMiddleware(config);

    // Client via X-Real-IP
    auto tc1 = TestContext.create(["X-Real-IP": "203.0.113.50"]);
    bool called1 = false;
    mw(tc1.ctx, () { called1 = true; });
    assert(called1);

    // Same X-Real-IP - blocked
    auto tc2 = TestContext.create(["X-Real-IP": "203.0.113.50"]);
    bool called2 = false;
    mw(tc2.ctx, () { called2 = true; });
    assert(!called2, "Same X-Real-IP should be rate limited");
}

/// Test 19: Custom key extractor
@("Test 19: Custom key extractor")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 1;
    config.burstSize = 0;
    config.windowSize = 10.seconds;
    config.keyExtractor = (ref Context ctx) {
        return ctx.request.getHeader("X-API-Key");
    };

    auto mw = rateLimitMiddleware(config);

    // API key 1
    auto tc1 = TestContext.create(["X-API-Key": "key-abc123"]);
    bool called1 = false;
    mw(tc1.ctx, () { called1 = true; });
    assert(called1);

    // Same API key - blocked
    auto tc2 = TestContext.create(["X-API-Key": "key-abc123"]);
    bool called2 = false;
    mw(tc2.ctx, () { called2 = true; });
    assert(!called2, "Same API key should be rate limited");

    // Different API key - allowed
    auto tc3 = TestContext.create(["X-API-Key": "key-xyz789"]);
    bool called3 = false;
    mw(tc3.ctx, () { called3 = true; });
    assert(called3, "Different API key should be allowed");
}

/// Test 20: Custom message in response
@("Test 20: Custom error message")
unittest
{
    import std.json : parseJSON;

    RateLimitConfig config;
    config.requestsPerWindow = 1;
    config.burstSize = 0;
    config.windowSize = 10.seconds;
    config.limitExceededMessage = "Please slow down!";

    auto mw = rateLimitMiddleware(config);

    auto tc1 = TestContext.create();
    mw(tc1.ctx, () {});

    auto tc2 = TestContext.create();
    mw(tc2.ctx, () {});

    auto json = parseJSON(tc2.response.getBody());
    assert(json["error"].str == "Please slow down!", "Custom message should be in response");
}

//
// Test 21-25: Convenience Constructor and Edge Cases
//

/// Test 21: Convenience constructor works
@("Test 21: Convenience constructor")
unittest
{
    auto mw = rateLimitMiddleware(100, 20);  // 100 req/s, burst 20

    auto tc = TestContext.create();
    bool called = false;
    mw(tc.ctx, () { called = true; });

    assert(called, "Convenience constructor should create working middleware");
}

/// Test 22: Default config works
@("Test 22: Default config")
unittest
{
    auto mw = rateLimitMiddleware();

    auto tc = TestContext.create();
    bool called = false;
    mw(tc.ctx, () { called = true; });

    assert(called, "Default config should allow requests");
}

/// Test 23: Empty key extractor returns fallback
@("Test 23: Null key extractor handled")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 100;
    config.keyExtractor = null;  // Explicitly null

    auto mw = rateLimitMiddleware(config);

    auto tc = TestContext.create();
    bool called = false;
    mw(tc.ctx, () { called = true; });

    assert(called, "Should handle null key extractor gracefully");
}

/// Test 24: High traffic scenario
@("Test 24: High traffic scenario")
unittest
{
    RateLimitConfig config;
    config.requestsPerWindow = 100;
    config.burstSize = 50;
    config.windowSize = 1.seconds;

    auto limiter = new RateLimiter(config);

    int allowed = 0;
    int blocked = 0;

    // Simulate 200 rapid requests
    for (int i = 0; i < 200; i++)
    {
        if (limiter.isAllowed("high_traffic"))
            allowed++;
        else
            blocked++;
    }

    assert(allowed == 150, "Should allow exactly 150 (100 + 50 burst)");
    assert(blocked == 50, "Should block remaining 50");
}

/// Test 25: Thread safety - multiple concurrent access
@("Test 25: Thread safety")
unittest
{
    import core.atomic : atomicOp;

    RateLimitConfig config;
    config.requestsPerWindow = 50;
    config.burstSize = 0;
    config.windowSize = 10.seconds;

    auto limiter = new RateLimiter(config);

    shared int allowedCount = 0;
    shared int totalRequests = 0;

    // Spawn multiple threads
    Thread[] threads;
    for (int t = 0; t < 4; t++)
    {
        threads ~= new Thread({
            for (int i = 0; i < 25; i++)
            {
                atomicOp!"+="(totalRequests, 1);
                if (limiter.isAllowed("concurrent"))
                {
                    atomicOp!"+="(allowedCount, 1);
                }
            }
        });
    }

    foreach (thread; threads)
        thread.start();

    foreach (thread; threads)
        thread.join();

    assert(totalRequests == 100, "All requests should be processed");
    assert(allowedCount == 50, "Exactly 50 should be allowed with thread safety");
}
