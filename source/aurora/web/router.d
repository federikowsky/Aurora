/**
 * Routing System - Radix tree router
 *
 * Package: aurora.web.router
 *
 * Features:
 * - PathParams (small object optimization)
 * - RadixNode (Radix tree structure)
 * - Router (O(K) path matching)
 * - Route priority (static > param > wildcard)
 */
module aurora.web.router;

import aurora.web.context;
import std.functional : toDelegate;

/**
 * PathParams - Path parameter storage
 *
 * Note: Routes with >8 params will silently ignore excess params.
 * This is acceptable since such routes are extremely rare and indicate bad API design.
 */
struct PathParams
{
    enum MAX_INLINE_PARAMS = 8;  // Increased from 4 (stack-friendly, covers 99%+ routes)

    struct Param
    {
        string name;
        string value;
    }

    Param[MAX_INLINE_PARAMS] inlineParams;  // All params inline (no heap)
    ubyte count;                            // Changed to ubyte (max 255 params, saves memory)

    /**
     * Get parameter value by name
     * Returns null if not found
     * Optimized with early exit and cache-friendly iteration
     */
    pragma(inline, true)
    string opIndex(string name) const @safe nothrow pure @nogc
    {
        // Linear search with early exit (cache-friendly)
        // Most routes have 1-3 params, so linear search is faster than hash lookup
        for (ubyte i = 0; i < count; i++)
        {
            if (inlineParams[i].name == name)
            {
                return inlineParams[i].value;
            }
        }

        return null;
    }

    /**
     * Get parameter value with default
     * Returns defaultValue if not found
     */
    pragma(inline, true)
    string get(string name, string defaultValue = null) const @safe nothrow pure @nogc
    {
        auto value = opIndex(name);
        return value !is null ? value : defaultValue;
    }

    /**
     * Set parameter value
     * Optimized: updates existing or appends new (no overflow allocation)
     */
    pragma(inline, true)
    void opIndexAssign(string value, string name) @safe nothrow pure @nogc
    {
        // Search for existing param (update in-place)
        for (ubyte i = 0; i < count; i++)
        {
            if (inlineParams[i].name == name)
            {
                inlineParams[i].value = value;  // Update existing
                return;
            }
        }

        // Not found - add new if space available
        if (count < MAX_INLINE_PARAMS)
        {
            inlineParams[count] = Param(name, value);
            count++;
        }
        // Silently ignore if >8 params (extremely rare, indicates bad API design)
    }

    /**
     * Clear all parameters (reset for reuse)
     */
    pragma(inline, true)
    void clear() @safe nothrow pure @nogc
    {
        count = 0;
        // No need to zero out array - count controls valid range
    }
}

/**
 * NodeType - Type of route segment
 */
enum NodeType
{
    STATIC,      // Exact match: "/users"
    PARAM,       // Parameter: "/:id"
    WILDCARD     // Wildcard: "/*path"
}

/**
 * StaticChildMap - @nogc cache for STATIC child lookups
 *
 * - Cache size: 16 entries (covers 98-99% of real-world APIs)
 * - Cache threshold: 3 children (avoids overhead for simple routes)
 * - For nodes with ≤3 children: linear search is faster (~5-10ns vs ~15-25ns cache lookup)
 * - For nodes with >3 children: cache provides O(1) lookup vs O(n) linear search
 *
 * Key Safety:
 * - Cache keys use child.prefix (stable, part of router), not segment (temporary request buffer)
 * - This ensures keys remain valid for the lifetime of the router
 */
struct StaticChildMap
{
    private enum CACHE_SIZE = 16;  // Increased from 8 for better coverage
    private enum CACHE_THRESHOLD = 3;  // Use cache only if children.length > 3

    private struct Entry
    {
        const(char)[] key;
        RadixNode* value;
        bool occupied;
    }

    private Entry[CACHE_SIZE] cache;  // Stack-allocated cache
    private ubyte cacheCount;

