/**
 * Aurora Router-Based API Example
 * 
 * Demonstrates building APIs using Router with UDA (User-Defined Attributes)
 * and modular sub-routers.
 * 
 * Features:
 * - Sub-routers for API versioning
 * - Grouped routes by resource
 * - Route middleware per-router
 * - Router composition
 */
module examples.router_api;

import aurora;
import std.conv : to;
import std.json;
import std.format : format;

// ============================================================================
// Data Models
// ============================================================================

struct Product
{
    int id;
    string name;
    string category;
    double price;
    int stock;
}

struct Order
{
    int id;
    int[] productIds;
    string status;
    double total;
}

// In-memory storage
__gshared Product[int] products;
__gshared Order[int] orders;
__gshared int nextProductId = 1;
__gshared int nextOrderId = 1;

// ============================================================================
// Product Routes (Sub-Router)
// ============================================================================

Router createProductRouter()
{
    auto router = new Router();
    
    // GET /products
    router.get("/", (ref Context ctx) {
        JSONValue[] list;
        foreach (p; products.values)
        {
            list ~= productToJson(p);
        }
        ctx.header("Content-Type", "application/json")
           .send(JSONValue(list).toString());
    });
    
    // GET /products/:id
    router.get("/:id", (ref Context ctx) {
        int id;
        try {
            id = ctx.params.get("id", "").to!int;
        } catch (Exception) {
            ctx.status(400).json(`{"error":"Invalid product ID"}`);
            return;
        }
        
        if (auto p = id in products)
        {
            ctx.header("Content-Type", "application/json")
               .send(productToJson(*p).toString());
        }
        else
        {
            ctx.status(404).json(`{"error":"Product not found"}`);
        }
    });
    
    // GET /products/category/:category
    router.get("/category/:category", (ref Context ctx) {
        auto category = ctx.params.get("category", "");
        
        JSONValue[] filtered;
        foreach (p; products.values)
        {
            if (p.category == category)
            {
                filtered ~= productToJson(p);
            }
        }
        
        ctx.header("Content-Type", "application/json")
           .send(JSONValue(filtered).toString());
    });
    
    // POST /products
    router.post("/", (ref Context ctx) {
        try
        {
            auto bodyStr = ctx.request ? cast(string)ctx.request.body : "";
            auto json = parseJSON(bodyStr);
            
            auto product = Product(
                nextProductId++,
                json["name"].str,
                ("category" in json) ? json["category"].str : "general",
                json["price"].floating,
                ("stock" in json) ? cast(int)json["stock"].integer : 0
            );
            
            products[product.id] = product;
            
            ctx.status(201)
               .header("Content-Type", "application/json")
               .send(productToJson(product).toString());
        }
        catch (Exception e)
        {
            ctx.status(400).json(`{"error":"Invalid product data"}`);
        }
    });
    
    // PUT /products/:id
    router.put("/:id", (ref Context ctx) {
        int id;
        try {
            id = ctx.params.get("id", "").to!int;
        } catch (Exception) {
            ctx.status(400).json(`{"error":"Invalid product ID"}`);
            return;
        }
        
        if (id !in products)
        {
            ctx.status(404).json(`{"error":"Product not found"}`);
            return;
        }
        
        try
        {
            auto bodyStr = ctx.request ? cast(string)ctx.request.body : "";
            auto json = parseJSON(bodyStr);
            
            products[id] = Product(
                id,
                json["name"].str,
                json["category"].str,
                json["price"].floating,
                cast(int)json["stock"].integer
            );
            
            ctx.header("Content-Type", "application/json")
               .send(productToJson(products[id]).toString());
        }
        catch (Exception e)
        {
            ctx.status(400).json(`{"error":"Invalid product data"}`);
        }
    });
    
    // DELETE /products/:id
    router.delete_("/:id", (ref Context ctx) {
        int id;
        try {
            id = ctx.params.get("id", "").to!int;
        } catch (Exception) {
            ctx.status(400).json(`{"error":"Invalid product ID"}`);
            return;
        }
        
        if (id in products)
        {
            products.remove(id);
            ctx.status(204).send("");
        }
        else
        {
            ctx.status(404).json(`{"error":"Product not found"}`);
        }
    });
    
    return router;
}

// ============================================================================
// Order Routes (Sub-Router)
// ============================================================================

