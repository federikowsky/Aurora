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

// Test 9: Allocate more than arena size uses fallback
@("allocate more than arena size uses fallback allocation")
unittest
{
    auto arena = new Arena(1024);

    // Request more than arena capacity
    auto buffer = arena.allocate(2000);

    // Should succeed via fallback malloc (BUG #7 fix)
    buffer.shouldNotBeNull;
    buffer.length.shouldEqual(2000);

    // Verify we can write to it
    buffer[0] = 42;
    buffer[1999] = 99;
    buffer[0].shouldEqual(42);
    buffer[1999].shouldEqual(99);

    // Cleanup should handle fallback allocations
    arena.reset();
}

// Test 10: Allocate 0 bytes
@("allocate 0 bytes returns empty buffer")
unittest
{
    auto arena = new Arena(4096);
    
    auto buffer = arena.allocate(0);
    
    buffer.length.shouldEqual(0);
}

// Test 11: Arena exhaustion uses fallback
@("arena exhaustion uses fallback gracefully")
unittest
{
    auto arena = new Arena(1000);
    
    auto buf1 = arena.allocate(600);
    auto buf2 = arena.allocate(300);
    
    buf1.shouldNotBeNull;
    buf2.shouldNotBeNull;
    
    // Arena space is exhausted (with alignment)
    // Allocation should succeed via fallback malloc
    auto buf3 = arena.allocate(200);
    buf3.shouldNotBeNull;  // Fallback allocation works
    buf3.length.shouldEqual(200);
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

// Test 18: Multiple fallback allocations and cleanup
@("multiple fallback allocations with cleanup")
unittest
{
    auto arena = new Arena(512);  // Small arena to trigger fallbacks

    // First allocation uses arena
    auto buf1 = arena.allocate(256);
    buf1.shouldNotBeNull;
    buf1.length.shouldEqual(256);

    // Second allocation uses arena
    auto buf2 = arena.allocate(200);
    buf2.shouldNotBeNull;
    buf2.length.shouldEqual(200);

    // Third allocation exceeds arena, uses fallback (BUG #7 fix)
    auto buf3 = arena.allocate(1000);
    buf3.shouldNotBeNull;
    buf3.length.shouldEqual(1000);

    // Fourth large allocation also uses fallback
    auto buf4 = arena.allocate(2000);
    buf4.shouldNotBeNull;
    buf4.length.shouldEqual(2000);

    // Verify all buffers are writable
    buf1[0] = 1;
    buf2[0] = 2;
    buf3[0] = 3;
    buf4[0] = 4;

    buf1[0].shouldEqual(1);
    buf2[0].shouldEqual(2);
    buf3[0].shouldEqual(3);
    buf4[0].shouldEqual(4);

    // Reset should cleanup both arena and fallback allocations
    arena.reset();

    // After reset, arena should be available again
    auto buf5 = arena.allocate(256);
    buf5.shouldNotBeNull;

    // Cleanup on destroy
    destroy(arena);
}
