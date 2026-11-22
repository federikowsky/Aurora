#!/usr/bin/env python3
"""Exercise App middleware semantics over a real HTTP/1.1 socket."""

from __future__ import annotations

import contextlib
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time


def wait_for(predicate, message: str) -> None:
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.01)
    raise AssertionError(message)


@contextlib.contextmanager
def server(binary: str):
    with tempfile.TemporaryDirectory(prefix="aurora-middleware-") as tmp:
        directory = Path(tmp)
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        with (directory / "server.log").open("wb") as log:
            process = subprocess.Popen(
                [binary, str(port), tmp], stdout=log, stderr=log
            )
            try:
                def ready() -> bool:
                    if process.poll() is not None:
                        raise AssertionError(f"startup exit {process.returncode}")
                    try:
                        with socket.create_connection(("127.0.0.1", port), 0.1):
                            return True
                    except OSError:
                        return False

                wait_for(ready, "server did not start")
                yield port
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


def request(port: int, method: str, path: str) -> tuple[int, dict[bytes, bytes], bytes]:
    with socket.create_connection(("127.0.0.1", port), 5) as peer:
        peer.settimeout(2)
        peer.sendall(
            f"{method} {path} HTTP/1.1\r\n"
            "Host: localhost\r\n"
            "Connection: close\r\n\r\n".encode()
        )
        response = bytearray()
        while True:
            chunk = peer.recv(65_536)
            if not chunk:
                break
            response.extend(chunk)

    header_block, separator, body = bytes(response).partition(b"\r\n\r\n")
    assert separator, response
    lines = header_block.split(b"\r\n")
    status = int(lines[0].split()[1])
    headers: dict[bytes, bytes] = {}
    for line in lines[1:]:
        name, colon, value = line.partition(b":")
        assert colon, line
        headers[name.strip().lower()] = value.strip()
    return status, headers, body


def assert_global(headers: dict[bytes, bytes], order: bytes) -> None:
    assert headers.get(b"x-global-policy") == b"executed", headers
    assert headers.get(b"x-execution-order") == order, headers


def probe(port: int) -> None:
    status, headers, body = request(port, "GET", "/ok")
    assert (status, body) == (200, b"ok"), (status, headers, body)
    assert_global(headers, b"5")

    status, headers, body = request(port, "GET", "/missing")
    assert status == 404 and b"Not Found" in body, (status, headers, body)
    assert_global(headers, b"4")

    status, headers, body = request(port, "OPTIONS", "/missing")
    assert (status, body) == (204, b""), (status, headers, body)
    assert headers.get(b"x-preflight-policy") == b"handled", headers
    assert_global(headers, b"4")

    status, headers, body = request(port, "GET", "/blocked")
    assert (status, body) == (401, b"blocked"), (status, headers, body)
    assert_global(headers, b"4")

    status, headers, body = request(port, "GET", "/users/42")
    assert (status, body) == (200, b"user"), (status, headers, body)
    assert headers.get(b"x-route-id") == b"42", headers
    assert_global(headers, b"5")

    status, headers, body = request(port, "GET", "/api/nested")
    assert (status, body) == (200, b"nested"), (status, headers, body)
    assert_global(headers, b"5")

    status, headers, body = request(port, "GET", "/boom")
    assert (status, body) == (418, b"handled"), (status, headers, body)
    assert headers.get(b"x-global-policy") == b"executed", headers
    assert b"x-execution-order" not in headers, headers


if __name__ == "__main__":
    binary = str(Path(sys.argv[1]).resolve())
    try:
        with server(binary) as port:
            probe(port)
        print("PASS global middleware socket contract", flush=True)
    except (AssertionError, OSError) as error:
        print(f"FAIL global middleware socket contract: {error!r}", flush=True)
        sys.exit(1)
