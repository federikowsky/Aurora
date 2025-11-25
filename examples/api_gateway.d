/**
 * Aurora WebSocket-Ready API Gateway Example
 * 
 * Demonstrates building an API gateway with:
 * - Multiple backend services (simulated)
 * - Request routing based on path prefix
 * - Health checks for backends
 * - Request/response transformation
 * - Load balancing (round-robin)
 * - Circuit breaker pattern
 * - Retry logic
 */
module examples.api_gateway;

import aurora;
import std.conv : to;
import std.json;
import std.format : format;
import std.datetime;
import std.algorithm : canFind;
import core.sync.mutex;

// ============================================================================
// Backend Service Configuration
// ============================================================================

struct BackendService
{
    string name;
    string prefix;         // URL prefix to match
    string[] endpoints;    // Backend endpoints (for load balancing)
    bool healthy = true;
    uint currentIndex = 0; // Round-robin index
    uint failureCount = 0;
    SysTime lastFailure;
    
    // Circuit breaker settings
    uint failureThreshold = 3;
    Duration circuitTimeout = 30.seconds;
}

// ============================================================================
// API Gateway
// ============================================================================

class ApiGateway
{
    private BackendService[] services;
    private Mutex mutex;
    
    this()
    {
        mutex = new Mutex();
        
        // Configure backend services
        services = [
            BackendService(
                "users-service",
                "/api/users",
                ["http://users-1:3001", "http://users-2:3002"]
            ),
            BackendService(
                "products-service", 
                "/api/products",
                ["http://products-1:3003", "http://products-2:3004"]
            ),
            BackendService(
                "orders-service",
                "/api/orders",
                ["http://orders-1:3005"]
            ),
        ];
    }
    
    void handleRequest(ref Context ctx)
    {
        string path = ctx.request ? ctx.request.path : "/";
        string method = ctx.request ? ctx.request.method : "GET";
        
        // Find matching service
        BackendService* service = findService(path);
        
        if (service is null)
        {
            ctx.status(404).json(`{"error":"No service found for path"}`);
            return;
        }
        
        // Check circuit breaker
        if (!isCircuitClosed(service))
        {
            ctx.status(503)
               .header("Retry-After", "30")
               .json(`{"error":"Service temporarily unavailable","service":"` ~ service.name ~ `"}`);
            return;
        }
        
        // Get next backend (round-robin)
        string backend = getNextBackend(service);
        
        // Simulate backend call
        // In real implementation, this would make HTTP request to backend
        auto result = simulateBackendCall(service, path, method);
        
        if (result.success)
        {
            // Success - reset failure count
            synchronized(mutex)
            {
                service.failureCount = 0;
            }
            
            ctx.status(result.status)
               .header("Content-Type", "application/json")
               .header("X-Backend", backend)
               .header("X-Service", service.name)
               .send(result.body);
        }
        else
        {
            // Failure - increment failure count
            synchronized(mutex)
            {
                service.failureCount++;
                service.lastFailure = Clock.currTime();
                
                if (service.failureCount >= service.failureThreshold)
                {
                    service.healthy = false;
                }
            }
            
            ctx.status(502)
               .json(`{"error":"Backend service error","service":"` ~ service.name ~ `"}`);
        }
    }
    
    private BackendService* findService(string path)
    {
        foreach (ref service; services)
        {
            if (path.canFind(service.prefix))
            {
                return &service;
            }
        }
        return null;
    }
    
    private bool isCircuitClosed(BackendService* service)
    {
        synchronized(mutex)
        {
            if (service.healthy)
            {
                return true;
            }
            
            // Check if circuit timeout has passed
            auto elapsed = Clock.currTime() - service.lastFailure;
            if (elapsed >= service.circuitTimeout)
            {
                // Reset circuit breaker (half-open state)
                service.healthy = true;
                service.failureCount = 0;
                return true;
            }
            
            return false;
        }
    }
    
