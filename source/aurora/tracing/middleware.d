/**
 * Tracing Middleware — Automatic Request Tracing
 *
 * Package: aurora.tracing.middleware
 *
 * Provides automatic distributed tracing for HTTP requests:
 * - Extracts trace context from incoming headers (traceparent, tracestate)
 * - Creates spans for each request with HTTP semantic attributes
 * - Propagates trace context to downstream services
 * - Exports spans via pluggable SpanExporter
 *
 * HTTP Semantic Conventions (OpenTelemetry subset):
 * - http.method: HTTP request method
 * - http.url: Full request URL
 * - http.route: Matched route pattern
 * - http.status_code: HTTP response status code
 * - http.request_content_length: Request body size
 * - http.response_content_length: Response body size
 * - net.host.name: Host header value
 * - user_agent.original: User-Agent header
 */
module aurora.tracing.middleware;

import aurora.tracing.context;
import aurora.tracing.span;
import aurora.tracing.exporter;
import aurora.web.context : Context;
import core.time : MonoTime;

// Import middleware types
alias NextFunction = void delegate();
alias Middleware = void delegate(ref Context ctx, NextFunction next);

// ============================================================================
// TRACING DATA (stored in context)
// ============================================================================

/**
 * Tracing data stored in request context.
 * Provides access to trace/span IDs for handlers.
 */
class TracingData
{
    string traceId;
    string spanId;
    string traceparent;
    bool sampled;
}

/**
 * Get tracing data from context.
 * Returns null if not available.
 */
TracingData getTracingData(ref Context ctx) @trusted
{
    return ctx.storage.get!TracingData("_tracing");
}

/**
 * Get trace ID from context.
 * Returns empty string if not available.
 */
string getTraceId(ref Context ctx) @trusted
{
    auto data = getTracingData(ctx);
    return data !is null ? data.traceId : "";
}

/**
 * Get span ID from context.
 * Returns empty string if not available.
 */
string getSpanId(ref Context ctx) @trusted
{
    auto data = getTracingData(ctx);
    return data !is null ? data.spanId : "";
}

/**
 * Get traceparent header value from context.
 * Returns empty string if not available.
 */
string getTraceparent(ref Context ctx) @trusted
{
    auto data = getTracingData(ctx);
    return data !is null ? data.traceparent : "";
}

// ============================================================================
// TRACING CONFIGURATION
// ============================================================================

/**
 * Tracing Configuration
 */
struct TracingConfig
{
    /// Service name (required)
    string serviceName = "aurora-service";
    
    /// Whether to record all spans (true) or respect incoming sampling decision (false)
    bool alwaysSample = false;
    
    /// Probability of sampling new traces (0.0 to 1.0)
    double samplingProbability = 1.0;
    
    /// Include request headers as attributes
    bool recordHeaders = false;
    
    /// Headers to include (if recordHeaders is true)
    string[] includedHeaders = ["content-type", "accept", "user-agent"];
    
    /// Skip tracing for these paths (exact match or glob with trailing *)
    string[] excludePaths = ["/health/*", "/metrics"];
    
    /// Create default configuration
    static TracingConfig defaults() @safe nothrow
    {
        return TracingConfig.init;
    }
}

// ============================================================================
// TRACING MIDDLEWARE
// ============================================================================

/**
 * Tracing Middleware
 *
 * Automatically creates spans for HTTP requests and exports them.
 */
class TracingMiddleware
{
    private
    {
        TracingConfig config;
        SpanExporter exporter;
        
        // Random state for sampling decisions
        uint randomState = 12345;
    }
    
    /**
     * Constructor
     *
     * Params:
     *   serviceName = Name of this service
     *   exporter = SpanExporter to use (required)
     *   config = Optional configuration
     */
    this(string serviceName, SpanExporter exporter, TracingConfig config = TracingConfig.defaults())
    {
        this.config = config;
        this.config.serviceName = serviceName;
        this.exporter = exporter;
    }
    
    /**
     * Simplified constructor with just service name and exporter.
     */
    this(string serviceName, SpanExporter exporter)
    {
        TracingConfig cfg;
        cfg.serviceName = serviceName;
        this(serviceName, exporter, cfg);
    }
    
