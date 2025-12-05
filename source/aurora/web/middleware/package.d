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
 * MiddlewarePipeline - Chain of Responsibility middleware execution
 *
 * Executes middleware in order, with each middleware calling next()
 * to continue the chain. If next() is not called, the chain stops.
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
     * Params:
     *   ctx = Request context (passed by ref so middleware can modify it)
     *   finalHandler = Handler to call after all middleware
     */
    void execute(ref Context ctx, Handler finalHandler)
    {
        executeChain(ctx, 0, finalHandler);
    }
    
    private void executeChain(ref Context ctx, uint index, Handler finalHandler)
    {
        if (index >= middlewares.length)
        {
            // Reached end of chain, execute final handler
            if (finalHandler !is null)
            {
                finalHandler(ctx);
            }
            return;
        }
        
        // Get current middleware
        auto currentMiddleware = middlewares[index];
        
        // Define next() function that continues the chain
        void next()
        {
            executeChain(ctx, index + 1, finalHandler);
        }
        
        // Call middleware with next()
        currentMiddleware(ctx, &next);
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
public import aurora.web.middleware.cors;
public import aurora.web.middleware.health;
public import aurora.web.middleware.loadshed;
public import aurora.web.middleware.logger;
public import aurora.web.middleware.ratelimit;
public import aurora.web.middleware.requestid;
public import aurora.web.middleware.security;
public import aurora.web.middleware.validation;
