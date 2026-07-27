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

    auto largeBodyStorage = new char[32 * 1024 * 1024];
    largeBodyStorage[] = 'x';
    string largeBody = cast(string)largeBodyStorage;
    app.get("/large", (ref Context ctx) {
        ctx.send(largeBody);
    });

    app.listen();
}
