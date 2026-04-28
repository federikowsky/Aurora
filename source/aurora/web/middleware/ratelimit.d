module aurora.web.middleware.ratelimit;

import aurora.web.middleware;
import aurora.web.context;
import aurora.http;
import core.time;
import core.sync.mutex;

struct RateLimitConfig
{
    uint requestsPerWindow = 100;
    uint burstSize = 10;
    Duration windowSize = 1.seconds;
    string delegate(ref Context) keyExtractor = null;
    string limitExceededMessage = "Too Many Requests";
    bool includeRetryAfter = true;
    Duration cleanupInterval = 60.seconds;
    Duration bucketExpiry = 5.minutes;
    size_t maxBuckets = 100_000;
}

private long currentTimeHnsecs() @safe nothrow @nogc
{
    import core.time : MonoTime, ticksToNSecs;
    return ticksToNSecs(MonoTime.currTime.ticks) / 100;
}

private struct TokenBucket
{
    double tokens;
    long lastRefillTime;
    long lastAccessTime;
    uint maxTokens;
    double refillRate;

    void initialize(uint maxTokens, Duration refillPeriod) @safe nothrow
    {
        this.maxTokens = maxTokens;
        this.tokens = maxTokens;
        auto now = currentTimeHnsecs();
        this.lastRefillTime = now;
        this.lastAccessTime = now;
        this.refillRate = cast(double) maxTokens / refillPeriod.total!"hnsecs";
    }

    bool tryConsume() @safe nothrow
    {
        refill();

        if (tokens >= 1.0)
        {
            tokens -= 1.0;
            lastAccessTime = currentTimeHnsecs();
            return true;
        }

        return false;
    }

    uint getRetryAfterSeconds() @safe nothrow
    {
        if (tokens >= 1.0)
            return 0;

        auto tokensNeeded = 1.0 - tokens;
        auto hnsecs = tokensNeeded / refillRate;
        return cast(uint)(hnsecs / 10_000_000) + 1;
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
}

class RateLimiter
{
    private RateLimitConfig config;
    private TokenBucket[string] buckets;
    private Mutex mutex;
    private long lastCleanupTime;
    private size_t totalCleaned;

    this(RateLimitConfig config) @trusted
    {
        this.config = config;
        this.mutex = new Mutex();
        this.lastCleanupTime = currentTimeHnsecs();
        this.totalCleaned = 0;
    }

    bool isAllowed(string key) @trusted nothrow
    {
        try
        {
            synchronized (mutex)
            {
                maybeCleanup();

                if (key !in buckets)
                {
                    if (config.maxBuckets > 0 && buckets.length >= config.maxBuckets)
                    {
                        doCleanup();

                        if (buckets.length >= config.maxBuckets)
                            return false;
                    }

                    TokenBucket bucket;
                    bucket.initialize(config.requestsPerWindow + config.burstSize, config.windowSize);
                    buckets[key] = bucket;
                }

                buckets[key].lastAccessTime = currentTimeHnsecs();
                return buckets[key].tryConsume();
            }
        }
        catch (Exception)
        {
            return true;
        }
    }

    uint getRetryAfter(string key) @trusted nothrow
    {
        try
        {
            synchronized (mutex)
            {
                if (auto bucket = key in buckets)
                    return bucket.getRetryAfterSeconds();
                return 1;
            }
        }
        catch (Exception)
        {
            return 1;
        }
    }

    size_t cleanup() @trusted
    {
        synchronized (mutex)
            return doCleanup();
    }

    RateLimiterStats getStats() @trusted nothrow
    {
        try
        {
            synchronized (mutex)
            {
                RateLimiterStats stats;
                stats.activeBuckets = buckets.length;
                stats.totalCleaned = totalCleaned;
                stats.maxBuckets = config.maxBuckets;
                return stats;
            }
        }
        catch (Exception)
        {
            return RateLimiterStats.init;
        }
    }

    private void maybeCleanup() @safe nothrow
    {
        if (config.cleanupInterval == Duration.zero)
            return;

        auto now = currentTimeHnsecs();
        auto elapsed = now - lastCleanupTime;

        if (elapsed >= config.cleanupInterval.total!"hnsecs")
        {
            try
            {
                doCleanup();
            }
            catch (Exception)
            {
            }
        }
    }

    private size_t doCleanup() @safe
    {
        auto now = currentTimeHnsecs();
        auto expiryHnsecs = config.bucketExpiry.total!"hnsecs";
        string[] keysToRemove;

        foreach (key, ref bucket; buckets)
        {
            if (now - bucket.lastAccessTime > expiryHnsecs)
                keysToRemove ~= key;
        }

        foreach (key; keysToRemove)
            buckets.remove(key);

        totalCleaned += keysToRemove.length;
        lastCleanupTime = now;
        return keysToRemove.length;
    }
}

struct RateLimiterStats
{
    size_t activeBuckets;
    size_t totalCleaned;
    size_t maxBuckets;
}

class RateLimitMiddleware
{
    private RateLimitConfig config;
    private RateLimiter limiter;

    this(RateLimitConfig config)
    {
        this.config = config;
        this.limiter = new RateLimiter(config);
    }

    void handle(Context ctx, NextFunction next)
    {
        string key = extractKey(ctx);

        if (!limiter.isAllowed(key))
        {
            sendRateLimitResponse(ctx, key);
            return;
        }

        next();
    }

    private string extractKey(ref Context ctx)
    {
        if (config.keyExtractor !is null)
        {
            try
            {
                return config.keyExtractor(ctx);
            }
            catch (Exception)
            {
                return "default";
            }
        }

        if (ctx.request !is null)
        {
            auto xff = ctx.request.getHeader("X-Forwarded-For");
            if (xff.length > 0)
            {
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

        return "default";
    }

    private void sendRateLimitResponse(Context ctx, string key)
    {
        if (ctx.response is null)
            return;

        ctx.response.setStatus(429);
        ctx.response.setHeader("Content-Type", "application/json");

        if (config.includeRetryAfter)
        {
            import std.conv : to;
            auto retryAfter = limiter.getRetryAfter(key);
            ctx.response.setHeader("Retry-After", retryAfter.to!string);
        }

        import std.format : format;
        auto body_ = format(`{"error":"%s","status":429}`, config.limitExceededMessage);
        ctx.response.setBody(body_);
    }
}

Middleware rateLimitMiddleware(RateLimitConfig config = RateLimitConfig())
{
    auto limiter = new RateLimitMiddleware(config);

    return (ref Context ctx, NextFunction next) {
        limiter.handle(ctx, next);
    };
}

Middleware rateLimitMiddleware(uint requestsPerSecond, uint burstSize = 10)
{
    RateLimitConfig config;
    config.requestsPerWindow = requestsPerSecond;
    config.burstSize = burstSize;
    return rateLimitMiddleware(config);
}
