/**
 * Aurora Runtime Module
 *
 * Provides core runtime abstractions:
 * - Server (multi-threaded HTTP server)
 * - Worker threads
 * - Event loop (Reactor)
 * - Connection handling
 */
module aurora.runtime;

public import aurora.runtime.server;
public import aurora.runtime.worker;
public import aurora.runtime.reactor;
public import aurora.runtime.connection;
public import aurora.runtime.config;
