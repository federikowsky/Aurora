#!/usr/bin/env dub
/+ dub.sdl:
    name "aurora_simple_handler_probe_server"
    dependency "aurora" path="../.."
+/
module tests.integration.simple_handler_probe_server;

import aurora.http : HTTPRequest;
import aurora.runtime.server : RequestHandler, ResponseBuffer, Server, ServerConfig;
import core.time : msecs, seconds;
import std.conv : to;
import std.file : exists, write;
import std.path : buildPath;
import vibe.core.core : runTask, sleep;

void main(string[] args)
{
    auto config = ServerConfig.defaults();
    config.host = "127.0.0.1";
    config.port = to!ushort(args[1]);
    config.numWorkers = 1;
    config.readTimeout = 3.seconds;
    auto directory = args[2];

    void handler(scope HTTPRequest* request, scope ref ResponseBuffer writer) @trusted
    {
        writer.write(200, "text/plain", "simple handler");
    }

    RequestHandler requestHandler = &handler;
    auto server = new Server(requestHandler, config);
    server.hooks.onStart(() {
        runTask(() nothrow {
            try
            {
                while (!exists(buildPath(directory, "stop"))) sleep(2.msecs);
                server.stop();
            }
            catch (Exception) {}
        });
    });
    server.run();
    write(buildPath(directory, "stopped"), "run returned");
}
