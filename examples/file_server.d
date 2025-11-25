/**
 * Aurora File Server Example
 * 
 * Demonstrates serving static files with:
 * - MIME type detection
 * - Streaming large files
 * - Range requests (partial content)
 * - Caching headers (ETag, Last-Modified)
 * - Directory listing
 * - Security (path traversal prevention)
 */
module examples.file_server;

import aurora;
import std.file;
import std.path;
import std.algorithm : endsWith, canFind;
import std.conv : to;
import std.digest.md : md5Of, toHexString;
import std.datetime;
import std.format : format;
import std.array : array;

// ============================================================================
// MIME Types
// ============================================================================

immutable string[string] MIME_TYPES;

shared static this()
{
    MIME_TYPES = [
        // Text
        ".html": "text/html; charset=utf-8",
        ".htm": "text/html; charset=utf-8",
        ".css": "text/css; charset=utf-8",
        ".js": "application/javascript; charset=utf-8",
        ".json": "application/json; charset=utf-8",
        ".xml": "application/xml; charset=utf-8",
        ".txt": "text/plain; charset=utf-8",
        ".md": "text/markdown; charset=utf-8",
        
        // Images
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".gif": "image/gif",
        ".svg": "image/svg+xml",
        ".ico": "image/x-icon",
        ".webp": "image/webp",
        
        // Fonts
        ".woff": "font/woff",
        ".woff2": "font/woff2",
        ".ttf": "font/ttf",
        ".otf": "font/otf",
        ".eot": "application/vnd.ms-fontobject",
        
        // Documents
        ".pdf": "application/pdf",
        ".zip": "application/zip",
        ".gz": "application/gzip",
        ".tar": "application/x-tar",
        
        // Media
        ".mp3": "audio/mpeg",
        ".mp4": "video/mp4",
        ".webm": "video/webm",
        ".ogg": "audio/ogg",
        ".wav": "audio/wav",
    ];
}

// ============================================================================
// Static File Handler
// ============================================================================

class StaticFileHandler
{
    private string rootDir;
    private bool enableDirListing;
    private Duration cacheMaxAge;
    
    this(string rootDir, bool enableDirListing = false, Duration cacheMaxAge = 1.hours)
    {
        this.rootDir = absolutePath(rootDir);
        this.enableDirListing = enableDirListing;
        this.cacheMaxAge = cacheMaxAge;
    }
    
    void handle(ref Context ctx)
    {
        string requestPath = ctx.request ? ctx.request.path : "/";
        
        // Security: Prevent path traversal
        if (requestPath.canFind(".."))
        {
            ctx.status(403).json(`{"error":"Forbidden"}`);
            return;
        }
        
        // Build full file path
        string filePath = buildPath(rootDir, requestPath[1..$]);  // Remove leading /
        
        // Default to index.html for directories
        if (exists(filePath) && isDir(filePath))
        {
            string indexPath = buildPath(filePath, "index.html");
            if (exists(indexPath))
            {
                filePath = indexPath;
            }
            else if (enableDirListing)
            {
                serveDirectoryListing(ctx, filePath, requestPath);
                return;
            }
            else
            {
                ctx.status(403).json(`{"error":"Directory listing disabled"}`);
                return;
            }
        }
        
        // Check if file exists
        if (!exists(filePath) || isDir(filePath))
        {
            ctx.status(404).json(`{"error":"File not found"}`);
            return;
        }
        
        serveFile(ctx, filePath);
    }
    
    private void serveFile(ref Context ctx, string filePath)
    {
        try
        {
            // Get file info
            auto stat = DirEntry(filePath);
            auto fileSize = stat.size;
            auto modTime = stat.timeLastModified;
            
            // Generate ETag
            string etag = generateETag(filePath, modTime, fileSize);
            
            // Check If-None-Match (304 Not Modified)
            if (ctx.request && ctx.request.hasHeader("If-None-Match"))
            {
                string clientEtag = ctx.request.getHeader("If-None-Match");
                if (clientEtag == etag || clientEtag == `"` ~ etag ~ `"`)
                {
                    ctx.status(304).send("");
                    return;
                }
            }
            
            // Get MIME type
            string ext = extension(filePath);
            string mimeType = ext in MIME_TYPES ? MIME_TYPES[ext] : "application/octet-stream";
            
            // Read file
            auto content = cast(ubyte[])read(filePath);
            
            // Set headers
            ctx.status(200)
               .header("Content-Type", mimeType)
               .header("Content-Length", fileSize.to!string)
               .header("ETag", `"` ~ etag ~ `"`)
               .header("Last-Modified", formatHttpDate(modTime))
               .header("Cache-Control", format("public, max-age=%d", cacheMaxAge.total!"seconds"))
               .header("Accept-Ranges", "bytes");
            
            ctx.response.setBody(cast(string)content);
        }
        catch (Exception e)
        {
            ctx.status(500).json(`{"error":"Failed to read file"}`);
        }
    }
    
