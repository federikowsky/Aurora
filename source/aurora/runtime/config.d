/**
 * Connection Configuration
 *
 * Configuration structures for connection timeout and behavior settings.
 */
module aurora.runtime.config;

import core.time;

/**
 * Connection Configuration
 *
 * Defines timeout values and connection behavior settings.
 */
struct ConnectionConfig
{
    /// Read timeout - max time to read request headers
    Duration readTimeout = 30.seconds;

    /// Write timeout - max time to send response
    Duration writeTimeout = 30.seconds;

    /// Keep-alive timeout - max time to wait for next request
    Duration keepAliveTimeout = 60.seconds;

    /// Maximum requests per connection (before forced close)
    ulong maxRequestsPerConnection = 100;

    /// Default configuration
    static ConnectionConfig defaults() @safe nothrow @nogc
    {
        return ConnectionConfig.init;
    }
}