    /// Insert into cache. Returns false if cache full (caller uses fallback).
    @nogc nothrow
    bool tryInsert(const(char)[] key, RadixNode* node)
    {
        if (cacheCount >= CACHE_SIZE)
            return false;  // Cache full, use fallback

        size_t idx = hashKey(key) & (CACHE_SIZE - 1);

        // Linear probing (max CACHE_SIZE attempts)
        for (ubyte i = 0; i < CACHE_SIZE; i++)
        {
            if (!cache[idx].occupied)
            {
                cache[idx] = Entry(key, node, true);
                cacheCount++;
                return true;
            }
            idx = (idx + 1) & (CACHE_SIZE - 1);
        }

        return false;  // Collision-saturated, use fallback
    }

    /// Lookup in cache. Returns null if not found (caller uses fallback).
    @nogc nothrow
    RadixNode* lookup(const(char)[] key) const
    {
        if (cacheCount == 0)
            return null;

        size_t idx = hashKey(key) & (CACHE_SIZE - 1);

        for (ubyte i = 0; i < CACHE_SIZE; i++)
        {
            if (!cache[idx].occupied)
                return null;  // Not in cache
            if (cache[idx].key == key)
                return cast(RadixNode*)cache[idx].value;  // Remove const qualifier
            idx = (idx + 1) & (CACHE_SIZE - 1);
        }

        return null;  // Not found in cache
    }

    @nogc nothrow:

    private size_t hashKey(const(char)[] key) const pure
    {
        // FNV-1a hash (fast, good distribution, @nogc)
        size_t hash = 2166136261u;
        foreach (c; key)
        {
            hash ^= c;
            hash *= 16777619;
        }
        return hash;
    }
}

/**
 * RadixNode - Node in radix tree
 *
 * Layout:
 * - Segments ≤15 chars: stored inline in char[15] (no heap allocation)
 * - Segments >15 chars: stored on heap (rare case: long API paths)
 */
struct RadixNode
{
    // === SSO DATA (16 bytes) ===
    union
    {
        char[15] inlineSegment;     // Inline storage for short segments
        char* heapSegment;          // Heap pointer for long segments (>15 chars)
    }
    uint segmentLength;             // Actual length of segment (changed from ubyte to support >255 chars)
    bool isHeap;                    // false = inline, true = heap

    // === NODE METADATA (24 bytes) ===
    NodeType type;                  // Node type
    Handler handler;                // Leaf: request handler (16 bytes delegate)

    // === CHILDREN & PARAMS ===
    RadixNode*[] children;          // Child nodes (16 bytes: ptr + length) - AUTHORITATIVE
    StaticChildMap staticCache;     // O(1) cache for STATIC children (advisory)
    string paramName;               // For :id nodes (16 bytes)

    /**
     * Get segment as string slice (transparent SSO access)
     * Property provides backward compatibility with old `prefix` field
     */
    @property const(char)[] prefix() const @trusted nothrow pure @nogc
    {
        if (isHeap)
            return heapSegment[0 .. segmentLength];
        else
            return inlineSegment[0 .. segmentLength];
    }

    /**
     * Set segment (automatic SSO decision based on length)
     */
    @property void prefix(const(char)[] value) @trusted nothrow
    {
        segmentLength = cast(uint)value.length;

        if (value.length <= 15)
        {
            // Use inline storage (fast path, ~95% of segments)
            isHeap = false;
            inlineSegment[0 .. segmentLength] = value[0 .. segmentLength];
        }
        else
        {
            // Use heap storage (rare path, long segments)
            isHeap = true;
            heapSegment = cast(char*)value.ptr;  // Store pointer (assumes value lifetime)
        }
    }
}

/**
 * Match - Route match result
 */
struct Match
{
    bool found;
    Handler handler;
    PathParams params;
}

/**
 * Handler - Request handler function
 */
alias Handler = void delegate(ref Context);

