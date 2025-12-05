/**
 * Span Exporter — Export Interface & Implementations
 *
 * Package: aurora.tracing.exporter
 *
 * Provides pluggable span export backends:
 * - SpanExporter interface for custom implementations
 * - ConsoleSpanExporter for development/debugging
 * - NoopSpanExporter for production when sampling is disabled
 *
 * Future implementations could include:
 * - OTLPSpanExporter (OpenTelemetry Protocol)
 * - JaegerSpanExporter
 * - ZipkinSpanExporter
 */
module aurora.tracing.exporter;

import aurora.tracing.span;
import aurora.tracing.context;
import std.stdio : File, stdout;
import core.time : Duration;

// ============================================================================
// SPAN EXPORTER INTERFACE
// ============================================================================

/**
 * Span Exporter Interface
 *
 * Implement this interface to export spans to various backends.
 */
interface SpanExporter
{
    /**
     * Export a batch of spans.
     *
     * Params:
     *   spans = Array of completed spans to export
     *
     * Returns: true if export successful, false otherwise
     */
    bool exportSpans(const(Span)[] spans);
    
    /**
     * Export a single span.
     *
     * Default implementation calls exportSpans with single-element array.
     */
    final bool exportSpan(const ref Span span)
    {
        return exportSpans([span]);
    }
    
    /**
     * Shutdown the exporter, flushing any pending data.
     */
    void shutdown();
    
    /**
     * Force flush any buffered spans.
     *
     * Returns: true if flush successful
     */
    bool forceFlush();
}

// ============================================================================
// CONSOLE SPAN EXPORTER
// ============================================================================

/**
 * Console Span Exporter
 *
 * Exports spans to stdout/stderr in a human-readable format.
 * Useful for development and debugging.
 */
class ConsoleSpanExporter : SpanExporter
{
    private
    {
        File output;
        bool useColors;
        bool verbose;
    }
    
    /**
     * Constructor
     *
     * Params:
     *   output = Output file (default: stdout)
     *   useColors = Use ANSI colors (default: true)
     *   verbose = Include all attributes and events (default: false)
     */
    this(File output = stdout, bool useColors = true, bool verbose = false)
    {
        this.output = output;
        this.useColors = useColors;
        this.verbose = verbose;
    }
    
    override bool exportSpans(const(Span)[] spans)
    {
        try
        {
            foreach (ref span; spans)
            {
                exportSingleSpan(span);
            }
            return true;
        }
        catch (Exception)
        {
            return false;
        }
    }
    
    override void shutdown()
    {
        // Flush output
        output.flush();
    }
    
    override bool forceFlush()
    {
        try
        {
            output.flush();
            return true;
        }
        catch (Exception)
        {
            return false;
        }
    }
    
    private void exportSingleSpan(const ref Span span) @trusted
    {
        import std.format : format;
        import std.conv : to;
        
        // ANSI colors
        string reset = useColors ? "\033[0m" : "";
        string cyan = useColors ? "\033[36m" : "";
        string yellow = useColors ? "\033[33m" : "";
        string green = useColors ? "\033[32m" : "";
        string red = useColors ? "\033[31m" : "";
        string dim = useColors ? "\033[2m" : "";
        
        // Status color
        string statusColor;
        string statusText;
        final switch (span.status.code)
        {
            case SpanStatusCode.UNSET:
                statusColor = dim;
                statusText = "UNSET";
                break;
            case SpanStatusCode.OK:
                statusColor = green;
                statusText = "OK";
                break;
            case SpanStatusCode.ERROR:
                statusColor = red;
                statusText = "ERROR";
                break;
        }
        
        // Duration
        auto durationUs = span.duration.total!"usecs";
        string durationStr;
        if (durationUs >= 1_000_000)
            durationStr = format!"%.2fs"(durationUs / 1_000_000.0);
        else if (durationUs >= 1_000)
            durationStr = format!"%.2fms"(durationUs / 1_000.0);
        else
            durationStr = format!"%dμs"(durationUs);
        
        // Output format:
        // [SPAN] service/name trace=abc123 span=def456 parent=789012 duration=1.23ms status=OK
        output.writef("%s[SPAN]%s %s%s%s/%s%s%s trace=%s%s%s span=%s%s%s",
            cyan, reset,
            yellow, span.serviceName, reset,
            cyan, span.name, reset,
            dim, span.traceId[0 .. 8], reset,  // Truncate trace-id for readability
            dim, span.spanId[0 .. 8], reset    // Truncate span-id
        );
        
        // Parent (if not root)
        if (!span.isRoot)
        {
            output.writef(" parent=%s%s%s",
                dim, span.parentId[0 .. 8], reset
            );
        }
        
        // Duration and status
        output.writef(" %s%s%s %s%s%s",
            dim, durationStr, reset,
            statusColor, statusText, reset
        );
        
        // Kind (if not INTERNAL)
        if (span.kind != SpanKind.INTERNAL)
        {
            string kindStr;
            final switch (span.kind)
            {
                case SpanKind.INTERNAL: kindStr = ""; break;
                case SpanKind.SERVER: kindStr = "SERVER"; break;
                case SpanKind.CLIENT: kindStr = "CLIENT"; break;
                case SpanKind.PRODUCER: kindStr = "PRODUCER"; break;
                case SpanKind.CONSUMER: kindStr = "CONSUMER"; break;
            }
            output.writef(" %s[%s]%s", dim, kindStr, reset);
        }
        
        output.writeln();
        
        // Verbose mode: attributes and events
        if (verbose)
        {
            // Attributes
            foreach (key, value; span.attributes)
            {
                output.writefln("  %s%s%s = %s", dim, key, reset, value.toString());
            }
            
            // Events
            foreach (event; span.events)
            {
                output.writefln("  %s[EVENT]%s %s", yellow, reset, event.name);
            }
            
            // Error description
            if (span.status.code == SpanStatusCode.ERROR && span.status.description.length > 0)
            {
                output.writefln("  %sError: %s%s", red, span.status.description, reset);
            }
        }
    }
}

