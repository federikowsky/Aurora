#!/usr/bin/env python3
"""Aurora NUMA / memory-locality micro-suite."""

from __future__ import annotations

import argparse
import csv
import json
import os
import platform
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run/report Aurora NUMA memory-locality checks.")
    parser.add_argument("--out-dir", default="artifacts/perf/numa", help="Artifact output directory.")
    parser.add_argument("--threads", type=int, default=1, help="Worker threads per scenario.")
    parser.add_argument("--size-mib", type=int, default=64, help="Total bytearray size per scenario.")
    parser.add_argument("--stride", type=int, default=64, help="Access stride in bytes.")
    parser.add_argument("--passes", type=int, default=4, help="Sequential passes over the buffer.")
    parser.add_argument("--cpu-node", type=int, default=0, help="CPU node for local/remote scenarios.")
    parser.add_argument("--local-mem-node", type=int, default=0, help="Memory node for local scenario.")
    parser.add_argument("--remote-mem-node", type=int, default=1, help="Memory node for remote scenario.")
    parser.add_argument("--cpu", type=int, default=None, help="Optional explicit CPU affinity for the current process.")
    parser.add_argument("--membind", type=int, default=None, help="Optional explicit numactl membind for direct child scenario.")
    parser.add_argument("--child-scenario", default=None, help=argparse.SUPPRESS)
    parser.add_argument("--enforce", action="store_true", help="Fail when NUMA is supported and a scenario fails.")
    return parser.parse_args()


def online_nodes() -> list[int]:
    node_root = Path("/sys/devices/system/node")
    nodes: list[int] = []
    if not node_root.exists():
        return nodes
    for path in sorted(node_root.glob("node[0-9]*")):
        try:
            nodes.append(int(path.name[4:]))
        except ValueError:
            pass
    return nodes


def set_cpu_affinity(cpu: int | None) -> str | None:
    if cpu is None or not hasattr(os, "sched_setaffinity"):
        return None
    try:
        os.sched_setaffinity(0, {cpu})
        return f"pinned-cpu-{cpu}"
    except OSError as exc:
        return f"cpu-affinity-failed: {exc}"


