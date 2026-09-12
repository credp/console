#!/usr/bin/env python3
"""Deterministic SDRAM backend comparison seed.

This is a command-level benchmark scaffold, not a production RTL simulator.
It creates hostile logical traces and runs them through three deliberately
simple backend-policy models so the workload and metric plumbing can be
reviewed before RTL wrappers are added.
"""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path
from statistics import mean
from typing import Iterable


T_RCD = 3
T_RP = 3
T_RFC = 11
T_WR_RECOVERY = 5
BL8_WORDS = 8
CUSTOM_FREQ_MHZ = 104.0
SIMPLE_FREQ_MHZ = 165.0
EQUAL_FREQ_MHZ = 100.0
REFRESH_INTERVAL = 780


@dataclass(frozen=True)
class Request:
    cycle: int
    client: int
    op: str
    address: int
    words: int
    byte_enable: int
    tag: int


@dataclass
class Metrics:
    workload: str
    backend: str
    freq_mhz: float
    requests: int = 0
    useful_bytes: int = 0
    cycles: int = 0
    activates: int = 0
    precharges: int = 0
    reads: int = 0
    writes: int = 0
    refreshes: int = 0
    row_hits: int = 0
    row_conflicts: int = 0
    dir_changes: int = 0
    idle_cycles: int = 0
    refresh_stall_cycles: int = 0
    backend_stall_cycles: int = 0
    max_latency: int = 0
    avg_latency: float = 0.0
    p95_latency: int = 0
    max_first_response: int = 0

    @property
    def mb_s(self) -> float:
        if self.cycles <= 0:
            return 0.0
        seconds = self.cycles / (self.freq_mhz * 1_000_000.0)
        return (self.useful_bytes / 1_000_000.0) / seconds


def decode(address: int) -> tuple[int, int, int, int]:
    """Mapping 5: stripe-1k-bank-chip, matching sdram_addr_decode.sv."""
    chip = (address >> 10) & 0x1
    bank = (address >> 11) & 0x3
    row = (address >> 14) & 0x1FFF
    column = ((address >> 13) & 0x1) << 9 | ((address >> 1) & 0x1FF)
    return chip, bank, row, column


def split_bl8(req: Request) -> Iterable[Request]:
    remaining = req.words
    address = req.address
    tag = req.tag
    while remaining:
        _chip, _bank, _row, column = decode(address)
        burst_left = BL8_WORDS - (column % BL8_WORDS)
        row_left = 512 - ((address >> 1) & 0x1FF)
        words = min(remaining, burst_left, row_left, BL8_WORDS)
        yield Request(req.cycle, req.client, req.op, address, words, req.byte_enable, tag)
        remaining -= words
        address += words * 2
        tag += 1


class BackendModel:
    def __init__(self, name: str, freq_mhz: float, request_overhead: int, open_row: bool):
        self.name = name
        self.freq_mhz = freq_mhz
        self.request_overhead = request_overhead
        self.open_row = open_row

    def run(self, workload: str, trace: list[Request]) -> Metrics:
        time = 0
        last_op = ""
        open_rows: dict[tuple[int, int], int] = {}
        latencies: list[int] = []
        first_latencies: list[int] = []
        metrics = Metrics(workload=workload, backend=self.name, freq_mhz=self.freq_mhz)
        next_refresh = REFRESH_INTERVAL

        for request in trace:
            if time < request.cycle:
                metrics.idle_cycles += request.cycle - time
                time = request.cycle
            issue_start = time
            time += self.request_overhead
            for op in split_bl8(request):
                while time >= next_refresh:
                    metrics.refreshes += 1
                    metrics.refresh_stall_cycles += T_RFC
                    time += T_RFC
                    open_rows.clear()
                    next_refresh += REFRESH_INTERVAL
                chip, bank, row, _column = decode(op.address)
                key = (chip, bank)
                if last_op and last_op != op.op:
                    metrics.dir_changes += 1
                    time += 1
                if self.open_row and open_rows.get(key) == row:
                    metrics.row_hits += 1
                else:
                    if key in open_rows:
                        metrics.row_conflicts += 1
                        metrics.precharges += 1
                        time += T_RP
                    metrics.activates += 1
                    time += T_RCD
                    open_rows[key] = row
                if not self.open_row:
                    metrics.precharges += 1
                if op.op == "R":
                    metrics.reads += 1
                    first_latencies.append(time + 2 - issue_start)
                    time += 2 + BL8_WORDS
                else:
                    metrics.writes += 1
                    first_latencies.append(time - issue_start)
                    time += BL8_WORDS + T_WR_RECOVERY
                if not self.open_row:
                    time += T_RP
                    open_rows.pop(key, None)
                last_op = op.op
            latency = time - issue_start
            latencies.append(latency)
            metrics.backend_stall_cycles += max(0, issue_start - request.cycle)
            metrics.useful_bytes += request.words * 2
            metrics.requests += 1

        metrics.cycles = time
        metrics.max_latency = max(latencies, default=0)
        metrics.avg_latency = mean(latencies) if latencies else 0.0
        metrics.p95_latency = percentile(latencies, 95)
        metrics.max_first_response = max(first_latencies, default=0)
        return metrics


