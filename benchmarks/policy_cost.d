#!/usr/bin/env dub
/+ dub.sdl:
    name "aurora_policy_cost"
    dependency "aurora" path=".."
+/
/**
 * Component comparison: identical route selection, policy and response checks on
 * the same bytes parsed for each request. Copy this file into benchmarks/ on the baseline to run
 * its manual composition control. Usage: policy_cost manual|bound [iterations].
 * A separate "setup" row measures 128 endpoints including snapshot registration.
 */
module benchmarks.policy_cost;

import aurora.http : HTTPRequest, HTTPResponse;
import aurora.web.context : Context;
import aurora.web.router : Router, Handler;
import mw = aurora.web.middleware;
import core.memory : GC;
import std.conv : to;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.functional : toDelegate;
import std.stdio : writefln;

private void globalPolicy(ref Context c, scope mw.NextFunction next)
{
    c.response.setHeader("X-Global", "yes");
    next();
}

private void groupPolicy(ref Context c, scope mw.NextFunction next)
{
    if (c.request.getHeader("X-Access") != "accepted") {
        c.status(403).send("denied");
        return;
    }
    next();
}

private void routePolicy(ref Context c, scope mw.NextFunction next)
{
    c.response.setHeader("X-Id", c.params["id"]);
    next();
}

private void endpoint(ref Context c) { c.send("ok"); }
private void missing(ref Context c) { c.status(404).send("missing"); }

private Handler manualWrap(Handler h, mw.Middleware m)
{
    auto p = new mw.MiddlewarePipeline;
    p.use(m);
    return (ref Context c) { p.execute(c, h); };
}

private Router fixture(bool bound, string[] extra = null)
{
    auto root = new Router();
    auto h = toDelegate(&endpoint);
    auto g = toDelegate(&groupPolicy);
    auto r = toDelegate(&routePolicy);
    root.get("/public", h);
    Router area;
    if (bound) {
        static if (__traits(hasMember, mw, "withMiddleware")) {
            area = new Router("/items", g);
            area.get("/", h);
            area.get("/:id", mw.withMiddleware(h, r));
            foreach (path; extra) area.get(path, h);
        } else throw new Exception("bound mode requires scoped middleware");
    } else {
        area = new Router("/items");
        area.get("/", manualWrap(h, g));
        area.get("/:id", manualWrap(manualWrap(h, r), g));
        foreach (path; extra) area.get(path, manualWrap(h, g));
    }
    root.includeRouter(area);
    return root;
}

private void measure(string name, size_t n, size_t warm, scope void delegate(size_t) operation)
{
    foreach (i; 0 .. warm) operation(i);
    GC.collect();
    const collections = GC.profileStats().numCollections;
    const before = GC.allocatedInCurrentThread();
    auto timer = StopWatch(AutoStart.yes);
    foreach (i; 0 .. n) operation(i);
    timer.stop();
    const bytes = GC.allocatedInCurrentThread() - before;
    const count = GC.profileStats().numCollections - collections;
    writefln("%s,%s,%s,%s,%s,%s", name, n, warm, timer.peek.total!"nsecs", bytes, count);
}

void main(string[] args)
{
    if (args.length < 2 || (args[1] != "manual" && args[1] != "bound"))
        throw new Exception("expected manual or bound");
    bool bound = args[1] == "bound";
    if (args.length == 4) {
        import aurora.app : App;
        import aurora.runtime.server : ServerConfig;
        import core.time : msecs;
        import std.file : exists;
        import vibe.core.core : runTask, sleep;
        auto config = ServerConfig.defaults();
        config.host = "127.0.0.1";
        config.port = args[2].to!ushort;
        config.numWorkers = 1;
        auto app = new App(config);
        app.use(toDelegate(&globalPolicy));
        app.includeRouter(fixture(bound));
        auto stopFile = args[3];
        app.onStart(() {
            runTask(() nothrow {
                try {
                    while (!exists(stopFile)) sleep(5.msecs);
                    app.stop();
                } catch (Exception) {}
            });
        });
        app.listen();
        return;
    }
    size_t n = args.length > 2 ? args[2].to!size_t : 100_000;
    auto router = fixture(bound);
    auto global = new mw.MiddlewarePipeline;
    global.use(toDelegate(&globalPolicy));
    auto fallback = toDelegate(&missing);

    enum paths = ["/public", "/public", "/items", "/items/42", "/items/42", "/missing"];
    enum names = ["bare", "global", "group", "group_route", "denied", "miss"];
    enum codes = [200, 200, 200, 200, 403, 404];
    enum bodies = ["ok", "ok", "ok", "ok", "denied", "missing"];
    // Request bytes, telemetry output and network I/O are outside the timed loop.
    ubyte[][6] buffers;
    foreach (i; 0 .. buffers.length) {
        buffers[i] = cast(ubyte[])("GET " ~ paths[i] ~ " HTTP/1.1\r\nHost: localhost\r\nX-Access: " ~
            (i == 4 ? "none" : "accepted") ~ "\r\n\r\n").dup;
    }
    void dispatch(size_t i) {
        auto req = HTTPRequest.parse(buffers[i]);
        if (!req.isComplete()) throw new Exception("invalid benchmark request");
        HTTPResponse resp;
        Context c;
        c.request = &req;
        c.response = &resp;
        auto m = router.match(cast(string) req.methodRaw(), cast(string) req.pathRaw());
        auto h = m.found ? m.handler : fallback;
        c.params = m.params;
        if (i == 0) h(c); else global.execute(c, h);
        if (resp.getStatus() != codes[i] || resp.getBody() != bodies[i] ||
            resp.getHeaders.get("X-Global", "") != (i ? "yes" : "") ||
            resp.getHeaders.get("X-Id", "") != (i == 3 ? "42" : ""))
            throw new Exception("incorrect response: " ~ names[i]);
    }
    foreach (k; 0 .. buffers.length)
        measure(names[k], n, n / 10, (size_t i) { dispatch(k); });
    measure("mixed", n, n / 10, (size_t i) { dispatch(i % 6); });

    // Isolate continuation cost from parser, header maps and response creation.
    mw.Middleware counter = (ref Context c, scope mw.NextFunction next) {
        c.storage.set("calls", c.storage.get!int("calls") + 1);
        next();
    };
    Handler finalHandler = (ref Context c) { c.responseSent = true; };
    foreach (depth; [0, 1, 3]) {
        Handler h = finalHandler;
        if (bound) {
            static if (__traits(hasMember, mw, "withMiddleware")) {
                mw.Middleware[] policies;
                foreach (_; 0 .. depth) policies ~= counter;
                h = mw.withMiddleware(h, policies);
            }
        } else {
            foreach (_; 0 .. depth) h = manualWrap(h, counter);
        }
        measure("chain" ~ depth.to!string, n, n / 10, (size_t i) {
            Context c;
            h(c);
            if (!c.responseSent || c.storage.get!int("calls") != depth)
                throw new Exception("incorrect continuation count");
        });
    }

    string[] extra;
    foreach (i; 0 .. 128) extra ~= "/static" ~ i.to!string;
    measure("setup128extra", 20, 3, (size_t i) {
        auto x = fixture(bound, extra);
        if (!x.match("GET", "/items/static127").found) throw new Exception("missing endpoint");
    });
}
