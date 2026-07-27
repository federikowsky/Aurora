#!/usr/bin/env python3
"""End-to-end HTTP/1.1 framing regression probe for Aurora."""

from __future__ import annotations

import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time


HOST = "127.0.0.1"
PORT = 8080


def receive_all(connection: socket.socket, timeout: float = 2.0) -> bytes:
    connection.settimeout(timeout)
    chunks: list[bytes] = []
    while True:
        try:
            chunk = connection.recv(65_536)
        except TimeoutError:
            break
        if not chunk:
            break
        chunks.append(chunk)
    return b"".join(chunks)


def wait_until_ready(process: subprocess.Popen[bytes]) -> None:
    deadline = time.monotonic() + 10.0
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(
                f"Aurora server exited before readiness (code {process.returncode})"
            )
        try:
            with socket.create_connection((HOST, PORT), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise TimeoutError("Aurora server did not listen within 10 seconds")


def verify_fragmented_content_length() -> None:
    with socket.create_connection((HOST, PORT), timeout=2.0) as connection:
        connection.sendall(
            b"POST /echo HTTP/1.1\r\n"
            b"Host: localhost\r\n"
            b"Content-Length: 5\r\n"
            b"Connection: close\r\n\r\n"
        )
        connection.settimeout(0.25)
        try:
            premature = connection.recv(4096)
        except TimeoutError:
            premature = b""
        assert premature == b"", f"premature response: {premature!r}"

        connection.sendall(b"hello")
        response = receive_all(connection)
        assert response.startswith(b"HTTP/1.1 200"), response
        assert response.endswith(b"hello"), response


def verify_pipelined_ordering() -> None:
    with socket.create_connection((HOST, PORT), timeout=2.0) as connection:
        connection.sendall(
            b"GET / HTTP/1.1\r\n"
            b"Host: localhost\r\n"
            b"Connection: keep-alive\r\n\r\n"
            b"GET /json HTTP/1.1\r\n"
            b"Host: localhost\r\n"
            b"Connection: close\r\n\r\n"
        )
        response = receive_all(connection)
        assert response.count(b"HTTP/1.1 200") == 2, response

        first_body = response.find(b"Hello, World!")
        second_body = response.find(b'{"message":"Hello, World!"}')
        assert first_body != -1, response
        assert second_body != -1, response
        assert first_body < second_body, response


def verify_fragmented_multichunk_body() -> None:
    with socket.create_connection((HOST, PORT), timeout=2.0) as connection:
        connection.sendall(
            b"POST /echo HTTP/1.1\r\n"
            b"Host: localhost\r\n"
            b"Transfer-Encoding: chunked\r\n"
            b"Connection: close\r\n\r\n"
        )
        connection.sendall(b"4\r\nWiki\r\n")
        time.sleep(0.05)

        connection.settimeout(0.15)
        try:
            premature = connection.recv(4096)
        except TimeoutError:
            premature = b""
        assert premature == b"", f"premature chunk response: {premature!r}"

        connection.sendall(b"5\r\npedia\r\n0\r\n\r\n")
        response = receive_all(connection)
        assert response.startswith(b"HTTP/1.1 200"), response
        assert response.endswith(b"Wikipedia"), response


def main() -> int:
    binary = Path(sys.argv[1] if len(sys.argv) > 1 else "benchmarks/aurora_benchmark")
    if not binary.is_file():
        raise FileNotFoundError(binary)

    process = subprocess.Popen(
        [str(binary.resolve())],
        start_new_session=True,
    )
    try:
        wait_until_ready(process)
        verify_fragmented_content_length()
        print("fragmented-content-length: PASS")
        verify_pipelined_ordering()
        print("pipelined-ordering: PASS")
        verify_fragmented_multichunk_body()
        print("fragmented-multichunk-body: PASS")
        return 0
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGINT)
            try:
                process.wait(timeout=5.0)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5.0)


if __name__ == "__main__":
    raise SystemExit(main())
