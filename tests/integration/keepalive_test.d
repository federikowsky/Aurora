/**
 * Keep-Alive Integration Test
 * 
 * Tests HTTP/1.1 keep-alive connection reuse behavior.
 * Verifies buffer pooling and timeout configuration.
 */
module tests.integration.keepalive_test;

import unit_threaded;

@("keep-alive: buffer reuse across requests")
@trusted unittest
{
    import aurora.mem.pool : BufferPool, BufferSize;
    
    // Simulate keep-alive buffer reuse pattern
    auto pool = new BufferPool();
    
    // First request - acquire buffer
    auto buffer = pool.acquire(BufferSize.MEDIUM);
    assert(buffer.length == 16384);  // 16KB
    
    // Simulate request processing...
    buffer[0] = 'G';
    buffer[1] = 'E';
    buffer[2] = 'T';
    
    // Release at end of connection (not per request!)
    pool.release(buffer);
    
    // Verify pool reuse
    auto buffer2 = pool.acquire(BufferSize.MEDIUM);
    assert(buffer2.ptr == buffer.ptr);  // Same memory reused
    pool.release(buffer2);
}

@("keep-alive: timeout configuration")
unittest
{
    import aurora.runtime.server : ServerConfig;
    import core.time : seconds;
    
    auto config = ServerConfig.defaults();
    
    // Verify keep-alive timeout is configurable
    assert(config.keepAliveTimeout >= 30.seconds);
    assert(config.keepAliveTimeout <= 120.seconds);
    
    // Verify can be customized
    config.keepAliveTimeout = 60.seconds;
    assert(config.keepAliveTimeout == 60.seconds);
}

@("keep-alive: max requests per connection")
unittest
{
    import aurora.runtime.server : ServerConfig;
    
    auto config = ServerConfig.defaults();
    
    // Verify max requests per connection is configurable
    assert(config.maxRequestsPerConnection >= 100);
    
    // Verify can be customized
    config.maxRequestsPerConnection = 1000;
    assert(config.maxRequestsPerConnection == 1000);
}

@("keep-alive: HTTPRequest shouldKeepAlive API exists")
unittest
{
    import aurora.http : HTTPRequest;
    
    // Verify shouldKeepAlive method exists
    HTTPRequest req;
    bool keepAlive = req.shouldKeepAlive();
    // Invalid request returns false
    assert(keepAlive == false);
}