Router createOrderRouter()
{
    auto router = new Router();
    
    // GET /orders
    router.get("/", (ref Context ctx) {
        JSONValue[] list;
        foreach (o; orders.values)
        {
            list ~= orderToJson(o);
        }
        ctx.header("Content-Type", "application/json")
           .send(JSONValue(list).toString());
    });
    
    // GET /orders/:id
    router.get("/:id", (ref Context ctx) {
        int id;
        try {
            id = ctx.params.get("id", "").to!int;
        } catch (Exception) {
            ctx.status(400).json(`{"error":"Invalid order ID"}`);
            return;
        }
        
        if (auto o = id in orders)
        {
            ctx.header("Content-Type", "application/json")
               .send(orderToJson(*o).toString());
        }
        else
        {
            ctx.status(404).json(`{"error":"Order not found"}`);
        }
    });
    
    // POST /orders
    router.post("/", (ref Context ctx) {
        try
        {
            auto bodyStr = ctx.request ? cast(string)ctx.request.body : "";
            auto json = parseJSON(bodyStr);
            
            // Parse product IDs
            int[] productIds;
            foreach (item; json["products"].array)
            {
                productIds ~= cast(int)item.integer;
            }
            
            // Calculate total
            double total = 0;
            foreach (pid; productIds)
            {
                if (auto p = pid in products)
                {
                    total += p.price;
                }
            }
            
            auto order = Order(
                nextOrderId++,
                productIds,
                "pending",
                total
            );
            
            orders[order.id] = order;
            
            ctx.status(201)
               .header("Content-Type", "application/json")
               .send(orderToJson(order).toString());
        }
        catch (Exception e)
        {
            ctx.status(400).json(`{"error":"Invalid order data"}`);
        }
    });
    
    // PATCH /orders/:id/status
    router.patch("/:id/status", (ref Context ctx) {
        int id;
        try {
            id = ctx.params.get("id", "").to!int;
        } catch (Exception) {
            ctx.status(400).json(`{"error":"Invalid order ID"}`);
            return;
        }
        
        if (auto o = id in orders)
        {
            try
            {
                auto bodyStr = ctx.request ? cast(string)ctx.request.body : "";
                auto json = parseJSON(bodyStr);
                o.status = json["status"].str;
                
                ctx.header("Content-Type", "application/json")
                   .send(orderToJson(*o).toString());
            }
            catch (Exception)
            {
                ctx.status(400).json(`{"error":"Invalid status"}`);
            }
        }
        else
        {
            ctx.status(404).json(`{"error":"Order not found"}`);
        }
    });
    
    return router;
}

// ============================================================================
// Main Application
// ============================================================================

void main()
{
    // Seed data
    seedData();
    
    // Create main router
    auto mainRouter = new Router();
    
    // Mount sub-routers with prefixes
    auto productRouter = createProductRouter();
    auto orderRouter = createOrderRouter();
    
    // API v1 routes
    mainRouter.mount("/api/v1/products", productRouter);
    mainRouter.mount("/api/v1/orders", orderRouter);
    
    // Root routes
    mainRouter.get("/", (ref Context ctx) {
        ctx.json(["message": "Welcome to Aurora Shop API", "version": "1.0"]);
    });
    
    mainRouter.get("/health", (ref Context ctx) {
        ctx.json([
            "status": "healthy",
            "products": products.length.to!string,
            "orders": orders.length.to!string
        ]);
    });
    
    // Stats endpoint
    mainRouter.get("/api/v1/stats", (ref Context ctx) {
        double totalRevenue = 0;
        foreach (o; orders.values)
        {
            if (o.status == "completed")
            {
                totalRevenue += o.total;
            }
        }
        
        JSONValue stats;
        stats["totalProducts"] = products.length;
        stats["totalOrders"] = orders.length;
        stats["totalRevenue"] = totalRevenue;
        
        ctx.header("Content-Type", "application/json")
           .send(stats.toString());
    });
    
    // Create app with router
    auto config = ServerConfig.defaults();
    config.numWorkers = 4;
    
    auto app = new App(config);
    app.includeRouter(mainRouter);
    
    // Add CORS
    app.use(new CORSMiddleware(CORSConfig()));
    
    import std.stdio : writefln;
    writefln("Shop API starting on http://localhost:8080");
    writefln("\nEndpoints:");
    writefln("  Products: /api/v1/products[/:id][/category/:category]");
    writefln("  Orders:   /api/v1/orders[/:id][/:id/status]");
    writefln("  Stats:    /api/v1/stats");
    
    app.listen(8080);
}

// ============================================================================
// Helpers
// ============================================================================

JSONValue productToJson(Product p)
{
    JSONValue json;
    json["id"] = p.id;
    json["name"] = p.name;
    json["category"] = p.category;
    json["price"] = p.price;
    json["stock"] = p.stock;
    return json;
}

JSONValue orderToJson(Order o)
{
    JSONValue json;
    json["id"] = o.id;
    json["products"] = JSONValue(o.productIds);
    json["status"] = o.status;
    json["total"] = o.total;
    return json;
}

void seedData()
{
    products[1] = Product(1, "Laptop", "electronics", 999.99, 50);
    products[2] = Product(2, "Mouse", "electronics", 29.99, 200);
    products[3] = Product(3, "Keyboard", "electronics", 79.99, 100);
    products[4] = Product(4, "Monitor", "electronics", 299.99, 30);
    products[5] = Product(5, "Headphones", "audio", 149.99, 75);
    nextProductId = 6;
    
    orders[1] = Order(1, [1, 2], "completed", 1029.98);
    orders[2] = Order(2, [3, 4, 5], "pending", 529.97);
    nextOrderId = 3;
}
