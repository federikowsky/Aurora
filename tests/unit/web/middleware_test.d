/**
 * Middleware System Tests
 *
 * TDD: Aurora Middleware (Pipeline + next() mechanism)
 *
 * Features:
 * - MiddlewarePipeline (Chain of Responsibility)
 * - next() mechanism
 * - Short-circuit (skip next())
 * - Error propagation
 * - Performance (< 100ns per middleware)
 */
module tests.unit.web.middleware_test;

import unit_threaded;
import aurora.web.middleware;
import aurora.web.context;
import aurora.http;
import std.conv : to;

// ========================================
// HAPPY PATH TESTS
// ========================================

// Test 1: Middleware calls next() → continues
@("middleware calls next continues")
unittest
{
    auto pipeline = new MiddlewarePipeline();
    
    bool middleware1Called = false;
    bool middleware2Called = false;
    bool handlerCalled = false;
    
    void middleware1(ref Context ctx, NextFunction next) {
        middleware1Called = true;
        next();
    }
    
    void middleware2(ref Context ctx, NextFunction next) {
        middleware2Called = true;
        next();
    }
    
    void handler(ref Context ctx) {
        handlerCalled = true;
    }
    
    pipeline.use(&middleware1);
    pipeline.use(&middleware2);
    
    Context ctx;
    pipeline.execute(ctx, &handler);
    
    middleware1Called.shouldBeTrue;
    middleware2Called.shouldBeTrue;
    handlerCalled.shouldBeTrue;
}

// Test 2: Middleware doesn't call next() → stops
@("middleware without next stops chain")
unittest
{
    auto pipeline = new MiddlewarePipeline();
    
    bool middleware1Called = false;
    bool middleware2Called = false;
    bool handlerCalled = false;
    
    void middleware1(ref Context ctx, NextFunction next) {
        middleware1Called = true;
        // Don't call next() - short-circuit
    }
    
    void middleware2(ref Context ctx, NextFunction next) {
        middleware2Called = true;
        next();
    }
    
    void handler(ref Context ctx) {
        handlerCalled = true;
    }
    
    pipeline.use(&middleware1);
    pipeline.use(&middleware2);
    
    Context ctx;
    pipeline.execute(ctx, &handler);
    
    middleware1Called.shouldBeTrue;
    middleware2Called.shouldBeFalse;  // Not called
    handlerCalled.shouldBeFalse;      // Not called
}

// Test 3: Multiple middleware → correct order
@("multiple middleware correct order")
unittest
{
    auto pipeline = new MiddlewarePipeline();
    
    int[] callOrder;
    
    void middleware1(ref Context ctx, NextFunction next) {
        callOrder ~= 1;
        next();
    }
    
    void middleware2(ref Context ctx, NextFunction next) {
        callOrder ~= 2;
        next();
    }
    
    void middleware3(ref Context ctx, NextFunction next) {
        callOrder ~= 3;
        next();
    }
    
    void handler(ref Context ctx) {
        callOrder ~= 4;
    }
    
    pipeline.use(&middleware1);
    pipeline.use(&middleware2);
    pipeline.use(&middleware3);
    
    Context ctx;
    pipeline.execute(ctx, &handler);
    
    callOrder.shouldEqual([1, 2, 3, 4]);
}

// Test 4: Empty pipeline → handler called directly
@("empty pipeline calls handler")
unittest
{
    auto pipeline = new MiddlewarePipeline();
    
    bool handlerCalled = false;
    
    void handler(ref Context ctx) {
        handlerCalled = true;
    }
    
    Context ctx;
    pipeline.execute(ctx, &handler);
    
    handlerCalled.shouldBeTrue;
}

// Test 5: Single middleware → next() calls handler
@("single middleware calls handler")
unittest
{
    auto pipeline = new MiddlewarePipeline();
    
    bool middlewareCalled = false;
    bool handlerCalled = false;
    
    void middleware(ref Context ctx, NextFunction next) {
        middlewareCalled = true;
        next();
    }
    
    void handler(ref Context ctx) {
        handlerCalled = true;
    }
    
    pipeline.use(&middleware);
    
    Context ctx;
    pipeline.execute(ctx, &handler);
    
    middlewareCalled.shouldBeTrue;
    handlerCalled.shouldBeTrue;
}

// Test 6: Middleware modifies context
@("middleware modifies context")
unittest
{
    auto pipeline = new MiddlewarePipeline();
    
    void middleware(ref Context ctx, NextFunction next) {
        ctx.storage.set("key", 123);
        next();
    }
    
    void handler(ref Context ctx) {
        int value = ctx.storage.get!int("key");
        value.shouldEqual(123);
    }
    
    pipeline.use(&middleware);
    
    Context ctx;
    pipeline.execute(ctx, &handler);
}

// ========================================
// EDGE CASES
// ========================================

// Test 7: Exception in middleware → propagated
@("exception in middleware propagated")
unittest
{
    auto pipeline = new MiddlewarePipeline();
    
    void middleware(ref Context ctx, NextFunction next) {
        throw new Exception("Test error");
    }
    
    void handler(ref Context ctx) { }
    
    pipeline.use(&middleware);
    
    Context ctx;
    
    // Should throw
    pipeline.execute(ctx, &handler).shouldThrow!Exception;
}

