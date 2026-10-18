#!/usr/bin/env python3
"""Check real canonical server configuration, startup, response and exit."""
from pathlib import Path
import http.client
import signal
import subprocess
import sys
import time

server = subprocess.Popen([str(Path(sys.argv[1]).resolve()), "--workers=1", "--in-flight=17"],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
try:
    for _ in range(100):
        try:
            c = http.client.HTTPConnection("127.0.0.1", 8080, timeout=.2)
            c.request("GET", "/")
            response = c.getresponse()
            assert response.status == 200 and response.read() == b"Hello, World!"
            c.close()
            break
        except OSError:
            if server.poll() is not None:
                raise AssertionError("server exited before readiness")
            time.sleep(.05)
    else:
        raise AssertionError("server readiness timeout")
finally:
    if server.poll() is None:
        server.send_signal(signal.SIGINT)
    try:
        output, _ = server.communicate(timeout=10)
    except subprocess.TimeoutExpired:
        server.kill()
        server.communicate()
        raise AssertionError("shutdown timeout")
assert server.returncode == 0, output
assert b"Workers: 1\n" in output, output
assert b"Max in-flight requests: 17\n" in output, output
print("PASS canonical benchmark worker/limit configuration and HTTP lifecycle")
