#!/usr/bin/env python3
"""Socket contract for server-wide in-flight admission and permit cleanup.

Uses an out-of-band filesystem barrier, so slow CI cannot make handlers finish
before competing requests arrive. Run against debug and release fixtures.
"""
import concurrent.futures
import contextlib
import pathlib
import signal
import socket
import subprocess
import sys
import tempfile
import time

from http_framing_probe import receive_all, receive_response, response_headers


def wait_for(predicate, message, seconds=10):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(0.01)
    raise AssertionError(message)


def send(port, path="/", keep_alive=False):
    connection = socket.create_connection(("127.0.0.1", port), timeout=3)
    connection.sendall(request(path, keep_alive))
    return connection


def request(path, keep_alive=False):
    return (f"GET {path} HTTP/1.1\r\nHost: localhost\r\nConnection: "
            f"{'keep-alive' if keep_alive else 'close'}\r\n\r\n").encode()


def status(connection, expected):
    response = receive_response(connection, timeout=5)
    actual = int(response.split(b" ", 2)[1])
    assert actual == expected, (actual, expected, response[:200])
    if expected == 503:
        headers = response_headers(response)
        assert headers[b"retry-after"] == b"5", headers
        assert headers[b"connection"] == b"close", headers
    return response


@contextlib.contextmanager
def server(binary, workers, limit):
    with tempfile.TemporaryDirectory(prefix="aurora-admission-") as tmp:
        directory = pathlib.Path(tmp)
        with socket.socket() as reserve:
            reserve.bind(("127.0.0.1", 0))
            port = reserve.getsockname()[1]
        with (directory / "server.log").open("wb") as log:
            process = subprocess.Popen([binary, str(port), str(workers),
                                        str(limit), tmp], stdout=log, stderr=log)
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
                (directory / "release").touch()
                process.send_signal(signal.SIGINT)
                try:
                    code = process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                    raise AssertionError("server failed to stop")
                if code != 0:
                    raise AssertionError(f"server exit {code}: " +
                                         (directory / "server.log").read_text())


def check_limit(binary, workers, limit):
    with server(binary, workers, limit) as (port, directory):
        count = limit or 4
        with contextlib.ExitStack() as sockets:
            holders = []
            for index in range(count):
                holders.append(sockets.enter_context(send(port, "/hold")))
                wait_for(lambda: (directory / f"entered-{index + 1}").exists(),
                         "handler was not admitted")
            if limit:
                def competitor(_):
                    with send(port, "/") as connection:
                        status(connection, 503)
                with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                    list(pool.map(competitor, range(8)))
            (directory / "release").touch()
            for connection in holders:
                status(connection, 200)
        # A subsequent request and repeated requests on one connection must
        # reacquire the permit; idle keep-alive must not hold it.
        with socket.create_connection(("127.0.0.1", port), timeout=3) as pipelined:
            pipelined.sendall(request("/", True) + request("/", False))
            response = receive_all(pipelined, timeout=5)
            assert response.count(b"HTTP/1.1 200 OK\r\n") == 2, response
            assert b"503 Service Unavailable" not in response, response
        with send(port, keep_alive=True) as connection:
            status(connection, 200)
            with send(port) as other:
                status(other, 200)
            for _ in range(3):
                connection.sendall(request("/", True))
                status(connection, 200)
        print(f"PASS limit workers={workers} limit={limit}", flush=True)


def check_exception(binary, workers):
    with server(binary, workers, 1) as (port, directory):
        with send(port, "/throw") as throwing:
            wait_for(lambda: (directory / "entered-1").exists(), "no handler")
            with send(port) as contender:
                status(contender, 503)
            (directory / "release").touch()
            status(throwing, 500)
        with send(port) as connection:
            status(connection, 200)
        print(f"PASS exception cleanup workers={workers}", flush=True)


def check_burst(binary, workers):
    with server(binary, workers, 2) as (port, directory):
        def contender(_):
            with send(port, "/hold") as connection:
                response = receive_response(connection, timeout=15)
                return int(response.split(b" ", 2)[1])
        with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
            futures = [pool.submit(contender, i) for i in range(16)]
            try:
                wait_for(lambda: sum(f.done() for f in futures) >= 14,
                         "burst did not reject excess requests")
                wait_for(lambda: len(list(directory.glob("entered-*"))) >= 2,
                         "admitted burst handlers did not enter")
                assert len(list(directory.glob("entered-*"))) == 2
                assert [f.result() for f in futures if f.done()] == [503] * 14
            finally:
                (directory / "release").touch()
            results = [f.result() for f in futures]
            assert results.count(200) == 2 and results.count(503) == 14, results
        with send(port) as connection:
            status(connection, 200)
        print(f"PASS burst atomic admission workers={workers}", flush=True)


def check_write_timeout(binary, workers):
    with server(binary, workers, 1) as (port, directory):
        with socket.socket() as slow:
            slow.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024)
            slow.connect(("127.0.0.1", port))
            slow.sendall(request("/large"))
            wait_for(lambda: (directory / "writing").exists(), "no response")
            # Receiving output proves the handler has returned and the writer
            # has started. Leave virtually all of the 32 MiB body unread.
            slow.settimeout(3)
            assert slow.recv(1) == b"H", "response write did not start"
            with send(port) as contender:
                status(contender, 503)
            # Poll until the write deadline releases the permit, even though
            # this peer remains connected and does not consume the body.
            def released():
                with send(port) as connection:
                    response = receive_response(connection, timeout=3)
                    code = int(response.split(b" ", 2)[1])
                    assert code in (200, 503), response[:200]
                    return code == 200
            wait_for(released, "permit retained after write timeout", seconds=5)
        print(f"PASS write timeout cleanup workers={workers}", flush=True)


if __name__ == "__main__":
    binary = str(pathlib.Path(sys.argv[1]).resolve())
    for workers in (1, 2):
        for limit in (1, 2, 0):
            check_limit(binary, workers, limit)
        check_exception(binary, workers)
        check_burst(binary, workers)
        check_write_timeout(binary, workers)
