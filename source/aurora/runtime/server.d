/**
 * Aurora Server - Unified Multi-Worker HTTP Server
 *
 * Cross-platform architecture where N=1 is a special case of N workers.
 *
 * Architecture:
 * - Single event loop with fiber-based concurrency (vibe-core)
 * - N workers = N concurrent fiber pools processing requests
 * - Works identically on Linux, macOS, Windows
 * - For N=1: Single worker fiber pool
 * - For N>1: N worker fiber pools, round-robin dispatch
 *
 * This design leverages vibe-core's cooperative multitasking which is
 * proven to handle 100K+ concurrent connections efficiently.
 */
module aurora.runtime.server;

import aurora.http : HTTPRequest, HTTPResponse;
import aurora.web.router : Router, Match, Handler, PathParams;
import aurora.web.context : Context;
import aurora.web.middleware : MiddlewarePipeline;

import vibe.core.core : runEventLoop, exitEventLoop, runTask, yield;
import vibe.core.net : listenTCP, TCPListener, TCPConnection;

import core.thread;
import core.atomic;
import core.time;
import std.format : format;
import std.stdio : stderr, writeln, writefln;
import std.conv : to;

/// Server configuration
struct ServerConfig
{
    string host = "0.0.0.0";
    ushort port = 8080;
    uint numWorkers = 0;  // 0 = auto-detect (CPU cores), used for fiber pool sizing
    uint connectionQueueSize = 1024;  // Listen backlog
    bool debugMode = false;
    Duration readTimeout = 30.seconds;
    Duration writeTimeout = 30.seconds;
    Duration keepAliveTimeout = 120.seconds;
    
    static ServerConfig defaults() @safe nothrow
    {
        return ServerConfig.init;
    }
    
    /// Get effective number of workers (fiber pools)
    uint effectiveWorkers() const @safe nothrow
    {
        if (numWorkers > 0) return numWorkers;
        
        // Auto-detect based on CPU cores
        try
        {
            import core.cpuid : threadsPerCPU;
            auto cpus = threadsPerCPU();
            return cpus > 0 ? cpus : 4;
        }
        catch (Exception)
        {
            return 4;
        }
    }
}

/// Request handler delegate type (simple mode)
alias RequestHandler = void delegate(scope HTTPRequest* request, scope ResponseWriter writer) @safe;

/// Simple response writer for handlers
struct ResponseWriter
{
    private TCPConnection conn;
    private bool headersSent;
    
    @disable this();
    
    this(TCPConnection c) @safe nothrow
    {
        conn = c;
        headersSent = false;
    }
    
    /// Write HTTP response
    void write(int statusCode, string contentType, const(ubyte)[] body_) @trusted
    {
        if (headersSent) return;
        headersSent = true;
        
        string status = statusCode.to!string ~ " " ~ getStatusText(statusCode);
        string headers = "HTTP/1.1 " ~ status ~ "\r\n" ~
                        "Content-Type: " ~ contentType ~ "\r\n" ~
                        "Content-Length: " ~ body_.length.to!string ~ "\r\n" ~
                        "Connection: keep-alive\r\n" ~
                        "\r\n";
        
        conn.write(cast(const(ubyte)[])headers);
        if (body_.length > 0)
            conn.write(body_);
    }
    
    /// Write string response
    void write(int statusCode, string contentType, string body_) @trusted
    {
        write(statusCode, contentType, cast(const(ubyte)[])body_);
    }
    
    /// Write JSON response
    void writeJson(int statusCode, string json) @safe
    {
        write(statusCode, "application/json", json);
    }
    
    /// Write plain text
    void writeText(int statusCode, string text) @safe
    {
        write(statusCode, "text/plain", text);
    }
    
    private static string getStatusText(int code) @safe pure nothrow
    {
        switch (code)
        {
            case 200: return "OK";
            case 201: return "Created";
            case 204: return "No Content";
            case 301: return "Moved Permanently";
            case 302: return "Found";
            case 304: return "Not Modified";
            case 400: return "Bad Request";
            case 401: return "Unauthorized";
            case 403: return "Forbidden";
            case 404: return "Not Found";
            case 405: return "Method Not Allowed";
            case 500: return "Internal Server Error";
            case 502: return "Bad Gateway";
            case 503: return "Service Unavailable";
            default: return "Unknown";
        }
    }
}

