/**
 * Middleware Package
 *
 * Provides middleware types, pipeline execution, and common middleware.
 */
module aurora.web.middleware;

import aurora.web.context;
import aurora.web.router : Handler;

// Core middleware types
alias NextFunction = void delegate();
alias Middleware = void delegate(ref Context ctx, NextFunction next);

/**
 * Stack-allocated middleware executor (zero allocations)
 *
 * This struct eliminates heap allocations while preserving the (ctx, next) API.
 * It uses a member function delegate pattern with recursive execution.
 *
 * Technical details:
 * - The struct is stack-allocated for each request (fiber stack)
 * - &this.next is a member function delegate - NO heap allocation!
 * - Middleware can call next() to execute the rest of the chain synchronously
 * - When next() is called, it executes remaining middleware + handler, then returns
 */
private struct MiddlewareExecutor
{
    private Context* ctx;              // Pointer to context (ref cannot be field)
    private Middleware[] middlewares;     // Middleware chain
    private Handler finalHandler;         // Final handler after middleware
    private uint currentIndex;            // Current middleware index

    /**
     * next() function passed to middleware
     * Executes the rest of the chain synchronously, then returns
     */
    void next() @trusted
    {
        // Move to next middleware
        currentIndex++;

        // Execute rest of chain
        continueExecution();
    }

    /**
     * Continue execution from current index
     * This is the actual execution logic
     */
    private void continueExecution() @trusted
    {
        // If we have more middleware, execute next one
        if (currentIndex < middlewares.length)
        {
            // Call middleware with &this.next (member delegate, stack-only)
            // The middleware can call next() which will recursively call continueExecution()
            middlewares[currentIndex](*ctx, &this.next);
        }
        // If no more middleware and we have a handler, execute it
        else if (finalHandler !is null)
        {
            finalHandler(*ctx);
        }
    }

    /**
     * Execute middleware chain
     * This is the hot path - optimized for zero allocations
     */
    void execute() @trusted
    {
        currentIndex = 0;
        continueExecution();
    }
}

/**
 * MiddlewarePipeline - Chain of Responsibility middleware execution
 *
 * Executes middleware in order, with each middleware calling next()
 * to continue the chain. If next() is not called, the chain stops.
 *
 * Uses stack-allocated executor for zero-allocation execution
 */
class MiddlewarePipeline
{
    private Middleware[] middlewares;

    /**
     * Add middleware to the pipeline
     */
    void use(Middleware mw)
    {
        middlewares ~= mw;
    }

    /**
     * Execute the pipeline with a final handler
     *
     * Stack-allocates executor (no heap allocations)
     *
     * Params:
     *   ctx = Request context (passed by ref so middleware can modify it)
     *   finalHandler = Handler to call after all middleware
     */
    void execute(ref Context ctx, Handler finalHandler)
    {
        // Stack-allocated executor (fiber stack, zero heap)
        // Pass address of ctx
        auto executor = MiddlewareExecutor(&ctx, middlewares, finalHandler, 0);
        executor.execute();
    }

    /**
     * Get middleware count
     */
    @property size_t length() const
    {
        return middlewares.length;
    }

    /**
     * Clear all middleware
     */
    void clear()
    {
        middlewares = [];
    }
}

public import aurora.web.middleware.bulkhead;
public import aurora.web.middleware.circuitbreaker;
public import aurora.web.middleware.compression;
public import aurora.web.middleware.cors;
public import aurora.web.middleware.health;
public import aurora.web.middleware.loadshed;
public import aurora.web.middleware.logger;
public import aurora.web.middleware.memory;
public import aurora.web.middleware.ratelimit;
public import aurora.web.middleware.requestid;
public import aurora.web.middleware.security;
public import aurora.web.middleware.validation;

