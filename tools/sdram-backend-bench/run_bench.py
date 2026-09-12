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
VIDEO_LINE_BYTES = 2560
VIDEO_LINE_WORDS = VIDEO_LINE_BYTES // 2
SOURCE_LINES = 720
SOURCE_FPS = 60
AUDIO_BYTES_PER_SEC = 192_000
AUDIO_CHUNK_BYTES = 256


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


@dataclass
class BackendState:
    time: int = 0
    last_op: str = ""
    next_refresh: int = REFRESH_INTERVAL
    open_rows: dict[tuple[int, int], int] | None = None

    def __post_init__(self) -> None:
        if self.open_rows is None:
            self.open_rows = {}


@dataclass(frozen=True)
class DeadlineRequest:
    request: Request
    klass: str
    deadline: int
    line: int = -1


@dataclass
class MachineResult:
    workload: str
    backend: str
    freq_mhz: float
    background_kind: str
    background_target_mb_s: float
    background_done_bytes: int
    total_cycles: int
    video_lines: int
    video_misses: int
    min_video_slack: int
    audio_chunks: int
    audio_misses: int
    min_audio_slack: int
    max_queued_lines: int
    max_latency: int
    activates: int
    precharges: int
    reads: int
    writes: int
    refreshes: int
    row_hits: int
    row_conflicts: int
    dir_changes: int

    @property
    def background_mb_s(self) -> float:
        if self.total_cycles <= 0:
            return 0.0
        seconds = self.total_cycles / (self.freq_mhz * 1_000_000.0)
        return (self.background_done_bytes / 1_000_000.0) / seconds


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

    def service(self, state: BackendState, request: Request, metrics: Metrics) -> tuple[int, int]:
        issue_start = state.time
        state.time += self.request_overhead
        first_response = state.time
        first_seen = False
        assert state.open_rows is not None
        for op in split_bl8(request):
            while state.time >= state.next_refresh:
                metrics.refreshes += 1
                metrics.refresh_stall_cycles += T_RFC
                state.time += T_RFC
                state.open_rows.clear()
                state.next_refresh += REFRESH_INTERVAL
            chip, bank, row, _column = decode(op.address)
            key = (chip, bank)
            if state.last_op and state.last_op != op.op:
                metrics.dir_changes += 1
                state.time += 1
            if self.open_row and state.open_rows.get(key) == row:
                metrics.row_hits += 1
            else:
                if key in state.open_rows:
                    metrics.row_conflicts += 1
                    metrics.precharges += 1
                    state.time += T_RP
                metrics.activates += 1
                state.time += T_RCD
                state.open_rows[key] = row
            if not self.open_row:
                metrics.precharges += 1
            if op.op == "R":
                metrics.reads += 1
                if not first_seen:
                    first_response = state.time + 2
                    first_seen = True
                state.time += 2 + BL8_WORDS
            else:
                metrics.writes += 1
                if not first_seen:
                    first_response = state.time
                    first_seen = True
                state.time += BL8_WORDS + T_WR_RECOVERY
            if not self.open_row:
                state.time += T_RP
                state.open_rows.pop(key, None)
            state.last_op = op.op
        metrics.useful_bytes += request.words * 2
        metrics.requests += 1
        return first_response - issue_start, state.time - issue_start

    def run(self, workload: str, trace: list[Request]) -> Metrics:
        state = BackendState()
        latencies: list[int] = []
        first_latencies: list[int] = []
        metrics = Metrics(workload=workload, backend=self.name, freq_mhz=self.freq_mhz)

        for request in trace:
            if state.time < request.cycle:
                metrics.idle_cycles += request.cycle - state.time
                state.time = request.cycle
            issue_start = state.time
            first_latency, latency = self.service(state, request, metrics)
            first_latencies.append(first_latency)
            latencies.append(latency)
            metrics.backend_stall_cycles += max(0, issue_start - request.cycle)

        metrics.cycles = state.time
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