def percentile(values: list[int], pct: int) -> int:
    if not values:
        return 0
    ordered = sorted(values)
    index = min(len(ordered) - 1, (len(ordered) * pct) // 100)
    return ordered[index]


def seq(name: str, op: str, base: int, count: int, words: int, stride_words: int) -> tuple[str, list[Request]]:
    return name, [
        Request(i * 2, 0, op, base + i * stride_words * 2, words, 0x3, i)
        for i in range(count)
    ]


def workloads() -> list[tuple[str, list[Request]]]:
    out: list[tuple[str, list[Request]]] = []
    out.append(seq("long_sequential_reads", "R", 0x00000, 64, 32, 32))
    out.append(seq("long_sequential_writes", "W", 0x10000, 64, 32, 32))
    out.append(("alternating_reads_writes", [
        Request(i * 2, 0, "R" if i % 2 == 0 else "W", 0x20000 + i * 16, 8, 0x3, i)
        for i in range(96)
    ]))
    out.append(("same_bank_row_thrashing", [
        Request(i, 0, "R", (0 if i % 2 == 0 else 0x4000) + 0x0000, 8, 0x3, i)
        for i in range(96)
    ]))
    out.append(("bank_interleaving", [
        Request(i, 0, "R", 0x30000 + ((i % 4) << 11), 8, 0x3, i)
        for i in range(96)
    ]))
    out.append(("chip_interleaving", [
        Request(i, 0, "R", 0x38000 + ((i % 2) << 10), 8, 0x3, i)
        for i in range(96)
    ]))
    out.append(("poor_row_locality", [
        Request(i, 0, "R", 0x40000 + ((i * 37) % 512) * 0x4000, 8, 0x3, i)
        for i in range(96)
    ]))
    out.append(("good_row_locality", [
        Request(i, 0, "R", 0x50000 + (i % 32) * 16, 8, 0x3, i)
        for i in range(96)
    ]))
    out.append(("small_awkward_requests", [
        Request(i, 0, "W", 0x60000 + i * 14, 3 + (i % 5), 1 << (i % 2), i)
        for i in range(96)
    ]))
    out.append(("boundary_cases", [
        Request(i, 0, "R", 0x70000 + offset, words, 0x3, i)
        for i, (offset, words) in enumerate([
            (1008, 8), (1016, 8), (1020, 12), (2040, 16),
            (4092, 16), (8190, 32), (16376, 32), (32760, 64),
        ] * 8)
    ]))
    out.append(seq("maximum_size_requests", "W", 0x80000, 24, 256, 256))
    out.append(("two_client_contention", [
        Request(i, i % 2, "R", 0x90000 + (i % 2) * 0x20000 + i * 16, 8, 0x3, i)
        for i in range(160)
    ]))
    out.append(("latency_sensitive_vs_hog", [
        *(Request(i * 32, 0, "R", 0xA0000 + i * 2, 2, 0x3, i) for i in range(64)),
        *(Request(i, 1, "W", 0xB0000 + i * 64, 32, 0x3, 1000 + i) for i in range(64)),
    ]))
    out.append(("refresh_pressure", [
        Request(i, 0, "R" if i % 3 else "W", 0xC0000 + i * 16, 8, 0x3, i)
        for i in range(512)
    ]))
    out.append(("starvation_attempts", [
        *(Request(i, 0, "R", 0xD0000 + i * 16, 8, 0x3, i) for i in range(128)),
        *(Request(i * 64, 1, "R", 0xE0000 + i * 2, 1, 0x3, 2000 + i) for i in range(32)),
    ]))
    out.append(("byte_enable_stress", [
        Request(i, 0, "W", 0xF0000 + i * 6, 3, [0x1, 0x2, 0x3][i % 3], i)
        for i in range(128)
    ]))
    out.append(("mixed_graphics_audio", sorted([
        *(Request(i * 4, 0, "R", 0x100000 + i * 16, 8, 0x3, i) for i in range(160)),
        *(Request(i * 11, 1, "W", 0x140000 + i * 32, 16, 0x3, 1000 + i) for i in range(80)),
        *(Request(i * 23, 1, "R", 0x180000 + i * 2, 2, 0x3, 2000 + i) for i in range(48)),
    ], key=lambda r: (r.cycle, r.client, r.tag))))
    return out


TRACE_HEADER = ["cycle", "client", "op", "address", "words", "byte_enable", "tag"]


def trace_path_name(name: str) -> str:
    return f"{name}.csv"


def write_trace(path: Path, trace: list[Request]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(TRACE_HEADER)
        for req in trace:
            writer.writerow([
                req.cycle,
                req.client,
                req.op,
                f"0x{req.address:x}",
                req.words,
                f"0x{req.byte_enable:x}",
                req.tag,
            ])


def dump_traces(directory: Path) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    manifest = directory / "manifest.csv"
    with manifest.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["workload", "file", "requests", "useful_bytes"])
        for name, trace in workloads():
            filename = trace_path_name(name)
            write_trace(directory / filename, trace)
            writer.writerow([
                name,
                filename,
                len(trace),
                sum(req.words * 2 for req in trace),
            ])


def parse_int(value: str) -> int:
    return int(value, 0)


def read_trace(path: Path) -> list[Request]:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != TRACE_HEADER:
            raise ValueError(f"{path}: expected header {TRACE_HEADER}, got {reader.fieldnames}")
        return [
            Request(
                cycle=parse_int(row["cycle"]),
                client=parse_int(row["client"]),
                op=row["op"],
                address=parse_int(row["address"]),
                words=parse_int(row["words"]),
                byte_enable=parse_int(row["byte_enable"]),
                tag=parse_int(row["tag"]),
            )
            for row in reader
        ]


def load_traces(directory: Path) -> list[tuple[str, list[Request]]]:
    manifest = directory / "manifest.csv"
    if manifest.exists():
        with manifest.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            return [
                (row["workload"], read_trace(directory / row["file"]))
                for row in reader
            ]
    return [
        (path.stem, read_trace(path))
        for path in sorted(directory.glob("*.csv"))
        if path.name != "manifest.csv"
    ]


def run_all(freq_mode: str, trace_set: list[tuple[str, list[Request]]]) -> list[Metrics]:
    if freq_mode == "equal":
        simple_freq = custom_freq = EQUAL_FREQ_MHZ
    else:
        simple_freq = SIMPLE_FREQ_MHZ
        custom_freq = CUSTOM_FREQ_MHZ
    backends = [
        BackendModel("stock_simple", simple_freq, request_overhead=0, open_row=False),
        BackendModel("request_simple", simple_freq, request_overhead=4, open_row=False),
        BackendModel("custom_current", custom_freq, request_overhead=2, open_row=True),
    ]
    return [
        backend.run(name, trace)
        for name, trace in trace_set
        for backend in backends
    ]


def print_summary(rows: list[Metrics]) -> None:
    header = (
        "workload", "backend", "freq", "MB/s", "cycles", "avg_lat",
        "p95_lat", "max_lat", "ACT", "PRE", "RD", "WR", "REF",
        "hits", "conflicts", "dirchg"
    )
    print(",".join(header))
    for row in rows:
        print(",".join([
            row.workload,
            row.backend,
            f"{row.freq_mhz:.1f}",
            f"{row.mb_s:.2f}",
            str(row.cycles),
            f"{row.avg_latency:.1f}",
            str(row.p95_latency),
            str(row.max_latency),
            str(row.activates),
            str(row.precharges),
            str(row.reads),
            str(row.writes),
            str(row.refreshes),
            str(row.row_hits),
            str(row.row_conflicts),
            str(row.dir_changes),
        ]))


def write_csv(path: str, rows: list[Metrics]) -> None:
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(Metrics.__dataclass_fields__.keys()) + ["mb_s"])
        writer.writeheader()
        for row in rows:
            data = {field: getattr(row, field) for field in Metrics.__dataclass_fields__}
            data["mb_s"] = f"{row.mb_s:.6f}"
            writer.writerow(data)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--clock-mode", choices=["equal", "fmax"], default="equal")
    parser.add_argument("--csv")
    parser.add_argument("--dump-traces", type=Path)
    parser.add_argument("--trace-dir", type=Path)
    args = parser.parse_args()
    if args.dump_traces:
        dump_traces(args.dump_traces)
    trace_set = load_traces(args.trace_dir) if args.trace_dir else workloads()
    rows = run_all(args.clock_mode, trace_set)
    print_summary(rows)
    if args.csv:
        write_csv(args.csv, rows)


if __name__ == "__main__":
    main()
