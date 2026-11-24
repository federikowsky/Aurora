/+ dub.sdl:
    name "aurora_scoped_middleware_example"
    dependency "aurora" path=".."
+/
/** Public health, authenticated reads and writer-only updates on the same path.
 * The two environment-provided tokens are a local example identity source.
 */
module examples.middleware_example;

import aurora;
import std.process : environment;

void main()
{
    auto reader = environment.get("DEMO_READER_TOKEN", "");
    auto writer = environment.get("DEMO_WRITER_TOKEN", "");
    if (!reader.length || !writer.length || reader == writer)
        throw new Exception("Set distinct DEMO_READER_TOKEN and DEMO_WRITER_TOKEN");
    auto readCredential = "Bearer " ~ reader;
    auto writeCredential = "Bearer " ~ writer;

    Middleware identify = (ref Context ctx, scope NextFunction next) {
        auto credential = ctx.request.getHeader("Authorization");
        bool canWrite = credential == writeCredential;
        if (!canWrite && credential != readCredential) {
            ctx.status(401).header("WWW-Authenticate", "Bearer").send("authentication required");
            return;
        }
        ctx.storage.set("canWrite", cast(int)canWrite);
        next();
    };
    Middleware requireWriter = (ref Context ctx, scope NextFunction next) {
        if (!ctx.storage.get!int("canWrite")) {
            ctx.status(403).send("writer required");
            return;
        }
        next();
    };

    auto config = ServerConfig.defaults();
    config.host = "127.0.0.1";
    auto app = new App(config);
    app.use((new RequestIdMiddleware).middleware);
    app.get("/health", (ref Context ctx) { ctx.send("ok"); });

    auto reports = new Router("/reports", identify);
    reports.get("/:id", (ref Context ctx) { ctx.send(ctx.params["id"]); });
    void update(ref Context ctx) { ctx.status(204); }
    reports.put("/:id", withMiddleware(&update, requireWriter));
    app.includeRouter(reports);
    app.listen(8080);
}
