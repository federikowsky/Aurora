/**
 * Object Pool - Generic object pooling (Fixed capacity)
 * 
 * Features:
 * - Pre-allocates objects at initialization (one-time GC cost)
 * - Fixed-size free list (no GC growth in hot path)
 * - Returns null when pool exhausted (no unbounded growth)
 * - Double-release detection in debug mode
 * - Lifecycle hooks for init/cleanup
 * 
 * Performance: O(1) acquire/release, zero GC allocations after initialization
 * 
 * Usage:
 * ---
 * auto pool = new ObjectPool!Connection(16);
 * auto conn = pool.acquire();
 * // ... use conn ...
 * pool.release(conn);
 * ---
 */
module aurora.mem.object_pool;

/**
 * Generic object pool - Fixed capacity, no unbounded growth.
 * 
 * Params:
 *   T = Type of objects to pool (class or struct)
 */
class ObjectPool(T)
{
    /// Element type: T for classes, T* for structs
    static if (is(T == class))
        alias Element = T;
    else
        alias Element = T*;
    
    private enum MAX_CAPACITY = 256;  /// Maximum pool size
    
    // Pre-allocated object storage
    private Element[MAX_CAPACITY] pool;
    
    // Free list - STATIC ARRAY (no GC growth)
    private Element[MAX_CAPACITY] freeList;
    private size_t freeCount;
    
    // Actual capacity (set at initialization)
    private size_t capacity;
    
    // Lifecycle hooks
    private void delegate(ref T) initializerHook;
    private void delegate(ref T) cleanupHook;
    
    /**
     * Initialize pool with specified capacity.
     * 
     * Params:
     *   requestedCapacity = Number of objects to pre-allocate (max 256)
     */
    this(size_t requestedCapacity = 16) @safe
    {
        capacity = requestedCapacity < MAX_CAPACITY ? requestedCapacity : MAX_CAPACITY;
        
        // Pre-allocate objects (one-time GC cost)
        for (size_t i = 0; i < capacity; i++)
        {
            pool[i] = allocateObject();
            if (pool[i] !is null)
            {
                freeList[freeCount] = pool[i];
                freeCount++;
            }
        }
    }
    
    /**
     * Set initialization hook (called on acquire).
     */
    void setInitializer(void delegate(ref T) hook) @safe nothrow
    {
        initializerHook = hook;
    }
    
    /**
     * Set cleanup hook (called on release).
     */
    void setCleanup(void delegate(ref T) hook) @safe nothrow
    {
        cleanupHook = hook;
    }
    
    /**
     * Acquire an object from the pool.
     * 
     * Returns: Object from pool, or null if pool exhausted.
     */
    Element acquire() @trusted
    {
        Element obj;
        
        // Try to get from free list (O(1), no GC)
        if (freeCount > 0)
        {
            freeCount--;
            obj = freeList[freeCount];
        }
        else
        {
            // Pool exhausted - return null (no unbounded growth)
            return null;
        }
        
        // Call initialization hook if set
        if (initializerHook !is null && obj !is null)
        {
            static if (is(T == class))
                initializerHook(obj);
            else
                initializerHook(*obj);
        }
        
        return obj;
    }
    
    /**
     * Release object back to pool.
     */
    void release(Element obj) @trusted
    {
        if (obj is null)
            return;
        
        // Debug: check for double-release
        debug
        {
            for (size_t i = 0; i < freeCount; i++)
            {
                if (freeList[i] is obj)
                {
                    assert(false, "Double release detected!");
                }
            }
        }
        
        // Call cleanup hook if set
        if (cleanupHook !is null)
        {
            static if (is(T == class))
                cleanupHook(obj);
            else
                cleanupHook(*obj);
        }
        
        // Bounds check - prevent overflow
        if (freeCount >= capacity)
        {
            // Pool is full, cannot accept more objects
            debug
            {
                assert(false, "Pool overflow - more releases than acquires");
            }
            return;
        }
        
        // Return to free list (O(1), no GC)
        freeList[freeCount] = obj;
        freeCount++;
    }
    
    /**
     * Get number of available objects in pool.
     */
    size_t available() const @nogc @safe nothrow pure
    {
        return freeCount;
    }
    
    /**
     * Get pool capacity.
     */
    size_t getCapacity() const @nogc @safe nothrow pure
    {
        return capacity;
    }
    
    // ========================================
    // Private helpers
    // ========================================
    
    private static Element allocateObject() @safe
    {
        static if (is(T == class))
        {
            // Classes: use new (GC)
            return new T();
        }
        else
        {
            // Structs: use new (GC-allocated pointer)
            return new T();
        }
    }
}
