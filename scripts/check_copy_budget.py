#!/usr/bin/env python3
"""Static zero-copy / copy-budget report for Aurora hot paths."""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
from dataclasses import asdict, dataclass
from pathlib import Path

DEFAULT_PATHS = [
    "source/aurora/runtime/server.d",
    "source/aurora/http",
    "source/aurora/web/router.d",
    "source/aurora/web/context.d",
    "source/aurora/mem",
]

PATTERNS = [
    ("gc_new", re.compile(r"\bnew\s+(?:ubyte|string|char|\w+)\b")),
    ("dup_idup", re.compile(r"\.(?:dup|idup)\b")),
    ("array_materialize", re.compile(r"\.array\b|\barray\s*\(")),
    ("string_concat", re.compile(r"(?<![<>=!~])~(?![=])")),
    ("to_string", re.compile(r"\bto!\s*(?:string|\(string\))")),
    ("appender", re.compile(r"\bappender\b|\bAppender\b")),
]


@dataclass
class Finding:
    path: str
    line: int
    pattern: str
    text: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Scan Aurora hot paths for obvious copy/allocation markers.")
    parser.add_argument("--out-dir", default="artifacts/perf/copy-budget", help="Artifact output directory.")
    parser.add_argument("--path", action="append", dest="paths", help="Path to scan; may be passed multiple times.")
    parser.add_argument("--fail-on-findings", action="store_true", help="Exit non-zero if findings are present.")
    return parser.parse_args()


def iter_files(paths: list[str]) -> list[Path]:
    files: list[Path] = []
    for raw in paths:
        path = Path(raw)
        if path.is_file() and path.suffix == ".d":
            files.append(path)
        elif path.is_dir():
            files.extend(sorted(child for child in path.rglob("*.d") if child.is_file()))
    return sorted(set(files))


def is_ignored(line: str) -> bool:
    stripped = line.strip()
    return (
        not stripped
        or stripped.startswith("//")
        or stripped.startswith("*")
        or stripped.startswith("/+")
        or stripped.startswith("+/")
        or stripped.startswith("import ")
        or stripped.startswith("module ")
        or "copy-budget: allow" in stripped
    )


def scan_file(path: Path) -> list[Finding]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        lines = path.read_text(errors="replace").splitlines()
    findings: list[Finding] = []
    for index, line in enumerate(lines, start=1):
        if is_ignored(line):
            continue
        for name, pattern in PATTERNS:
            if pattern.search(line):
                findings.append(Finding(str(path), index, name, line.strip()))
    return findings


def write_outputs(out_dir: Path, findings: list[Finding], scanned_files: list[Path], fail_on_findings: bool) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    summary = {
        "status": "fail" if fail_on_findings and findings else "pass",
        "mode": "enforcing" if fail_on_findings else "report-only",
        "scanned_files": [str(path) for path in scanned_files],
        "finding_count": len(findings),
        "patterns": [name for name, _ in PATTERNS],
        "findings": [asdict(finding) for finding in findings],
    }
    (out_dir / "copy_budget.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with (out_dir / "copy_budget_findings.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["path", "line", "pattern", "text"])
        writer.writeheader()
        for finding in findings:
            writer.writerow(asdict(finding))
    lines = [
        "# Aurora Zero-Copy / Copy-Budget Static Report", "",
        f"- Mode: `{summary['mode']}`",
        f"- Status: `{summary['status']}`",
        f"- Scanned files: `{len(scanned_files)}`",
        f"- Findings: `{len(findings)}`", "",
        "This report flags obvious markers only. Reviewers must still validate lifetime, ownership, and hot-path placement manually.", "",
    ]
    if findings:
        lines.extend(["## Findings", "", "| Path | Line | Pattern | Text |", "| --- | ---: | --- | --- |"])
        for finding in findings[:200]:
            safe_text = finding.text.replace("|", "\\|")
            lines.append(f"| `{finding.path}` | {finding.line} | `{finding.pattern}` | `{safe_text}` |")
        if len(findings) > 200:
            lines.append("\n_Only first 200 findings shown; full data is in JSON/CSV._")
    else:
        lines.append("No obvious copy/allocation markers found in the configured hot-path scan.")
    (out_dir / "copy_budget_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    scanned_files = iter_files(args.paths or DEFAULT_PATHS)
    findings: list[Finding] = []
    for path in scanned_files:
        findings.extend(scan_file(path))
    write_outputs(Path(args.out_dir), findings, scanned_files, args.fail_on_findings)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as handle:
            handle.write("\n## Aurora zero-copy / copy-budget static report\n")
            handle.write((Path(args.out_dir) / "copy_budget_report.md").read_text(encoding="utf-8"))
    print(json.dumps({"mode": "enforcing" if args.fail_on_findings else "report-only", "scanned_files": len(scanned_files), "findings": len(findings)}, indent=2))
    return 1 if args.fail_on_findings and findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
