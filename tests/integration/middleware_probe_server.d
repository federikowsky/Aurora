#!/usr/bin/env dub
/+ dub.sdl:
    name "aurora_middleware_probe_server"
    dependency "aurora" path="../.."
+/
module tests.integration.middleware_probe_server;

import aurora;
import WebMiddleware = aurora.web.middleware;
import core.time : msecs, seconds;
import std.conv : to;
import std.file : exists, write;
import std.path : buildPath;
import vibe.core.core : runTask, sleep;

final class ProbeError : Exception
{
    this() { super("probe failure"); }
}

void main(string[] args)
{
    auto config = ServerConfig.defaults();
    config.host = "127.0.0.1";
    config.port = to!ushort(args[1]);
    config.numWorkers = 1;
    config.maxConnections = 0;
    config.maxInFlightRequests = 0;
    config.readTimeout = 3.seconds;
    auto directory = args[2];

    auto app = new App(config);

    app.use((ref Context ctx, WebMiddleware.NextFunction next) {
        ctx.storage.set("order", ctx.storage.get!int("order") + 1);
        ctx.header("X-Global-Policy", "executed");
        next();
        ctx.storage.set("order", ctx.storage.get!int("order") + 1);
        ctx.header("X-Execution-Order", ctx.storage.get!int("order").to!string);
    });

    app.use((ref Context ctx, WebMiddleware.NextFunction next) {
        ctx.storage.set("order", ctx.storage.get!int("order") + 1);

        auto method = cast(string) ctx.request.methodRaw();
        auto path = cast(string) ctx.request.pathRaw();
        if (method == "OPTIONS")
        {
            ctx.status(204).header("X-Preflight-Policy", "handled");
        }
        else if (path == "/blocked")
        {
            ctx.status(401).send("blocked");
        }
        else
        {
            next();
        }

        ctx.storage.set("order", ctx.storage.get!int("order") + 1);
    });

    app.get("/ok", (ref Context ctx) {
        ctx.storage.set("order", ctx.storage.get!int("order") + 1);
        ctx.send("ok");
    });

    app.get("/blocked", (ref Context ctx) {
        ctx.send("handler must not execute");
    });

    app.get("/users/:id", (ref Context ctx) {
        ctx.storage.set("order", ctx.storage.get!int("order") + 1);
        ctx.header("X-Route-Id", ctx.params["id"]);
        ctx.send("user");
    });

    auto nested = new Router("/api");
    nested.get("/nested", (ref Context ctx) {
        ctx.storage.set("order", ctx.storage.get!int("order") + 1);
        ctx.send("nested");
    });
    app.includeRouter(nested);

    app.get("/boom", (ref Context ctx) {
        throw new ProbeError();
    });
    app.addExceptionHandler!ProbeError((ref Context ctx, ProbeError error) {
        ctx.status(418).send("handled");
    });

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
