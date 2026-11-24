#!/usr/bin/env python3
"""Matched release binaries, A/A control, rotated orders, verified HTTP responses."""
import argparse
import concurrent.futures
import csv
import http.client
import json
import os
from pathlib import Path
import platform
import socket
import subprocess
import tempfile
import threading
import time


def launch(args, cmd):
    return (["taskset", "-c", args.server_cpus] if args.server_cpus else []) + cmd


def component(args, binary, mode, block, tag):
    cmd = launch(args, [binary, mode, str(args.iterations)])
    raw = subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=120).stdout
    (args.output / f"{block}-{tag}-component.csv").write_text(raw)
    rows = {}
    for name, n, warm, ns, size, gc in csv.reader(raw.splitlines()):
        rows[name] = dict(n=int(n), warm=int(warm), ns_op=int(ns)/int(n),
                          dgc_B_op=int(size)/int(n), collections=int(gc))
    if len(rows) != 11:
        raise RuntimeError(f"incomplete component results: {rows}")
    return rows


# The two public cases distinguish bare/global at component level. On the socket
# both pass through the same real App policy; all configurations serve the same mix.
cases = [("/public", 200, b"ok"), ("/public", 200, b"ok"), ("/items", 200, b"ok"),
         ("/items/42", 200, b"ok"), ("/items/42", 403, b"denied"), ("/missing", 404, None)]


def client_request(conn, i):
    path, code, body = cases[i]
    conn.request("GET", path, headers={"X-Access": "none" if i == 4 else "accepted"})
    res = conn.getresponse()
    data = res.read()
    ok = (data == body) if body is not None else (json.loads(data) == {"error": "Not Found"})
    if not (ok and res.status == code and res.getheader("X-Global") == "yes" and
            res.getheader("X-Id") == ("42" if i == 3 else None)):
        raise RuntimeError((i, res.status, res.getheaders(), data))


def socket_sample(args, binary, mode, block, tag):
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    with tempfile.TemporaryDirectory() as tmp, (args.output / f"{block}-{tag}-server.log").open("wb") as log:
        stop = Path(tmp) / "stop"
        proc = subprocess.Popen(launch(args, [binary, mode, str(port), str(stop)]),
                                stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 8
            while True:
                try:
                    with socket.create_connection(("127.0.0.1", port), .15):
                        break
                except OSError:
                    if proc.poll() is not None or time.monotonic() >= deadline:
                        raise RuntimeError("server not ready")
                    time.sleep(.01)
            times = {}
            def start():
                times["start"] = time.perf_counter_ns()
            def finish():
                times["end"] = time.perf_counter_ns()
            ready = threading.Barrier(args.clients, action=start, timeout=20)
            done = threading.Barrier(args.clients, action=finish, timeout=20)
            def worker(k):
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=4)
                try:
                    for i in range(args.warm):
                        client_request(conn, (k+i) % 6)
                    ready.wait()
                    samples = []
                    for i in range(args.requests):
                        t = time.perf_counter_ns()
                        client_request(conn, (k+i) % 6)
                        samples.append(time.perf_counter_ns()-t)
                    done.wait()
                    return samples
                except BaseException:
                    ready.abort()
                    done.abort()
                    raise
                finally:
                    conn.close()
            with concurrent.futures.ThreadPoolExecutor(args.clients) as pool:
                measured = [v for client in pool.map(worker, range(args.clients)) for v in client]
        finally:
            stop.touch()
            try:
                code = proc.wait(timeout=8)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
                raise RuntimeError("server failed to stop")
            if code:
                raise RuntimeError(f"server exited {code}")
    (args.output / f"{block}-{tag}-latency-ns.txt").write_text("\n".join(map(str, measured))+"\n")
    measured.sort()
    from math import ceil
    def q(p):
        return measured[ceil(len(measured)*p)-1]/1000
    return dict(ok=len(measured), errors=0, timeouts=0,
                rps=len(measured)*1e9/(times["end"]-times["start"]),
                p50_us=q(.50), p95_us=q(.95), p99_us=q(.99))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("baseline")
    p.add_argument("candidate")
    p.add_argument("output", type=Path)
    p.add_argument("--kind", choices=["component", "tcp"], required=True)
    p.add_argument("--blocks", type=int, default=8)
    p.add_argument("--iterations", type=int, default=60000)
    p.add_argument("--requests", type=int, default=240)
    p.add_argument("--warm", type=int, default=48)
    p.add_argument("--clients", type=int, default=4)
    p.add_argument("--server-cpus", default=None)
    args = p.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output/"config.json").write_text(json.dumps(dict(vars(args), output=str(args.output),
        python=platform.python_version(), platform=platform.platform(),
        driver_cpus=sorted(os.sched_getaffinity(0))), indent=2)+"\n")
    variants = dict(A1=(args.baseline, "manual"), A2=(args.baseline, "manual"),
                    M=(args.candidate, "manual"), B=(args.candidate, "bound"))
    orders = ["A1 A2 B M","A2 M A1 B","M B A2 A1","B A1 M A2"]
    run = component if args.kind == "component" else socket_sample
    with (args.output/"results.jsonl").open("w", buffering=1) as out:
        for block in range(args.blocks):
            for tag in orders[block % len(orders)].split():
                row = run(args, *variants[tag], block, tag)
                print(json.dumps(dict(block=block, tag=tag, result=row)), file=out)


if __name__ == "__main__":
    main()
