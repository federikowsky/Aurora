/**
 * Test helper: parse a raw HTTP/1.1 request into Wire's ParsedHttpRequest.
 *
 * NOTE: This copies ParsedHttpRequest out of the parser instance (tests only).
 * Production code must keep ParsedHttpRequest by reference to avoid per-request copies.
 */
module tests.helpers.parsed_request;

import wire : ParserHandle, createParser, destroyParser, parseHTTPWith, getRequest;
import wire.types : ParsedHttpRequest;
import wire.bindings : llhttp_errno;

ParsedHttpRequest parseRequest(scope const(ubyte)[] data) @trusted
{
    auto parser = createParser();
    assert(parser !is null, "createParser() failed in tests");
    scope(exit) destroyParser(parser);

    // Tests may intentionally feed malformed requests; return the request either way.
    cast(void) parseHTTPWith(parser, data);
    return getRequest(parser);
}

bool parseOk(const ref ParsedHttpRequest req) @nogc nothrow @safe
{
    return req.content.errorCode == 0 || req.content.errorCode == cast(int) llhttp_errno.HPE_PAUSED_UPGRADE;
}
