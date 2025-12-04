/**
 * Rate Limiting Middleware
 *
 * Package: aurora.web.middleware.ratelimit
 *
 * Features:
 * - Token bucket algorithm
 * - Per-client rate limiting (by IP or custom key)
 * - Configurable requests/second and burst size
 * - 429 Too Many Requests response
 * - Retry-After header
 */
module aurora.web.middleware.ratelimit;

import aurora.web.middleware;
import aurora.web.context;
import aurora.http;
import core.time;
import core.sync.mutex;

/**
 * RateLimitConfig - Rate limiter configuration
 */
struct RateLimitConfig
{
    /// Maximum requests per window
    uint requestsPerWindow = 100;
    
    /// Burst size (allows temporary spikes)
    uint burstSize = 10;
    
    /// Time window for rate limiting
    Duration windowSize = 1.seconds;
    
    /// Custom key extractor (default: use path as fallback since we can't easily get IP)
    string delegate(ref Context) keyExtractor = null;
    
    /// Custom message for 429 response
    string limitExceededMessage = "Too Many Requests";
    
    /// Include Retry-After header
    bool includeRetryAfter = true;
}

/**
 * TokenBucket - Token bucket for rate limiting
 */
private struct TokenBucket
{
    double tokens;
    long lastRefillTime;  // MonoTime in hnsecs
    uint maxTokens;
    double refillRate;  // tokens per hnsec
    
    void initialize(uint maxTokens, Duration refillPeriod) @safe nothrow
    {
        this.maxTokens = maxTokens;
        this.tokens = maxTokens;
        this.lastRefillTime = currentTimeHnsecs();
        // Calculate refill rate: maxTokens tokens per refillPeriod
        this.refillRate = cast(double)maxTokens / refillPeriod.total!"hnsecs";
    }
    
    bool tryConsume() @safe nothrow
    {
        refill();
        
        if (tokens >= 1.0)
        {
            tokens -= 1.0;
            return true;
        }
        return false;
    }
    
    /// Get seconds until a token is available
    uint getRetryAfterSeconds() @safe nothrow
    {
        if (tokens >= 1.0) return 0;
        
        double tokensNeeded = 1.0 - tokens;
        double hnsecs = tokensNeeded / refillRate;
        return cast(uint)(hnsecs / 10_000_000) + 1;  // Round up
    }
    
    private void refill() @safe nothrow
    {
        auto now = currentTimeHnsecs();
        auto elapsed = now - lastRefillTime;
        
        if (elapsed > 0)
        {
            tokens += elapsed * refillRate;
            if (tokens > maxTokens)
                tokens = maxTokens;
            lastRefillTime = now;
        }
    }
    
    private static long currentTimeHnsecs() @safe nothrow
    {
        import core.time : MonoTime;
        try {
            return MonoTime.currTime.ticks;
        } catch (Exception) {
            return 0;
        }
    }
}

/**
 * RateLimiter - Thread-safe rate limiter with per-key buckets
 */
class RateLimiter
{
    private RateLimitConfig config;
    private TokenBucket[string] buckets;
    private Mutex mutex;
    
    this(RateLimitConfig config) @trusted
    {
        this.config = config;
        this.mutex = new Mutex();
    }
    
    /**
     * Check if request is allowed
     * Returns: true if allowed, false if rate limited
     */
    bool isAllowed(string key) @trusted nothrow
    {
        try {
            synchronized (mutex)
            {
                if (key !in buckets)
                {
                    TokenBucket bucket;
                    bucket.initialize(
                        config.requestsPerWindow + config.burstSize,
                        config.windowSize
                    );
                    buckets[key] = bucket;
                }
                
                return buckets[key].tryConsume();
            }
        } catch (Exception) {
            return true;  // On error, allow the request
        }
    }
    
    /**
     * Get Retry-After seconds for a key
     */
    uint getRetryAfter(string key) @trusted nothrow
    {
        try {
            synchronized (mutex)
            {
                if (auto bucket = key in buckets)
                {
                    return bucket.getRetryAfterSeconds();
                }
                return 1;
            }
        } catch (Exception) {
            return 1;
        }
    }
    
    /**
     * Clean up old buckets (call periodically)
     */
    void cleanup() @trusted
    {
        // TODO: Implement bucket cleanup for keys not seen in a while
        // This prevents memory growth with many unique keys
    }
}

/**
 * RateLimitMiddleware - Rate limiting middleware class
 */
class RateLimitMiddleware
{
    private RateLimitConfig config;
    private RateLimiter limiter;
    
    this(RateLimitConfig config)
    {
        this.config = config;
        this.limiter = new RateLimiter(config);
    }
    
    /**
     * Handle request
     */
    void handle(Context ctx, NextFunction next)
    {
        // Extract key for rate limiting
        string key = extractKey(ctx);
        
        // Check rate limit
        if (!limiter.isAllowed(key))
        {
            sendRateLimitResponse(ctx, key);
            return;
        }
        
        // Allowed - continue to next middleware/handler
        next();
    }
    
    private string extractKey(ref Context ctx)
    {
        // Use custom extractor if provided
        if (config.keyExtractor !is null)
        {
            try {
                return config.keyExtractor(ctx);
            } catch (Exception) {
                return "default";
            }
        }
        
        // Default: use X-Forwarded-For or X-Real-IP if behind proxy
        if (ctx.request !is null)
        {
            auto xff = ctx.request.getHeader("X-Forwarded-For");
            if (xff.length > 0)
            {
                // Take first IP in chain
                import std.string : indexOf;
                auto commaPos = xff.indexOf(',');
                if (commaPos > 0)
                    return xff[0 .. commaPos];
                return xff;
            }
            
            auto realIp = ctx.request.getHeader("X-Real-IP");
            if (realIp.length > 0)
                return realIp;
        }
        
        // Fallback to "default" (single bucket for all)
        return "default";
    }
    
    private void sendRateLimitResponse(Context ctx, string key)
    {
        if (ctx.response is null) return;
        
        ctx.response.setStatus(429);
        ctx.response.setHeader("Content-Type", "application/json");
        
        if (config.includeRetryAfter)
        {
            import std.conv : to;
            auto retryAfter = limiter.getRetryAfter(key);
            ctx.response.setHeader("Retry-After", retryAfter.to!string);
        }
        
        import std.format : format;
        string body_ = format(`{"error":"%s","status":429}`, config.limitExceededMessage);
        ctx.response.setBody(body_);
    }
}

/**
 * Helper function to create rate limiting middleware
 */
Middleware rateLimitMiddleware(RateLimitConfig config = RateLimitConfig())
{
    auto limiter = new RateLimitMiddleware(config);
    
    return (ref Context ctx, NextFunction next) {
        limiter.handle(ctx, next);
    };
}

/**
 * Convenience constructors
 */
Middleware rateLimitMiddleware(uint requestsPerSecond, uint burstSize = 10)
{
    RateLimitConfig config;
    config.requestsPerWindow = requestsPerSecond;
    config.burstSize = burstSize;
    return rateLimitMiddleware(config);
}
