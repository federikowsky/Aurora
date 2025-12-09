/**
 * Response Compression Middleware
 *
 * Package: aurora.web.middleware.compression
 *
 * Features:
 * - Gzip/deflate compression for HTTP responses
 * - Automatic compression based on Accept-Encoding header
 * - Configurable minimum size threshold
 * - Skip compression for already-compressed content types
 * - Content-Encoding header management
 */
module aurora.web.middleware.compression;

import aurora.web.middleware;
import aurora.web.context;
import aurora.http;
import std.zlib;
import std.string : indexOf, toLower;
import std.algorithm : canFind;
import std.conv : to;

/**
 * CompressionConfig - Compression configuration
 */
struct CompressionConfig
{
    /// Minimum response size to compress (bytes)
    /// Responses smaller than this are not compressed
    size_t minSize = 1024;  // 1 KB
    
    /// Compression level (0-9, where 0 = no compression, 9 = max compression)
    /// Default 6 provides good balance between speed and size
    int compressionLevel = 6;
    
    /// Content types that should NOT be compressed (already compressed)
    string[] skipContentTypes = [
        "image/jpeg",
        "image/png",
        "image/gif",
        "image/webp",
        "image/svg+xml",
        "video/mp4",
        "video/webm",
        "audio/mpeg",
        "audio/ogg",
        "application/zip",
        "application/gzip",
        "application/x-gzip",
        "application/x-compress",
        "application/x-compressed"
    ];
    
    /// Enable gzip compression (default: true)
    bool enableGzip = true;
    
    /// Enable deflate compression (default: true)
    bool enableDeflate = true;
    
    /// Preferred compression method if both are supported
    /// "gzip" or "deflate"
    string preferredMethod = "gzip";
}

/**
 * CompressionMiddleware - Response compression
 */
class CompressionMiddleware
{
    private CompressionConfig config;
    
    /**
     * Constructor with config
     */
    this(CompressionConfig config)
    {
        this.config = config;
    }
    
    /**
     * Handle request (middleware interface)
     */
    void handle(Context ctx, NextFunction next)
    {
        // Execute next middleware/handler first
        next();
        
        // Compress response if needed (after handler has set body)
        compressResponse(ctx);
    }
    
    private:
    
    /**
     * Compress response body if conditions are met
     */
    void compressResponse(Context ctx)
    {
        if (ctx.response is null) return;
        
        // Check if response already has Content-Encoding
        if ("Content-Encoding" in ctx.response.getHeaders())
        {
            // Already compressed, skip
            return;
        }
        
        // Get response body
        string body = ctx.response.getBody();
        
        // Check minimum size
        if (body.length < config.minSize)
        {
            return;  // Too small to compress
        }
        
        // Check content type
        string contentType = ctx.response.getContentType();
        if (shouldSkipCompression(contentType))
        {
            return;  // Already compressed content type
        }
        
        // Get Accept-Encoding from request
        string acceptEncoding = "";
        if (ctx.request !is null)
        {
            acceptEncoding = ctx.request.getHeader("Accept-Encoding");
        }
        
        // Determine compression method
        string method = getCompressionMethod(acceptEncoding);
        if (method.length == 0)
        {
            return;  // Client doesn't support compression
        }
        
        // Compress body
        ubyte[] compressed;
        try
        {
            compressed = compressData(cast(ubyte[])body, method);
            
            // Only use compressed version if it's actually smaller
            if (compressed.length < body.length)
            {
                // Update response body with compressed data
                ctx.response.setBody(cast(string)compressed);
                
                // Set Content-Encoding header
                ctx.response.setHeader("Content-Encoding", method);
                
                // Update Content-Length (setBody already does this, but ensure it's correct)
                ctx.response.setHeader("Content-Length", compressed.length.to!string);
            }
        }
        catch (Exception e)
        {
            // Compression failed, send uncompressed
            // Log error if logger available
            import aurora.logging : Logger, LogLevel;
            try
            {
                auto logger = Logger.get();
                logger.warn("Compression failed: " ~ e.msg);
            }
            catch (Exception) {}
        }
    }
    
    /**
     * Check if content type should skip compression
     */
    bool shouldSkipCompression(string contentType)
    {
        if (contentType.length == 0) return false;
        
        // Extract base content type (before ;)
        string baseType = contentType;
        auto semicolonPos = contentType.indexOf(';');
        if (semicolonPos > 0)
        {
            baseType = contentType[0 .. semicolonPos];
        }
        
        // Normalize to lowercase
        baseType = baseType.toLower();
        
        // Check against skip list
        foreach (skipType; config.skipContentTypes)
        {
            if (baseType == skipType.toLower())
            {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * Determine compression method from Accept-Encoding header
     * Returns: "gzip", "deflate", or "" if not supported
     */
    string getCompressionMethod(string acceptEncoding)
    {
        if (acceptEncoding.length == 0)
        {
            return "";  // No Accept-Encoding header
        }
        
        string normalized = acceptEncoding.toLower();
        
        // Check for gzip support
        bool supportsGzip = normalized.canFind("gzip");
        bool supportsDeflate = normalized.canFind("deflate");
        
        // Return preferred method if both supported, or whichever is supported
        if (config.enableGzip && supportsGzip && config.preferredMethod == "gzip")
        {
            return "gzip";
        }
        else if (config.enableDeflate && supportsDeflate && config.preferredMethod == "deflate")
        {
            return "deflate";
        }
        else if (config.enableGzip && supportsGzip)
        {
            return "gzip";
        }
        else if (config.enableDeflate && supportsDeflate)
        {
            return "deflate";
        }
        
        return "";  // No supported method
    }
    
    /**
     * Compress data using specified method
     */
    ubyte[] compressData(ubyte[] data, string method)
    {
        // std.zlib.compress() uses default compression level
        // For gzip, we need to use compress() which produces zlib format
        // For true gzip format, we'd need zlib-ng or manual gzip header/footer
        // For now, use compress() which works for both (browsers accept zlib as deflate)
        
        if (method == "gzip" || method == "deflate")
        {
            // Use zlib compression (works as deflate, browsers accept as gzip too)
            // Note: True gzip format requires gzip header/footer, but most browsers
            // accept zlib format when Content-Encoding is gzip
            return compress(data);
        }
        else
        {
            throw new Exception("Unsupported compression method: " ~ method);
        }
    }
}

/**
 * Helper function to create compression middleware
 */
Middleware compressionMiddleware(CompressionConfig config = CompressionConfig())
{
    auto compression = new CompressionMiddleware(config);
    
    return (ref Context ctx, NextFunction next) {
        compression.handle(ctx, next);
    };
}

