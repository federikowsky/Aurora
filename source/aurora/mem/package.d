/**
 * Aurora Memory Management
 * 
 * Provides high-performance, @nogc memory management primitives:
 * 
 * $(UL
 *   $(LI $(LREF BufferPool) - Thread-local buffer pool with size buckets)
 *   $(LI $(LREF ObjectPool) - Generic object pool with pre-allocation)
 *   $(LI $(LREF Arena) - Bump allocator with bulk deallocation)
 * )
 * 
 * Design Principles:
 * - Zero GC allocations in hot path
 * - O(1) acquire/release operations
 * - Thread-local pools (no contention)
 * - Cache-line aligned allocations (64 bytes)
 * 
 * Performance Targets:
 * - BufferPool acquire: < 100ns
 * - BufferPool release: < 50ns
 * - Arena allocate: < 50ns
 * - Arena reset: < 100ns
 */
module aurora.mem;

public import aurora.mem.pool;
public import aurora.mem.object_pool;
public import aurora.mem.arena;
public import aurora.mem.pressure;
