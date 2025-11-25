/**
 * Arena Allocator - Bump allocator with bulk deallocation
 * 
 * Features:
 * - O(1) allocation (bump pointer)
 * - Bulk deallocation via reset()
 * - Alignment support (default 8-byte, up to cache-line)
 * - No per-allocation overhead
 * - Perfect for request-scoped allocations
 * - @nogc hot path
 * 
 * Performance:
 * - Allocate: < 50ns
 * - Reset: < 100ns
 * 
 * Usage:
 * ---
 * auto arena = new Arena(4096);
 * auto buffer = arena.allocate(256);
 * // ... use buffer ...
 * arena.reset();  // Bulk free all allocations
 * ---
 */
module aurora.mem.arena;

import core.stdc.stdlib : malloc, free;
import core.stdc.string : memset;

version(Posix)
{
    import core.sys.posix.stdlib : posix_memalign;
}

/**
 * Arena allocator - bump allocator with reset.
 * 
 * Thread-local use only. Not thread-safe.
 */
class Arena
{
    private enum CACHE_LINE_SIZE = 64;
    private enum DEFAULT_ALIGNMENT = 8;
    private enum MAX_FALLBACK_BUFFERS = 128;
    
    private ubyte[] memory;       /// Arena backing memory
    private size_t offset;        /// Current allocation offset
    
    // Fallback allocations (when arena is full)
    private void*[MAX_FALLBACK_BUFFERS] fallbackBuffers;
    private size_t fallbackCount;
    
    /**
     * Create arena with specified size.
     * 
     * Params:
     *   size = Size of arena in bytes
     */
    this(size_t size) @trusted
    {
        memory = allocateMemory(size);
        offset = 0;
        fallbackCount = 0;
    }
    
    /**
     * Allocate buffer from arena (8-byte aligned).
     * 
     * Returns: Buffer of requested size, or null if allocation fails.
     */
    ubyte[] allocate(size_t size) @nogc @trusted nothrow
    {
        return allocateAligned(size, DEFAULT_ALIGNMENT);
    }
    
    /**
     * Allocate buffer with custom alignment.
     * 
     * Params:
     *   size = Size in bytes
     *   alignment = Alignment (must be power of 2)
     * 
     * Returns: Aligned buffer, or null if allocation fails.
     */
    ubyte[] allocateAligned(size_t size, size_t alignment) @nogc @trusted nothrow
    {
        if (size == 0)
            return null;
        
        // Align offset to requested alignment
        size_t alignedOffset = alignUp(offset, alignment);
        
        // Check if we have enough space
        if (memory.ptr !is null && alignedOffset + size <= memory.length)
        {
            // Allocate from arena
            ubyte[] buffer = memory[alignedOffset .. alignedOffset + size];
            
            // Bump pointer
            offset = alignedOffset + size;
            
            return buffer;
        }
        
        // Arena exhausted - fallback to malloc
        return allocateFallback(size, alignment);
    }
    
    /**
     * Reset arena - deallocate all allocations in bulk.
     * 
     * Performance: O(1) for arena memory, O(n) for fallback buffers.
     */
    void reset() @nogc @trusted nothrow
    {
        // Reset bump pointer
        offset = 0;
        
        // Free fallback allocations
        for (size_t i = 0; i < fallbackCount; i++)
        {
            free(fallbackBuffers[i]);
        }
        fallbackCount = 0;
        
        // Memory remains allocated - ready for reuse
    }
    
    /**
     * Get available space in arena (excluding fallback).
     */
    size_t available() const @nogc @safe nothrow pure
    {
        if (memory.ptr is null)
            return 0;
        return memory.length > offset ? memory.length - offset : 0;
    }
    
    /**
     * Get total arena size.
     */
    size_t capacity() const @nogc @safe nothrow pure
    {
        return memory.length;
    }
    
    /**
     * Get current used bytes in arena (excluding fallback).
     */
    size_t used() const @nogc @safe nothrow pure
    {
        return offset;
    }
    
    /**
     * Cleanup arena memory.
     */
    void cleanup() @nogc @trusted nothrow
    {
        // Free arena backing memory
        if (memory.ptr !is null)
        {
            free(memory.ptr);
            memory = null;
        }
        offset = 0;
        
        // Free fallback allocations
        for (size_t i = 0; i < fallbackCount; i++)
        {
            free(fallbackBuffers[i]);
        }
        fallbackCount = 0;
    }
    
    ~this()
    {
        cleanup();
    }
    
    // ========================================
    // Private helpers
    // ========================================
    
    private ubyte[] allocateMemory(size_t size) @nogc @trusted nothrow
    {
        if (size == 0)
            return null;
        
        version(Posix)
        {
            // Allocate cache-line aligned memory
            void* ptr;
            int result = posix_memalign(&ptr, CACHE_LINE_SIZE, size);
            
            if (result != 0 || ptr is null)
                return null;
            
            // Zero the memory
            memset(ptr, 0, size);
            
            return (cast(ubyte*)ptr)[0 .. size];
        }
        else
        {
            // Windows: use malloc
            void* ptr = malloc(size);
            
            if (ptr is null)
                return null;
            
            memset(ptr, 0, size);
            return (cast(ubyte*)ptr)[0 .. size];
        }
    }
    
    /**
     * Fallback allocation when arena is full.
     */
    private ubyte[] allocateFallback(size_t size, size_t alignment) @nogc @trusted nothrow
    {
        if (fallbackCount >= MAX_FALLBACK_BUFFERS)
        {
            // No more space for tracking fallback allocations
            return null;
        }
        
        void* ptr;
        
        version(Posix)
        {
            // Allocate aligned memory (minimum cache-line alignment)
            size_t actualAlignment = alignment < CACHE_LINE_SIZE ? CACHE_LINE_SIZE : alignment;
            int result = posix_memalign(&ptr, actualAlignment, size);
            
            if (result != 0 || ptr is null)
                return null;
            
            memset(ptr, 0, size);
        }
        else
        {
            // Windows: use malloc (not aligned)
            ptr = malloc(size);
            
            if (ptr is null)
                return null;
            
            memset(ptr, 0, size);
        }
        
        // Track for cleanup
        fallbackBuffers[fallbackCount] = ptr;
        fallbackCount++;
        
        return (cast(ubyte*)ptr)[0 .. size];
    }
    
    /**
     * Align value up to alignment boundary.
     */
    private static size_t alignUp(size_t value, size_t alignment) @nogc @safe nothrow pure
    {
        return (value + alignment - 1) & ~(alignment - 1);
    }
}
