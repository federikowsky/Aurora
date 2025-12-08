/**
 * Aurora Runtime Module
 *
 * Provides core runtime abstractions:
 * - Server (fiber-based HTTP server with async I/O)
 * - Worker (multi-worker support for Linux/FreeBSD)
 * - Hooks (server lifecycle hooks and exception handlers)
 */
module aurora.runtime;

public import aurora.runtime.server;
public import aurora.runtime.hooks;

// Worker module only available on platforms with SO_REUSEPORT
version(linux)
{
    public import aurora.runtime.worker;
}
version(FreeBSD)
{
    public import aurora.runtime.worker;
}