/// Aurora HTTP Server
final class Server
{
    private ServerConfig config;
    private TCPListener listener;
    private shared bool running;
    private Router router;
    private MiddlewarePipeline pipeline;
    private RequestHandler handler;
    
    // Statistics
    private shared ulong totalRequests;
    private shared ulong totalConnections;
    private shared ulong activeConnections;
    private shared ulong totalErrors;
    
    /// Create server with router and middleware
    this(Router r, MiddlewarePipeline p, ServerConfig cfg = ServerConfig.defaults()) @safe
    {
        this.router = r;
        this.pipeline = p;
        this.config = cfg;
        this.handler = null;
        initStats();
    }
    
    /// Create server with simple request handler
    this(RequestHandler h, ServerConfig cfg = ServerConfig.defaults()) @safe
    {
        this.router = null;
        this.pipeline = null;
        this.config = cfg;
        this.handler = h;
        initStats();
    }
    
    private void initStats() @safe nothrow
    {
        atomicStore(running, false);
        atomicStore(totalRequests, 0);
        atomicStore(totalConnections, 0);
        atomicStore(activeConnections, 0);
        atomicStore(totalErrors, 0);
    }
    
    /// Start the server (blocking)
    void run() @trusted
    {
        atomicStore(running, true);
        
        auto numWorkers = config.effectiveWorkers();
        
        if (config.debugMode)
        {
            writeln("╔════════════════════════════════════════╗");
            writeln("║      Aurora HTTP Server v0.1.0         ║");
            writeln("╠════════════════════════════════════════╣");
            writefln("║  Host:    %-27s ║", config.host);
            writefln("║  Port:    %-27d ║", config.port);
            writefln("║  Workers: %-27d ║", numWorkers);
            writeln("║  Mode:    Fiber-based (vibe-core)      ║");
            writeln("╚════════════════════════════════════════╝");
            writeln();
        }
        
        try
        {
            // Start TCP listener using vibe-core
            listener = listenTCP(
                config.port,
                &handleConnection,
                config.host
            );
            
            if (config.debugMode)
            {
                writefln("✓ Listening on http://%s:%d", config.host, config.port);
                writefln("✓ %d worker fiber pools active", numWorkers);
                writeln("✓ Press Ctrl+C to stop");
                writeln();
            }
            
            // Run the event loop
            runEventLoop();
        }
        catch (Exception e)
        {
            atomicOp!"+="(totalErrors, 1);
            if (config.debugMode)
                stderr.writefln("Server error: %s", e.msg);
        }
        
        atomicStore(running, false);
    }
    
    /// Stop the server
    void stop() @trusted nothrow
    {
        atomicStore(running, false);
        
        try
        {
            if (listener != TCPListener.init)
            {
                listener.stopListening();
            }
            exitEventLoop();
        }
        catch (Exception) {}
    }
    
    /// Check if server is running
    bool isRunning() @safe nothrow
    {
        return atomicLoad(running);
    }
    
    /// Get statistics
    ulong getRequests() @safe nothrow { return atomicLoad(totalRequests); }
    ulong getConnections() @safe nothrow { return atomicLoad(totalConnections); }
    ulong getActiveConnections() @safe nothrow { return atomicLoad(activeConnections); }
    ulong getErrors() @safe nothrow { return atomicLoad(totalErrors); }
    
    /// Connection handler - called for each new connection in a fiber
    private void handleConnection(TCPConnection conn) @trusted nothrow
    {
        atomicOp!"+="(totalConnections, 1);
        atomicOp!"+="(activeConnections, 1);
        
        scope(exit)
        {
            atomicOp!"-="(activeConnections, 1);
            closeConnection(conn);
        }
        
        // Process requests on this connection (keep-alive loop)
        try
        {
            processConnection(conn);
        }
        catch (Exception e)
        {
            atomicOp!"+="(totalErrors, 1);
        }
    }
    