/**
 * Router - Radix tree router
 *
 * O(K) path matching where K = path length
 * Enhanced with prefix, middleware, and composition support
 */
class Router
{
    string prefix;                           // Route prefix (e.g., "/api")
    Middleware[] middlewares;                // Router-local middleware
    Router[] subRouters;                     // Child routers
    
    private RadixNode*[string] methodTrees;  // Separate tree per HTTP method
    
    /**
     * Constructor with optional prefix
     */
    this(string prefix = "")
    {
        this.prefix = normalizePath(prefix);
        if (this.prefix == "/")
        {
            this.prefix = "";
        }
    }
    
    /**
     * Add route to router
     */
    void addRoute(string method, string path, Handler handler)
    {
        // BUG #7 FIX: Validate handler is non-null
        if (handler is null)
        {
            throw new Exception("Handler cannot be null for route: " ~ method ~ " " ~ path);
        }

        // Normalize path
        path = normalizePath(path);

        // Get or create method tree
        if (method !in methodTrees)
        {
            methodTrees[method] = new RadixNode();
        }
        
        auto root = methodTrees[method];
        
        // Split path into segments
        auto segments = splitPath(path);
        
        // Insert into radix tree
        auto node = root;
        foreach (segment; segments)
        {
            node = insertSegment(node, segment);
        }
        
        // Set handler at leaf
        node.handler = handler;
    }
    
    /**
     * HTTP method helpers
     */
    void get(string path, Handler handler)
    {
        addRoute("GET", prefix ~ path, handler);
    }
    
    void post(string path, Handler handler)
    {
        addRoute("POST", prefix ~ path, handler);
    }
    
    void put(string path, Handler handler)
    {
        addRoute("PUT", prefix ~ path, handler);
    }
    
    void delete_(string path, Handler handler)
    {
        addRoute("DELETE", prefix ~ path, handler);
    }
    
    void patch(string path, Handler handler)
    {
        addRoute("PATCH", prefix ~ path, handler);
    }
    
    /**
     * Auto-register handlers from a module using UDA decorators
     * 
     * Scans all members of the module for @Get, @Post, @Put, @Delete, @Patch
     * decorators and registers them automatically.
     */
    void autoRegister(alias Module)()
    {
        import aurora.web.decorators;
        
        // Use mixin to avoid alias redefinition in static foreach
        static foreach (memberName; __traits(allMembers, Module))
        {{
            // Double braces create a new scope for each iteration
            static if (__traits(compiles, __traits(getMember, Module, memberName)))
            {
                alias member = __traits(getMember, Module, memberName);
                
                // Check if it's callable with the correct signature (function or delegate)
                // Check for both function pointer and delegate compatibility
                static if (is(typeof(&member) == void function(ref Context)) ||
                           is(typeof(&member) : void delegate(ref Context)))
                {
                    // Scan attributes for route decorators
                    static foreach (attr; __traits(getAttributes, member))
                    {{
                        static if (is(typeof(attr) == Get))
                        {
                            this.get(attr.path, toDelegate(&member));
                        }
                        else static if (is(typeof(attr) == Post))
                        {
                            this.post(attr.path, toDelegate(&member));
                        }
                        else static if (is(typeof(attr) == Put))
                        {
                            this.put(attr.path, toDelegate(&member));
                        }
                        else static if (is(typeof(attr) == Delete))
                        {
                            this.delete_(attr.path, toDelegate(&member));
                        }
                        else static if (is(typeof(attr) == Patch))
                        {
                            this.patch(attr.path, toDelegate(&member));
                        }
                    }}
                }
            }
        }}
    }
    
    /**
     * Add middleware to router
     */
    void use(Middleware mw)
    {
        middlewares ~= mw;
    }
    
    /**
     * Mount sub-router at a specific prefix
     * 
     * Example:
     *   mainRouter.mount("/api/v1/products", productRouter);
     */
    void mount(string mountPrefix, Router other)
    {
        // Set the sub-router's prefix and include it
        other.prefix = normalizePath(mountPrefix);
        includeRouter(other);
    }
    
