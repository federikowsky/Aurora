#!/usr/bin/env dub
/+ dub.sdl:
    name "aurora_protocol_probe_server"
    dependency "aurora" path="../.."
+/
/**
 * Dedicated server for end-to-end HTTP protocol regression probes.
 *
 * Keep this configuration intentionally strict so tests can exercise
 * connection retirement and write deadlines without changing benchmark
 * semantics.
 */
module tests.integration.protocol_probe_server;

import aurora;
import core.time : msecs;

void main()
{
    auto config = ServerConfig.defaults();
    config.host = "127.0.0.1";
    config.port = 8080;
    config.numWorkers = 1;
    config.maxConnections = 0;
    config.maxInFlightRequests = 0;
    config.maxRequestsPerConnection = 2;
    config.writeTimeout = 100.msecs;

    auto app = new App(config);

    app.get("/", (ref Context ctx) {
        ctx.send("Hello, World!");
    });

    app.get("/json", (ref Context ctx) {
        ctx.json(["message": "Hello, World!"]);
    });

    app.post("/echo", (ref Context ctx) {
        ctx.send(ctx.request.body());
    });

    app.get("/response-headers", (ref Context ctx) {
        ctx.status(201)
            .header("Content-Type", "text/plain")
            .header("X-Aurora-Probe", "preserved");
        ctx.send("created");
    });

    app.route("HEAD", "/response-head", (ref Context ctx) {
        ctx.header("Content-Type", "text/plain")
            .header("X-Aurora-Probe", "head");
        ctx.send("hidden");
    });

    app.get("/response-no-content", (ref Context ctx) {
        ctx.status(204).header("X-Aurora-Probe", "no-content");
        ctx.send("must-not-be-sent");
    });

    app.get("/response-not-modified", (ref Context ctx) {
        ctx.status(304)
            .header("ETag", "\"aurora-probe\"")
            .header("X-Aurora-Probe", "not-modified");
        ctx.send("must-not-be-sent");
    });

    app.route("HEAD", "/response-error", (ref Context ctx) {
        throw new Exception("response probe failure");
    });

    auto largeBodyStorage = new char[32 * 1024 * 1024];
    largeBodyStorage[] = 'x';
    string largeBody = cast(string)largeBodyStorage;
    app.get("/large", (ref Context ctx) {
        ctx.send(largeBody);
    });

    app.listen();
}
