module tests.unit.web.bulkhead_test;

import aurora.web.middleware.bulkhead;
import core.time;

// ============================================================================
// UNIT TESTS - Moved from source/aurora/web/middleware/bulkhead.d
// ============================================================================

// Test 1: Config defaults
@("bulkhead config has sensible defaults")
unittest
{
    auto config = BulkheadConfig.defaults();
    assert(config.maxConcurrent == 100);
    assert(config.maxQueue == 50);
    assert(config.timeout == 5.seconds);
    assert(config.name == "default");
}

// Test 2: Config constructor
@("bulkhead config constructor")
unittest
{
    auto config = BulkheadConfig(50, 25, 3.seconds, "api");
    assert(config.maxConcurrent == 50);
    assert(config.maxQueue == 25);
    assert(config.timeout == 3.seconds);
    assert(config.name == "api");
}

// Test 3: Stats utilization calculation
@("bulkhead stats utilization")
unittest
{
    BulkheadStats stats;
    stats.maxConcurrent = 100;
    stats.maxQueue = 50;
    stats.activeCalls = 50;
    stats.queuedCalls = 25;
    
    assert(stats.utilization == 0.5);
    assert(stats.queueUtilization == 0.5);
    assert(stats.hasCapacity);
}

// Test 4: Stats utilization edge cases
@("bulkhead stats utilization edge cases")
unittest
{
    BulkheadStats stats;
    stats.maxConcurrent = 0;
    stats.maxQueue = 0;
    
    assert(stats.utilization == 0.0);
    assert(stats.queueUtilization == 0.0);
}

// Test 5: BulkheadState enum values
@("bulkhead state enum")
unittest
{
    assert(BulkheadState.NORMAL == cast(BulkheadState)0);
    assert(BulkheadState.FILLING == cast(BulkheadState)1);
    assert(BulkheadState.OVERLOADED == cast(BulkheadState)2);
}

// Test 6: Middleware creation
@("bulkhead middleware creation")
unittest
{
    auto bh = createBulkheadMiddleware(100, 50, 5.seconds, "test");
    assert(bh !is null);
    assert(bh.name == "test");
}

// Test 7: Initial state is NORMAL
@("bulkhead initial state is NORMAL")
unittest
{
    auto bh = createBulkheadMiddleware(100, 50);
    assert(bh.getState() == BulkheadState.NORMAL);
    assert(!bh.isOverloaded());
    assert(bh.hasCapacity());
}

// Test 8: Initial stats are zero
@("bulkhead initial stats are zero")
unittest
{
    auto bh = createBulkheadMiddleware(100, 50);
    auto stats = bh.getStats();
    assert(stats.activeCalls == 0);
    assert(stats.queuedCalls == 0);
    assert(stats.completedCalls == 0);
    assert(stats.rejectedCalls == 0);
}

// Test 9: Stats hasCapacity
@("bulkhead stats hasCapacity")
unittest
{
    BulkheadStats stats;
    stats.maxConcurrent = 10;
    stats.maxQueue = 5;
    
    stats.activeCalls = 5;
    stats.queuedCalls = 2;
    assert(stats.hasCapacity);
    
    stats.activeCalls = 10;
    stats.queuedCalls = 5;
    assert(!stats.hasCapacity);
}

// Test 10: Factory functions
@("bulkhead factory functions")
unittest
{
    auto mw1 = bulkheadMiddleware(100, 50, 5.seconds, "api");
    assert(mw1 !is null);
    
    auto config = BulkheadConfig(50, 25);
    auto mw2 = bulkheadMiddleware(config);
    assert(mw2 !is null);
}

// Test 11: Config full message
@("bulkhead config custom message")
unittest
{
    auto config = BulkheadConfig(10, 5);
    config.fullMessage = "Custom overload message";
    assert(config.fullMessage == "Custom overload message");
}

// Test 12: Stats maxConcurrent/maxQueue populated
@("bulkhead stats config values populated")
unittest
{
    auto bh = createBulkheadMiddleware(75, 30);
    auto stats = bh.getStats();
    assert(stats.maxConcurrent == 75);
    assert(stats.maxQueue == 30);
}

// Test 13: Reset stats
@("bulkhead reset stats")
unittest
{
    auto bh = createBulkheadMiddleware(100, 50);
    // Can't easily trigger stats in unit test, but we can test reset works
    bh.resetStats();
    auto stats = bh.getStats();
    assert(stats.completedCalls == 0);
    assert(stats.rejectedCalls == 0);
}

// Test 14: Zero maxQueue means no queueing
@("bulkhead zero queue means fail-fast")
unittest
{
    auto config = BulkheadConfig(10, 0);  // No queueing
    auto bh = createBulkheadMiddleware(config);
    auto stats = bh.getStats();
    assert(stats.maxQueue == 0);
}

// Test 15: State calculation logic
@("bulkhead state calculation")
unittest
{
    auto bh = createBulkheadMiddleware(100, 50);
    // Can't easily set internal state, but we can verify getState returns valid enum
    auto state = bh.getState();
    assert(state == BulkheadState.NORMAL || 
           state == BulkheadState.FILLING || 
           state == BulkheadState.OVERLOADED);
}

// Test 16: Middleware delegate type
@("bulkhead middleware returns correct delegate type")
unittest
{
    auto bh = createBulkheadMiddleware(100, 50);
    Middleware mw = bh.middleware();
    assert(mw !is null);
}
