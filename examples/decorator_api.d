/**
 * Aurora Decorator-Based API Example (FastAPI Style)
 * 
 * Demonstrates route registration using UDA (User Defined Attributes)
 * similar to Python's FastAPI or Flask decorators.
 * 
 * Features:
 * - @Get, @Post, @Put, @Delete, @Patch decorators
 * - Auto-registration of handlers
 * - Clean, declarative route definitions
 * - No manual router.get() calls needed
 */
module examples.decorator_api;

import aurora;
import aurora.web.decorators;  // Import @Get, @Post, etc.
import std.conv : to;
import std.json;

// ============================================================================
// Data Store (simulated database)
// ============================================================================

struct Task
{
    int id;
    string title;
    string description;
    bool completed;
    string priority;  // low, medium, high
}

__gshared Task[int] tasks;
__gshared int nextTaskId = 1;

// ============================================================================
// Route Handlers with Decorators (FastAPI Style!)
// ============================================================================

/**
 * GET / - API Root
 */
@Get("/")
void index(ref Context ctx)
{
    ctx.json([
        "name": "Aurora Task API",
        "version": "1.0",
        "style": "decorator-based (like FastAPI)"
    ]);
}

/**
 * GET /health - Health check
 */
@Get("/health")
void healthCheck(ref Context ctx)
{
    ctx.json(`{"status":"healthy","tasks":` ~ tasks.length.to!string ~ `}`);
}

/**
 * GET /tasks - List all tasks
 */
@Get("/tasks")
void listTasks(ref Context ctx)
{
    JSONValue[] taskList;
    foreach (task; tasks.values)
    {
        taskList ~= taskToJson(task);
    }
    
    ctx.header("Content-Type", "application/json")
       .send(JSONValue(taskList).toString());
}

/**
 * GET /tasks/:id - Get single task
 */
@Get("/tasks/:id")
void getTask(ref Context ctx)
{
    int id;
    try {
        id = ctx.params.get("id", "").to!int;
    } catch (Exception) {
        ctx.status(400).json(`{"error":"Invalid task ID"}`);
        return;
    }
    
    if (auto task = id in tasks)
    {
        ctx.header("Content-Type", "application/json")
           .send(taskToJson(*task).toString());
    }
    else
    {
        ctx.status(404).json(`{"error":"Task not found"}`);
    }
}

/**
 * POST /tasks - Create new task
 */
@Post("/tasks")
void createTask(ref Context ctx)
{
    try
    {
        auto bodyStr = ctx.request ? cast(string)ctx.request.body : "";
        if (bodyStr.length == 0)
        {
            ctx.status(400).json(`{"error":"Request body is empty"}`);
            return;
        }
        
        auto json = parseJSON(bodyStr);
        
        // Validate required field
        if ("title" !in json)
        {
            ctx.status(400).json(`{"error":"Missing required field: title"}`);
            return;
        }
        
        auto task = Task(
            nextTaskId++,
            json["title"].str,
            ("description" in json) ? json["description"].str : "",
            false,
            ("priority" in json) ? json["priority"].str : "medium"
        );
        
        tasks[task.id] = task;
        
        ctx.status(201)
           .header("Content-Type", "application/json")
           .header("Location", "/tasks/" ~ task.id.to!string)
           .send(taskToJson(task).toString());
    }
    catch (JSONException e)
    {
        ctx.status(400).json(`{"error":"Invalid JSON"}`);
    }
}

/**
 * PUT /tasks/:id - Full update task
 */
@Put("/tasks/:id")
void updateTask(ref Context ctx)
{
    int id;
    try {
        id = ctx.params.get("id", "").to!int;
    } catch (Exception) {
        ctx.status(400).json(`{"error":"Invalid task ID"}`);
        return;
    }
    
    if (id !in tasks)
    {
        ctx.status(404).json(`{"error":"Task not found"}`);
        return;
    }
    
    try
    {
        auto bodyStr = ctx.request ? cast(string)ctx.request.body : "";
        auto json = parseJSON(bodyStr);
        
        tasks[id] = Task(
            id,
            json["title"].str,
            ("description" in json) ? json["description"].str : "",
            ("completed" in json) ? json["completed"].boolean : false,
            ("priority" in json) ? json["priority"].str : "medium"
        );
        
        ctx.header("Content-Type", "application/json")
           .send(taskToJson(tasks[id]).toString());
    }
    catch (Exception)
    {
        ctx.status(400).json(`{"error":"Invalid request"}`);
    }
}

/**
 * PATCH /tasks/:id - Partial update (toggle completed, etc.)
 */
@Patch("/tasks/:id")
void patchTask(ref Context ctx)
{
    int id;
    try {
        id = ctx.params.get("id", "").to!int;
    } catch (Exception) {
        ctx.status(400).json(`{"error":"Invalid task ID"}`);
        return;
    }
    
    if (auto task = id in tasks)
    {
        try
        {
            auto bodyStr = ctx.request ? cast(string)ctx.request.body : "";
            auto json = parseJSON(bodyStr);
            
            // Update only provided fields
            if ("title" in json) task.title = json["title"].str;
            if ("description" in json) task.description = json["description"].str;
            if ("completed" in json) task.completed = json["completed"].boolean;
            if ("priority" in json) task.priority = json["priority"].str;
            
            ctx.header("Content-Type", "application/json")
               .send(taskToJson(*task).toString());
        }
        catch (Exception)
        {
            ctx.status(400).json(`{"error":"Invalid request"}`);
        }
    }
    else
    {
        ctx.status(404).json(`{"error":"Task not found"}`);
    }
}

/**
 * PATCH /tasks/:id/toggle - Toggle task completion
 */