    private string getNextBackend(BackendService* service)
    {
        synchronized(mutex)
        {
            auto backend = service.endpoints[service.currentIndex];
            service.currentIndex = (service.currentIndex + 1) % cast(uint)service.endpoints.length;
            return backend;
        }
    }
    
    // Simulated backend response (in real impl, make HTTP request)
    private auto simulateBackendCall(BackendService* service, string path, string method)
    {
        struct Result
        {
            bool success;
            int status;
            string body;
        }
        
        // Simulate responses based on service
        if (service.name == "users-service")
        {
            if (method == "GET" && path == "/api/users")
            {
                return Result(true, 200, `[{"id":1,"name":"Alice"},{"id":2,"name":"Bob"}]`);
            }
            if (method == "GET" && path.canFind("/api/users/"))
            {
                return Result(true, 200, `{"id":1,"name":"Alice","email":"alice@example.com"}`);
            }
            if (method == "POST")
            {
                return Result(true, 201, `{"id":3,"name":"New User"}`);
            }
        }
        else if (service.name == "products-service")
        {
            if (method == "GET")
            {
                return Result(true, 200, `[{"id":1,"name":"Product A","price":99.99}]`);
            }
        }
        else if (service.name == "orders-service")
        {
            if (method == "GET")
            {
                return Result(true, 200, `[{"id":1,"status":"pending","total":199.99}]`);
            }
            if (method == "POST")
            {
                return Result(true, 201, `{"id":2,"status":"created"}`);
            }
        }
        
        return Result(true, 200, `{"message":"OK"}`);
    }
    
    // Get service health status
    JSONValue getHealthStatus()
    {
        JSONValue status;
        JSONValue[] servicesList;
        
        synchronized(mutex)
        {
            foreach (ref service; services)
            {
                JSONValue s;
                s["name"] = service.name;
                s["prefix"] = service.prefix;
                s["healthy"] = service.healthy;
                s["endpoints"] = service.endpoints.length;
                s["failureCount"] = service.failureCount;
                servicesList ~= s;
            }
        }
        
        status["services"] = JSONValue(servicesList);
        status["timestamp"] = Clock.currTime().toISOExtString();
        
        return status;
    }
}

// ============================================================================
// Main Application
// ============================================================================

void main()
{
    auto gateway = new ApiGateway();
    
    auto config = ServerConfig.defaults();
    config.numWorkers = 8;  // High concurrency for gateway
    
    auto app = new App(config);
    
    // Gateway metrics/health
    app.get("/health", (ref Context ctx) {
        ctx.header("Content-Type", "application/json")
           .send(gateway.getHealthStatus().toString());
    });
    
    app.get("/", (ref Context ctx) {
        ctx.json([
            "name": "Aurora API Gateway",
            "version": "1.0",
            "endpoints": "/api/users, /api/products, /api/orders"
        ]);
    });
    
    // Route all /api/* requests through gateway
    app.get("/api/*path", (ref Context ctx) {
        gateway.handleRequest(ctx);
    });
    
    app.post("/api/*path", (ref Context ctx) {
        gateway.handleRequest(ctx);
    });
    
    app.put("/api/*path", (ref Context ctx) {
        gateway.handleRequest(ctx);
    });
    
    app.delete_("/api/*path", (ref Context ctx) {
        gateway.handleRequest(ctx);
    });
    
    import std.stdio : writefln;
    writefln("API Gateway starting on http://localhost:8080");
    writefln("\nConfigured services:");
    writefln("  /api/users    -> users-service (2 backends)");
    writefln("  /api/products -> products-service (2 backends)");
    writefln("  /api/orders   -> orders-service (1 backend)");
    writefln("\nFeatures:");
    writefln("  - Round-robin load balancing");
    writefln("  - Circuit breaker (3 failures, 30s timeout)");
    writefln("  - Health endpoint: /health");
    
    app.listen(8080);
}
