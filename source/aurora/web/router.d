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

/**
 * PathParams - Path parameter storage
 *
 * Small object optimization: 4 inline params, overflow to heap
 */
struct PathParams
{
    enum MAX_INLINE_PARAMS = 4;
    
    struct Param
    {
        string name;
        string value;
    }
    
    Param[MAX_INLINE_PARAMS] inlineParams;
    Param[] overflowParams;
    uint count;
    
    /**
     * Get parameter value by name
     * Returns null if not found
     */
    string opIndex(string name)
    {
        // Search inline params
        for (uint i = 0; i < count && i < MAX_INLINE_PARAMS; i++)
        {
            if (inlineParams[i].name == name)
            {
                return inlineParams[i].value;
            }
        }
        
        // Search overflow params
        foreach (param; overflowParams)
        {
            if (param.name == name)
            {
                return param.value;
            }
        }
        
        return null;
    }
    
    /**
     * Get parameter value with default
     * Returns defaultValue if not found
     */
    string get(string name, string defaultValue = null)
    {
        auto value = opIndex(name);
        return value !is null ? value : defaultValue;
    }
    
    /**
     * Set parameter value
     */
    void opIndexAssign(string value, string name)
    {
        // BUG #4 FIX: Check if param exists, update instead of append
        // Search inline params for existing
        for (uint i = 0; i < count && i < MAX_INLINE_PARAMS; i++)
        {
            if (inlineParams[i].name == name)
            {
                inlineParams[i].value = value;  // Update
                return;
            }
        }

        // Search overflow params for existing
        foreach (ref param; overflowParams)
        {
            if (param.name == name)
            {
                param.value = value;  // Update
                return;
            }
        }

        // Not found, add new
        if (count < MAX_INLINE_PARAMS)
        {
            inlineParams[count] = Param(name, value);
        }
        else
        {
            overflowParams ~= Param(name, value);
        }
        count++;
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
 * RadixNode - Node in radix tree
 */
struct RadixNode
{
    string prefix;              // Path segment
    NodeType type;              // Node type
    Handler handler;            // Leaf: request handler
    RadixNode*[] children;      // Child nodes
    string paramName;           // For :id nodes
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
        
        // Scan all members of the module at compile-time
        static foreach (memberName; __traits(allMembers, Module))
        {
            // Get the member, with compile-time check
            static if (__traits(compiles, __traits(getMember, Module, memberName)))
            {
                alias member = __traits(getMember, Module, memberName);
                
                // Check if it's a function with the correct signature
                static if (is(typeof(&member) : Handler))
                {
                    // Scan attributes
                    static foreach (attr; __traits(getAttributes, member))
                    {
                        // Check for @Get
                        static if (is(typeof(attr) == Get))
                        {
                            this.get(attr.path, &member);
                        }
                        // Check for @Post
                        else static if (is(typeof(attr) == Post))
                        {
                            this.post(attr.path, &member);
                        }
                        // Check for @Put
                        else static if (is(typeof(attr) == Put))
                        {
                            this.put(attr.path, &member);
                        }
                        // Check for @Delete
                        else static if (is(typeof(attr) == Delete))
                        {
                            this.delete_(attr.path, &member);
                        }
                        // Check for @Patch
                        else static if (is(typeof(attr) == Patch))
                        {
                            this.patch(attr.path, &member);
                        }
                    }
                }
            }
        }
    }
    
    /**
     * Add middleware to router
     */
    void use(Middleware mw)
    {
        middlewares ~= mw;
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
        
        // Strip query string
        import std.string : indexOf;
        auto queryPos = path.indexOf('?');
        if (queryPos >= 0)
        {
            path = path[0 .. queryPos];
        }
        
        // Get method tree
        if (method !in methodTrees)
        {
            return Match(false);
        }
        
        auto root = methodTrees[method];
        
        // Match path
        PathParams params;
        auto handler = matchRecursive(root, path, params);
        
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
            return ["/"];
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
        return newNode;
    }
    
    /**
     * Match path recursively
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
                    params.count = savedCount;
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
                    params.count = savedCount;
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
