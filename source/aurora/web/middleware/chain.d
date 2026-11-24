/** The same synchronous continuation contract for application and endpoint policy. */
module aurora.web.middleware.chain;

import aurora.web.context : Context;
import aurora.web.router : Handler;

alias NextFunction = void delegate();
alias Middleware = void delegate(ref Context ctx, scope NextFunction next);

/// Bind endpoint policies in outer-to-inner order at registration time.
/// The caller's array is copied; middleware instances keep their normal identity.
Handler withMiddleware(Handler endpoint, Middleware[] policy...)
{
    if (endpoint is null) throw new Exception("Middleware requires a non-null endpoint");
    return bindPolicy(endpoint, snapshotPolicy(policy));
}

package(aurora) Middleware[] snapshotPolicy(Middleware[] policy)
{
    foreach (mw; policy) requireMiddleware(mw);
    return policy.length ? policy.dup : null;
}

private void requireMiddleware(Middleware mw)
{
    if (mw is null) throw new Exception("Middleware cannot be null");
}

package(aurora) Handler bindPolicy(Handler endpoint, Middleware[] policy)
{
    // Keep bare routes (including their delegate identity) untouched.
    return policy.length ? boundHandler(endpoint, policy) : endpoint;
}

private Handler boundHandler(Handler endpoint, Middleware[] policy)
{
    return (ref Context ctx) { runChain(ctx, policy, endpoint); };
}

private void runChain(ref Context ctx, Middleware[] remaining, Handler endpoint)
{
    if (!remaining.length)
    {
        if (endpoint !is null) endpoint(ctx);
        return;
    }

    bool advanced;
    void next()
    {
        if (advanced) throw new Exception("Middleware next() called more than once");
        advanced = true;
        runChain(ctx, remaining[1 .. $], endpoint);
    }
    remaining[0](ctx, &next);
}

/// Mutable during configuration only, before serving. The terminal is selected per request.
class MiddlewarePipeline
{
    private Middleware[] middlewares;

    void use(Middleware mw)
    {
        requireMiddleware(mw);
        middlewares ~= mw;
    }

    void execute(ref Context ctx, Handler finalHandler)
    {
        runChain(ctx, middlewares, finalHandler);
    }

    @property size_t length() const { return middlewares.length; }
    void clear() { middlewares = null; }
}
