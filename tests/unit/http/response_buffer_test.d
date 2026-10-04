module tests.unit.http.response_buffer_test;

import aurora.http.util : buildResponseInto;
import std.conv : to;
import std.exception : enforce;

// Keep this call valid from the public hot-path attribute contract.
private size_t buildBounded(ubyte[] buffer, int status, const(char)[] contentType,
    const(char)[] body, bool keepAlive) @safe @nogc nothrow
{
    return buildResponseInto(buffer, status, contentType, body, keepAlive);
}

private void checkCapacity(int status, string reason, string contentType,
    string body, bool keepAlive, bool exhaustive = true)
{
    // The expected wire bytes are independent of the production status/number helpers.
    auto expected = "HTTP/1.1 " ~ to!string(status) ~ " " ~ reason ~ "\r\n" ~
        "Content-Type: " ~ contentType ~ "\r\nContent-Length: " ~
        to!string(body.length) ~ "\r\nConnection: " ~
        (keepAlive ? "keep-alive" : "close") ~ "\r\nServer: Aurora/0.2\r\n\r\n" ~ body;
    enum guardSize = 128;
    enum ubyte canary = 0xA5;
    auto storage = new ubyte[guardSize + expected.length + 8 + guardSize];
    auto mutableType = contentType.dup;
    auto mutableBody = body.dup;

    void check(size_t capacity)
    {
        storage[] = canary;
        auto supplied = storage[guardSize .. guardSize + capacity];
        auto written = buildBounded(supplied, status, mutableType, mutableBody, keepAlive);
        auto context = "status=" ~ to!string(status) ~ " capacity=" ~ to!string(capacity);

        foreach (value; storage[0 .. guardSize])
            enforce(value == canary, "response write before supplied slice: " ~ context);
        foreach (value; storage[guardSize + capacity .. $])
            enforce(value == canary, "response write after supplied slice: " ~ context);
        enforce(mutableType == contentType && mutableBody == body,
            "response builder changed its inputs: " ~ context);

        if (capacity < expected.length)
            enforce(written == 0, "undersized response reported success: " ~ context);
        else
        {
            enforce(written == expected.length, "incorrect response length: " ~ context);
            enforce(cast(const(char)[])supplied[0 .. written] == expected,
                "incorrect response framing or content: " ~ context);
            foreach (value; supplied[written .. $])
                enforce(value == canary, "response changed unused buffer tail: " ~ context);
        }
    }

    if (exhaustive)
        foreach (capacity; 0 .. expected.length + 9)
            check(capacity);
    else
    {
        // Large bodies exercise body-copy boundaries without quadratic test work.
        foreach (capacity; [size_t(0), 1, 16, 20, 64, 128, 256, 4096])
            check(capacity);
        foreach (capacity; expected.length - 8 .. expected.length + 9)
            check(capacity);
    }
}

@("response buffer never writes outside the supplied capacity")
unittest
{
    foreach (keepAlive; [false, true])
    {
        checkCapacity(200, "OK", "text/plain", "abc", keepAlive);
        checkCapacity(201, "Created", "", "", keepAlive);
        checkCapacity(418, "I'm a teapot", "application/json", "{\"ok\":true}", keepAlive);
        checkCapacity(431, "Request Header Fields Too Large", "text/plain", "x", keepAlive);
        checkCapacity(599, "Unknown", "text/plain", "uncommon status", keepAlive);
    }
}

@("response buffer bounds long headers and large binary bodies")
unittest
{
    import std.array : replicate;

    checkCapacity(200, "OK", "text/" ~ replicate("a", 4091), "abc", true);
    checkCapacity(418, "I'm a teapot", "application/octet-stream",
        replicate("\0\x7f\xff\r\n", 13_108), false, false);
}

@("response output does not borrow mutable inputs")
unittest
{
    auto contentType = "text/plain".dup;
    auto body = "abc".dup;
    ubyte[256] buffer;
    auto written = buildBounded(buffer[], 200, contentType, body, true);
    enforce(written != 0, "response did not fit in the test buffer");
    auto expected = buffer[0 .. written].dup;
    contentType[] = 'x';
    body[] = 'y';
    enforce(buffer[0 .. written] == expected, "response retained mutable input storage");
}