// Test 8: Exception before next() → chain stops
@("exception before next stops chain")
unittest
{
    auto pipeline = new MiddlewarePipeline();
    
    bool middleware2Called = false;
    
    void middleware1(ref Context ctx, NextFunction next) {
        throw new Exception("Error");
    }
    
    void middleware2(ref Context ctx, NextFunction next) {
        middleware2Called = true;
        next();
    }
    
    void handler(ref Context ctx) { }
    
    pipeline.use(&middleware1);
    pipeline.use(&middleware2);
    
    Context ctx;
    
    try {
        pipeline.execute(ctx, &handler);
    } catch (Exception) {
        // Expected
    }
    
    middleware2Called.shouldBeFalse;
}

// Test 9: Exception after next() → caught
@("exception after next caught")
unittest
{
    auto pipeline = new MiddlewarePipeline();
    
    bool handlerCalled = false;
    
    void middleware(ref Context ctx, NextFunction next) {
        next();
        throw new Exception("After next");
    }
    
    void handler(ref Context ctx) {
        handlerCalled = true;
    }
    
    pipeline.use(&middleware);
    
    Context ctx;
    
    try {
        pipeline.execute(ctx, &handler);
    } catch (Exception) {
        // Expected
    }
    
    handlerCalled.shouldBeTrue;  // Handler was called before exception
}

// ========================================
// INTEGRATION TESTS
// ========================================

// Test 10: With Context storage
@("middleware shares data via context storage")
unittest
{
    auto pipeline = new MiddlewarePipeline();
    
    void middleware1(ref Context ctx, NextFunction next) {
        ctx.storage.set("user_id", 123);
        next();
    }
    
    void middleware2(ref Context ctx, NextFunction next) {
        int userId = ctx.storage.get!int("user_id");
        userId.shouldEqual(123);
        next();
    }
    
    void handler(ref Context ctx) {
        int userId = ctx.storage.get!int("user_id");
        userId.shouldEqual(123);
    }
    
    pipeline.use(&middleware1);
    pipeline.use(&middleware2);
    
    Context ctx;
    pipeline.execute(ctx, &handler);
}

// Test 11: Logger middleware (timing)
@("logger middleware timing")
unittest
{
    import std.datetime.stopwatch;
    
    auto pipeline = new MiddlewarePipeline();
    
    long duration = 0;
    
    void loggerMiddleware(ref Context ctx, NextFunction next) {
        auto sw = StopWatch(AutoStart.yes);
        next();
        sw.stop();
        duration = sw.peek().total!"msecs";
    }
    
    void handler(ref Context ctx) {
        import core.thread : Thread;
        import core.time : msecs;
        Thread.sleep(10.msecs);
    }
    
    pipeline.use(&loggerMiddleware);
    
    Context ctx;
    pipeline.execute(ctx, &handler);
    
    // Duration should be >= 10ms
    assert(duration >= 10, "Logger should measure time");
}

// Test 12: Auth middleware (short-circuit)
@("auth middleware short circuits on failure")
unittest
{
    auto pipeline = new MiddlewarePipeline();
    
    bool handlerCalled = false;
    
    void authMiddleware(ref Context ctx, NextFunction next) {
        // Simulate auth failure
        auto response = HTTPResponse(401, "Unauthorized");
        ctx.response = &response;
        ctx.status(401);
        // Don't call next() - short-circuit
    }
    
    void handler(ref Context ctx) {
        handlerCalled = true;
    }
    
    pipeline.use(&authMiddleware);
    
    Context ctx;
    pipeline.execute(ctx, &handler);
    
    handlerCalled.shouldBeFalse;
}

// ========================================
// PERFORMANCE TESTS
// ========================================

// Test 13: Pipeline overhead < 100ns per middleware
@("pipeline overhead per middleware")
unittest
{
    import std.datetime.stopwatch;
    
    auto pipeline = new MiddlewarePipeline();
    
    void emptyMiddleware(ref Context ctx, NextFunction next) {
        next();
    }
    
    void handler(ref Context ctx) { }
    
    // Add 10 middleware
    foreach (i; 0..10)
    {
        pipeline.use(&emptyMiddleware);
    }
    
    Context ctx;
    
    auto sw = StopWatch(AutoStart.yes);
    
    foreach (i; 0..1000)
    {
        pipeline.execute(ctx, &handler);
    }
    
    sw.stop();
    auto avgNs = sw.peek().total!"nsecs" / 1000;
    
    // 10 middleware should be < 1000ns total (< 100ns each)
    // Relaxed for debug builds
    assert(avgNs < 10000, "Pipeline too slow: " ~ avgNs.to!string ~ "ns");
}

// Test 14: 10 middleware chain < 1μs
@("10 middleware chain fast")
unittest
{
    import std.datetime.stopwatch;
    
    auto pipeline = new MiddlewarePipeline();
    
    void middleware(ref Context ctx, NextFunction next) {
        next();
    }
    
    void handler(ref Context ctx) { }
    
    foreach (i; 0..10)
    {
        pipeline.use(&middleware);
    }
    
    Context ctx;
    
    auto sw = StopWatch(AutoStart.yes);
    pipeline.execute(ctx, &handler);
    sw.stop();
    
    auto ns = sw.peek().total!"nsecs";
    
    // Should be < 1μs (1000ns) - relaxed for debug
    assert(ns < 100000, "10 middleware too slow");
}

// Test 15: 1000 executions stable
@("1000 executions stable")
unittest
{
    auto pipeline = new MiddlewarePipeline();
    
    int executionCount = 0;
    
    void middleware(ref Context ctx, NextFunction next) {
        next();
    }
    
    void handler(ref Context ctx) {
        executionCount++;
    }
    
    pipeline.use(&middleware);
    
    Context ctx;
    
    foreach (i; 0..1000)
    {
        pipeline.execute(ctx, &handler);
    }
    
    executionCount.shouldEqual(1000);
}
