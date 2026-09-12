#!/usr/bin/env python3
"""Run a small deterministic RTL trace replay smoke matrix."""

from __future__ import annotations

import csv
import subprocess
import sys
import tempfile
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
BENCH = REPO / "tools" / "sdram-backend-bench"
RTL = REPO / "rtl" / "scanout-sdram-controller"


def run(args: list[str], **kwargs: object) -> None:
    print("+", " ".join(args), flush=True)
    subprocess.run(args, check=True, **kwargs)


def row_count(path: Path) -> int:
    with path.open(newline="", encoding="utf-8") as handle:
        return sum(1 for _ in csv.DictReader(handle))


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="sdram-rtl-smoke-") as tmp:
        trace_csv = Path(tmp) / "write-smoke.csv"
        trace_mem = Path(tmp) / "write-smoke.mem"

        run([
            sys.executable,
            str(BENCH / "generate_trace.py"),
            "--output",
            str(trace_csv),
            "--lines",
            "1",
            "--line-packet-words",
            "128",
            "--background-kind",
            "sequential_write",
            "--background-mb-s",
            "2",
            "--background-words",
            "8",
            "--no-audio",
        ])
        run([
            sys.executable,
            str(BENCH / "trace_to_mem.py"),
            str(trace_csv),
            str(trace_mem),
        ])

        count = row_count(trace_csv)
        env = {
            **dict(),
            "TRACE_MEM": str(trace_mem),
            "TRACE_COUNT": str(count),
        }
        inherited = dict(**__import__("os").environ)
        inherited.update(env)

        run(["make", "trace-current"], cwd=RTL, env=inherited)
        run(["make", "trace-agg23-stock"], cwd=RTL, env=inherited)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