@Patch("/tasks/:id/toggle")
void toggleTask(ref Context ctx)
{
    int id;
    try {
        id = ctx.params.get("id", "").to!int;
    } catch (Exception) {
        ctx.status(400).json(`{"error":"Invalid task ID"}`);
        return;
    }
    
    if (auto task = id in tasks)
    {
        task.completed = !task.completed;
        ctx.header("Content-Type", "application/json")
           .send(taskToJson(*task).toString());
    }
    else
    {
        ctx.status(404).json(`{"error":"Task not found"}`);
    }
}

/**
 * DELETE /tasks/:id - Delete task
 */
@Delete("/tasks/:id")
void deleteTask(ref Context ctx)
{
    int id;
    try {
        id = ctx.params.get("id", "").to!int;
    } catch (Exception) {
        ctx.status(400).json(`{"error":"Invalid task ID"}`);
        return;
    }
    
    if (id in tasks)
    {
        tasks.remove(id);
        ctx.status(204).send("");
    }
    else
    {
        ctx.status(404).json(`{"error":"Task not found"}`);
    }
}

/**
 * GET /tasks/priority/:level - Filter tasks by priority
 */
@Get("/tasks/priority/:level")
void getTasksByPriority(ref Context ctx)
{
    string priority = ctx.params.get("level", "");
    
    JSONValue[] filtered;
    foreach (task; tasks.values)
    {
        if (task.priority == priority)
        {
            filtered ~= taskToJson(task);
        }
    }
    
    ctx.header("Content-Type", "application/json")
       .send(JSONValue(filtered).toString());
}

/**
 * GET /tasks/completed - Get completed tasks only
 */
@Get("/tasks/completed")
void getCompletedTasks(ref Context ctx)
{
    JSONValue[] completed;
    foreach (task; tasks.values)
    {
        if (task.completed)
        {
            completed ~= taskToJson(task);
        }
    }
    
    ctx.header("Content-Type", "application/json")
       .send(JSONValue(completed).toString());
}

/**
 * GET /tasks/pending - Get pending tasks only
 */
@Get("/tasks/pending")
void getPendingTasks(ref Context ctx)
{
    JSONValue[] pending;
    foreach (task; tasks.values)
    {
        if (!task.completed)
        {
            pending ~= taskToJson(task);
        }
    }
    
    ctx.header("Content-Type", "application/json")
       .send(JSONValue(pending).toString());
}

// ============================================================================
// Helpers
// ============================================================================

JSONValue taskToJson(Task task)
{
    JSONValue json;
    json["id"] = task.id;
    json["title"] = task.title;
    json["description"] = task.description;
    json["completed"] = task.completed;
    json["priority"] = task.priority;
    return json;
}

void seedData()
{
    tasks[1] = Task(1, "Learn Aurora", "Study the Aurora framework", false, "high");
    tasks[2] = Task(2, "Build API", "Create a REST API with decorators", false, "high");
    tasks[3] = Task(3, "Write tests", "Add unit tests", false, "medium");
    tasks[4] = Task(4, "Deploy", "Deploy to production", false, "low");
    nextTaskId = 5;
}

// ============================================================================
// Main Application
// ============================================================================

void main()
{
    // Seed sample data
    seedData();
    
    // Create router and AUTO-REGISTER all decorated handlers!
    auto router = new Router();
    
    // This single line registers ALL @Get, @Post, @Put, @Delete, @Patch handlers
    // defined in this module - just like FastAPI!
    router.autoRegister!(examples.decorator_api)();
    
    // Create app
    auto config = ServerConfig.defaults();
    config.numWorkers = 4;
    
    auto app = new App(config);
    app.includeRouter(router);
    
    // Add middleware
    app.use(new CORSMiddleware(CORSConfig()));
    
    import std.stdio : writefln;
    writefln("╔══════════════════════════════════════════════════════════════╗");
    writefln("║         Aurora Decorator API (FastAPI Style)                  ║");
    writefln("╠══════════════════════════════════════════════════════════════╣");
    writefln("║  Decorators used:                                             ║");
    writefln("║    @Get(\"/path\")    - GET requests                           ║");
    writefln("║    @Post(\"/path\")   - POST requests                          ║");
    writefln("║    @Put(\"/path\")    - PUT requests                           ║");
    writefln("║    @Patch(\"/path\")  - PATCH requests                         ║");
    writefln("║    @Delete(\"/path\") - DELETE requests                        ║");
    writefln("╠══════════════════════════════════════════════════════════════╣");
    writefln("║  Endpoints (auto-registered):                                 ║");
    writefln("║    GET    /                    - API info                     ║");
    writefln("║    GET    /health              - Health check                 ║");
    writefln("║    GET    /tasks               - List all tasks               ║");
    writefln("║    GET    /tasks/:id           - Get single task              ║");
    writefln("║    POST   /tasks               - Create task                  ║");
    writefln("║    PUT    /tasks/:id           - Full update                  ║");
    writefln("║    PATCH  /tasks/:id           - Partial update               ║");
    writefln("║    PATCH  /tasks/:id/toggle    - Toggle completion            ║");
    writefln("║    DELETE /tasks/:id           - Delete task                  ║");
    writefln("║    GET    /tasks/priority/:lvl - Filter by priority           ║");
    writefln("║    GET    /tasks/completed     - Get completed tasks          ║");
    writefln("║    GET    /tasks/pending       - Get pending tasks            ║");
    writefln("╚══════════════════════════════════════════════════════════════╝");
    writefln("");
    writefln("Server starting on http://localhost:8080");
    writefln("");
    writefln("Test commands:");
    writefln("  curl http://localhost:8080/tasks");
    writefln("  curl -X POST http://localhost:8080/tasks -d '{\"title\":\"New task\"}'");
    writefln("  curl -X PATCH http://localhost:8080/tasks/1/toggle");
    
    app.listen(8080);
}
