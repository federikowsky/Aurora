/**
 * Buffer Pool - Zero-allocation buffer management
 * 
 * Features:
 * - 5 size buckets (TINY, SMALL, MEDIUM, LARGE, HUGE)
 * - Thread-local free lists (lock-free)
 * - Cache-line aligned buffers (64-byte alignment)
 * - Fallback to malloc when pool exhausted
 * - O(1) acquire/release
 * - @nogc hot path for zero GC pressure
 * 
 * Performance Targets:
 * - Acquire: < 100ns (P99)
 * - Release: < 50ns (P99)
 * - Zero GC allocations in hot path
 * 
 * Size Buckets:
 * - TINY:   1 KB  - Small responses, headers
 * - SMALL:  4 KB  - Typical HTTP requests
 * - MEDIUM: 16 KB - Large headers, medium bodies
 * - LARGE:  64 KB - File uploads, streaming
 * - HUGE:  256 KB - Very large responses/uploads
 */
module aurora.mem.pool;

import core.stdc.stdlib : malloc, free;
import core.stdc.string : memset;

version(Posix)
{
    import core.sys.posix.stdlib : posix_memalign;
}
else version(Windows)
{
    import core.sys.windows.winbase : GetLastError;
    
    // Windows aligned memory allocation
    extern(C) void* _aligned_malloc(size_t size, size_t alignment) @nogc nothrow;
    extern(C) void _aligned_free(void* ptr) @nogc nothrow;
}

// Re-export ObjectPool and Arena for convenience
public import aurora.mem.object_pool;
public import aurora.mem.arena;

/**
 * Buffer size buckets (power-of-2 for alignment)
 */
enum BufferSize : size_t
{
    TINY   = 1024,      /// 1 KB   - Small responses, headers
    SMALL  = 4096,      /// 4 KB   - Typical HTTP requests
    MEDIUM = 16384,     /// 16 KB  - Large headers, medium bodies
    LARGE  = 65536,     /// 64 KB  - File uploads, streaming
    HUGE   = 262144,    /// 256 KB - Very large responses/uploads
}

/// Number of bucket types
private enum NUM_BUCKETS = 5;

/// Bucket sizes in order (for index-based lookup)
private immutable size_t[NUM_BUCKETS] BUCKET_SIZES = [
    BufferSize.TINY,
    BufferSize.SMALL,
    BufferSize.MEDIUM,
    BufferSize.LARGE,
    BufferSize.HUGE
];

/**
 * Thread-local buffer pool for zero-contention memory management.
 * 
 * Design:
 * - Uses static arrays for free lists (no GC in hot path)
 * - Index-based bucket management for DRY code
 * - Cache-line aligned allocations (64 bytes)
 * - Tracks non-pooled buffers to prevent double-free
 */
class BufferPool
{
    private enum CACHE_LINE_SIZE = 64;
    private enum MAX_BUFFERS_PER_BUCKET = 128;
    
    // Free lists per bucket - STATIC ARRAYS (no GC growth)
    // Using a 2D array indexed by bucket index
    private ubyte[][MAX_BUFFERS_PER_BUCKET][NUM_BUCKETS] freeLists;
    private size_t[NUM_BUCKETS] freeCounts;

    // Track non-pooled buffers to prevent double-free
    private void*[256] allocatedBuffers;
    private size_t allocatedCount;
    
    /**
     * Create a new buffer pool (thread-local).
     * Initially empty - buffers allocated on demand.
     */
    this() @safe nothrow
    {
        // All arrays are zero-initialized by default
    }
    
    /**
     * Acquire a buffer of at least `size` bytes.
     * 
     * Returns: Buffer from pool or newly allocated, null on failure.
     * 
     * Performance: O(1), < 100ns target
     */
    ubyte[] acquire(size_t size) @nogc @trusted nothrow
    {
        // Find appropriate bucket index
        int bucketIdx = findBucketIndex(size);
        
        if (bucketIdx < 0)
        {
            // Non-standard size (larger than HUGE), allocate directly
            return allocateNonPooledBuffer(size);
        }
        
        size_t bucketSize = BUCKET_SIZES[bucketIdx];
        
        // Pop from free list (O(1), no GC)
        if (freeCounts[bucketIdx] > 0)
        {
            freeCounts[bucketIdx]--;
            return freeLists[bucketIdx][freeCounts[bucketIdx]];
        }
        
        // Pool empty, allocate new buffer
        return allocateBuffer(bucketSize);
    }
    
    /**
     * Acquire buffer by bucket enum.
     */
    ubyte[] acquire(BufferSize bucketSize) @nogc @trusted nothrow
    {
        return acquire(cast(size_t)bucketSize);
    }
    
