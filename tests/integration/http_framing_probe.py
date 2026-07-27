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


def receive_response(connection: socket.socket, timeout: float = 2.0) -> bytes:
    connection.settimeout(timeout)
    response = bytearray()
    while b"\r\n\r\n" not in response:
        chunk = connection.recv(65_536)
        if not chunk:
            raise AssertionError(f"connection closed before headers: {response!r}")
        response.extend(chunk)

    header_end = response.index(b"\r\n\r\n") + 4
    headers = response[:header_end]
    content_length = None
    for line in headers.split(b"\r\n"):
        name, separator, value = line.partition(b":")
        if separator and name.lower() == b"content-length":
            content_length = int(value.strip())
            break
    if content_length is None:
        raise AssertionError(f"missing Content-Length: {headers!r}")

    total_length = header_end + content_length
    while len(response) < total_length:
        chunk = connection.recv(min(65_536, total_length - len(response)))
        if not chunk:
            raise AssertionError(
                f"connection closed after {len(response)} of {total_length} bytes"
            )
        response.extend(chunk)
    return bytes(response)


def response_headers(response: bytes) -> dict[bytes, bytes]:
    header_block = response.split(b"\r\n\r\n", 1)[0]
    result: dict[bytes, bytes] = {}
    for line in header_block.split(b"\r\n")[1:]:
        name, separator, value = line.partition(b":")
        if separator:
            result[name.strip().lower()] = value.strip().lower()
    return result


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


def verify_connection_retirement_is_advertised() -> None:
    with socket.create_connection((HOST, PORT), timeout=2.0) as connection:
        request = (
            b"GET / HTTP/1.1\r\n"
            b"Host: localhost\r\n"
            b"Connection: keep-alive\r\n\r\n"
        )

        connection.sendall(request)
        first = receive_response(connection)
        assert response_headers(first).get(b"connection") == b"keep-alive", first

        connection.sendall(request)
        second = receive_response(connection)
        assert response_headers(second).get(b"connection") == b"close", second

        connection.settimeout(1.0)
        assert connection.recv(1) == b"", "server did not close retired connection"


def verify_write_timeout_closes_slow_reader() -> None:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as connection:
        connection.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4_096)
        connection.settimeout(3.0)
        connection.connect((HOST, PORT))
        connection.sendall(
            b"GET /large HTTP/1.1\r\n"
            b"Host: localhost\r\n"
            b"Connection: close\r\n\r\n"
        )

        # Do not consume the response until well after the 100 ms server
        # deadline. A correctly cancelled write must then terminate with a
        # truncated response instead of resuming and sending the full 32 MiB.
        time.sleep(0.5)
        received = receive_all(connection, timeout=3.0)
        header_end = received.find(b"\r\n\r\n")
        assert header_end >= 0, received[:256]
        declared = int(
            response_headers(received)[b"content-length"]
        )
        actual = len(received) - header_end - 4
        assert 0 < actual < declared, (actual, declared)


def main() -> int:
    binary = Path(
        sys.argv[1]
        if len(sys.argv) > 1
        else "tests/integration/aurora_protocol_probe_server"
    )
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
        verify_connection_retirement_is_advertised()
        print("connection-retirement-header: PASS")
        verify_write_timeout_closes_slow_reader()
        print("write-timeout: PASS")
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
