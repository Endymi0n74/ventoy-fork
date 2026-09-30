#!/usr/bin/env python3
"""
Build and run the Ventoy sort test harness.
Uses the clang found on this machine at C:\\Program Files\\LLVM\\bin.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SRC = SCRIPT_DIR / "ventoy_sort_test.c"
OUTDIR = SCRIPT_DIR / "_build_sort_test"
OUT = OUTDIR / "ventoy_sort_test.exe"
CLANG = Path(r"C:\Program Files\LLVM\bin\clang.exe")


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(
        description="Build and run the Ventoy sort test harness."
    )
    parser.add_argument(
        "--perf",
        action="store_true",
        help="Enable the optional perf comparison build path "
             "(VENTOY_SORT_TEST_PERF=1).",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=1,
        help="Seed for the test executable's rand() stream "
             "(default: 1, fully deterministic). Vary it for "
             "perf timing / fuzz-data variance studies.",
    )
    parser.add_argument(
        "--sweep",
        type=int,
        default=0,
        help="Run the perf workloads over seeds 1..N and report "
             "mean/min/max timings per size (requires --perf).",
    )
    parser.add_argument(
        "--reps",
        type=int,
        default=0,
        help="Inner repetitions per timed measurement (default: "
             "auto-calibrate to ~50 ms blocks). Requires --perf.",
    )
    args = parser.parse_args()

    if not CLANG.is_file():
        print(f"ERROR: clang not found at {CLANG}")
        print("Please adjust the CLANG path in this script.")
        return 1

    if not SRC.is_file():
        print(f"ERROR: source not found at {SRC}")
        return 1

    OUTDIR.mkdir(parents=True, exist_ok=True)

    cmd = [
        str(CLANG),
        "-o", str(OUT),
        str(SRC),
        "-std=c11",
        "-O0",
        "-Wall",
        "-Wextra",
        "-Werror",
    ]
    if args.perf:
        cmd.append("-DVENTOY_SORT_TEST_PERF=1")

    print(f"[build] {' '.join(cmd)}")
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        if proc.stdout:
            print(proc.stdout, end="")
        if proc.stderr:
            print(proc.stderr, end="", file=sys.stderr)
        print("ERROR: compilation failed")
        return 1

    run_args = [str(OUT), "--seed", str(args.seed)]
    if args.sweep > 0:
        run_args += ["--sweep", str(args.sweep)]
    if args.reps > 0:
        run_args += ["--reps", str(args.reps)]
    print(f"[run] {' '.join(run_args)}")
    proc = subprocess.run(run_args, capture_output=True, text=True)
    if proc.stdout:
        print(proc.stdout, end="")
    if proc.stderr:
        print(proc.stderr, end="", file=sys.stderr)

    rc = proc.returncode
    if rc == 0:
        print()
        print("ventoy_sort_test: all checks passed.")
    else:
        print()
        print(f"ventoy_sort_test: {rc} check(s) failed.")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
