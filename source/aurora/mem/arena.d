/**
 * Arena Allocator - Bump allocator with bulk deallocation
 * 
 * Features:
 * - O(1) allocation (bump pointer)
 * - Bulk deallocation via reset()
 * - Alignment support
 * - No per-allocation overhead
 * - Perfect for request-scoped allocations
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
 * Arena allocator - bump allocator with reset
 */
class Arena
{
    private ubyte[] memory;      // Arena backing memory
    private size_t offset;        // Current allocation offset
    private enum DEFAULT_ALIGNMENT = 8;
    
    /**
     * Create arena with specified size
     */
    this(size_t size)
    {
        // Allocate arena backing memory
        memory = allocateMemory(size);
        offset = 0;
    }
    
    /**
     * Allocate buffer from arena (8-byte aligned)
     * 
     * Returns: Buffer of requested size, or null if insufficient space
     */
    ubyte[] allocate(size_t size)
    {
        return allocateAligned(size, DEFAULT_ALIGNMENT);
    }
    
    /**
     * Allocate buffer with custom alignment
     * 
     * Returns: Aligned buffer, or null if insufficient space
     */
    ubyte[] allocateAligned(size_t size, size_t alignment)
    {
        if (size == 0)
            return [];
        
        // Align offset to requested alignment
        size_t alignedOffset = alignUp(offset, alignment);
        
        // Check if we have enough space
        if (alignedOffset + size > memory.length)
            return null;  // Out of space
        
        // Allocate from arena
        ubyte[] buffer = memory[alignedOffset .. alignedOffset + size];
        
        // Bump pointer
        offset = alignedOffset + size;
        
        return buffer;
    }
    
    /**
     * Reset arena - deallocate all allocations in bulk
     * 
     * Performance: O(1) - just resets bump pointer
     */
    void reset()
    {
        offset = 0;
        // Memory remains allocated - ready for reuse
    }
    
    /**
     * Get available space in arena
     */
    size_t available() const
    {
        return memory.length - offset;
    }
    
    /**
     * Cleanup arena memory
     */
    ~this()
    {
        cleanup();
    }
    
    void cleanup()
    {
        // Free arena backing memory
        if (memory.ptr !is null)
        {
            free(memory.ptr);
            memory = null;
        }
    }
    
    // Private helpers
    
    private ubyte[] allocateMemory(size_t size)
    {
        version(Posix)
        {
            // Allocate cache-line aligned memory
            void* ptr;
            int result = posix_memalign(&ptr, 64, size);
            
            if (result != 0 || ptr is null)
                return null;
            
            // Zero the memory
            memset(ptr, 0, size);
            
            return (cast(ubyte*)ptr)[0..size];
        }
        else
        {
            // Windows: use malloc
            void* ptr = malloc(size);
            
            if (ptr is null)
                return null;
            
            memset(ptr, 0, size);
            return (cast(ubyte*)ptr)[0..size];
        }
    }
    
    private size_t alignUp(size_t value, size_t alignment)
    {
        return (value + alignment - 1) / alignment * alignment;
    }
}
