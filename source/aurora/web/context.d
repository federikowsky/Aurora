/**
 * Context - Request-scoped context object
 *
 * Package: aurora.web.context
 *
 * Features:
 * - Request/response pointers
 * - Helper methods (json, send, status)
 * - ContextStorage (small object optimization)
 * - Route parameters
 */
module aurora.web.context;

import aurora.http;
import aurora.web.router : PathParams;

/**
 * ContextStorage - Key-value storage for middleware data sharing
 *
 * Uses small object optimization:
 * - First 4 entries stored inline (no allocation)
 * - Overflow to heap for > 4 entries
 */
struct ContextStorage
{
    enum MAX_INLINE_VALUES = 4;
    
    struct Entry
    {
        string key;
        void* value;
    }
    
    Entry[MAX_INLINE_VALUES] inlineEntries;
    Entry[] overflowEntries;
    uint count;
    
    /**
     * Get value by key
     * Returns T.init if key not found
     * 
     * Note: Only supports types that can be safely cast to/from void*:
     * - Integers (int, uint, size_t, etc.)
     * - Pointers
     * - Class references
     */
    T get(T)(string key) if (is(T : void*) || is(T == class) || __traits(isIntegral, T))
    {
        // Search inline entries first
        for (uint i = 0; i < count && i < MAX_INLINE_VALUES; i++)
        {
            if (inlineEntries[i].key == key)
            {
                static if (__traits(isIntegral, T))
                    return cast(T) cast(size_t) inlineEntries[i].value;
                else
                    return cast(T) inlineEntries[i].value;
            }
        }
        
        // Search overflow entries
        foreach (entry; overflowEntries)
        {
            if (entry.key == key)
            {
                static if (__traits(isIntegral, T))
                    return cast(T) cast(size_t) entry.value;
                else
                    return cast(T) entry.value;
            }
        }
        
        return T.init;
    }
    
    /**
     * Set value by key
     * Inline storage for first 4 entries, heap for overflow
     * 
     * Note: Only supports types that can be safely cast to/from void*
     */
    void set(T)(string key, T value) if (is(T : void*) || is(T == class) || __traits(isIntegral, T))
    {
        static if (__traits(isIntegral, T))
            auto storedValue = cast(void*) cast(size_t) value;
        else
            auto storedValue = cast(void*) value;
            
        if (count < MAX_INLINE_VALUES)
        {
            inlineEntries[count] = Entry(key, storedValue);
        }
        else
        {
            overflowEntries ~= Entry(key, storedValue);
        }
        count++;
    }
    
    /**
     * Check if key exists
     */
    bool has(string key)
    {
        // Search inline entries
        for (uint i = 0; i < count && i < MAX_INLINE_VALUES; i++)
        {
            if (inlineEntries[i].key == key)
            {
                return true;
            }
        }
        
        // Search overflow entries
        foreach (entry; overflowEntries)
        {
            if (entry.key == key)
            {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * Remove entry by key
     */
    void remove(string key)
    {
        // Search inline entries
        for (uint i = 0; i < count && i < MAX_INLINE_VALUES; i++)
        {
            if (inlineEntries[i].key == key)
            {
                // Shift remaining entries
                for (uint j = i; j < count - 1 && j < MAX_INLINE_VALUES - 1; j++)
                {
                    inlineEntries[j] = inlineEntries[j + 1];
                }
                count--;
                return;
            }
        }
        
        // Search overflow entries
        import std.algorithm : remove;
        foreach (idx, entry; overflowEntries)
        {
            if (entry.key == key)
            {
                overflowEntries = overflowEntries.remove(idx);
                count--;
                return;
            }
        }
    }
}

/**
 * Context - Request-scoped context object
 *
 * Holds request/response data and provides helper methods
 * for handlers and middleware.
 */
align(64) struct Context
{
    // Request data (read-only after parse)
    HTTPRequest* request;
    
    // Response builder (writable)
    HTTPResponse* response;
    
    // Route parameters (extracted from path)
    PathParams params;
    
    // Middleware storage (key-value)
    ContextStorage storage;
    
    // State
    bool responseSent;
    
    /**
     * Set response status code
     */
    Context status(int code)
    {
        if (response !is null)
        {
            response.setStatus(code);
        }
        return this;  // Enable chaining: ctx.status(200).send("OK")
    }
    
    /**
     * Set response header
     */
    Context header(string name, string value)
    {
        if (response !is null)
        {
            response.setHeader(name, value);
        }
        return this;  // Enable chaining
    }
    
    /**
     * Send text response
     */
    void send(string text)
    {
        if (response !is null)
        {
            response.setBody(text);
        }
    }
    
    /**
     * Send JSON response
     * Sets Content-Type and serializes data
     */
    void json(T)(T data)
    {
        if (response !is null)
        {
            response.setHeader("Content-Type", "application/json");
            
            // Use fastjsond native serialization
            import aurora.schema.json : serialize;
            response.setBody(serialize(data));
        }
    }
}