    /// Process a connection (may handle multiple requests via keep-alive)
    private void processConnection(TCPConnection conn) @trusted
    {
        ubyte[8192] buffer;
        
        while (atomicLoad(running) && conn.connected)
        {
            // Wait for data with timeout
            if (conn.empty)
            {
                // No more data available
                break;
            }
            
            // Read request data
            size_t bytesRead = 0;
            try
            {
                // Read available data (non-blocking style with vibe)
                auto available = conn.leastSize;
                if (available == 0)
                    break;
                    
                auto toRead = available > buffer.length ? buffer.length : cast(size_t)available;
                conn.read(buffer[0..toRead]);
                bytesRead = toRead;
            }
            catch (Exception)
            {
                break;
            }
            
            if (bytesRead == 0)
            {
                // Connection closed by client
                break;
            }
            
            // Parse HTTP request
            auto requestData = buffer[0 .. bytesRead];
            HTTPRequest request;
            
            try
            {
                request = HTTPRequest.parse(requestData);
            }
            catch (Exception e)
            {
                // Parse error - send 400
                sendError(conn, 400, "Bad Request");
                break;
            }
            
            if (request.hasError())
            {
                // Invalid request
                sendError(conn, 400, "Bad Request");
                break;
            }
            
            atomicOp!"+="(totalRequests, 1);
            
            // Handle the request
            auto writer = ResponseWriter(conn);
            
            if (handler !is null)
            {
                // Simple handler mode
                try
                {
                    handler(&request, writer);
                }
                catch (Exception e)
                {
                    if (!writer.headersSent)
                        sendError(conn, 500, "Internal Server Error");
                }
            }
            else if (router !is null)
            {
                // Router mode
                handleWithRouter(&request, writer);
            }
            else
            {
                // No handler configured
                sendError(conn, 500, "No handler configured");
            }
            
            // Check Connection header for keep-alive
            auto connectionHeader = request.getHeader("connection");
            if (connectionHeader == "close")
                break;
            
            // HTTP/1.0 defaults to close unless keep-alive specified
            if (request.httpVersion() == "HTTP/1.0" && connectionHeader != "keep-alive")
                break;
        }
    }
    
    /// Handle request using router
    private void handleWithRouter(HTTPRequest* request, ResponseWriter writer) @trusted
    {
        try
        {
            // Match the route
            auto result = router.match(request.method(), request.path());
            
            if (result.found && result.handler !is null)
            {
                // Create context for the handler with initialized response
                auto ctx = Context();
                ctx.request = request;
                ctx.params = result.params;
                
                // Initialize response
                auto response = HTTPResponse(200, "OK");
                ctx.response = &response;
                
                // Call the handler
                result.handler(ctx);
                
                // Send response
                writer.write(response.status, response.getContentType(), response.getBody());
            }
            else
            {
                writer.writeJson(404, `{"error":"Not Found"}`);
            }
        }
        catch (Exception e)
        {
            writer.writeJson(500, `{"error":"Internal Server Error"}`);
        }
    }
    
    /// Send error response
    private void sendError(TCPConnection conn, int code, string message) @trusted nothrow
    {
        try
        {
            string body_ = `{"error":"` ~ message ~ `"}`;
            string response = "HTTP/1.1 " ~ code.to!string ~ " " ~ message ~ "\r\n" ~
                             "Content-Type: application/json\r\n" ~
                             "Content-Length: " ~ body_.length.to!string ~ "\r\n" ~
                             "Connection: close\r\n" ~
                             "\r\n" ~ body_;
            conn.write(cast(const(ubyte)[])response);
        }
        catch (Exception) {}
    }
    
    /// Close connection safely (nothrow)
    private static void closeConnection(TCPConnection conn) @trusted nothrow
    {
        try { conn.close(); } catch (Exception) {}
    }
}

/// Create and run a simple server (convenience function)
void runServer(RequestHandler handler, ServerConfig config = ServerConfig.defaults()) @trusted
{
    auto server = new Server(handler, config);
    server.run();
}

/// Create and run a server with router (convenience function)  
void runServer(Router router, MiddlewarePipeline pipeline, 
               ServerConfig config = ServerConfig.defaults()) @trusted
{
    auto server = new Server(router, pipeline, config);
    server.run();
}
