/**
 * Aurora HTTP Framework
 *
 * High-performance HTTP/1.1 backend framework for D.
 *
 * Quick Start:
 * ---
 * import aurora;
 *
 * void main() {
 *     auto app = new App();
 *     
 *     app.get("/", (ref Context ctx) {
 *         ctx.send("Hello, Aurora!");
 *     });
 *     
 *     app.listen(8080);
 * }
 * ---
 *
 * Features:
 * - Express.js-like routing API
 * - Middleware pipeline
 * - Schema validation (Pydantic-like)
 * - High-performance HTTP parsing (Wire)
 * - Multi-threaded worker pool
 * - Memory pools (zero GC in hot path)
 *
 * Modules:
 * - aurora.app: Main application class
 * - aurora.web: Router, Context, Middleware
 * - aurora.http: HTTP parsing and response building
 * - aurora.schema: Validation and JSON serialization
 * - aurora.config: Configuration management
 * - aurora.logging: Structured logging
 * - aurora.metrics: Performance metrics
 */
module aurora;

// Main application
public import aurora.app;

// Web framework
public import aurora.web;

// HTTP protocol
public import aurora.http;

// Schema validation
public import aurora.schema;

// Configuration
public import aurora.config;

// Logging
public import aurora.logging;

// Metrics
public import aurora.metrics;

// Distributed Tracing (OpenTelemetry-compatible)
public import aurora.tracing;

// Memory management (advanced usage)
public import aurora.mem;

// Runtime (advanced usage)
public import aurora.runtime;