    /**
     * Release buffer back to pool.
     * 
     * Performance: O(1), < 50ns target
     */
    void release(ubyte[] buffer) @nogc @trusted nothrow
    {
        if (buffer.ptr is null || buffer.length == 0)
            return;
        
        // Find bucket index by exact size match
        int bucketIdx = findBucketByExactSize(buffer.length);
        
        if (bucketIdx < 0)
        {
            // Not a pooled size, free non-pooled buffer
            releaseNonPooledBuffer(buffer);
            return;
        }
        
        // Bounds check - prevent unbounded growth
        if (freeCounts[bucketIdx] >= MAX_BUFFERS_PER_BUCKET)
        {
            // Pool is full, free the buffer instead
            free(buffer.ptr);
            return;
        }
        
        // Debug: check for double-release
        debug
        {
            for (size_t i = 0; i < freeCounts[bucketIdx]; i++)
            {
                if (freeLists[bucketIdx][i].ptr == buffer.ptr)
                {
                    assert(false, "Double release detected!");
                }
            }
        }
        
        // Push to free list (O(1), no GC)
        freeLists[bucketIdx][freeCounts[bucketIdx]] = buffer;
        freeCounts[bucketIdx]++;
    }
    
    /**
     * Cleanup pool resources.
     * Called by destructor and can be called manually.
     */
    void cleanup() @nogc @trusted nothrow
    {
        // Free all buffers in all bucket free lists
        foreach (bucketIdx; 0 .. NUM_BUCKETS)
        {
            for (size_t i = 0; i < freeCounts[bucketIdx]; i++)
            {
                free(freeLists[bucketIdx][i].ptr);
            }
            freeCounts[bucketIdx] = 0;
        }
        
        // Free tracked non-pooled buffers
        for (size_t i = 0; i < allocatedCount; i++)
        {
            free(allocatedBuffers[i]);
        }
        allocatedCount = 0;
    }
    
    ~this()
    {
        cleanup();
    }
    
    // ========================================
    // Private helpers
    // ========================================
    
    /**
     * Find bucket index for requested size (rounds up).
     * Returns -1 if size is larger than largest bucket.
     */
    private static int findBucketIndex(size_t size) @nogc @safe nothrow pure
    {
        if (size == 0)
            return 0; // TINY
        
        foreach (i, bucketSize; BUCKET_SIZES)
        {
            if (size <= bucketSize)
                return cast(int)i;
        }
        
        return -1; // Larger than all buckets
    }
    
    /**
     * Find bucket index by exact size match.
     * Returns -1 if size doesn't match any bucket exactly.
     */
    private static int findBucketByExactSize(size_t size) @nogc @safe nothrow pure
    {
        foreach (i, bucketSize; BUCKET_SIZES)
        {
            if (size == bucketSize)
                return cast(int)i;
        }
        return -1;
    }
    
    /**
     * Allocate and track non-pooled buffer.
     */
    private ubyte[] allocateNonPooledBuffer(size_t size) @nogc @trusted nothrow
    {
        auto buffer = allocateBuffer(size);
        
        if (buffer.ptr is null)
            return null;
        
        // Track for double-free prevention
        if (allocatedCount < allocatedBuffers.length)
        {
            allocatedBuffers[allocatedCount] = buffer.ptr;
            allocatedCount++;
        }
        
        return buffer;
    }
    
    /**
     * Release non-pooled buffer with double-free prevention.
     */
    private void releaseNonPooledBuffer(ubyte[] buffer) @nogc @trusted nothrow
    {
        // Find buffer in tracking array
        for (size_t i = 0; i < allocatedCount; i++)
        {
            if (allocatedBuffers[i] == buffer.ptr)
            {
                // Free buffer
                free(buffer.ptr);
                
                // Remove from tracking (swap with last)
                allocatedBuffers[i] = allocatedBuffers[allocatedCount - 1];
                allocatedCount--;
                return;
            }
        }
        
        // Buffer not found in tracking - potential double-free or invalid buffer
        debug
        {
            assert(false, "Attempt to release non-tracked buffer (potential double-free)");
        }
        
        // In release mode, just free it (best effort)
        free(buffer.ptr);
    }
    
    /**
     * Allocate cache-line aligned buffer.
     */
    private static ubyte[] allocateBuffer(size_t size) @nogc @trusted nothrow
    {
        if (size == 0)
            return null;
        
        version(Posix)
        {
            // Allocate cache-line aligned buffer using posix_memalign
            void* ptr;
            int result = posix_memalign(&ptr, CACHE_LINE_SIZE, size);
            
            if (result != 0 || ptr is null)
                return null;
            
            // Zero the buffer for security
            memset(ptr, 0, size);
            
            return (cast(ubyte*)ptr)[0 .. size];
        }
        else version(Windows)
        {
            // Windows: use _aligned_malloc for cache-line alignment
            void* ptr = _aligned_malloc(size, CACHE_LINE_SIZE);
            
            if (ptr is null)
                return null;
            
            memset(ptr, 0, size);
            return (cast(ubyte*)ptr)[0 .. size];
        }
        else
        {
            // Fallback - use malloc (not aligned)
            void* ptr = malloc(size);
            
            if (ptr is null)
                return null;
            
            memset(ptr, 0, size);
            return (cast(ubyte*)ptr)[0 .. size];
        }
    }
}
