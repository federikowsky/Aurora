#!/usr/bin/env dub
/+ dub.sdl:
    name "aurora_allocation_profile"
    dependency "aurora" path=".."
+/
/**
 * Reproducible D-GC allocation profile for Aurora hot-path components.
 *
 * This intentionally measures only allocations visible to D's garbage
 * collector. Native allocations performed by Wire, libc or eventcore are
 * outside this counter and must not be inferred as zero from these results.
 */
module benchmarks.allocation_profile;

import aurora.http : HTTPRequest, HTTPResponse;
import aurora.http.util : buildResponseInto;
import aurora.web.context : Context;
import aurora.web.router : Router;
import core.memory : GC;
import std.datetime.stopwatch : AutoStart, StopWatch;
import std.stdio : writefln;

enum ITERATIONS = 100_000;
enum WARMUP_ITERATIONS = 10_000;

private __gshared size_t sink;

private struct Measurement
{
    string name;
    ulong allocatedBytes;
    size_t collections;
    double bytesPerOperation;
    double nanosecondsPerOperation;
}

private Measurement measure(alias operation)(string name)
{
    foreach (_; 0 .. WARMUP_ITERATIONS)
        operation();

    GC.collect();
    auto allocationBefore = GC.allocatedInCurrentThread();
    auto collectionsBefore = GC.profileStats().numCollections;

    GC.disable();
    scope(exit) GC.enable();

    auto watch = StopWatch(AutoStart.yes);
    foreach (_; 0 .. ITERATIONS)
        operation();
    watch.stop();

    auto allocationAfter = GC.allocatedInCurrentThread();
    auto collectionsAfter = GC.profileStats().numCollections;
    auto allocated = allocationAfter - allocationBefore;
    auto elapsedNanoseconds = watch.peek().total!"nsecs";

    return Measurement(
        name,
        allocated,
        collectionsAfter - collectionsBefore,
        cast(double)allocated / cast(double)ITERATIONS,
        cast(double)elapsedNanoseconds / cast(double)ITERATIONS
    );
}

private void emit(Measurement result)
{
    writefln(
        `{"path":"%s","iterations":%d,"warmup_iterations":%d,` ~
        `"d_gc_allocated_bytes":%d,"d_gc_bytes_per_op":%.4f,` ~
        `"d_gc_collections":%d,"nanoseconds_per_op":%.4f}`,
        result.name,
        ITERATIONS,
        WARMUP_ITERATIONS,
        result.allocatedBytes,
        result.bytesPerOperation,
        result.collections,
        result.nanosecondsPerOperation
    );
}

private void emitAndRequireZero(Measurement result)
{
    emit(result);
    if (result.allocatedBytes != 0 || result.collections != 0)
    {
        throw new Exception(
            result.name ~ " violated its zero-D-GC allocation contract"
        );
    }
}

void main()
{
    auto requestBytes = cast(ubyte[])(
        "GET / HTTP/1.1\r\n" ~
        "Host: localhost\r\n" ~
        "Connection: keep-alive\r\n\r\n"
    ).dup;
    auto parsedRequest = HTTPRequest.parse(requestBytes);

    auto router = new Router();
    router.get("/", (ref Context ctx) {
        ctx.send("Hello, World!");
    });
    router.get("/users/:id", (ref Context ctx) {
        ctx.send("user");
    });

    ubyte[4096] responseBuffer;

    void parseCore()
    {
        auto request = HTTPRequest.parse(requestBytes);
        sink += request.isComplete();
    }

    void keepAliveFlag()
    {
        sink += parsedRequest.shouldKeepAlive();
    }

    void convenienceAccessors()
    {
        auto method = parsedRequest.method();
        auto path = parsedRequest.path();
        sink += method.length + path.length;
    }

    void rawAccessors()
    {
        auto method = parsedRequest.methodRaw();
        auto path = parsedRequest.pathRaw();
        sink += method.length + path.length;
    }

    void staticRoute()
    {
        auto matched = router.match("GET", "/");
        sink += matched.found;
    }

    void parameterRoute()
    {
        auto matched = router.match("GET", "/users/42");
        sink += matched.params["id"].length;
    }

    void responseBuilder()
    {
        sink += buildResponseInto(
            responseBuffer[],
            200,
            "text/plain",
            "Hello, World!",
            true
        );
    }

    void responseLifecycle()
    {
        auto response = HTTPResponse(200, "OK");
        response.setBody("Hello, World!");
        sink += response.getBody().length;
    }

    void routedRequestNoIo()
    {
        auto matched = router.match(
            cast(string)parsedRequest.methodRaw(),
            cast(string)parsedRequest.pathRaw()
        );

        auto response = HTTPResponse(200, "OK");
        Context context;
        context.request = &parsedRequest;
        context.response = &response;
        if (matched.handler !is null)
            matched.handler(context);

        sink += buildResponseInto(
            responseBuffer[],
            response.status,
            response.getContentType(),
            response.getBody(),
            parsedRequest.shouldKeepAlive()
        );
    }

    writefln(
        `{"schema":"aurora-d-gc-profile-v1","allocation_scope":` ~
        `"D GC only; native allocations and network I/O excluded"}`
    );
    emitAndRequireZero(measure!parseCore("parser-core"));
    emitAndRequireZero(measure!keepAliveFlag("keep-alive-flag"));
    emit(measure!convenienceAccessors("method-plus-path"));
    emitAndRequireZero(measure!rawAccessors("method-plus-path-raw"));
    emitAndRequireZero(measure!staticRoute("router-static"));
    emitAndRequireZero(measure!parameterRoute("router-inline-param"));
    emitAndRequireZero(
        measure!responseBuilder("preallocated-response-builder")
    );
    emit(measure!responseLifecycle("response-object-lifecycle"));
    emit(measure!routedRequestNoIo("routed-request-no-io"));
    writefln(`{"sink":%d}`, sink);
}
