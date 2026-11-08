#!/usr/bin/env python3
"""Exercise the Aurora-WebSocket consumer across an actual TCP upgrade."""
import contextlib
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time


def wait_for(predicate, message):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.01)
    raise AssertionError(message)


@contextlib.contextmanager
def server(binary):
    with tempfile.TemporaryDirectory(prefix="aurora-websocket-") as tmp:
        directory = Path(tmp)
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        with (directory / "server.log").open("wb") as log:
            process = subprocess.Popen([binary, str(port), tmp], stdout=log, stderr=log)
            try:
                def ready():
                    if process.poll() is not None:
                        raise AssertionError(f"startup exit {process.returncode}")
                    try:
                        with socket.create_connection(("127.0.0.1", port), .1):
                            return True
                    except OSError:
                        return False

                wait_for(ready, "server did not start")
                yield port, directory
            finally:
                (directory / "stop").touch()
                try:
                    code = process.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                    raise AssertionError("stop did not terminate the server")
                assert code == 0, (code, (directory / "server.log").read_text())
                assert (directory / "stopped").exists(), "App.listen() did not return"


def request(path, method=b"GET", version=b"1.1", key=b"dGhlIHNhbXBsZSBub25jZQ=="):
    return (method + b" " + path + b" HTTP/" + version + b"\r\n"
            b"Host: localhost\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n"
            b"Sec-WebSocket-Key: " + key + b"\r\n"
            b"Sec-WebSocket-Version: 13\r\n\r\n")


def handshake(reader, code):
    line = reader.readline()
    assert line.startswith(b"HTTP/1.1 " + code + b" "), line
    headers = {}
    while (line := reader.readline()) != b"\r\n":
        assert line, "EOF before end of handshake headers"
        name, value = line.split(b":", 1)
        headers[name.lower()] = value.strip()
    if code == b"101":
        assert headers[b"upgrade"].lower() == b"websocket", headers
        assert headers[b"sec-websocket-accept"] == b"s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", headers
    return headers


def send_frame(peer, opcode, payload):
    key = b"\x12\x34\x56\x78"
    peer.sendall(bytes((0x80 | opcode, 0x80 | len(payload))) + key + bytes(
        value ^ key[index % len(key)] for index, value in enumerate(payload)))


def echo_and_close(peer, reader):
    send_frame(peer, 1, b"echo")
    frame = reader.read(6)
    assert frame == b"\x81\x04echo", ("expected echo after upgrade", frame)
    frame = reader.read(4)
    assert frame == b"\x88\x02\x03\xe8", ("expected one normal close frame", frame)
    send_frame(peer, 8, b"\x03\xe8")
    assert reader.read(1) == b"", "socket did not close after the handshake"


def synchronous(port, directory):
    with socket.create_connection(("127.0.0.1", port), 5) as peer, peer.makefile("rb") as reader:
        peer.sendall(request(b"/sync"))
        handshake(reader, b"101")
        echo_and_close(peer, reader)


def reject_invalid(port, **fields):
    with socket.create_connection(("127.0.0.1", port), 5) as peer, peer.makefile("rb") as reader:
        peer.sendall(request(b"/sync", **fields))
        headers = handshake(reader, b"400")
        assert b"sec-websocket-accept" not in headers, headers
        assert reader.read(int(headers[b"content-length"])) == b"invalid upgrade"


if __name__ == "__main__":
    binary = str(Path(sys.argv[1]).resolve())
    failed = False
    cases = {
        "synchronous": synchronous,
        "reject_post": lambda port, _: reject_invalid(port, method=b"POST"),
        "reject_http_1_0": lambda port, _: reject_invalid(port, version=b"1.0"),
        "reject_invalid_alphabet": lambda port, _: reject_invalid(port, key=b"!GhlIHNhbXBsZSBub25jZQ=="),
        "reject_wrong_decoded_length": lambda port, _: reject_invalid(port, key=b"dGhlIHNhbXBsZSBub25jZQAA"),
    }
    with server(binary) as (port, directory):
        for name, case in cases.items():
            try:
                case(port, directory)
                print(f"PASS {name}", flush=True)
            except (AssertionError, OSError) as error:
                print(f"FAIL {name}: {error!r}", flush=True)
                failed = True
    sys.exit(int(failed))
