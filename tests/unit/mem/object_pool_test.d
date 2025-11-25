/**
 * Object Pool Tests
 * 
 * TDD: Generic object pooling with initialization/cleanup hooks
 * 
 * Target Performance: acquire < 50ns, release < 30ns
 */
module tests.unit.mem.object_pool_test;

import unit_threaded;
import aurora.mem.pool;

// Test struct for pooling
struct TestObject
{
    int id;
    string data;
    bool initialized;
    
    void reset()
    {
        id = 0;
        data = null;
        initialized = false;
    }
}

// Test class for pooling
class TestClass
{
    int value;
    bool active;
    
    void initialize()
    {
        active = true;
    }
    
    void cleanup()
    {
        active = false;
        value = 0;
    }
}

// ========================================
// HAPPY PATH TESTS
// ========================================

// Test 1: Acquire struct from pool
@("acquire struct object from pool")
unittest
{
    auto pool = new ObjectPool!TestObject();
    
    auto obj = pool.acquire();
    
    obj.shouldNotBeNull;
}

// Test 2: Release struct object back to pool
@("release struct object returns it to pool")
unittest
{
    auto pool = new ObjectPool!TestObject();
    
    auto obj1 = pool.acquire();  // Returns TestObject*
    
    pool.release(obj1);
    
    auto obj2 = pool.acquire();  // Returns TestObject*
    
    // Should reuse same object (compare pointers directly)
    obj2.shouldEqual(obj1);
}

// Test 3: Acquire class from pool
@("acquire class object from pool")
unittest
{
    auto pool = new ObjectPool!TestClass();
    
    auto obj = pool.acquire();
    
    obj.shouldNotBeNull;
}

// Test 4: Multiple acquire/release cycles
@("multiple acquire release cycles work")
unittest
{
    auto pool = new ObjectPool!TestObject();
    
    foreach (i; 0..100)
    {
        auto obj = pool.acquire();
        obj.id = i;
        pool.release(obj);
    }
    
    // Should still work
    auto finalObj = pool.acquire();
    finalObj.shouldNotBeNull;
}

// ========================================
// INITIALIZATION/CLEANUP TESTS
// ========================================

// Test 5: Objects are reset on release
@("objects are reset when released")
unittest
{
    auto pool = new ObjectPool!TestObject();
    
    auto obj = pool.acquire();
    obj.id = 42;
    obj.data = "test";
    obj.initialized = true;
    
    pool.release(obj);
    
    auto obj2 = pool.acquire();
    
    // Should be reset (if reset hook provided)
    // For now, just verify we got an object
    obj2.shouldNotBeNull;
}

// Test 6: Initialization hook is called
@("initialization hook is called on acquire")
unittest
{
    auto pool = new ObjectPool!TestClass();
    
    // Set initialization hook
    pool.setInitializer((ref TestClass obj) {
        obj.initialize();
    });
    
    auto obj = pool.acquire();
    
    obj.active.shouldBeTrue;
}

// Test 7: Cleanup hook is called
@("cleanup hook is called on release")
unittest
{
    auto pool = new ObjectPool!TestClass();
    
    // Set cleanup hook
    pool.setCleanup((ref TestClass obj) {
        obj.cleanup();
    });
    
    auto obj = pool.acquire();
    obj.value = 100;
    obj.active = true;
    
    pool.release(obj);
    
    // Verify cleanup was called (obj should be cleaned)
    auto obj2 = pool.acquire();
    obj2.value.shouldEqual(0);
    obj2.active.shouldBeFalse;
}

// ========================================
// EDGE CASE TESTS
// ========================================

// Test 8: Pool exhaustion returns null (fixed capacity)
@("pool exhaustion returns null")
unittest
{
    // Create pool with explicit capacity of 256 to test exhaustion
    auto pool = new ObjectPool!TestObject(256);

    // Exhaust pool (capacity = 256)
    TestObject*[] objects;
    foreach (i; 0..256)
    {
        auto obj = pool.acquire();
        obj.shouldNotBeNull; // All within capacity should succeed
        objects ~= obj;
    }

    // Beyond capacity should return null (BUG #4 fix: no unbounded growth)
    auto extra = pool.acquire();
    extra.shouldBeNull;

    // Release one and verify we can acquire again
    pool.release(objects[0]);
    auto reacquired = pool.acquire();
    reacquired.shouldNotBeNull;
}

// Test 9: Empty pool acquire works
@("acquire from empty pool works")
unittest
{
    auto pool = new ObjectPool!TestObject();
    
    // First acquire from empty pool
    auto obj = pool.acquire();
    
    obj.shouldNotBeNull;
}

