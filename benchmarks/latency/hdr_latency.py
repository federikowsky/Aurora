#!/usr/bin/env python3
"""Aurora latency benchmark with high-dynamic-range percentile artifacts."""

from __future__ import annotations

import argparse
import csv
import http.client
import json
import math
import os
import platform
import socket
import statistics
import sys
import threading
import time
from pathlib import Path
from urllib.parse import urlparse


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run an Aurora HTTP latency benchmark and write p50/p90/p99/p999 artifacts.")
    parser.add_argument("--url", default="http://127.0.0.1:8080/", help="HTTP URL to benchmark.")
    parser.add_argument("--duration-sec", type=float, default=8.0, help="Measured benchmark duration.")
    parser.add_argument("--warmup-sec", type=float, default=2.0, help="Warmup duration before recording.")
    parser.add_argument("--connections", type=int, default=16, help="Parallel keep-alive client connections.")
    parser.add_argument("--timeout-sec", type=float, default=3.0, help="Per-request socket timeout.")
    parser.add_argument("--out-dir", default="artifacts/perf/latency", help="Output artifact directory.")
    parser.add_argument("--baseline", default="benchmarks/latency/baseline.json", help="Baseline/guard policy JSON.")
    return parser.parse_args()


def percentile(sorted_values: list[int], pct: float) -> int | None:
    if not sorted_values:
        return None
    if pct <= 0:
        return sorted_values[0]
    if pct >= 100:
        return sorted_values[-1]
    rank = math.ceil((pct / 100.0) * len(sorted_values))
    return sorted_values[max(0, min(len(sorted_values) - 1, rank - 1))]


def ns_to_us(value: int | None) -> float | None:
    return None if value is None else value / 1_000.0


def request_loop(parsed_url, deadline: float, record: bool, timeout_sec: float, stop_event: threading.Event) -> dict:
    latencies: list[int] = []
    errors = 0
    requests = 0
    host = parsed_url.hostname or "127.0.0.1"
    port = parsed_url.port or (443 if parsed_url.scheme == "https" else 80)
    path = parsed_url.path or "/"
    if parsed_url.query:
        path += "?" + parsed_url.query

    conn = None

    def connect():
        if parsed_url.scheme == "https":
            return http.client.HTTPSConnection(host, port, timeout=timeout_sec)
        return http.client.HTTPConnection(host, port, timeout=timeout_sec)

    while time.perf_counter() < deadline and not stop_event.is_set():
        if conn is None:
            conn = connect()
        start = time.perf_counter_ns()
        try:
            conn.request("GET", path, headers={"Connection": "keep-alive"})
            response = conn.getresponse()
            response.read()
            if response.status >= 500:
                errors += 1
                continue
            requests += 1
            if record:
                latencies.append(time.perf_counter_ns() - start)
        except (OSError, http.client.HTTPException, socket.timeout):
            errors += 1
            try:
                conn.close()
            except Exception:
                pass
            conn = None

    if conn is not None:
        try:
            conn.close()
        except Exception:
            pass
    return {"latencies_ns": latencies, "errors": errors, "requests": requests}


def run_phase(parsed_url, duration_sec: float, connections: int, timeout_sec: float, record: bool) -> dict:
    deadline = time.perf_counter() + duration_sec
    stop_event = threading.Event()
    results: list[dict] = []
    lock = threading.Lock()

    def target():
        result = request_loop(parsed_url, deadline, record, timeout_sec, stop_event)
        with lock:
            results.append(result)

    threads = [threading.Thread(target=target, daemon=True) for _ in range(connections)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=max(1.0, duration_sec + timeout_sec + 1.0))
    stop_event.set()

    merged: list[int] = []
    errors = 0
    requests = 0
    for result in results:
        merged.extend(result["latencies_ns"])
        errors += int(result["errors"])
        requests += int(result["requests"])
    return {"latencies_ns": merged, "errors": errors, "requests": requests}


def load_policy(path: Path) -> dict:
    if not path.exists():
        return {
            "mode": "absolute-sanity",
            "relative_guard_enabled": False,
            "absolute_guard": {"p99_us_max": 1_000_000, "p999_us_max": 2_000_000, "throughput_rps_min": 10.0},
        }
    return json.loads(path.read_text(encoding="utf-8"))


def evaluate_guard(summary: dict, policy: dict) -> dict:
    guard = policy.get("absolute_guard", {})
    failures: list[str] = []
    p99_us = summary["latency_us"].get("p99")
    p999_us = summary["latency_us"].get("p999")
    throughput = float(summary.get("throughput_rps", 0.0))
    if guard.get("p99_us_max") is not None and p99_us is not None and p99_us > float(guard["p99_us_max"]):
        failures.append(f"p99_us {p99_us:.3f} > absolute guard {float(guard['p99_us_max']):.3f}")
    if guard.get("p999_us_max") is not None and p999_us is not None and p999_us > float(guard["p999_us_max"]):
        failures.append(f"p999_us {p999_us:.3f} > absolute guard {float(guard['p999_us_max']):.3f}")
    if guard.get("throughput_rps_min") is not None and throughput < float(guard["throughput_rps_min"]):
        failures.append(f"throughput_rps {throughput:.3f} < absolute guard {float(guard['throughput_rps_min']):.3f}")

    baseline = policy.get("baseline", {})
    relative_report = {}
    for metric, current in {"p99_us": p99_us, "p999_us": p999_us, "throughput_rps": throughput}.items():
        base = baseline.get(metric)
        if current is not None and base:
            relative_report[metric] = {"current": float(current), "baseline": float(base), "ratio": float(current) / float(base)}

    return {
        "status": "fail" if failures else "pass",
        "mode": policy.get("mode", "absolute-sanity"),
        "relative_guard_enabled": bool(policy.get("relative_guard_enabled", False)),
        "relative_report": relative_report,
        "failures": failures,
        "note": policy.get("note", ""),
    }