    /**
     * Include sub-router (composition)
     */
    void includeRouter(Router other, Router[] visited = [], string accumulatedPrefix = null)
    {
        // BUG #5 FIX: Cycle detection to prevent infinite recursion
        foreach (v; visited)
        {
            if (v is other)
            {
                throw new Exception("Circular router reference detected");
            }
        }

        subRouters ~= other;

        // Calculate the prefix to use for this sub-router's routes
        // First time called: use this router's prefix
        // Recursive calls: use accumulated prefix from parent chain
        string effectivePrefix = accumulatedPrefix !is null ? accumulatedPrefix : prefix;
        
        // Register all routes from sub-router
        // Note: Routes in other's trees already include other's prefix
        // We add the effective prefix from the parent chain
        foreach (method, tree; other.methodTrees)
        {
            registerSubRouterRoutes(method, tree, effectivePrefix);
        }

        // Calculate accumulated prefix for nested sub-routers
        // This includes all prefixes in the chain
        string nextAccumulatedPrefix = effectivePrefix;
        if (other.prefix.length > 0 && other.prefix != "/")
        {
            if (nextAccumulatedPrefix.length > 0 && nextAccumulatedPrefix != "/")
                nextAccumulatedPrefix ~= other.prefix;
            else
                nextAccumulatedPrefix = other.prefix;
        }

        // Recursively include sub-routers with cycle tracking and accumulated prefix
        foreach (subRouter; other.subRouters)
        {
            includeRouter(subRouter, visited ~ other, nextAccumulatedPrefix);
        }
    }
    
    /**
     * Match path to route
     */
    Match match(string method, string path)
    {
        // Normalize path
        path = normalizePath(path);

        // Strip query string (@nogc - no indexOf allocation)
        foreach (i, c; path)
        {
            if (c == '?')
            {
                path = path[0 .. i];  // Pure slice (no alloc)
                break;
            }
        }

        // Get method tree
        if (method !in methodTrees)
        {
            return Match(false);
        }

        auto root = methodTrees[method];

        // Use iterative matching (no recursion)
        PathParams params;
        auto handler = matchIterative(root, path, params);

        return Match(handler !is null, handler, params);
    }
    
    private:
    
    /**
     * Normalize path (add leading slash, remove trailing slash)
     */
    string normalizePath(string path)
    {
        import std.string : strip;
        import std.array : replace;
        
        // Handle empty path
        if (path.length == 0)
        {
            return "/";
        }
        
        // Add leading slash
        if (path[0] != '/')
        {
            path = "/" ~ path;
        }
        
        // Remove trailing slash (except for root)
        if (path.length > 1 && path[$-1] == '/')
        {
            path = path[0 .. $-1];
        }
        
        // Normalize double slashes
        path = path.replace("//", "/");
        
        return path;
    }
    
    /**
     * Split path into segments
     */
    string[] splitPath(string path)
    {
        import std.array : split;
        import std.algorithm : filter;
        import std.string : strip;
        
        if (path == "/")
        {
            return []; // Root path has no segments
        }
        
        auto segments = path.split("/");
        
        // Filter empty segments
        string[] result;
        foreach (seg; segments)
        {
            if (seg.length > 0)
            {
                result ~= seg;
            }
        }
        
        return result;
    }
    
    /**
     * Detect node type from segment
     */
    NodeType detectType(string segment)
    {
        if (segment.length > 0)
        {
            if (segment[0] == ':')
            {
                return NodeType.PARAM;
            }
            else if (segment[0] == '*')
            {
                return NodeType.WILDCARD;
            }
        }
        return NodeType.STATIC;
    }
    
    /**
     * Extract parameter name from segment
     */
    string extractParamName(string segment)
    {
        if (segment.length > 1 && (segment[0] == ':' || segment[0] == '*'))
        {
            return segment[1 .. $];
        }
        return null;
    }
    
