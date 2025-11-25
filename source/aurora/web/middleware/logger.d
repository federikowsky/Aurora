/**
 * Logger Middleware
 *
 * Package: aurora.web.middleware.logger
 *
 * Features:
 * - Request/response logging
 * - Duration measurement
 * - Configurable format (JSON, custom)
 * - Log level filtering
 */
module aurora.web.middleware.logger;

import aurora.web.middleware;
import aurora.web.context;
import aurora.http;
import std.datetime.stopwatch;
import core.time;

/**
 * LogFormat - Output format for logs
 */
enum LogFormat
{
    SIMPLE,   // "GET /path 200 - 123μs"
    JSON,     // {"method":"GET","path":"/path","status":200,"duration_us":123}
    CUSTOM    // User-defined format
}

/**
 * LogLevel - Logging level
 */
enum LogLevel
{
    DEBUG,
    INFO,
    WARN,
    ERROR
}

/**
 * LoggerMiddleware - Request/response logger
 */
class LoggerMiddleware
{
    LogFormat format = LogFormat.SIMPLE;
    LogLevel level = LogLevel.INFO;
    bool logHeaders = false;
    bool logBody = false;
    string customFormat;
    
    private void delegate(string) logFunc;
    
    /**
     * Constructor with optional custom log function
     */
    this(void delegate(string) logFunc = null)
    {
        if (logFunc is null)
        {
            // Default: print to stdout
            this.logFunc = (string msg) {
                import std.stdio : writeln;
                writeln(msg);
            };
        }
        else
        {
            this.logFunc = logFunc;
        }
    }
    
    /**
     * Handle request (middleware interface)
     */
    void handle(Context ctx, NextFunction next)
    {
        auto sw = StopWatch(AutoStart.yes);
        
        // Extract request info
        string method = ctx.request ? ctx.request.method : "UNKNOWN";
        string path = ctx.request ? ctx.request.path : "/";
        
        // Call next middleware/handler
        try
        {
            next();
        }
        catch (Exception e)
        {
            // Log error and re-throw
            sw.stop();
            logRequest(method, path, 500, sw.peek());
            throw e;
        }
        
        sw.stop();
        
        // Extract response info
        int status = ctx.response ? ctx.response.getStatus() : 0;
        
        // Log request
        logRequest(method, path, status, sw.peek());
    }
    
    private:
    
    /**
     * Log request with given info
     */
    void logRequest(string method, string path, int status, Duration duration)
    {
        string logMsg;
        
        final switch (format)
        {
            case LogFormat.SIMPLE:
                import std.format : format;
                logMsg = format("%s %s %d - %dμs", method, path, status, duration.total!"usecs");
                break;
                
            case LogFormat.JSON:
                import std.format : format;
                logMsg = format(`{"method":"%s","path":"%s","status":%d,"duration_us":%d}`,
                    method, path, status, duration.total!"usecs");
                break;
                
            case LogFormat.CUSTOM:
                logMsg = customFormat;
                import std.array : replace;
                logMsg = logMsg.replace("{method}", method);
                logMsg = logMsg.replace("{path}", path);
                import std.conv : to;
                logMsg = logMsg.replace("{status}", status.to!string);
                logMsg = logMsg.replace("{duration}", duration.total!"usecs".to!string);
                break;
        }
        
        logFunc(logMsg);
    }
}

/**
 * Helper function to create logger middleware
 */
Middleware loggerMiddleware(LoggerMiddleware logger = null)
{
    if (logger is null)
    {
        logger = new LoggerMiddleware();
    }
    
    return (ref Context ctx, NextFunction next) {
        logger.handle(ctx, next);
    };
}
