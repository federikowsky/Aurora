#!/usr/bin/env dub
/+ dub.sdl:
    name "aurora_admission_probe_server"
    dependency "aurora" path="../.."
+/
module tests.integration.admission_probe_server;

import aurora;
import core.atomic : atomicOp;
import core.time : msecs, seconds;
import std.conv : to;
import std.file : exists, write;
import std.path : buildPath;
import vibe.core.core : sleep;

// Files are an out-of-band test barrier, not production synchronization.
// The client never needs an admission permit to release a blocked handler.
void main(string[] args)
{
    auto config = ServerConfig.defaults();
    config.host = "127.0.0.1";
    config.port = to!ushort(args[1]);
    config.numWorkers = to!uint(args[2]);
    config.maxInFlightRequests = to!uint(args[3]);
    config.maxConnections = 0;
    config.writeTimeout = 2.seconds;
    config.maxRequestsPerConnection = 0;
    auto directory = args[4];
    auto app = new App(config);
    shared uint entered;

    void hold(ref Context ctx, bool fail)
    {
        auto number = atomicOp!"+="(entered, 1);
        write(buildPath(directory, "entered-" ~ number.to!string), "entered");
        while (!exists(buildPath(directory, "release"))) sleep(2.msecs);
        if (fail) throw new Exception("admission probe handler failure");
        ctx.send("released");
    }
    app.get("/hold", (ref Context ctx) { hold(ctx, false); });
    app.get("/throw", (ref Context ctx) { hold(ctx, true); });
    app.get("/", (ref Context ctx) { ctx.send("ok"); });

    auto large = new char[32 * 1024 * 1024];
    large[] = 'x';
    app.get("/large", (ref Context ctx) {
        ctx.send(cast(string)large);
        write(buildPath(directory, "writing"), "writing");
    });
    app.listen();
}