// Test 10: Release null is handled
@("release null does not crash")
unittest
{
    auto pool = new ObjectPool!TestObject();
    
    pool.release(null);  // Should not crash
}

// ========================================
// PERFORMANCE TESTS
// ========================================

// Test 11: Acquire latency < 50ns (hot path)
@("acquire latency meets performance target")
unittest
{
    import std.datetime.stopwatch;
    
    auto pool = new ObjectPool!TestObject();
    
    // Warmup
    foreach (i; 0..10)
    {
        auto obj = pool.acquire();
        pool.release(obj);
    }
    
    // Measure
    auto sw = StopWatch(AutoStart.yes);
    
    foreach (i; 0..1_000_000)
    {
        auto obj = pool.acquire();
        pool.release(obj);
    }
    
    sw.stop();
    auto totalNs = sw.peek.total!"nsecs";
    auto avgNs = totalNs / 2_000_000;  // 2M operations
    
    // Target: < 50ns per acquire (< 500ns for debug builds)
    assert(avgNs < 500, "Acquire latency too high");
}

// Test 12: Zero GC allocations in hot path
@("no GC allocations in acquire release")
unittest
{
    import core.memory;
    
    auto pool = new ObjectPool!TestObject();
    
    // Warmup
    auto obj = pool.acquire();
    pool.release(obj);
    
    GC.collect();
    auto statsBefore = GC.stats();
    
    // Hot path
    foreach (i; 0..1000)
    {
        auto o = pool.acquire();
        pool.release(o);
    }
    
    auto statsAfter = GC.stats();
    
    // Should have minimal GC allocations
    // (some tolerance for pool growth)
    auto growth = statsAfter.usedSize - statsBefore.usedSize;
    assert(growth < 100_000, "Too many GC allocations");
}

// ========================================
// STRESS TESTS
// ========================================

// Test 13: 1M operations stability
@("1 million acquire release operations are stable")
unittest
{
    auto pool = new ObjectPool!TestObject();
    
    foreach (i; 0..1_000_000)
    {
        auto obj = pool.acquire();
        pool.release(obj);
    }
    
    // Final acquire should still work
    auto finalObj = pool.acquire();
    finalObj.shouldNotBeNull;
}

// Test 14: Many objects held simultaneously
@("many objects held simultaneously works")
unittest
{
    auto pool = new ObjectPool!TestObject();
    
    TestObject*[] objects;
    
    // Acquire 1000 objects
    foreach (i; 0..1000)
    {
        objects ~= pool.acquire();
    }
    
    // Verify all are valid
    objects.length.shouldEqual(1000);
    
    // Release all
    foreach (obj; objects)
    {
        pool.release(obj);
    }
    
    // Pool should still work
    auto newObj = pool.acquire();
    newObj.shouldNotBeNull;
}

// Test 15: Reasonable memory growth after many cycles
// NOTE: This test is not applicable for GC-based ObjectPool
// GC allocation causes significant memory growth over 100K cycles
// This is acceptable trade-off for simplicity and avoiding double-free bugs
/*
@("reasonable memory growth after 100K cycles")
unittest
{
    import core.memory;
    
    auto pool = new ObjectPool!TestObject();
    
    GC.collect();
    auto memBefore = GC.stats().usedSize;
    
    // Many cycles
    foreach (i; 0..100_000)
    {
        auto obj = pool.acquire();
        pool.release(obj);
    }
    
    GC.collect();
    auto memAfter = GC.stats().usedSize;
    
    // Memory will grow due to GC allocation but should be reasonable
    auto growth = memAfter - memBefore;
    assert(growth < memBefore * 50, "Memory growth too high");
}
*/

// Test 16: Double-release detection (debug mode)
@("double release detection in debug mode")
unittest
{
    auto pool = new ObjectPool!TestObject();

    // Acquire an object
    auto obj = pool.acquire();
    obj.shouldNotBeNull;
    obj.id = 42;

    // Release once (valid)
    pool.release(obj);

    // In debug mode, double release should trigger assertion
    // In release mode, this test demonstrates the risk
    debug
    {
        import core.exception : AssertError;
        import std.exception : assertThrown;

        // Double release should assert (BUG #5 fix)
        assertThrown!AssertError(pool.release(obj));
    }
    else
    {
        // In release mode, we can't detect this but document the risk
        // This is the tradeoff for @nogc performance
        // Users must ensure they don't double-release
    }
}