def cycles_for_usec(freq_mhz: float, usec: float) -> int:
    return max(1, round(freq_mhz * usec))


def machine_line_period_cycles(freq_mhz: float) -> int:
    return cycles_for_usec(freq_mhz, 1_000_000.0 / (SOURCE_LINES * SOURCE_FPS))


def packetize_line(line: int, arrival: int, packet_words: int, deadline: int) -> list[DeadlineRequest]:
    base = 0x200000 + line * VIDEO_LINE_BYTES
    out = []
    remaining = VIDEO_LINE_WORDS
    offset = 0
    part = 0
    while remaining:
        words = min(remaining, packet_words)
        out.append(DeadlineRequest(
            Request(arrival, 0, "W", base + offset * 2, words, 0x3, (line << 4) + part),
            "video",
            deadline,
            line,
        ))
        offset += words
        remaining -= words
        part += 1
    return out


def background_request(kind: str, index: int, cycle: int) -> Request:
    sequential_address = 0x400000 + index * 64
    randomish = 0x500000 + ((index * 1103515245 + 12345) & 0x3ffff) * 2
    row_a = 0x600000 + (index % 2) * 0x4000
    row_good = 0x700000 + (index % 64) * 16
    bank_conflict = 0x780000 + (index % 4) * 0x4000
    direction = "R"
    address = sequential_address
    if kind == "seq_w":
        direction = "W"
    elif kind == "mixed_seq":
        direction = "R" if index % 2 == 0 else "W"
    elif kind == "rand_r":
        address = randomish
    elif kind == "rand_w":
        direction = "W"
        address = randomish
    elif kind == "mixed_rand":
        direction = "R" if index % 2 == 0 else "W"
        address = randomish
    elif kind == "poor_row":
        address = row_a
    elif kind == "good_row":
        address = row_good
    elif kind == "bank_conflict":
        address = bank_conflict
    elif kind == "rw_thrash":
        direction = "R" if index % 2 == 0 else "W"
    return Request(cycle, 1, direction, address, 32, 0x3, 0x8000 + index)


