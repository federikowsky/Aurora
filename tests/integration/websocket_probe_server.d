#!/usr/bin/env dub
/+ dub.sdl:
    name "aurora_websocket_probe_server"
    dependency "aurora" path="../.."
+/
module tests.integration.websocket_probe_server;

import aurora;
import aurora.web.websocket;
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
    config.maxConnections = 0;
    config.readTimeout = 3.seconds;
    auto directory = args[2];
    auto app = new App(config);
    app.get("/", (ref Context ctx) { ctx.send("ready"); });

    void synchronous(ref Context ctx)
    {
        auto socket = upgradeWebSocket(ctx);
        if (socket is null)
        {
            ctx.status(400).send("invalid upgrade");
            return;
        }
        scope(exit) socket.close();
        auto message = socket.receive();
        if (!message.isNull)
            socket.send(message.get.text);
    }

    app.get("/sync", &synchronous);
    app.post("/sync", &synchronous);
    app.onStart(() {
        runTask(() nothrow {
            try
            {
                while (!exists(buildPath(directory, "stop"))) sleep(2.msecs);
                app.stop();
            }
            catch (Exception) {}
        });
    });
    app.listen();
    write(buildPath(directory, "stopped"), "listen returned");
}
