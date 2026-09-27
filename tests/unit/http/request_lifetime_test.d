module tests.unit.http.request_lifetime_test;

import aurora.http : HTTPRequest;
import std.exception : enforce;

@("live requests retain their own metadata after another parse")
unittest
{
    // Both buffers and requests remain alive: a second parse must not reset
    // the first request's parser, even on the same OS thread.
    auto firstBytes = cast(ubyte[])("POST /first?owner=alpha HTTP/1.1\r\n" ~
        "Host: alpha\r\nX-Owner: first\r\nContent-Length: 3\r\n" ~
        "Connection: keep-alive\r\n\r\nONE").dup;
    auto secondBytes = cast(ubyte[])("PUT /second?owner=beta HTTP/1.1\r\n" ~
        "Host: beta\r\nX-Owner: second\r\nContent-Length: 3\r\n" ~
        "Connection: close\r\n\r\nTWO").dup;
    auto first = HTTPRequest.parse(firstBytes);
    {
        auto second = HTTPRequest.parse(secondBytes);
        enforce(second.methodRaw() == "PUT" && second.pathRaw() == "/second");
        enforce(second.body() == "TWO" && !second.shouldKeepAlive());
        enforce(first.methodRaw() == "POST", "another parse changed the method");
        enforce(first.pathRaw() == "/first", "another parse changed the path");
        enforce(first.queryParamRaw("owner") == "alpha", "another parse changed the query");
        enforce(first.getHeader("X-Owner") == "first", "another parse changed a header");
        enforce(first.body() == "ONE", "another parse changed the body");
        enforce(first.shouldKeepAlive() && first.isComplete() && !first.hasError());
    }
    // Releasing another request must not invalidate this one either.
    enforce(first.pathRaw() == "/first" && first.body() == "ONE");
}