def build_machine_arrivals(
    backend: BackendModel,
    background_kind: str,
    background_target_mb_s: float,
    line_buffers: int,
    line_packet_words: int,
    frames: int,
    lines: int | None,
) -> list[DeadlineRequest]:
    line_period = machine_line_period_cycles(backend.freq_mhz)
    audio_period = cycles_for_usec(backend.freq_mhz, AUDIO_CHUNK_BYTES / AUDIO_BYTES_PER_SEC * 1_000_000.0)
    total_lines = lines if lines is not None else SOURCE_LINES * frames
    arrivals: list[DeadlineRequest] = []
    for line in range(total_lines):
        arrival = line * line_period
        deadline = arrival + (line_buffers - 1) * line_period
        arrivals.extend(packetize_line(line, arrival, line_packet_words, deadline))
    audio_chunks = max(1, (total_lines * line_period) // audio_period)
    for chunk in range(audio_chunks):
        arrival = chunk * audio_period
        req = Request(arrival, 0, "W", 0x300000 + chunk * AUDIO_CHUNK_BYTES,
                      AUDIO_CHUNK_BYTES // 2, 0x3, 0x4000 + chunk)
        arrivals.append(DeadlineRequest(req, "audio", arrival + audio_period, -1))
    if background_target_mb_s > 0:
        bytes_per_cycle = background_target_mb_s / backend.freq_mhz
        interval = max(1, round(64 / bytes_per_cycle))
        background_count = max(1, (total_lines * line_period) // interval)
        for index in range(background_count):
            cycle = index * interval
            arrivals.append(DeadlineRequest(
                background_request(background_kind, index, cycle),
                "background",
                1 << 60,
                -1,
            ))
    return sorted(arrivals, key=lambda item: (item.request.cycle, item.request.client, item.request.tag))


def run_machine_capture(
    backend: BackendModel,
    background_kind: str,
    background_target_mb_s: float,
    line_buffers: int,
    line_packet_words: int,
    frames: int,
    lines: int | None,
) -> MachineResult:
    arrivals = build_machine_arrivals(
        backend, background_kind, background_target_mb_s,
        line_buffers, line_packet_words, frames, lines,
    )
    pending: list[DeadlineRequest] = []
    state = BackendState()
    metrics = Metrics("machine_capture", backend.name, backend.freq_mhz)
    video_misses = 0
    audio_misses = 0
    min_video_slack = 1 << 60
    min_audio_slack = 1 << 60
    video_lines_seen: set[int] = set()
    completed_line_parts: dict[int, int] = {}
    expected_parts = (VIDEO_LINE_WORDS + line_packet_words - 1) // line_packet_words
    audio_chunks = 0
    max_queued_lines = 0
    max_latency = 0
    background_done_bytes = 0
    index = 0

    while index < len(arrivals) or pending:
        if not pending and index < len(arrivals) and state.time < arrivals[index].request.cycle:
            state.time = arrivals[index].request.cycle
        while index < len(arrivals) and arrivals[index].request.cycle <= state.time:
            pending.append(arrivals[index])
            index += 1
        queued_lines = {item.line for item in pending if item.klass == "video"}
        queued_lines.discard(-1)
        max_queued_lines = max(max_queued_lines, len(queued_lines))
        pending.sort(key=lambda item: (
            0 if item.klass == "video" else 1 if item.klass == "audio" else 2,
            item.deadline,
            item.request.cycle,
            item.request.tag,
        ))
        item = pending.pop(0)
        if state.time < item.request.cycle:
            state.time = item.request.cycle
        start = state.time
        _first, latency = backend.service(state, item.request, metrics)
        max_latency = max(max_latency, latency + max(0, start - item.request.cycle))
        if item.klass == "video":
            video_lines_seen.add(item.line)
            completed_line_parts[item.line] = completed_line_parts.get(item.line, 0) + 1
            if completed_line_parts[item.line] == expected_parts:
                slack = item.deadline - state.time
                min_video_slack = min(min_video_slack, slack)
                if slack < 0:
                    video_misses += 1
        elif item.klass == "audio":
            audio_chunks += 1
            slack = item.deadline - state.time
            min_audio_slack = min(min_audio_slack, slack)
            if slack < 0:
                audio_misses += 1
        else:
            background_done_bytes += item.request.words * 2

    return MachineResult(
        workload=f"machine_capture_{line_buffers}buf_{line_packet_words}w",
        backend=backend.name,
        freq_mhz=backend.freq_mhz,
        background_kind=background_kind,
        background_target_mb_s=background_target_mb_s,
        background_done_bytes=background_done_bytes,
        total_cycles=state.time,
        video_lines=len(video_lines_seen),
        video_misses=video_misses,
        min_video_slack=0 if min_video_slack == 1 << 60 else min_video_slack,
        audio_chunks=audio_chunks,
        audio_misses=audio_misses,
        min_audio_slack=0 if min_audio_slack == 1 << 60 else min_audio_slack,
        max_queued_lines=max_queued_lines,
        max_latency=max_latency,
        activates=metrics.activates,
        precharges=metrics.precharges,
        reads=metrics.reads,
        writes=metrics.writes,
        refreshes=metrics.refreshes,
        row_hits=metrics.row_hits,
        row_conflicts=metrics.row_conflicts,
        dir_changes=metrics.dir_changes,
    )


def machine_backends(freq_mode: str) -> list[BackendModel]:
    if freq_mode == "equal":
        simple_freq = custom_freq = EQUAL_FREQ_MHZ
    else:
        simple_freq = SIMPLE_FREQ_MHZ
        custom_freq = CUSTOM_FREQ_MHZ
    return [
        BackendModel("stock_simple", simple_freq, request_overhead=0, open_row=False),
        BackendModel("request_simple", simple_freq, request_overhead=4, open_row=False),
        BackendModel("custom_current", custom_freq, request_overhead=2, open_row=True),
    ]


def run_machine_sweep(
    freq_mode: str,
    background_kinds: list[str],
    line_buffers: int,
    line_packet_words: int,
    frames: int,
    lines: int | None,
    max_background_mb_s: int,
) -> list[MachineResult]:
    rows: list[MachineResult] = []
    for backend in machine_backends(freq_mode):
        for kind in background_kinds:
            last_passing: MachineResult | None = None
            low = 0
            high = max_background_mb_s
            while low <= high:
                target = ((low + high) // 20) * 10
                if target < low:
                    target = low
                if target > high:
                    target = high
                result = run_machine_capture(
                    backend, kind, float(target), line_buffers,
                    line_packet_words, frames, lines,
                )
                if result.video_misses or result.audio_misses:
                    high = target - 10
                else:
                    last_passing = result
                    low = target + 10
            if last_passing is not None:
                rows.append(last_passing)
    return rows


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


def print_machine_summary(rows: list[MachineResult]) -> None:
    header = (
        "workload", "backend", "freq", "background", "target_MB/s",
        "sustained_bg_MB/s", "cycles", "video_lines", "video_miss",
        "min_video_slack", "audio_chunks", "audio_miss", "min_audio_slack",
        "max_queued_lines", "max_latency", "ACT", "PRE", "RD", "WR", "REF",
        "hits", "conflicts", "dirchg"
    )
    print(",".join(header))
    for row in rows:
        print(",".join([
            row.workload,
            row.backend,
            f"{row.freq_mhz:.1f}",
            row.background_kind,
            f"{row.background_target_mb_s:.1f}",
            f"{row.background_mb_s:.2f}",
            str(row.total_cycles),
            str(row.video_lines),
            str(row.video_misses),
            str(row.min_video_slack),
            str(row.audio_chunks),
            str(row.audio_misses),
            str(row.min_audio_slack),
            str(row.max_queued_lines),
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


def write_machine_csv(path: str, rows: list[MachineResult]) -> None:
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(MachineResult.__dataclass_fields__.keys()) + ["background_mb_s"])
        writer.writeheader()
        for row in rows:
            data = {field: getattr(row, field) for field in MachineResult.__dataclass_fields__}
            data["background_mb_s"] = f"{row.background_mb_s:.6f}"
            writer.writerow(data)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--clock-mode", choices=["equal", "fmax"], default="equal")
    parser.add_argument("--csv")
    parser.add_argument("--dump-traces", type=Path)
    parser.add_argument("--trace-dir", type=Path)
    parser.add_argument("--machine-capture", action="store_true")
    parser.add_argument("--line-buffers", type=int, default=2)
    parser.add_argument("--line-packet-words", type=int, default=128)
    parser.add_argument("--frames", type=int, default=1)
    parser.add_argument("--lines", type=int)
    parser.add_argument("--max-background-mb-s", type=int, default=250)
    parser.add_argument("--background-kind", action="append", choices=[
        "seq_r", "seq_w", "mixed_seq", "rand_r", "rand_w", "mixed_rand",
        "poor_row", "good_row", "bank_conflict", "rw_thrash",
    ])
    args = parser.parse_args()
    if args.dump_traces:
        dump_traces(args.dump_traces)
    if args.machine_capture:
        background_kinds = args.background_kind or [
            "seq_r", "seq_w", "mixed_seq", "rand_r", "rand_w", "mixed_rand",
            "poor_row", "good_row", "bank_conflict", "rw_thrash",
        ]
        rows = run_machine_sweep(
            args.clock_mode,
            background_kinds,
            args.line_buffers,
            args.line_packet_words,
            args.frames,
            args.lines,
            args.max_background_mb_s,
        )
        print_machine_summary(rows)
        if args.csv:
            write_machine_csv(args.csv, rows)
        return
    trace_set = load_traces(args.trace_dir) if args.trace_dir else workloads()
    rows = run_all(args.clock_mode, trace_set)
    print_summary(rows)
    if args.csv:
        write_csv(args.csv, rows)


if __name__ == "__main__":
    main()
