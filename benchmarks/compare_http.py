#!/usr/bin/env python3
"""Paired canonical-server smoke benchmark; raw data, never a readiness score.

Usage: compare_http.py BASE_BINARY CANDIDATE_BINARY WRK OUTPUT_DIRECTORY
Build and record both exact source revisions and runner/toolchain separately.
Keep this process alone on the runner. Client and server share the host;
closed-loop wrk latency does not establish an overload SLO.
"""
import http.client
import json
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time


def compare(base, candidate, wrk, output):
    output.mkdir(parents=True, exist_ok=True)
    records = []
    percentile = '''done = function(summary, latency, requests)
  io.write(string.format("p50_us=%.3f p95_us=%.3f p99_us=%.3f p999_us=%.3f\\n",
    latency:percentile(50), latency:percentile(95), latency:percentile(99), latency:percentile(99.9)))
end
'''
    (output / "percentiles.lua").write_text(percentile)
    (output / "echo.lua").write_text('wrk.method = "POST"\nwrk.body = string.rep("e", 1024)\n' + percentile)
    for pair in range(3):
        # Counterbalance order. Retain individual samples rather than hiding
        # startup/order effects in an aggregate score.
        variants = [("base", base), ("candidate", candidate)]
        if pair % 2:
            variants.reverse()
        for variant, binary in variants:
            name = f"pair-{pair}-{variant}"
            with (output / (name + "-server.log")).open("w") as server_log:
                process = subprocess.Popen([str(binary)], stdout=server_log,
                                           stderr=subprocess.STDOUT)
                try:
                    for _ in range(200):
                        if process.poll() is not None:
                            raise RuntimeError(f"{variant}: server exited at startup")
                        try:
                            with socket.create_connection(("127.0.0.1", 8080), .1):
                                break
                        except OSError:
                            time.sleep(.05)
                    else:
                        raise TimeoutError(f"{variant}: readiness timeout")
                    for route, expected in [("/", b"Hello, World!"),
                                            ("/echo", b"\x00\xff" * 32768)]:
                        c = http.client.HTTPConnection("127.0.0.1", 8080, timeout=5)
                        try:
                            c.request("POST" if route == "/echo" else "GET", route,
                                      body=expected if route == "/echo" else None)
                            response = c.getresponse()
                            if response.status != 200 or response.read() != expected:
                                raise AssertionError(f"{variant}: wrong {route} response")
                        finally:
                            c.close()
                    for route in ("/", "/json", "/echo"):
                        script = output / ("echo.lua" if route == "/echo" else "percentiles.lua")
                        for duration, phase in [("3s", "warmup"), ("10s", "measure")]:
                            cmd = [str(wrk), "-t4", "-c100", "-d" + duration,
                                   "--latency", "-s", str(script),
                                   "http://127.0.0.1:8080" + route]
                            start = time.time()
                            label = name + "-" + (route.strip("/") or "plain") + "-" + phase
                            with (output / (label + ".log")).open("w") as log:
                                result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
                            records.append(dict(pair=pair, variant=variant, route=route,
                                                phase=phase, cmd=cmd, start=start,
                                                end=time.time(), exit=result.returncode))
                            (output / "commands.json").write_text(json.dumps(records, indent=2))
                            result.check_returncode()
                        print(name, route, flush=True)
                finally:
                    process.send_signal(signal.SIGINT)
                    try:
                        code = process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                        raise RuntimeError(f"{variant}: shutdown timeout")
                    if code:
                        raise RuntimeError(f"{variant}: shutdown exit {code}")


if __name__ == "__main__":
    compare(*(Path(arg).resolve() for arg in sys.argv[1:]))