def histogram_rows(latencies_ns: list[int]) -> list[dict[str, int]]:
    buckets: dict[int, int] = {}
    for latency_ns in latencies_ns:
        latency_us = max(1, math.ceil(latency_ns / 1_000))
        upper = 1 << (latency_us - 1).bit_length()
        buckets[upper] = buckets.get(upper, 0) + 1
    return [{"le_us": key, "count": buckets[key]} for key in sorted(buckets)]


def write_artifacts(out_dir: Path, summary: dict, latencies_ns: list[int]) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "latency.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    with (out_dir / "latency_metrics.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["metric", "value", "unit"])
        writer.writerow(["requests", summary["requests"], "count"])
        writer.writerow(["errors", summary["errors"], "count"])
        writer.writerow(["throughput", f'{summary["throughput_rps"]:.6f}', "requests/sec"])
        for name, value in summary["latency_us"].items():
            writer.writerow([name, "" if value is None else f"{value:.3f}", "microseconds"])

    with (out_dir / "latency_histogram.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["le_us", "count"])
        writer.writeheader()
        writer.writerows(histogram_rows(latencies_ns))

    total = len(latencies_ns)
    with (out_dir / "latency_percentiles.hdr").open("w", encoding="utf-8") as handle:
        handle.write("# Aurora high-dynamic-range latency percentile distribution\n")
        handle.write("# Text HDR-style artifact. Value is in microseconds.\n")
        handle.write('"Value","Percentile","TotalCount","1/(1-Percentile)"\n')
        for pct in (50.0, 75.0, 90.0, 95.0, 99.0, 99.9, 99.99, 100.0):
            value = ns_to_us(percentile(latencies_ns, pct)) or 0.0
            frac = pct / 100.0
            inverse = "Infinity" if pct >= 100 else f"{1.0 / (1.0 - frac):.3f}"
            handle.write(f"{value:.3f},{frac:.6f},{total},{inverse}\n")

    lines = [
        "# Aurora Latency Benchmark",
        "",
        f"- Status: `{summary['guard']['status']}`",
        f"- Requests: `{summary['requests']}`",
        f"- Errors: `{summary['errors']}`",
        f"- Throughput: `{summary['throughput_rps']:.2f} req/s`",
    ]
    for metric in ("p50", "p90", "p99", "p999"):
        value = summary["latency_us"][metric]
        lines.append(f"- {metric}: `{'n/a' if value is None else f'{value:.3f} us'}`")
    lines.extend(["", "## Guard", "", f"- Mode: `{summary['guard']['mode']}`", f"- Relative guard enabled: `{summary['guard']['relative_guard_enabled']}`"])
    if summary["guard"]["failures"]:
        lines.append("- Failures:")
        lines.extend(f"  - {failure}" for failure in summary["guard"]["failures"])
    else:
        lines.append("- Failures: none")
    (out_dir / "latency_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    parsed_url = urlparse(args.url)
    if parsed_url.scheme not in {"http", "https"}:
        print(f"unsupported URL scheme: {parsed_url.scheme}", file=sys.stderr)
        return 2
    if args.connections < 1:
        print("--connections must be >= 1", file=sys.stderr)
        return 2

    if args.warmup_sec > 0:
        run_phase(parsed_url, args.warmup_sec, args.connections, args.timeout_sec, record=False)

    start = time.perf_counter()
    measured = run_phase(parsed_url, args.duration_sec, args.connections, args.timeout_sec, record=True)
    elapsed = max(time.perf_counter() - start, 1e-9)
    latencies_ns = sorted(measured["latencies_ns"])
    mean_ns = int(statistics.fmean(latencies_ns)) if latencies_ns else None
    summary = {
        "url": args.url,
        "timestamp_unix": int(time.time()),
        "duration_sec": args.duration_sec,
        "elapsed_sec": elapsed,
        "connections": args.connections,
        "requests": measured["requests"],
        "errors": measured["errors"],
        "throughput_rps": measured["requests"] / elapsed,
        "latency_us": {
            "p50": ns_to_us(percentile(latencies_ns, 50.0)),
            "p90": ns_to_us(percentile(latencies_ns, 90.0)),
            "p99": ns_to_us(percentile(latencies_ns, 99.0)),
            "p999": ns_to_us(percentile(latencies_ns, 99.9)),
            "max": ns_to_us(percentile(latencies_ns, 100.0)),
            "mean": ns_to_us(mean_ns),
        },
        "environment": {"platform": platform.platform(), "python": platform.python_version(), "cpu_count": os.cpu_count()},
        "histogram": {"kind": "exact-sample-percentiles-with-power-of-two-us-buckets", "sample_count": len(latencies_ns)},
    }
    summary["guard"] = evaluate_guard(summary, load_policy(Path(args.baseline)))
    write_artifacts(Path(args.out_dir), summary, latencies_ns)
    print(json.dumps({"requests": summary["requests"], "throughput_rps": round(summary["throughput_rps"], 3), "p99_us": summary["latency_us"]["p99"], "p999_us": summary["latency_us"]["p999"], "guard": summary["guard"]["status"]}, indent=2))
    return 1 if summary["guard"]["status"] == "fail" else 0


if __name__ == "__main__":
    raise SystemExit(main())
