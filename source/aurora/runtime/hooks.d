/**
 * Aurora Server Hooks and Exception Handlers
 *
 * Provides extensibility points for the Aurora server:
 * - Server lifecycle hooks (onStart, onStop, onError, onRequest, onResponse)
 * - Typed exception handlers (FastAPI-style)
 *
 * Example:
 * ---
 * auto server = new Server(router, config);
 * 
 * // Lifecycle hooks
 * server.hooks.onStart(() => db.connect());
 * server.hooks.onStop(() => db.close());
 * server.hooks.onError((e, ctx) => logger.error(e.msg));
 * 
 * // Exception handlers (most specific first)
 * server.addExceptionHandler!ValidationError((ctx, e) => ctx.status(400).json(...));
 * server.addExceptionHandler!Exception((ctx, e) => ctx.status(500).json(...));
 * ---
 */
module aurora.runtime.hooks;

import aurora.web.context : Context;

// ============================================================================
// HOOK TYPE ALIASES
// ============================================================================

/// Hook called when the server starts (before accepting connections)
alias StartHook = void delegate();

/// Hook called when the server stops (after closing all connections)
alias StopHook = void delegate();

/// Hook called when an exception occurs during request handling
/// Note: This is for logging/metrics only. Use ExceptionHandler to modify the response.
alias ErrorHook = void delegate(Exception e, ref Context ctx);

/// Hook called before routing each request
alias RequestHook = void delegate(ref Context ctx);

/// Hook called after handler completion (before response is sent)
alias ResponseHook = void delegate(ref Context ctx);

// ============================================================================
// EXCEPTION HANDLER TYPES
// ============================================================================

/// Typed exception handler (user-facing API)
/// The handler receives the context and the specific exception type.
alias ExceptionHandler(E : Exception) = void delegate(ref Context ctx, E e);

/// Type-erased handler for internal storage
/// All handlers are stored as this type after wrapping.
alias TypeErasedHandler = void delegate(ref Context ctx, Exception e);

// ============================================================================
// SERVER HOOKS STRUCT
// ============================================================================

/**
 * Server hooks configuration.
 * 
 * Provides a clean API for registering lifecycle hooks:
 * - server.hooks.onStart(() => ...)
 * - server.hooks.onStop(() => ...)
 * - server.hooks.onError((e, ctx) => ...)
 * - server.hooks.onRequest((ctx) => ...)
 * - server.hooks.onResponse((ctx) => ...)
 *
 * Multiple hooks can be registered for each event type.
 * Hooks are executed in registration order.
 */
struct ServerHooks
{
private:
    StartHook[] _onStart;
    StopHook[] _onStop;
    ErrorHook[] _onError;
    RequestHook[] _onRequest;
    ResponseHook[] _onResponse;

public:
    // ========================================
    // HOOK REGISTRATION (clean API)
    // ========================================

    /// Register a hook to be called when the server starts.
    /// Multiple start hooks can be registered; they execute in order.
    void onStart(StartHook hook) @safe nothrow
    {
        if (hook !is null)
            _onStart ~= hook;
    }

    /// Register a hook to be called when the server stops.
    /// Multiple stop hooks can be registered; they execute in order.
    void onStop(StopHook hook) @safe nothrow
    {
        if (hook !is null)
            _onStop ~= hook;
    }

    /// Register a hook to be called on request errors.
    /// This is for logging/metrics - use exception handlers to modify responses.
    /// Multiple error hooks can be registered; they execute in order.
    void onError(ErrorHook hook) @safe nothrow
    {
        if (hook !is null)
            _onError ~= hook;
    }

    /// Register a hook to be called before routing each request.
    /// Useful for request ID generation, early validation, etc.
    /// Multiple request hooks can be registered; they execute in order.
    void onRequest(RequestHook hook) @safe nothrow
    {
        if (hook !is null)
            _onRequest ~= hook;
    }

    /// Register a hook to be called after handler completion.
    /// Useful for adding common headers, logging, etc.
    /// Multiple response hooks can be registered; they execute in order.
    void onResponse(ResponseHook hook) @safe nothrow
    {
        if (hook !is null)
            _onResponse ~= hook;
    }

    // ========================================
    // INTERNAL ACCESS (for Server)
    // ========================================

    /// Get all registered start hooks (internal use only)
    @property StartHook[] startHooks() @safe nothrow { return _onStart; }

    /// Get all registered stop hooks (internal use only)
    @property StopHook[] stopHooks() @safe nothrow { return _onStop; }

    /// Get all registered error hooks (internal use only)
    @property ErrorHook[] errorHooks() @safe nothrow { return _onError; }

    /// Get all registered request hooks (internal use only)
    @property RequestHook[] requestHooks() @safe nothrow { return _onRequest; }

    /// Get all registered response hooks (internal use only)
    @property ResponseHook[] responseHooks() @safe nothrow { return _onResponse; }

    // ========================================
    // UTILITY METHODS
    // ========================================

    /// Check if any hooks are registered
    @property bool hasHooks() const @safe nothrow
    {
        return _onStart.length > 0 ||
               _onStop.length > 0 ||
               _onError.length > 0 ||
               _onRequest.length > 0 ||
               _onResponse.length > 0;
    }

    /// Get count of all registered hooks
    @property size_t totalHooks() const @safe nothrow
    {
        return _onStart.length +
               _onStop.length +
               _onError.length +
               _onRequest.length +
               _onResponse.length;
    }

    /// Clear all hooks (useful for testing)
    void clear() @safe nothrow
    {
        _onStart = null;
        _onStop = null;
        _onError = null;
        _onRequest = null;
        _onResponse = null;
    }

    // ========================================
    // EXECUTION METHODS (for Server internal use)
    // ========================================

    /// Execute all start hooks in order
    void executeOnStart() @trusted
    {
        foreach (hook; _onStart)
        {
            hook();
        }
    }

    /// Execute all stop hooks in order
    void executeOnStop() @trusted
    {
        foreach (hook; _onStop)
        {
            hook();
        }
    }

    /// Execute all error hooks in order
    void executeOnError(Exception e, ref Context ctx) @trusted
    {
        foreach (hook; _onError)
        {
            hook(e, ctx);
        }
    }

    /// Execute all request hooks in order
    void executeOnRequest(ref Context ctx) @trusted
    {
        foreach (hook; _onRequest)
        {
            hook(ctx);
        }
    }

    /// Execute all response hooks in order
    void executeOnResponse(ref Context ctx) @trusted
    {
        foreach (hook; _onResponse)
        {
            hook(ctx);
        }
    }
}