def touch_memory(size_mib: int, stride: int, passes: int, threads: int) -> dict:
    if size_mib <= 0 or stride <= 0 or threads <= 0:
        raise ValueError("size, stride, and threads must be positive")
    total_size = size_mib * 1024 * 1024
    chunk_size = max(stride, total_size // threads)

    def worker(index: int) -> tuple[int, int]:
        start = index * chunk_size
        end = total_size if index == threads - 1 else min(total_size, (index + 1) * chunk_size)
        buf = bytearray(end - start)
        operations = 0
        checksum = 0
        for current_pass in range(passes):
            value = current_pass & 0xFF
            for offset in range(0, len(buf), stride):
                buf[offset] = (buf[offset] + value + 1) & 0xFF
                checksum ^= buf[offset]
                operations += 1
        return operations, checksum

    start_ns = time.perf_counter_ns()
    with ThreadPoolExecutor(max_workers=threads) as executor:
        results = list(executor.map(worker, range(threads)))
    elapsed_ns = max(time.perf_counter_ns() - start_ns, 1)
    operations = sum(item[0] for item in results)
    checksum = 0
    for _, part in results:
        checksum ^= part
    bytes_touched = operations * stride
    elapsed_sec = elapsed_ns / 1_000_000_000.0
    return {
        "operations": operations,
        "bytes_touched": bytes_touched,
        "elapsed_sec": elapsed_sec,
        "bandwidth_mib_s": (bytes_touched / (1024 * 1024)) / elapsed_sec,
        "ns_per_access": elapsed_ns / max(operations, 1),
        "checksum": checksum,
    }


def run_child(args: argparse.Namespace) -> int:
    result = {
        "scenario": args.child_scenario or "direct",
        "status": "ok",
        "affinity": set_cpu_affinity(args.cpu),
        "cpu": args.cpu,
        "membind": args.membind,
        "threads": args.threads,
        "size_mib": args.size_mib,
        "stride": args.stride,
        "passes": args.passes,
    }
    try:
        result.update(touch_memory(args.size_mib, args.stride, args.passes, args.threads))
    except Exception as exc:
        result["status"] = "failed"
        result["error"] = str(exc)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / f"{result['scenario']}.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] == "ok" else 1


def run_numactl_scenario(args: argparse.Namespace, scenario: str, cpu_node: int, mem_node: int) -> dict:
    numactl = shutil.which("numactl")
    command = [
        numactl or "numactl",
        f"--cpunodebind={cpu_node}",
        f"--membind={mem_node}",
        sys.executable,
        __file__,
        "--out-dir", args.out_dir,
        "--threads", str(args.threads),
        "--size-mib", str(args.size_mib),
        "--stride", str(args.stride),
        "--passes", str(args.passes),
        "--child-scenario", scenario,
    ]
    if numactl is None:
        return {"scenario": scenario, "status": "skipped", "reason": "numactl-not-found", "command": command}
    completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    artifact = Path(args.out_dir) / f"{scenario}.json"
    if artifact.exists():
        try:
            result = json.loads(artifact.read_text(encoding="utf-8"))
            result["command"] = command
            result["stderr"] = completed.stderr.strip()
            return result
        except json.JSONDecodeError:
            pass
    return {"scenario": scenario, "status": "failed" if completed.returncode else "ok", "returncode": completed.returncode, "stdout": completed.stdout[-4000:], "stderr": completed.stderr[-4000:], "command": command}


def write_summary(out_dir: Path, summary: dict) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "numa.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with (out_dir / "numa_results.csv").open("w", newline="", encoding="utf-8") as handle:
        fields = ["scenario", "status", "bandwidth_mib_s", "ns_per_access", "threads", "size_mib", "stride", "reason"]
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for item in summary.get("results", []):
            writer.writerow({field: item.get(field, "") for field in fields})
    lines = [
        "# Aurora NUMA / Memory Locality Report", "",
        f"- Status: `{summary['status']}`",
        f"- Platform: `{summary['platform']}`",
        f"- NUMA nodes: `{summary['numa_nodes']}`",
        f"- numactl: `{summary['numactl']}`", "",
        "## Results", "",
        "| Scenario | Status | Bandwidth MiB/s | ns/access | Reason |",
        "| --- | --- | ---: | ---: | --- |",
    ]
    for item in summary.get("results", []):
        lines.append(f"| {item.get('scenario', '')} | {item.get('status', '')} | {item.get('bandwidth_mib_s', '')} | {item.get('ns_per_access', '')} | {item.get('reason', '')} |")
    (out_dir / "numa_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    if args.child_scenario:
        return run_child(args)
    out_dir = Path(args.out_dir)
    nodes = online_nodes()
    is_linux = platform.system() == "Linux"
    numactl = shutil.which("numactl")
    supported = is_linux and len(nodes) >= 2 and numactl is not None
    summary = {
        "status": "ok" if supported else "skipped",
        "platform": platform.platform(),
        "python": platform.python_version(),
        "numa_nodes": nodes,
        "numactl": numactl,
        "parameters": {"threads": args.threads, "size_mib": args.size_mib, "stride": args.stride, "passes": args.passes, "cpu_node": args.cpu_node, "local_mem_node": args.local_mem_node, "remote_mem_node": args.remote_mem_node},
        "results": [],
    }
    if not is_linux:
        summary["reason"] = "non-linux-platform"
        summary["results"].append({"scenario": "numa", "status": "skipped", "reason": "non-linux-platform"})
    elif len(nodes) < 2:
        summary["reason"] = "less-than-two-numa-nodes"
        summary["results"].append({"scenario": "numa", "status": "skipped", "reason": "less-than-two-numa-nodes"})
    elif numactl is None:
        summary["reason"] = "numactl-not-found"
        summary["results"].append({"scenario": "numa", "status": "skipped", "reason": "numactl-not-found"})
    else:
        summary["results"].extend([
            run_numactl_scenario(args, "local", args.cpu_node, args.local_mem_node),
            run_numactl_scenario(args, "remote", args.cpu_node, args.remote_mem_node),
        ])
        summary["status"] = "failed" if any(item.get("status") == "failed" for item in summary["results"]) else "ok"
    write_summary(out_dir, summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as handle:
            handle.write("\n## Aurora NUMA / memory-locality report\n")
            handle.write((out_dir / "numa_report.md").read_text(encoding="utf-8"))
    print(json.dumps({"status": summary["status"], "reason": summary.get("reason"), "nodes": nodes}, indent=2))
    return 1 if args.enforce and summary["status"] == "failed" else 0


if __name__ == "__main__":
    raise SystemExit(main())
