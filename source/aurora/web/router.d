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
import aurora.web.middleware.chain : Middleware, bindPolicy, snapshotPolicy, withMiddleware;
import std.functional : toDelegate;

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

    /**
     * Restore a previous logical size after route backtracking.
     *
     * Shrinking the slice is required in addition to restoring `count`,
     * otherwise lookups can still observe stale overflow entries.
     */
    package(aurora) void truncate(uint newCount) @safe nothrow @nogc
    {
        assert(newCount <= count);

        auto oldInlineCount = count < MAX_INLINE_PARAMS
            ? count
            : MAX_INLINE_PARAMS;
        auto newInlineCount = newCount < MAX_INLINE_PARAMS
            ? newCount
            : MAX_INLINE_PARAMS;
        foreach (i; newInlineCount .. oldInlineCount)
            inlineParams[i] = Param.init;

        auto newOverflowLength = newCount > MAX_INLINE_PARAMS
            ? newCount - MAX_INLINE_PARAMS
            : 0;
        if (overflowParams.length > newOverflowLength)
            overflowParams = overflowParams[0 .. newOverflowLength];

        count = newCount;
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

// Shared registration syntax for App and Router. Keep the ordinary verb overload
// as the owner of the path, return value and virtual dispatch.
package(aurora) mixin template PolicyRegistration(alias attachGroup)
{
    private template beforeHandler(alias register, Location...)
    {
        auto beforeHandler(Location location, Middleware policy, Handler handler)
        {
            return register(location, withMiddleware(handler, policy));
        }

        auto beforeHandler(Location location, Middleware[] policies, Handler handler)
        {
            return register(location, withMiddleware(handler, policies));
        }
    }

    private alias DefineRoutes = void delegate(Router);

    /// Define a child inline. Import its routes only if the whole definition succeeds.
    final void group(string prefix, scope DefineRoutes define)
    {
        defineGroup(prefix, define);
    }

    /// ditto
    final void group(string prefix, Middleware policy, scope DefineRoutes define)
    {
        defineGroup(prefix, define, policy);
    }

    /// ditto
    final void group(string prefix, Middleware[] policies, scope DefineRoutes define)
    {
        defineGroup(prefix, define, policies);
    }

    private void defineGroup(string prefix, scope DefineRoutes define, Middleware[] policies...)
    {
        if (define is null) throw new Exception("A group requires a route definition");
        // All registrations in the block are local, including addRoute for
        // custom methods. Apply the prefix once, at the mount boundary.
        auto child = new Router("", policies);
        define(child);
        attachGroup(prefix, child);
    }
}

/**
 * Router - Radix tree router
 *
 * O(K) path matching where K = path length
 * Enhanced with prefix and composition support
 */
class Router
{
    immutable string prefix;
    private Middleware[] groupPolicy;
    
    private RadixNode*[string] methodTrees;  // Separate tree per HTTP method
    
    /**
     * Constructor with optional prefix
     */
    this(string prefix = "", Middleware[] policy...)
    {
        auto normalized = normalizePath(prefix);
        this.prefix = normalized == "/" ? "" : normalized;
        groupPolicy = snapshotPolicy(policy);
    }
    
    /**
     * Add route to router
     */
    void addRoute(string method, string path, Handler handler)
    {
        if (handler is null)
            throw new Exception("Handler cannot be null for route: " ~ method ~ " " ~ path);
        registerLeaf(method, path, handler, false);
    }

    // A preflight walk only checks existing nodes. It never creates a node or
    // binds a handler. Used to reject conflicting mounts before importing any leaf.
    private void registerLeaf(string method, string path, Handler handler, bool checkOnly)
    {
        path = normalizePath(path);
        auto root = method in methodTrees;
        if (root is null)
        {
            if (checkOnly) return;
            methodTrees[method] = new RadixNode();
        }
        auto node = methodTrees[method];
        if (path == "/")
        {
            node = segmentNode(node, path, !checkOnly);
            if (node is null) return;
        }
        else
        {
            import std.algorithm.iteration : splitter;
            foreach (segment; path.splitter('/'))
            {
                if (!segment.length) continue;
                node = segmentNode(node, segment, !checkOnly);
                if (node is null) return;
            }
        }
        if (node.handler !is null)
            throw new Exception("Duplicate route: " ~ method ~ " " ~ path);
        if (!checkOnly)
            node.handler = bindPolicy(handler, groupPolicy);
    }

    private string prefixed(string path)
    {
        if (!prefix.length) return path;
        return path.length && path[0] != '/' ? prefix ~ "/" ~ path : prefix ~ path;
    }

    /**
     * HTTP method helpers
     */
    void get(string path, Handler handler)
    {
        addRoute("GET", prefixed(path), handler);
    }
    
    void post(string path, Handler handler)
    {
        addRoute("POST", prefixed(path), handler);
    }
    
    void put(string path, Handler handler)
    {
        addRoute("PUT", prefixed(path), handler);
    }
    
    void delete_(string path, Handler handler)
    {
        addRoute("DELETE", prefixed(path), handler);
    }
    
    void patch(string path, Handler handler)
    {
        addRoute("PATCH", prefixed(path), handler);
    }
    
    mixin PolicyRegistration!mount;
    alias get = beforeHandler!(get, string);
    alias post = beforeHandler!(post, string);
    alias put = beforeHandler!(put, string);
    alias delete_ = beforeHandler!(delete_, string);
    alias patch = beforeHandler!(patch, string);
    alias addRoute = beforeHandler!(addRoute, string, string);

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
    
    /// Import the child's current effective routes under an additional prefix.
    /// No child is retained or mutated. Each destination policy is applied once.
    void mount(string mountPrefix, Router other)
    {
        if (other is null || other is this)
            throw new Exception("A mount requires a distinct non-null router");
        auto extra = normalizePath(mountPrefix);
        auto base = extra == "/" ? prefix : prefix ~ extra;
        foreach (checkOnly; [true, false])
            foreach (method, tree; other.methodTrees)
                if (!checkOnly || method in methodTrees)
                    importLeaves(method, tree, base, checkOnly);
    }

    /// Include a snapshot of the child's routes under this router's prefix.
    void includeRouter(Router other)
    {
        mount("", other);
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
    RadixNode* segmentNode(RadixNode* node, string segment, bool create)
    {
        // BUG #2 FIX: Match PARAM/WILDCARD by type, not exact prefix
        auto segmentType = detectType(segment);
        auto segmentParamName = extractParamName(segment);

        foreach (child; node.children)
        {
            // For PARAM/WILDCARD: match by type (only one per parent allowed)
            if (segmentType != NodeType.STATIC && child.type == segmentType)
            {
                if (child.paramName != segmentParamName)
                {
                    throw new Exception("Conflicting route parameter names: " ~
                                        child.paramName ~ " and " ~ segmentParamName);
                }
                return child;
            }

            // For STATIC: exact prefix match
            if (segmentType == NodeType.STATIC && child.prefix == segment)
            {
                return child;
            }
        }

        if (!create) return null;

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
                if (path == child.prefix && child.handler !is null)
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
                    params.truncate(savedCount);
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
                    params.truncate(savedCount);
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
    private void importLeaves(string method, RadixNode* node, string pathPrefix, bool checkOnly)
    {
        if (node.handler !is null)
        {
            // This node has a handler, register it
            registerLeaf(method, pathPrefix, node.handler, checkOnly);
        }
        
        // Recursively register children
        foreach (child; node.children)
        {
            string childPath = pathPrefix;
            if (child.prefix != "/")
            {
                childPath ~= "/" ~ child.prefix;
            }
            importLeaves(method, child, childPath, checkOnly);
        }
    }
}
