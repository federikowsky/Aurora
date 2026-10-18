#!/usr/bin/env python3
"""Linux A/A–A/B evidence, using canonical servers and pinned wrk.

CPU/request includes startup, byte control, warm-up and shutdown; not a pure
steady-state counter. Collection success is not a performance/readiness gate.
"""
import argparse
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import resource
import signal
import socket
import subprocess
import sys
import time


def parse_wrk(text):
    requests = re.search(r"(\d+) requests in", text)
    rate = re.search(r"Requests/sec:\s+([\d.]+)", text)
    if not requests or not rate:
        raise ValueError("wrk output lacks request count/rate")
    errors = re.findall(r".*(?:Socket errors|Non-2xx).*", text)
    percentiles = {k: float(v) for k, v in re.findall(r"(p\d+)_us=([\d.]+)", text)}
    if set(percentiles) != {"p50", "p95", "p99", "p999"}:
        raise ValueError("wrk output lacks required percentiles")
    return dict(requests=int(requests[1]), rps=float(rate[1]),
                errors=errors, eligible=not errors, **percentiles)


def reap(process):
    deadline = time.monotonic() + 10
    while True:
        pid, status, usage = os.wait4(process.pid, os.WNOHANG)
        if pid:
            process.returncode = os.waitstatus_to_exitcode(status)
            if process.returncode:
                raise RuntimeError(f"server exit {process.returncode}")
            return usage
        if time.monotonic() > deadline:
            process.kill()
            _, status, _ = os.wait4(process.pid, 0)
            process.returncode = os.waitstatus_to_exitcode(status)
            raise TimeoutError("server shutdown exceeded 10 seconds")
        time.sleep(.02)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("base", "candidate", "wrk", "output"):
        parser.add_argument(name, type=lambda x: Path(x).resolve())
    parser.add_argument("--blocks", type=int, default=5)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--server-cpus", default="0,1")
    parser.add_argument("--client-cpus", default="2,3")
    args = parser.parse_args()
    server_cpus = {int(x) for x in args.server_cpus.split(",")}
    client_cpus = {int(x) for x in args.client_cpus.split(",")}
    assert server_cpus and client_cpus and server_cpus.isdisjoint(client_cpus)
    assert server_cpus | client_cpus <= os.sched_getaffinity(0)
    assert args.blocks > 0 and args.limit >= 0
    args.output.mkdir(parents=True, exist_ok=True)
    calibration = subprocess.Popen([sys.executable, "-c",
        "import time; end=time.monotonic()+.8\nwhile time.monotonic()<end: pass\nprint(time.process_time())"],
        stdout=subprocess.PIPE)
    _, status, cpu_check = os.wait4(calibration.pid, 0)
    calibration.returncode = os.waitstatus_to_exitcode(status)
    child_cpu = float(calibration.stdout.read())
    observed_cpu = cpu_check.ru_utime + cpu_check.ru_stime
    assert calibration.returncode == 0 and .5 < observed_cpu < 1.5
    assert abs(child_cpu - observed_cpu) < .1, "CPU accounting calibration disagrees"
    identity = dict(arguments={k: str(v) for k, v in vars(args).items()},
                    hashes={n: hashlib.sha256(getattr(args, n).read_bytes()).hexdigest()
                            for n in ("base", "candidate", "wrk")},
                    cpu_scope="whole server process incl. startup/control/warmup/shutdown",
                    warmup_seconds=2, measurement_seconds=5, connections=100,
                    workers=len(server_cpus), client_threads=len(client_cpus),
                    calibration=dict(wait4_cpu_s=observed_cpu, process_cpu_s=child_cpu))
    (args.output / "identity.json").write_text(json.dumps(identity, indent=2))
    lua = '''done = function(summary, latency, requests)
  io.write(string.format("p50_us=%.3f p95_us=%.3f p99_us=%.3f p999_us=%.3f\\n",
    latency:percentile(50), latency:percentile(95), latency:percentile(99), latency:percentile(99.9)))
end
'''
    (args.output / "latency.lua").write_text(lua)
    (args.output / "echo.lua").write_text('wrk.method="POST"\nwrk.body=string.rep("e",1024)\n' + lua)
    # A1/A2 deliberately execute exactly the same binary.
    schedule = [("A1", "B", "A2"), ("B", "A2", "A1"), ("A2", "A1", "B")]
    rows = []
    for block in range(args.blocks):
        for route in ("/", "/json", "/echo"):
            for label in schedule[block % len(schedule)]:
                # SO_REUSEPORT must not silently admit a second benchmark server.
                with socket.socket() as guard:
                    guard.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                    guard.bind(("127.0.0.1", 8080))
                binary = args.candidate if label == "B" else args.base
                stem = f"{block}-{label}-{route.strip('/') or 'plain'}"
                cmd = ["taskset", "-c", args.server_cpus, str(binary),
                       f"--workers={len(server_cpus)}", f"--in-flight={args.limit}"]
                with (args.output / (stem + "-server.log")).open("w") as log:
                    process = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
                    samples = []
                    try:
                        for _ in range(200):
                            try:
                                with socket.create_connection(("127.0.0.1", 8080), .1):
                                    break
                            except OSError:
                                time.sleep(.025)
                        else:
                            raise TimeoutError("server readiness")
                        c = http.client.HTTPConnection("127.0.0.1", 8080, timeout=5)
                        payload = b"\x00\xff" * 32768 if route == "/echo" else None
                        c.request("POST" if payload else "GET", route, body=payload)
                        response = c.getresponse()
                        body = response.read()
                        assert response.status == 200
                        if route == "/json":
                            assert json.loads(body) == {"message": "Hello, World!"}
                        else:
                            assert body == (payload or b"Hello, World!")
                        c.close()
                        for duration, phase in ((2, "warmup"), (5, "measure")):
                            script = args.output / ("echo.lua" if payload else "latency.lua")
                            load_cmd = ["taskset", "-c", args.client_cpus, str(args.wrk),
                                        f"-t{len(client_cpus)}", "-c100", f"-d{duration}s",
                                        "--latency", "-s", str(script),
                                        "http://127.0.0.1:8080" + route]
                            before = resource.getrusage(resource.RUSAGE_CHILDREN)
                            result = subprocess.run(load_cmd, capture_output=True, timeout=duration + 15)
                            after = resource.getrusage(resource.RUSAGE_CHILDREN)
                            raw = result.stdout.decode() + result.stderr.decode()
                            (args.output / (stem + "-" + phase + ".log")).write_text(raw)
                            result.check_returncode()
                            sample = parse_wrk(raw)
                            sample.update(phase=phase, command=load_cmd,
                                          client_cpu_s=(after.ru_utime + after.ru_stime -
                                                        before.ru_utime - before.ru_stime))
                            samples.append(sample)
                    finally:
                        try:
                            process.send_signal(signal.SIGINT)
                        except ProcessLookupError:
                            pass
                        usage = reap(process)
                    count = 1 + sum(x["requests"] for x in samples)
                    cpu = usage.ru_utime + usage.ru_stime
                    assert cpu > 0, "invalid server CPU accounting"
                    eligible = all(x["eligible"] for x in samples)
                    row = dict(block=block, label=label, route=route, command=cmd,
                               samples=samples, cpu_s=cpu, requests_including_control=count,
                               eligible=eligible,
                               cpu_us_per_request=cpu * 1e6 / count if eligible else None,
                               maxrss_kib=usage.ru_maxrss,
                               voluntary_switches=usage.ru_nvcsw,
                               involuntary_switches=usage.ru_nivcsw)
                    rows.append(row)
                    (args.output / "results.json").write_text(json.dumps(rows, indent=2))
                    print(stem, f"{row['cpu_us_per_request']:.3f} CPU us/request" if eligible
                          else "INELIGIBLE: socket/status error", flush=True)
    if any(not row["eligible"] for row in rows):
        raise SystemExit("Errors make rows ineligible; raw evidence retained, no performance pass")


if __name__ == "__main__":
    main()