    /**
     * Handle request (middleware interface)
     */
    void handle(ref Context ctx, NextFunction next)
    {
        if (ctx.request is null)
        {
            next();
            return;
        }
        
        string path = ctx.request.path;
        
        // Check if path is excluded from tracing
        if (isExcludedPath(path))
        {
            next();
            return;
        }
        
        // Extract or create trace context
        TraceContext traceCtx = extractTraceContext(ctx);
        
        // Check sampling decision
        if (!shouldSample(traceCtx))
        {
            // Store context for propagation even if not sampled
            storeTraceContext(ctx, traceCtx);
            next();
            return;
        }
        
        // Create span
        Span span = createSpan(ctx, traceCtx);
        
        // Store span in context for access by handlers
        storeSpanInContext(ctx, span);
        
        // Execute downstream handlers
        bool success = true;
        Exception caughtException = null;
        
        try
        {
            next();
        }
        catch (Exception e)
        {
            success = false;
            caughtException = e;
            span.setError(e.msg);
            span.addEvent("exception", [
                "exception.type": AttributeValue.fromString(typeid(e).name),
                "exception.message": AttributeValue.fromString(e.msg)
            ]);
        }
        
        // Finalize span
        finalizeSpan(ctx, span, success);
        
        // Export span
        exporter.exportSpan(span);
        
        // Re-throw exception if any
        if (caughtException !is null)
            throw caughtException;
    }
    
    /**
     * Get as middleware delegate
     */
    Middleware middleware() @safe
    {
        return &this.handle;
    }
    
    /**
     * Shutdown the exporter
     */
    void shutdown()
    {
        exporter.shutdown();
    }
    
    // ========================================================================
    // PRIVATE METHODS
    // ========================================================================
    
    /**
     * Extract trace context from incoming headers.
     */
    private TraceContext extractTraceContext(ref Context ctx) @trusted
    {
        // Try to parse traceparent header
        string traceparent = ctx.request.getHeader("traceparent");
        string tracestate = ctx.request.getHeader("tracestate");
        
        if (traceparent.length > 0)
        {
            auto traceCtx = TraceContext.parseWithState(traceparent, tracestate);
            if (traceCtx.valid)
                return traceCtx;
        }
        
        // No valid incoming context - generate new trace
        return TraceContext.generate(true);
    }
    
    /**
     * Determine if this request should be sampled.
     */
    private bool shouldSample(const ref TraceContext traceCtx) @trusted nothrow
    {
        // Always sample if configured
        if (config.alwaysSample)
            return true;
        
        // Respect incoming sampling decision
        if (traceCtx.isSampled())
            return true;
        
        // Apply sampling probability for new traces
        if (config.samplingProbability >= 1.0)
            return true;
        if (config.samplingProbability <= 0.0)
            return false;
        
        return randomFloat() < config.samplingProbability;
    }
    
    /**
     * Create a span for the request.
     */
    private Span createSpan(ref Context ctx, ref TraceContext traceCtx) @trusted
    {
        // Create child span from incoming context
        Span span = Span.fromContext(traceCtx, 
            ctx.request.method ~ " " ~ ctx.request.path,
            config.serviceName,
            SpanKind.SERVER);
        
        // Set HTTP semantic attributes
        span.setAttribute("http.method", ctx.request.method);
        span.setAttribute("http.url", ctx.request.path);
        
        // Detect scheme from X-Forwarded-Proto header (set by reverse proxies)
        string scheme = ctx.request.getHeader("x-forwarded-proto");
        if (scheme.length == 0)
            scheme = "http";
        span.setAttribute("http.scheme", scheme);
        
        // Host
        string host = ctx.request.getHeader("host");
        if (host.length > 0)
            span.setAttribute("net.host.name", host);
        
        // User agent
        string userAgent = ctx.request.getHeader("user-agent");
        if (userAgent.length > 0)
            span.setAttribute("user_agent.original", userAgent);
        
        // Request content length
        string contentLength = ctx.request.getHeader("content-length");
        if (contentLength.length > 0)
        {
            import std.conv : to;
            try
            {
                span.setAttribute("http.request_content_length", contentLength.to!long);
            }
            catch (Exception) {}
        }
        
        // Record configured headers
        if (config.recordHeaders)
        {
            foreach (headerName; config.includedHeaders)
            {
                string value = ctx.request.getHeader(headerName);
                if (value.length > 0)
                    span.setAttribute("http.request.header." ~ headerName, value);
            }
        }
        
        return span;
    }
    
