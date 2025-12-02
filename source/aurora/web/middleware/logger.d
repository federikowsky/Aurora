/**
 * Logger Middleware
 *
 * Package: aurora.web.middleware.logger
 *
 * Features:
 * - Request/response logging (Gin-style colored output)
 * - Duration measurement
 * - Configurable format (SIMPLE, JSON, GIN, CUSTOM)
 * - Log level filtering
 * - ANSI color support
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
    COLORED,  // 2025/01/22 - 15:04:05 | 200 |    1.234ms | GET "/path"
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

// ANSI Color codes
private enum Colors : string
{
    RESET   = "\033[0m",
    RED     = "\033[31m",
    GREEN   = "\033[32m",
    YELLOW  = "\033[33m",
    BLUE    = "\033[34m",
    MAGENTA = "\033[35m",
    CYAN    = "\033[36m",
    WHITE   = "\033[37m",
    BOLD    = "\033[1m",
    // Background colors for status
    BG_GREEN  = "\033[42m",
    BG_YELLOW = "\033[43m",
    BG_RED    = "\033[41m",
    BG_CYAN   = "\033[46m",
    BG_WHITE  = "\033[47m",
    BLACK     = "\033[30m",
}

/**
 * LoggerMiddleware - Request/response logger
 */
class LoggerMiddleware
{
    LogFormat format = LogFormat.COLORED;  // Default to COLORED format
    LogLevel level = LogLevel.INFO;
    bool logHeaders = false;
    bool logBody = false;
    bool useColors = true;  // Enable ANSI colors
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
     * Get status color based on HTTP status code
     */
    string getStatusColor(int status)
    {
        if (!useColors) return "";
        
        if (status >= 200 && status < 300)
            return Colors.BG_GREEN ~ Colors.BLACK;  // 2xx = Green
        else if (status >= 300 && status < 400)
            return Colors.BG_CYAN ~ Colors.BLACK;   // 3xx = Cyan
        else if (status >= 400 && status < 500)
            return Colors.BG_YELLOW ~ Colors.BLACK; // 4xx = Yellow
        else if (status >= 500)
            return Colors.BG_RED ~ Colors.WHITE;    // 5xx = Red
        else
            return Colors.BG_WHITE ~ Colors.BLACK;  // Other
    }
    
    /**
     * Get method color
     */
    string getMethodColor(string method)
    {
        if (!useColors) return "";
        
        switch (method)
        {
            case "GET":    return Colors.BLUE;
            case "POST":   return Colors.CYAN;
            case "PUT":    return Colors.YELLOW;
            case "DELETE": return Colors.RED;
            case "PATCH":  return Colors.GREEN;
            default:       return Colors.WHITE;
        }
    }
    
    /**
     * Format duration for display
     */
    string formatDuration(Duration duration)
    {
        import std.format : fmt = format;
        auto usecs = duration.total!"usecs";
        
        if (usecs < 1000)
            return fmt("%6dμs", usecs);
        else if (usecs < 1_000_000)
            return fmt("%6.2fms", usecs / 1000.0);
        else
            return fmt("%6.2fs ", usecs / 1_000_000.0);
    }
    
    /**
     * Log request with given info
     */
    void logRequest(string method, string path, int status, Duration duration)
    {
        import std.format : format;
        import std.datetime : Clock;
        
        string logMsg;
        
        final switch (this.format)
        {
            case LogFormat.SIMPLE:
                logMsg = format("%s %s %d - %dμs", method, path, status, duration.total!"usecs");
                break;
                
            case LogFormat.JSON:
                import std.datetime : Clock;
                auto now = Clock.currTime();
                logMsg = format(`{"timestamp":"%s","method":"%s","path":"%s","status":%d,"duration_us":%d}`,
                    now.toISOExtString(), method, path, status, duration.total!"usecs");
                break;
                
            case LogFormat.COLORED:
                // Colored format:
                // 2025/01/22 - 15:04:05 | 200 |    1.234ms | GET "/path"
                auto now = Clock.currTime();
                auto timestamp = format("%04d/%02d/%02d - %02d:%02d:%02d",
                    now.year, now.month, now.day,
                    now.hour, now.minute, now.second);
                
                auto durationStr = formatDuration(duration);
                auto reset = useColors ? Colors.RESET : "";
                auto statusColor = getStatusColor(status);
                auto methodColor = getMethodColor(method);
                
                logMsg = format("%s |%s %3d %s| %s |%s %-7s%s \"%s\"",
                    timestamp,
                    statusColor,
                    status,
                    reset,
                    durationStr,
                    methodColor,
                    method,
                    reset,
                    path);
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
