/**
 * Arena Allocator Tests
 * 
 * TDD: Bump allocator with reset capability
 * 
 * Target: Fast O(1) allocation, bulk deallocation via reset
 */
module tests.unit.mem.arena_test;

import unit_threaded;
import aurora.mem.pool;

// ========================================
// HAPPY PATH TESTS
// ========================================

// Test 1: Create arena with size
@("create arena with specified size")
unittest
{
    auto arena = new Arena(4096);  // 4 KB arena
    
    arena.shouldNotBeNull;
}

// Test 2: Allocate from arena
@("allocate buffer from arena")
unittest
{
    auto arena = new Arena(4096);
    
    auto buffer = arena.allocate(256);
    
    buffer.shouldNotBeNull;
    buffer.length.shouldEqual(256);
}

// Test 3: Multiple allocations
@("multiple allocations work")
unittest
{
    auto arena = new Arena(4096);
    
    auto buf1 = arena.allocate(100);
    auto buf2 = arena.allocate(200);
    auto buf3 = arena.allocate(300);
    
    buf1.length.shouldEqual(100);
    buf2.length.shouldEqual(200);
    buf3.length.shouldEqual(300);
}

// Test 4: Reset arena
@("reset arena clears all allocations")
unittest
{
    auto arena = new Arena(4096);
    
    auto buf1 = arena.allocate(1000);
    auto ptr1 = buf1.ptr;
    
    arena.reset();
    
    // After reset, can allocate from start again
    auto buf2 = arena.allocate(1000);
    auto ptr2 = buf2.ptr;
    
    // Should reuse same memory (bump pointer reset)
    ptr2.shouldEqual(ptr1);
}

// Test 5: Available space tracking
@("available space is tracked correctly")
unittest
{
    auto arena = new Arena(4096);
    
    auto initialSpace = arena.available();
    initialSpace.shouldEqual(4096);
    
    arena.allocate(1000);
    
    auto remainingSpace = arena.available();
    // Should have ~3096 bytes left (may have alignment padding)
    (remainingSpace < 3200 && remainingSpace > 3000).shouldBeTrue;
}

// ========================================
// ALIGNMENT TESTS
// ========================================

// Test 6: Aligned allocation
@("allocations are aligned to 8 bytes")
unittest
{
    auto arena = new Arena(4096);
    
    auto buffer = arena.allocate(13);  // Odd size
    
    // Should be 8-byte aligned
    auto addr = cast(size_t)buffer.ptr;
    (addr % 8).shouldEqual(0);
}

// Test 7: Custom alignment
@("allocate with custom alignment")
unittest
{
    auto arena = new Arena(4096);
    
    auto buffer = arena.allocateAligned(100, 64);  // 64-byte align (cache line)
    
    auto addr = cast(size_t)buffer.ptr;
    (addr % 64).shouldEqual(0);
}

// ========================================
// EDGE CASES
// ========================================

// Test 8: Allocate exact arena size
@("allocate exact arena size works")
unittest
{
    auto arena = new Arena(1024);
    
    auto buffer = arena.allocate(1024);
    
    buffer.length.shouldEqual(1024);
    arena.available().shouldEqual(0);
}

// Test 9: Allocate more than arena size
@("allocate more than arena size returns null or throws")
unittest
{
    auto arena = new Arena(1024);
    
    auto buffer = arena.allocate(2000);
    
    // Should return null when out of space
    buffer.shouldBeNull;
}

// Test 10: Allocate 0 bytes
@("allocate 0 bytes returns empty buffer")
unittest
{
    auto arena = new Arena(4096);
    
    auto buffer = arena.allocate(0);
    
    buffer.length.shouldEqual(0);
}

// Test 11: Arena exhaustion
@("arena exhaustion is handled gracefully")
unittest
{
    auto arena = new Arena(1000);
    
    auto buf1 = arena.allocate(600);
    auto buf2 = arena.allocate(300);
    
    buf1.shouldNotBeNull;
    buf2.shouldNotBeNull;
    
    // Arena is now exhausted (with alignment)
    auto buf3 = arena.allocate(200);
    buf3.shouldBeNull;
}

// Test 12: Reset multiple times
@("reset can be called multiple times")
unittest
{
    auto arena = new Arena(4096);
    
    foreach (i; 0..10)
    {
        arena.allocate(1000);
        arena.reset();
    }
    
    // Should still work
    auto buffer = arena.allocate(1000);
    buffer.shouldNotBeNull;
}

// ========================================
// PERFORMANCE TESTS
// ========================================

// Test 13: Allocation is fast
@("allocation latency is fast")
unittest
{
    import std.datetime.stopwatch;
    
    auto arena = new Arena(1_000_000);  // 1 MB
    
    auto sw = StopWatch(AutoStart.yes);
    
    foreach (i; 0..10_000)
    {
        arena.allocate(64);
    }
    
    sw.stop();
    auto totalNs = sw.peek.total!"nsecs";
    auto avgNs = totalNs / 10_000;
    
    // Target: < 50ns per allocation (bump allocator is fast!)
    assert(avgNs < 50, "Allocation too slow");
}

// Test 14: Reset is fast
@("reset latency is fast")
unittest
{
    import std.datetime.stopwatch;
    
    auto arena = new Arena(100_000);
    
    // Fill arena
    foreach (i; 0..1000)
    {
        arena.allocate(64);
    }
    
    auto sw = StopWatch(AutoStart.yes);
    
    arena.reset();
    
    sw.stop();
    auto ns = sw.peek.total!"nsecs";
    
    // Target: < 100ns for reset (just pointer reset)
    assert(ns < 100, "Reset too slow");
}

// ========================================
// STRESS TESTS
// ========================================

// Test 15: Many allocations
@("many allocations are stable")
unittest
{
    auto arena = new Arena(10_000_000);  // 10 MB
    
    foreach (i; 0..100_000)
    {
        auto buffer = arena.allocate(64);
        buffer.shouldNotBeNull;
    }
}

// Test 16: Varying sizes
@("varying allocation sizes work")
unittest
{
    import std.random;
    
    auto arena = new Arena(1_000_000);
    auto rnd = Random(42);
    
    while (arena.available() > 100)
    {
        auto size = uniform(1, 1000, rnd);
        auto buffer = arena.allocate(size);
        
        if (buffer !is null)
        {
            buffer.length.shouldEqual(size);
        }
    }
}

// Test 17: Arena cleanup
@("arena cleanup releases memory")
unittest
{
    auto arena = new Arena(4096);
    
    arena.allocate(1000);
    arena.allocate(1000);
    
    // Destroy arena (should cleanup)
    destroy(arena);
    
    // Test passes if no crash
}
