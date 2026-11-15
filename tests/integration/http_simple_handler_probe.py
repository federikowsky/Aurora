#!/usr/bin/env python3
"""Verify that Server's low-level RequestHandler emits its ResponseBuffer."""
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
    with tempfile.TemporaryDirectory(prefix="aurora-simple-handler-") as tmp:
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
                assert (directory / "stopped").exists(), "Server.run() did not return"


def probe(port):
    with socket.create_connection(("127.0.0.1", port), 5) as peer, peer.makefile("rb") as reader:
        peer.settimeout(1)
        peer.sendall(
            b"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        )
        status = reader.readline()
        assert status.startswith(b"HTTP/1.1 200 "), status
        headers = {}
        while (line := reader.readline()) != b"\r\n":
            assert line, "EOF before response headers"
            name, value = line.split(b":", 1)
            headers[name.lower()] = value.strip()
        body = reader.read(int(headers[b"content-length"]))
        assert body == b"simple handler", body


if __name__ == "__main__":
    binary = str(Path(sys.argv[1]).resolve())
    try:
        with server(binary) as port:
            probe(port)
        print("PASS low-level RequestHandler response", flush=True)
    except (AssertionError, OSError) as error:
        print(f"FAIL low-level RequestHandler response: {error!r}", flush=True)
        sys.exit(1)