    /**
     * Finalize span with response data.
     */
    private void finalizeSpan(ref Context ctx, ref Span span, bool success) @trusted
    {
        span.end();
        
        // Response status code
        int statusCode = ctx.response !is null ? ctx.response.getStatus() : 0;
        if (statusCode > 0)
        {
            span.setAttribute("http.status_code", cast(long)statusCode);
            
            // Set span status based on HTTP status
            if (statusCode >= 400)
            {
                span.setError("HTTP " ~ intToStr(statusCode));
            }
            else
            {
                span.setOk();
            }
        }
    }
    
    /**
     * Store trace context in request context for handler access.
     * Uses a simple approach: store a reference to a TracingData object.
     */
    private void storeTraceContext(ref Context ctx, ref TraceContext traceCtx) @trusted
    {
        // Store the trace data as a class instance
        auto data = new TracingData();
        data.traceId = traceCtx.traceIdHex();
        data.spanId = traceCtx.spanIdHex();
        data.traceparent = traceCtx.toTraceparent();
        data.sampled = traceCtx.isSampled();
        ctx.storage.set("_tracing", data);
    }
    
    /**
     * Store span in request context.
     */
    private void storeSpanInContext(ref Context ctx, ref Span span) @trusted
    {
        auto data = new TracingData();
        data.traceId = span.context.traceIdHex();
        data.spanId = span.context.spanIdHex();
        data.traceparent = span.context.toTraceparent();
        data.sampled = span.context.isSampled();
        ctx.storage.set("_tracing", data);
    }
    
    /**
     * Check if path should be excluded from tracing.
     */
    private bool isExcludedPath(string path) const @safe nothrow
    {
        foreach (pattern; config.excludePaths)
        {
            if (globMatch(path, pattern))
                return true;
        }
        return false;
    }
    
    /**
     * Simple glob matching (trailing * only).
     */
    private static bool globMatch(string path, string pattern) @safe nothrow
    {
        if (pattern.length == 0)
            return false;
        
        if (pattern[$ - 1] == '*')
        {
            string prefix = pattern[0 .. $ - 1];
            return path.length >= prefix.length && path[0 .. prefix.length] == prefix;
        }
        else
        {
            return path == pattern;
        }
    }
    
    /**
     * Simple pseudo-random number generator.
     */
    private float randomFloat() @safe nothrow
    {
        randomState ^= randomState << 13;
        randomState ^= randomState >> 17;
        randomState ^= randomState << 5;
        return (randomState & 0x7FFFFFFF) / cast(float)0x80000000;
    }
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

private string intToStr(int n) @safe nothrow
{
    if (n == 0) return "0";
    
    char[12] buffer;
    int pos = 11;
    bool negative = n < 0;
    if (negative) n = -n;
    
    while (n > 0)
    {
        buffer[pos--] = cast(char)('0' + n % 10);
        n /= 10;
    }
    
    if (negative)
        buffer[pos--] = '-';
    
    return buffer[pos + 1 .. 12].idup;
}

// ============================================================================
// FACTORY FUNCTION
// ============================================================================

/**
 * Create tracing middleware.
 *
 * Example:
 * ---
 * auto exporter = new ConsoleSpanExporter();
 * app.use(tracingMiddleware("my-service", exporter));
 * ---
 */
Middleware tracingMiddleware(string serviceName, SpanExporter exporter, 
                              TracingConfig config = TracingConfig.defaults())
{
    auto mw = new TracingMiddleware(serviceName, exporter, config);
    return mw.middleware;
}

/**
 * Create tracing middleware with instance access (for shutdown).
 */
TracingMiddleware createTracingMiddleware(string serviceName, SpanExporter exporter,
                                          TracingConfig config = TracingConfig.defaults())
{
    return new TracingMiddleware(serviceName, exporter, config);
}
