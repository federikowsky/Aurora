/**
 * Aurora Tracing Module — W3C Trace Context & Distributed Tracing
 *
 * Package: aurora.tracing
 *
 * Provides distributed tracing capabilities following W3C Trace Context standard:
 * - TraceContext parsing and generation (traceparent, tracestate headers)
 * - Span creation with timing, attributes, and status
 * - Pluggable SpanExporter interface for backend integration
 * - TracingMiddleware for automatic request tracing
 *
 * Standards:
 * - W3C Trace Context Level 1: https://www.w3.org/TR/trace-context/
 * - OpenTelemetry semantic conventions (subset)
 *
 * Features:
 * - Zero external dependencies (pure D implementation)
 * - Thread-safe span collection
 * - Configurable sampling
 * - Console exporter for development/debugging
 *
 * Example:
 * ---
 * import aurora.tracing;
 * 
 * // Create tracing middleware with console exporter
 * auto exporter = new ConsoleSpanExporter();
 * auto tracing = new TracingMiddleware("my-service", exporter);
 * 
 * app.use(tracing.middleware);
 * 
 * // In handlers, access trace context
 * void handler(ref Context ctx) {
 *     auto traceId = ctx.getTraceId();
 *     auto spanId = ctx.getSpanId();
 *     log.info("Processing request trace=", traceId);
 * }
 * ---
 *
 * Authors: Aurora Contributors
 * License: MIT
 * Standards: W3C Trace Context Level 1
 */
module aurora.tracing;

// Re-export public API
public import aurora.tracing.context;
public import aurora.tracing.span;
public import aurora.tracing.exporter;
public import aurora.tracing.middleware;