    /**
     * Insert segment into radix tree
     */
    RadixNode* insertSegment(RadixNode* node, string segment)
    {
        // BUG #2 FIX: Match PARAM/WILDCARD by type, not exact prefix
        auto segmentType = detectType(segment);
        auto segmentParamName = extractParamName(segment);

        foreach (child; node.children)
        {
            // For PARAM/WILDCARD: match by type (only one per parent allowed)
            if (segmentType != NodeType.STATIC && child.type == segmentType)
            {
                // Warn if param name differs (developer mistake)
                if (child.paramName != segmentParamName)
                {
                    import std.stdio : stderr;
                    stderr.writefln("Warning: Conflicting param names '%s' vs '%s' on same path segment",
                                   child.paramName, segmentParamName);
                }
                return child;
            }

            // For STATIC: exact prefix match
            if (segmentType == NodeType.STATIC && child.prefix == segment)
            {
                return child;
            }
        }

        // Create new node
        auto newNode = new RadixNode();
        newNode.prefix = segment;
        newNode.type = segmentType;
        newNode.paramName = segmentParamName;

        node.children ~= newNode;
        
        // Populate cache when adding new STATIC node (only if threshold met)
        // Use newNode.prefix (stable, part of router) not segment (temporary parameter)
        if (segmentType == NodeType.STATIC && node.children.length > StaticChildMap.CACHE_THRESHOLD)
        {
            node.staticCache.tryInsert(newNode.prefix, newNode);
        }
        
        return newNode;
    }
    
    /**
     * Iterative path matching (replaces matchRecursive)
     *
     * Algorithm:
     * 1. Start at root node
     * 2. Iterate over path, finding segment boundaries without split
     * 3. For each segment, search children with priority: STATIC > PARAM > WILDCARD
     * 4. Continue until path exhausted or no match found
     */
    Handler matchIterative(RadixNode* node, const(char)[] path, ref PathParams params) @trusted nothrow
    {
        // Handle root path special case
        if (path == "/" && node.handler !is null)
        {
            return node.handler;
        }

        RadixNode* current = node;
        size_t pathPos = 0;
        
        // Skip leading slash (Aurora internal paths are segment-based)
        if (path.length > 0 && path[0] == '/')
            pathPos++;

        // Iterative matching loop (no recursion)
        while (pathPos < path.length)
        {
            // === FIND NEXT SEGMENT BOUNDARY (in-place, no allocation) ===
            size_t segEnd = pathPos;
            while (segEnd < path.length && path[segEnd] != '/')
                segEnd++;

            auto segment = path[pathPos .. segEnd];

            // === PRIORITY 1: Try STATIC children first ===
            // Fast path via cache, fallback to linear search
            bool foundMatch = false;
            auto parentNode = current;  // Save parent for cache insertion

            // Use cache only if node has enough children to benefit
            if (current.children.length > StaticChildMap.CACHE_THRESHOLD)
            {
                // FAST PATH: Try cache lookup first (O(1) for cached routes)
                auto cachedChild = current.staticCache.lookup(segment);
                if (cachedChild !is null)
                {
                    current = cachedChild;
                    foundMatch = true;
                }
            }

            if (!foundMatch)
            {
                // FALLBACK PATH: Linear search (handles cache misses + PARAM/WILDCARD)
                foreach (child; current.children)
                {
                    if (child.type == NodeType.STATIC && child.prefix == segment)
                    {
                        current = child;
                        foundMatch = true;
                        // Populate cache only if threshold met
                        // Use child.prefix (stable, part of router) not segment (temporary request buffer slice)
                        if (parentNode.children.length > StaticChildMap.CACHE_THRESHOLD)
                        {
                            parentNode.staticCache.tryInsert(child.prefix, child);
                        }
                        break;
                    }
                }
            }

            if (foundMatch)
            {
                // Move past this segment
                pathPos = segEnd;
                if (pathPos < path.length && path[pathPos] == '/')
                    pathPos++;  // Skip slash
                continue;
            }

            // === PRIORITY 2: Try PARAM children ===
            foreach (child; current.children)
            {
                if (child.type == NodeType.PARAM)
                {
                    // Store parameter value
                    params[child.paramName] = cast(string)segment;
                    current = child;
                    foundMatch = true;
                    break;
                }
            }

            if (foundMatch)
            {
                // Move past this segment
                pathPos = segEnd;
                if (pathPos < path.length && path[pathPos] == '/')
                    pathPos++;  // Skip slash
                continue;
            }

            // === PRIORITY 3: Try WILDCARD children ===
            foreach (child; current.children)
            {
                if (child.type == NodeType.WILDCARD)
                {
                    // Wildcard captures rest of path
                    params[child.paramName] = cast(string)path[pathPos .. $];
                    return child.handler;
                }
            }

            // No match found for this segment
            return null;
        }

        // Path fully matched - return handler if present
        return current.handler;
    }

