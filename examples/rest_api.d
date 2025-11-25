/**
 * Aurora REST API Example
 * 
 * Demonstrates building a complete REST API with:
 * - CRUD operations for a resource (users)
 * - JSON request/response handling
 * - Path parameters and query strings
 * - Error handling
 * - Multiple HTTP methods
 * 
 * Uses the App.METHOD() fluent API style.
 */
module examples.rest_api;

import aurora;
import std.conv : to;
import std.json;
import std.format : format;

// ============================================================================
// Data Models
// ============================================================================

struct User
{
    int id;
    string name;
    string email;
    string role;
}

// In-memory "database"
__gshared User[int] users;
__gshared int nextId = 1;

// ============================================================================
// Main Application
// ============================================================================

void main()
{
    // Seed some data
    seedData();
    
    // Create app with 4 workers
    auto config = ServerConfig.defaults();
    config.numWorkers = 4;
    
    auto app = new App(config);
    
    // ========================================================================
    // CORS Middleware (allow cross-origin requests)
    // ========================================================================
    
    auto corsConfig = CORSConfig();
    corsConfig.allowedOrigins = ["*"];
    corsConfig.allowedMethods = ["GET", "POST", "PUT", "DELETE", "PATCH"];
    app.use(new CORSMiddleware(corsConfig));
    
    // ========================================================================
    // Security Headers
    // ========================================================================
    
    auto securityConfig = SecurityConfig();
    securityConfig.enableXSSProtection = true;
    securityConfig.enableContentTypeOptions = true;
    app.use(new SecurityMiddleware(securityConfig));
    
    // ========================================================================
    // API Routes
    // ========================================================================
    
    // GET /api/users - List all users
    app.get("/api/users", (ref Context ctx) {
        JSONValue[] userList;
        foreach (user; users.values)
        {
            userList ~= userToJson(user);
        }
        
        ctx.header("Content-Type", "application/json")
           .send(JSONValue(userList).toString());
    });
    
    // GET /api/users/:id - Get single user
    app.get("/api/users/:id", (ref Context ctx) {
        auto idStr = ctx.params.get("id", "");
        
        int id;
        try {
            id = idStr.to!int;
        } catch (Exception) {
            ctx.status(400).json(`{"error":"Invalid user ID"}`);
            return;
        }
        
        if (auto user = id in users)
        {
            ctx.header("Content-Type", "application/json")
               .send(userToJson(*user).toString());
        }
        else
        {
            ctx.status(404).json(`{"error":"User not found"}`);
        }
    });
    
    // POST /api/users - Create new user
    app.post("/api/users", (ref Context ctx) {
        try
        {
            // Parse request body
            auto bodyStr = ctx.request ? cast(string)ctx.request.body : "";
            if (bodyStr.length == 0)
            {
                ctx.status(400).json(`{"error":"Request body is empty"}`);
                return;
            }
            
            auto json = parseJSON(bodyStr);
            
            // Validate required fields
            if ("name" !in json || "email" !in json)
            {
                ctx.status(400).json(`{"error":"Missing required fields: name, email"}`);
                return;
            }
            
            // Create user
            auto user = User(
                nextId++,
                json["name"].str,
                json["email"].str,
                ("role" in json) ? json["role"].str : "user"
            );
            
            users[user.id] = user;
            
            ctx.status(201)
               .header("Content-Type", "application/json")
               .header("Location", "/api/users/" ~ user.id.to!string)
               .send(userToJson(user).toString());
        }
        catch (JSONException e)
        {
            ctx.status(400).json(`{"error":"Invalid JSON: ` ~ e.msg ~ `"}`);
        }
        catch (Exception e)
        {
            ctx.status(500).json(`{"error":"Internal server error"}`);
        }
    });
    
    // PUT /api/users/:id - Full update
    app.put("/api/users/:id", (ref Context ctx) {
        auto idStr = ctx.params.get("id", "");
        
        int id;
        try {
            id = idStr.to!int;
        } catch (Exception) {
            ctx.status(400).json(`{"error":"Invalid user ID"}`);
            return;
        }
        
        if (id !in users)
        {
            ctx.status(404).json(`{"error":"User not found"}`);
            return;
        }
        
        try
        {
            auto bodyStr = ctx.request ? cast(string)ctx.request.body : "";
            auto json = parseJSON(bodyStr);
            
            if ("name" !in json || "email" !in json)
            {
                ctx.status(400).json(`{"error":"PUT requires all fields"}`);
                return;
            }
            
            users[id] = User(
                id,
                json["name"].str,
                json["email"].str,
                ("role" in json) ? json["role"].str : "user"
            );
            
            ctx.header("Content-Type", "application/json")
               .send(userToJson(users[id]).toString());
        }
        catch (Exception e)
        {
            ctx.status(400).json(`{"error":"Invalid request"}`);
        }
    });
    
    // PATCH /api/users/:id - Partial update
    app.patch("/api/users/:id", (ref Context ctx) {
        auto idStr = ctx.params.get("id", "");
        
        int id;
        try {
            id = idStr.to!int;
        } catch (Exception) {
            ctx.status(400).json(`{"error":"Invalid user ID"}`);
            return;
        }
        
        if (auto user = id in users)
        {
            try
            {
                auto bodyStr = ctx.request ? cast(string)ctx.request.body : "";
                auto json = parseJSON(bodyStr);
                
                // Update only provided fields
                if ("name" in json) user.name = json["name"].str;
                if ("email" in json) user.email = json["email"].str;
                if ("role" in json) user.role = json["role"].str;
                
                ctx.header("Content-Type", "application/json")
                   .send(userToJson(*user).toString());
            }
            catch (Exception e)
            {
                ctx.status(400).json(`{"error":"Invalid request"}`);
            }
        }
        else
        {
            ctx.status(404).json(`{"error":"User not found"}`);
        }
    });
    
    // DELETE /api/users/:id - Delete user
    app.delete_("/api/users/:id", (ref Context ctx) {
        auto idStr = ctx.params.get("id", "");
        
        int id;
        try {
            id = idStr.to!int;
        } catch (Exception) {
            ctx.status(400).json(`{"error":"Invalid user ID"}`);
            return;
        }
        
        if (id in users)
        {
            users.remove(id);
            ctx.status(204).send("");  // No content
        }
        else
        {
            ctx.status(404).json(`{"error":"User not found"}`);
        }
    });
    
    // GET /api/users/search?name=xxx&role=xxx - Search users
    app.get("/api/users/search", (ref Context ctx) {
        // Note: Query parameters would come from request parsing
        // For now, return all users matching criteria
        JSONValue[] results;
        foreach (user; users.values)
        {
            results ~= userToJson(user);
        }
        ctx.header("Content-Type", "application/json")
           .send(JSONValue(results).toString());
    });
    
    // ========================================================================
    // Health & Info
    // ========================================================================
    
    app.get("/health", (ref Context ctx) {
        ctx.json(["status": "ok", "users": users.length.to!string]);
    });
    
    // Start server
    import std.stdio : writefln;
    writefln("REST API Server starting on http://localhost:8080");
    writefln("Endpoints:");
    writefln("  GET    /api/users         - List all users");
    writefln("  GET    /api/users/:id     - Get user by ID");
    writefln("  POST   /api/users         - Create user");
    writefln("  PUT    /api/users/:id     - Full update");
    writefln("  PATCH  /api/users/:id     - Partial update");
    writefln("  DELETE /api/users/:id     - Delete user");
    
    app.listen(8080);
}

// ============================================================================
// Helpers
// ============================================================================

JSONValue userToJson(User user)
{
    JSONValue json;
    json["id"] = user.id;
    json["name"] = user.name;
    json["email"] = user.email;
    json["role"] = user.role;
    return json;
}

void seedData()
{
    users[1] = User(1, "Alice Johnson", "alice@example.com", "admin");
    users[2] = User(2, "Bob Smith", "bob@example.com", "user");
    users[3] = User(3, "Charlie Brown", "charlie@example.com", "user");
    nextId = 4;
}
