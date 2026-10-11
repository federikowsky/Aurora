#!/usr/bin/env python3
"""Check actual process exit and drain, including implicit module teardown."""
from pathlib import Path
import subprocess
import sys

binary = str(Path(sys.argv[1]).resolve())
for mode in ("unused", "implicit", "explicit", "workers"):
    for repetition in range(50):
        result = subprocess.run([binary, mode], capture_output=True, timeout=10)
        if result.returncode:
            raise AssertionError((mode, repetition, result.returncode, result.stderr))
        expected = 0 if mode == "unused" else 1
        if result.stdout.count(b"final marker") != expected:
            raise AssertionError((mode, repetition, "missing/duplicated final output", result.stdout))
        if mode == "workers" and result.stdout.count(b"worker marker") != 8:
            raise AssertionError((mode, repetition, "missing/duplicated worker output", result.stdout))
    print(f"PASS {mode}: 50 process exits and output checks")