// ============================================================================
// NOOP SPAN EXPORTER
// ============================================================================

/**
 * No-op Span Exporter
 *
 * Does nothing. Use when tracing is disabled or for benchmarking.
 */
class NoopSpanExporter : SpanExporter
{
    override bool exportSpans(const(Span)[] spans)
    {
        return true;
    }
    
    override void shutdown()
    {
        // Nothing to do
    }
    
    override bool forceFlush()
    {
        return true;
    }
}

// ============================================================================
// BATCHING SPAN EXPORTER
// ============================================================================

/**
 * Batching Span Exporter
 *
 * Wraps another exporter and batches spans for efficient export.
 * Flushes when batch size or timeout is reached.
 */
class BatchingSpanExporter : SpanExporter
{
    private
    {
        SpanExporter delegate_;
        Span[] buffer;
        size_t maxBatchSize;
        size_t currentSize;
    }
    
    /**
     * Constructor
     *
     * Params:
     *   delegate_ = Underlying exporter to send batches to
     *   maxBatchSize = Maximum number of spans per batch (default: 512)
     */
    this(SpanExporter delegate_, size_t maxBatchSize = 512)
    {
        this.delegate_ = delegate_;
        this.maxBatchSize = maxBatchSize;
        this.buffer.reserve(maxBatchSize);
    }
    
    override bool exportSpans(const(Span)[] spans)
    {
        foreach (ref span; spans)
        {
            // Copy the span (const to mutable)
            Span mutableSpan = cast(Span)span;
            buffer ~= mutableSpan;
            
            if (buffer.length >= maxBatchSize)
            {
                if (!flush())
                    return false;
            }
        }
        return true;
    }
    
    override void shutdown()
    {
        flush();
        delegate_.shutdown();
    }
    
    override bool forceFlush()
    {
        return flush() && delegate_.forceFlush();
    }
    
    private bool flush()
    {
        if (buffer.length == 0)
            return true;
        
        bool result = delegate_.exportSpans(buffer);
        buffer.length = 0;
        return result;
    }
}

// ============================================================================
// MULTI SPAN EXPORTER
// ============================================================================

/**
 * Multi Span Exporter
 *
 * Exports spans to multiple backends simultaneously.
 */
class MultiSpanExporter : SpanExporter
{
    private SpanExporter[] exporters;
    
    /**
     * Constructor
     *
     * Params:
     *   exporters = Array of exporters to send spans to
     */
    this(SpanExporter[] exporters...)
    {
        this.exporters = exporters.dup;
    }
    
    /**
     * Add an exporter.
     */
    void addExporter(SpanExporter exporter)
    {
        exporters ~= exporter;
    }
    
    override bool exportSpans(const(Span)[] spans)
    {
        bool allSuccess = true;
        foreach (exporter; exporters)
        {
            if (!exporter.exportSpans(spans))
                allSuccess = false;
        }
        return allSuccess;
    }
    
    override void shutdown()
    {
        foreach (exporter; exporters)
        {
            exporter.shutdown();
        }
    }
    
    override bool forceFlush()
    {
        bool allSuccess = true;
        foreach (exporter; exporters)
        {
            if (!exporter.forceFlush())
                allSuccess = false;
        }
        return allSuccess;
    }
}
