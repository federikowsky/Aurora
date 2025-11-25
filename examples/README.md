# Aurora Framework Examples

This directory contains comprehensive examples demonstrating Aurora's features.

## Examples Overview

| Example | Description | Key Features |
|---------|-------------|--------------|
| `rest_api.d` | Complete REST API | CRUD, JSON, validation, error handling |
| `router_api.d` | Router-based API | Sub-routers, mounting, modular design |
| `decorator_api.d` | **FastAPI-style decorators** | @Get, @Post, auto-registration |
| `middleware_example.d` | Middleware patterns | Auth, rate limiting, logging, error handling |
| `file_server.d` | Static file server | MIME types, caching, directory listing |
| `api_gateway.d` | API Gateway | Load balancing, circuit breaker, routing |
| `microservice.d` | Microservice template | Health checks, metrics, graceful shutdown |

---

## 1. REST API (`rest_api.d`)

A complete CRUD REST API using the fluent `app.METHOD()` style.

```bash
# Build and run
ldc2 -O3 -I../source -I../lib/wire/source rest_api.d \
    $(find ../source -name '*.d') ../lib/wire/build/libwire.a -of=rest_api
./rest_api
```

**Test commands:**
```bash
# List users
curl http://localhost:8080/api/users

# Get single user
curl http://localhost:8080/api/users/1

# Create user
curl -X POST http://localhost:8080/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"David","email":"david@example.com"}'

# Update user
curl -X PUT http://localhost:8080/api/users/1 \
  -H "Content-Type: application/json" \
  -d '{"name":"Alice Updated","email":"alice@new.com","role":"admin"}'

# Partial update
curl -X PATCH http://localhost:8080/api/users/1 \
  -H "Content-Type: application/json" \
  -d '{"role":"superadmin"}'

# Delete user
curl -X DELETE http://localhost:8080/api/users/1
```

---

## 2. Decorator-Based API (`decorator_api.d`) - FastAPI Style!

The cleanest way to define routes - using UDA (User Defined Attributes) decorators:

```d
import aurora;
import aurora.web.decorators;

// Simply decorate your handlers - no manual registration!
@Get("/users")
void listUsers(ref Context ctx) {
    ctx.json(getAllUsers());
}

@Get("/users/:id")
void getUser(ref Context ctx) {
    auto id = ctx.params.get("id");
    ctx.json(findUser(id));
}

@Post("/users")
void createUser(ref Context ctx) {
    auto body = parseJSON(ctx.request.body);
    ctx.status(201).json(createNewUser(body));
}

@Put("/users/:id")
void updateUser(ref Context ctx) { /* ... */ }

@Patch("/users/:id")  
void patchUser(ref Context ctx) { /* ... */ }

@Delete("/users/:id")
void deleteUser(ref Context ctx) { /* ... */ }

void main() {
    auto router = new Router();
    
    // This single line auto-registers ALL decorated handlers!
    router.autoRegister!(examples.decorator_api)();
    
    auto app = new App();
    app.includeRouter(router);
    app.listen(8080);
}
```

**Available decorators:**
- `@Get("/path")` - GET requests
- `@Post("/path")` - POST requests  
- `@Put("/path")` - PUT requests
- `@Patch("/path")` - PATCH requests
- `@Delete("/path")` - DELETE requests

**Build and run:**
```bash
ldc2 -O2 decorator_api.d -I../source -I../lib/wire/source \
    ../build/libaurora.a ../lib/wire/build/libwire.a -of=decorator_api
./decorator_api
```

**Test:**
```bash
curl http://localhost:8080/tasks
curl -X POST http://localhost:8080/tasks -d '{"title":"New Task"}'
curl -X PATCH http://localhost:8080/tasks/1/toggle
```

---

## 3. Router-Based API (`router_api.d`)

Demonstrates modular API design with sub-routers.

```d
// Create sub-router for products
Router createProductRouter() {
    auto router = new Router();
    router.get("/", (ref Context ctx) { /* list */ });
    router.get("/:id", (ref Context ctx) { /* get one */ });
    router.post("/", (ref Context ctx) { /* create */ });
    return router;
}

// Mount sub-router with prefix
mainRouter.mount("/api/v1/products", productRouter);
```

**Endpoints:**
- `GET /api/v1/products` - List products
- `GET /api/v1/products/:id` - Get product
- `GET /api/v1/products/category/:category` - Filter by category
- `POST /api/v1/products` - Create product
- `GET /api/v1/orders` - List orders
- `POST /api/v1/orders` - Create order

---

## 4. Middleware Pipeline (`middleware_example.d`)

Shows how to build and chain middleware.

```d
// Middleware stack (order matters!)
app.use(requestIdMiddleware());        // 1. Add request ID
app.use(responseTimeMiddleware());     // 2. Measure response time
app.use(new ErrorHandler());           // 3. Catch errors
app.use(new RequestLogger());          // 4. Log requests
app.use(new RateLimiter(100, 60.seconds)); // 5. Rate limit
app.use(new AuthMiddleware());         // 6. Authentication
```

**Custom middleware example:**
```d
class AuthMiddleware {
    void handle(ref Context ctx, NextFunction next) {
        string token = ctx.request.getHeader("Authorization");
        
        if (isValidToken(token)) {
            ctx.storage.set("user", userData);
            next();  // Continue chain
        } else {
            ctx.status(401).json(`{"error":"Unauthorized"}`);
            // Don't call next() - stops chain
        }
    }
}
```

---

## 5. Static File Server (`file_server.d`)

Full-featured file server with caching.

```bash
# Serve current directory
./file_server

# Serve specific directory
./file_server --root=/var/www/html --port=8080

# Disable directory listing
./file_server --no-listing
```

**Features:**
- MIME type detection (40+ types)
- ETag and Last-Modified headers
- 304 Not Modified responses
- Cache-Control headers
- Directory listing with HTML UI
- Path traversal protection

---

## 6. API Gateway (`api_gateway.d`)

Microservices gateway with load balancing.

```d
// Configure backend services
services = [
    BackendService("users-service", "/api/users", 
        ["http://users-1:3001", "http://users-2:3002"]),
    BackendService("products-service", "/api/products",
        ["http://products-1:3003"]),
];
```

**Features:**
- Round-robin load balancing
- Circuit breaker (3 failures → open, 30s timeout)
- Health monitoring
- Request routing by path prefix

---

## 7. Microservice Template (`microservice.d`)

Production-ready microservice structure.

```bash
# Run with environment variables
SERVICE_NAME=my-service \
SERVICE_VERSION=2.0.0 \
PORT=3000 \
WORKERS=8 \
./microservice
```

**Endpoints:**
- `GET /health` - Combined health check
- `GET /health/live` - Kubernetes liveness probe
- `GET /health/ready` - Kubernetes readiness probe
- `GET /metrics` - Prometheus-compatible metrics

**Metrics output:**
```json
{
  "uptime_seconds": 3600,
  "total_requests": 150000,
  "total_errors": 12,
  "error_rate": 0.008,
  "avg_latency_ms": 0.45,
  "requests_per_second": 41.67
}
```

---

## Quick Build All Examples

```bash
cd examples

# Build all
for f in *.d; do
  echo "Building $f..."
  ldc2 -O3 -I../source -I../lib/wire/source "$f" \
    $(find ../source -name '*.d') \
    ../lib/wire/build/libwire.a \
    -of="${f%.d}"
done
```

## See Also

- `tests/realworld/` - Stress tests and benchmarks
- `source/aurora/` - Framework source code
- `docs/` - API documentation
