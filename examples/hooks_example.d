/**
 * Aurora V0.4 - Hooks & Exception Handlers Example
 * 
 * Demonstrates the new extensibility features:
 * - Server lifecycle hooks (onStart, onStop, onError, onRequest, onResponse)
 * - Typed exception handlers (FastAPI-style)
 * 
 * Build:
 *   dub run --config=hooks-example
 * 
 * Or manually:
 *   ldc2 -O2 -I../source hooks_example.d $(find ../source -name '*.d') -of=hooks_example
 * 
 * Test:
 *   curl http://localhost:8080/
 *   curl http://localhost:8080/validate?email=invalid
 *   curl http://localhost:8080/admin
 *   curl http://localhost:8080/crash
 */
module examples.hooks_example;

import aurora;
import std.stdio : writeln, writefln;
import std.datetime : Clock;

// ============================================================================
// CUSTOM EXCEPTIONS
// ============================================================================

/// Base application error with status code
class AppError : Exception
{
    int statusCode;
    
    this(string msg, int code = 500)
    {
        super(msg);
        this.statusCode = code;
    }
}

/// Validation error (400 Bad Request)
class ValidationError : AppError
{
    string field;
    
    this(string msg, string field = "")
    {
        super(msg, 400);
        this.field = field;
    }
}

/// Authorization error (403 Forbidden)
class AuthorizationError : AppError
{
    this(string msg)
    {
        super(msg, 403);
    }
}

/// Not found error (404)
class NotFoundError : AppError
{
    this(string msg)
    {
        super(msg, 404);
    }
}

// ============================================================================
// MAIN
// ============================================================================

void main()
{
    auto app = new App();
    
    // ========================================================================
    // LIFECYCLE HOOKS
    // ========================================================================
    
    // Called when server starts
    app.onStart(() {
        writeln("🚀 Server starting at ", Clock.currTime());
        writeln("   Initializing database connections...");
        writeln("   Loading configuration...");
        writeln("   Ready to accept requests!");
        writeln();
    });
    
    // Called when server stops
    app.onStop(() {
        writeln();
        writeln("🛑 Server stopping at ", Clock.currTime());
        writeln("   Closing database connections...");
        writeln("   Cleanup complete!");
    });
    
    // Called on every error (for logging/metrics)
    app.onError((Exception e, ref Context ctx) {
        writefln("❌ Error: %s [%s %s]", e.msg, ctx.request.method(), ctx.request.path());
    });
    
    // Called before routing each request
    app.onRequest((ref Context ctx) {
        // Add request ID header
        import std.uuid : randomUUID;
        ctx.response.setHeader("X-Request-ID", randomUUID().toString());
    });
    
    // Called after handler completion
    app.onResponse((ref Context ctx) {
        // Add timing header
        ctx.response.setHeader("X-Powered-By", "Aurora/0.4");
    });
    
    // ========================================================================
    // EXCEPTION HANDLERS (FastAPI-style)
    // ========================================================================
    
    // Handle ValidationError specifically
    app.addExceptionHandler!ValidationError((ref Context ctx, ValidationError e) {
        ctx.status(e.statusCode)
           .header("Content-Type", "application/json")
           .send(`{"error":"validation_error","message":"` ~ e.msg ~ `","field":"` ~ e.field ~ `"}`);
    });
    
    // Handle AuthorizationError
    app.addExceptionHandler!AuthorizationError((ref Context ctx, AuthorizationError e) {
        ctx.status(e.statusCode)
           .header("Content-Type", "application/json")
           .send(`{"error":"forbidden","message":"` ~ e.msg ~ `"}`);
    });
    
    // Handle NotFoundError
    app.addExceptionHandler!NotFoundError((ref Context ctx, NotFoundError e) {
        ctx.status(e.statusCode)
           .header("Content-Type", "application/json")
           .send(`{"error":"not_found","message":"` ~ e.msg ~ `"}`);
    });
    
    // Catch-all for any AppError (parent class)
    app.addExceptionHandler!AppError((ref Context ctx, AppError e) {
        ctx.status(e.statusCode)
           .header("Content-Type", "application/json")
           .send(`{"error":"app_error","message":"` ~ e.msg ~ `"}`);
    });
    
    // Catch-all for any Exception (last resort)
    app.addExceptionHandler!Exception((ref Context ctx, Exception e) {
        ctx.status(500)
           .header("Content-Type", "application/json")
           .send(`{"error":"internal_error","message":"An unexpected error occurred"}`);
    });
    
    // ========================================================================
    // ROUTES
    // ========================================================================
    
    // Home page
    app.get("/", (ref Context ctx) {
        ctx.send("Welcome to Aurora V0.4! Try:\n" ~
                 "  /validate?email=invalid  - triggers ValidationError\n" ~
                 "  /admin                   - triggers AuthorizationError\n" ~
                 "  /users/999               - triggers NotFoundError\n" ~
                 "  /crash                   - triggers generic Exception\n");
    });
    
    // Validation example - throws ValidationError
    app.get("/validate", (ref Context ctx) {
        string email = ctx.request.queryParam("email");
        
        if (email.length == 0 || email.indexOf("@") == -1)
        {
            throw new ValidationError("Invalid email format", "email");
        }
        
        ctx.header("Content-Type", "application/json")
           .send(`{"valid":true,"email":"` ~ email ~ `"}`);
    });
    
    // Admin page - throws AuthorizationError
    app.get("/admin", (ref Context ctx) {
        // Simulate authorization check
        throw new AuthorizationError("Admin access required");
    });
    
    // User lookup - throws NotFoundError
    app.get("/users/:id", (ref Context ctx) {
        string id = ctx.params.get("id", "");
        
        // Simulate user not found
        throw new NotFoundError("User " ~ id ~ " not found");
    });
    
    // Crash endpoint - throws generic Exception
    app.get("/crash", (ref Context ctx) {
        throw new Exception("Something went terribly wrong!");
    });
    
    // Health check (no errors)
    app.get("/health", (ref Context ctx) {
        ctx.header("Content-Type", "application/json")
           .send(`{"status":"healthy","version":"0.4"}`);
    });
    
    // ========================================================================
    // START SERVER
    // ========================================================================
    
    writeln("╔════════════════════════════════════════════╗");
    writeln("║   Aurora V0.4 - Hooks & Exception Demo     ║");
    writeln("╚════════════════════════════════════════════╝");
    writeln();
    writeln("Starting server on http://localhost:8080");
    writeln();
    
    app.listen(8080);
}

// Helper function (would normally use std.algorithm)
ptrdiff_t indexOf(string s, string needle)
{
    foreach (i; 0 .. s.length)
    {
        if (i + needle.length <= s.length && s[i .. i + needle.length] == needle)
            return i;
    }
    return -1;
}