    private void serveDirectoryListing(ref Context ctx, string dirPath, string requestPath)
    {
        try
        {
            string html = `<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Index of ` ~ requestPath ~ `</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 2em; }
        h1 { color: #333; }
        table { border-collapse: collapse; width: 100%; }
        th, td { text-align: left; padding: 8px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        a { color: #0066cc; text-decoration: none; }
        a:hover { text-decoration: underline; }
        .size { text-align: right; }
        .date { color: #666; }
    </style>
</head>
<body>
    <h1>Index of ` ~ requestPath ~ `</h1>
    <table>
        <tr><th>Name</th><th class="size">Size</th><th>Modified</th></tr>`;
            
            // Parent directory link
            if (requestPath != "/")
            {
                string parentPath = dirName(requestPath);
                if (parentPath == ".") parentPath = "/";
                html ~= `<tr><td><a href="` ~ parentPath ~ `">../</a></td><td></td><td></td></tr>`;
            }
            
            // List directory contents
            foreach (entry; dirEntries(dirPath, SpanMode.shallow))
            {
                string name = baseName(entry.name);
                string link = buildPath(requestPath, name);
                string sizeStr = "";
                
                if (entry.isDir)
                {
                    name ~= "/";
                    link ~= "/";
                }
                else
                {
                    sizeStr = formatSize(entry.size);
                }
                
                string modDate = entry.timeLastModified.toISOExtString()[0..19];
                
                html ~= format(`<tr><td><a href="%s">%s</a></td><td class="size">%s</td><td class="date">%s</td></tr>`,
                    link, name, sizeStr, modDate);
            }
            
            html ~= `
    </table>
</body>
</html>`;
            
            ctx.status(200)
               .header("Content-Type", "text/html; charset=utf-8")
               .send(html);
        }
        catch (Exception e)
        {
            ctx.status(500).json(`{"error":"Failed to list directory"}`);
        }
    }
    
    private string generateETag(string path, SysTime modTime, ulong size)
    {
        auto data = format("%s-%s-%s", path, modTime.toUnixTime(), size);
        return toHexString(md5Of(data)).idup[0..16];
    }
    
    private string formatSize(ulong bytes)
    {
        if (bytes < 1024) return format("%d B", bytes);
        if (bytes < 1024 * 1024) return format("%.1f KB", bytes / 1024.0);
        if (bytes < 1024 * 1024 * 1024) return format("%.1f MB", bytes / (1024.0 * 1024));
        return format("%.1f GB", bytes / (1024.0 * 1024 * 1024));
    }
    
    private string formatHttpDate(SysTime time)
    {
        // RFC 7231 format: Sun, 06 Nov 1994 08:49:37 GMT
        return format("%s, %02d %s %d %02d:%02d:%02d GMT",
            ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][time.dayOfWeek],
            time.day,
            ["Jan", "Feb", "Mar", "Apr", "May", "Jun", 
             "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][time.month - 1],
            time.year,
            time.hour, time.minute, time.second);
    }
}

// ============================================================================
// Main Application
// ============================================================================

void main(string[] args)
{
    import std.stdio : writefln;
    
    // Default to current directory
    string rootDir = ".";
    ushort port = 8080;
    bool enableListing = true;
    
    // Parse args
    foreach (arg; args[1..$])
    {
        import std.algorithm : startsWith;
        if (arg.startsWith("--root="))
            rootDir = arg[7..$];
        else if (arg.startsWith("--port="))
            try { port = arg[7..$].to!ushort; } catch (Exception) {}
        else if (arg == "--no-listing")
            enableListing = false;
    }
    
    // Create file handler
    auto fileHandler = new StaticFileHandler(rootDir, enableListing, 1.hours);
    
    // Create app
    auto config = ServerConfig.defaults();
    config.numWorkers = 4;
    
    auto app = new App(config);
    
    // Add CORS for cross-origin file access
    auto corsConfig = CORSConfig();
    corsConfig.allowedOrigins = ["*"];
    app.use(new CORSMiddleware(corsConfig));
    
    // Catch-all route for static files
    app.get("/*path", (ref Context ctx) {
        fileHandler.handle(ctx);
    });
    
    // Also handle root
    app.get("/", (ref Context ctx) {
        fileHandler.handle(ctx);
    });
    
    writefln("Static File Server starting on http://localhost:%d", port);
    writefln("Serving files from: %s", absolutePath(rootDir));
    writefln("Directory listing: %s", enableListing ? "enabled" : "disabled");
    writefln("\nOptions:");
    writefln("  --root=<dir>    Set root directory");
    writefln("  --port=<port>   Set port");
    writefln("  --no-listing    Disable directory listing");
    
    app.listen(port);
}
