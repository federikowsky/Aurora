/**
 * Object Pool - Generic object pooling (GC-based)
 * 
 * Simplified approach:
 * - Uses GC for allocations (accept some GC overhead)
 * - Free list for reuse
 * - No manual malloc/free (avoids double-free bugs)
 * - Lifecycle hooks for init/cleanup
 * 
 * Performance: O(1) acquire/release, some GC allocations
 */
module aurora.mem.object_pool;

/**
 * Generic object pool (GC-based)
 */
class ObjectPool(T)
{
    // Element type: T for classes, T* for structs
    static if (is(T == class))
        alias Element = T;
    else
        alias Element = T*;
    
    // Free list of available objects
    private Element[] freeList;
    
    // Lifecycle hooks
    private void delegate(ref T) initializerHook;
    private void delegate(ref T) cleanupHook;
    
    /**
     * Set initialization hook (called on acquire)
     */
    void setInitializer(void delegate(ref T) hook)
    {
        initializerHook = hook;
    }
    
    /**
     * Set cleanup hook (called on release)
     */
    void setCleanup(void delegate(ref T) hook)
    {
        cleanupHook = hook;
    }
    
    /**
     * Acquire an object from the pool
     */
    Element acquire()
    {
        Element obj;
        
        // Try to get from free list
        if (freeList.length > 0)
        {
            obj = freeList[$ - 1];
            freeList.length--;
        }
        else
        {
            // Pool empty, allocate new object (GC)
            obj = allocateObject();
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
     * Release object back to pool
     */
    void release(Element obj)
    {
        if (obj is null)
            return;
        
        // Call cleanup hook if set
        if (cleanupHook !is null)
        {
            static if (is(T == class))
                cleanupHook(obj);
            else
                cleanupHook(*obj);
        }
        
        // Return to free list
        freeList ~= obj;
    }
    
    // Private helpers
    
    private Element allocateObject()
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