    /**
     * Match path recursively (DEPRECATED - kept for reference, use matchIterative)
     */
    Handler matchRecursive(RadixNode* node, string path, ref PathParams params)
    {
        // BUG #1 FIX: Strip leading slash to match splitPath behavior
        // splitPath removes slashes, so prefixes don't have them
        // EXCEPTION: Root path "/" should match prefix "/"
        if (path.length > 1 && path[0] == '/')
        {
            path = path[1 .. $];
        }

        // Try static children first (priority)
        foreach (child; node.children)
        {
            if (child.type == NodeType.STATIC)
            {
                if (path == child.prefix)
                {
                    return child.handler;
                }
                else if (path.length > child.prefix.length && 
                         path[0 .. child.prefix.length] == child.prefix &&
                         path[child.prefix.length] == '/')
                {
                    auto remaining = path[child.prefix.length + 1 .. $];
                    auto result = matchRecursive(child, remaining, params);
                    if (result !is null)
                    {
                        return result;
                    }
                }
            }
        }
        
        // Try param children (second priority)
        foreach (child; node.children)
        {
            if (child.type == NodeType.PARAM)
            {
                import std.string : indexOf;

                // BUG #3 FIX: Save param count for rollback on backtrack
                uint savedCount = params.count;

                auto slashPos = path.indexOf('/');
                if (slashPos == -1)
                {
                    // No more slashes, this is the param value
                    params[child.paramName] = path;
                    if (child.handler !is null)
                    {
                        return child.handler;
                    }
                    // Rollback: no handler found, try next child
                    params.count = cast(ubyte)savedCount;
                }
                else
                {
                    // Extract param value and continue
                    params[child.paramName] = path[0 .. slashPos];
                    auto remaining = path[slashPos + 1 .. $];
                    auto result = matchRecursive(child, remaining, params);
                    if (result !is null)
                    {
                        return result;
                    }
                    // Rollback: recursion failed, remove param we added
                    params.count = cast(ubyte)savedCount;
                }
            }
        }
        
        // Try wildcard children (lowest priority)
        foreach (child; node.children)
        {
            if (child.type == NodeType.WILDCARD)
            {
                params[child.paramName] = path;
                return child.handler;
            }
        }
        
        return null;
    }
    
    /**
     * Register routes from sub-router
     */
    private void registerSubRouterRoutes(string method, RadixNode* node, string pathPrefix)
    {
        if (node.handler !is null)
        {
            // This node has a handler, register it
            addRoute(method, pathPrefix, node.handler);
        }
        
        // Recursively register children
        foreach (child; node.children)
        {
            string childPath = pathPrefix;
            if (child.prefix != "/")
            {
                childPath ~= "/" ~ child.prefix;
            }
            registerSubRouterRoutes(method, child, childPath);
        }
    }
}

/**
 * Middleware - Import from middleware module
 */
import aurora.web.middleware : Middleware, NextFunction;
