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
from enum import Enum
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


class BufferState(Enum):
    FREE = "FREE"
    FILLING = "FILLING"
    COMPLETE_AVAILABLE = "COMPLETE_AVAILABLE"
    DRAINING_TO_SDRAM = "DRAINING_TO_SDRAM"


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
    buffer: int = -1
    part: int = 0
    total_parts: int = 1


@dataclass
class MachineResult:
    workload: str
    backend: str
    freq_mhz: float
    background_kind: str
    raster_mode: str
    line_packet_words: int
    background_target_mb_s: float
    background_done_bytes: int
    total_cycles: int
    video_lines: int
    video_misses: int
    buffer_conflicts: int
    min_video_slack: int
    worst_video_drain_latency: int
    line_requests: int
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


@dataclass(frozen=True)
class RasterTiming:
    mode: str
    line_period: int
    active_lines: int
    total_lines: int


@dataclass
class LineBuffer:
    state: BufferState = BufferState.FREE
    line: int = -1
    completed_parts: int = 0
    total_parts: int = 0
    drain_start: int = -1


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


def machine_raster_timing(
    freq_mhz: float,
    mode: str,
    active_lines: int = SOURCE_LINES,
    total_lines: int = SOURCE_LINES,
) -> RasterTiming:
    if mode == "logical":
        line_period = cycles_for_usec(freq_mhz, 1_000_000.0 / (active_lines * SOURCE_FPS))
        return RasterTiming(mode, line_period, active_lines, active_lines)
    if total_lines < active_lines:
        raise ValueError("total raster lines must be >= active lines")
    line_period = cycles_for_usec(freq_mhz, 1_000_000.0 / (total_lines * SOURCE_FPS))
    return RasterTiming(mode, line_period, active_lines, total_lines)


def packetize_line(
    line: int,
    buffer: int,
    arrival: int,
    packet_words: int,
    deadline: int,
) -> list[DeadlineRequest]:
    base = 0x200000 + line * VIDEO_LINE_BYTES
    out = []
    remaining = VIDEO_LINE_WORDS
    offset = 0
    part = 0
    total_parts = (VIDEO_LINE_WORDS + packet_words - 1) // packet_words
    while remaining:
        words = min(remaining, packet_words)
        out.append(DeadlineRequest(
            Request(arrival, 0, "W", base + offset * 2, words, 0x3, (line << 4) + part),
            "video",
            deadline,
            line,
            buffer,
            part,
            total_parts,
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
    raster: RasterTiming,
    frames: int,
    lines: int,
) -> list[DeadlineRequest]:
    audio_period = cycles_for_usec(backend.freq_mhz, AUDIO_CHUNK_BYTES / AUDIO_BYTES_PER_SEC * 1_000_000.0)
    total_lines = lines
    arrivals: list[DeadlineRequest] = []
    total_active_span = total_lines * raster.line_period
    if total_lines >= raster.active_lines:
        total_active_span = frames * raster.total_lines * raster.line_period
    audio_chunks = max(1, total_active_span // audio_period)
    for chunk in range(audio_chunks):
        arrival = chunk * audio_period
        req = Request(arrival, 0, "W", 0x300000 + chunk * AUDIO_CHUNK_BYTES,
                      AUDIO_CHUNK_BYTES // 2, 0x3, 0x4000 + chunk)
        arrivals.append(DeadlineRequest(req, "audio", arrival + audio_period, -1))
    if background_target_mb_s > 0:
        bytes_per_cycle = background_target_mb_s / backend.freq_mhz
        interval = max(1, round(64 / bytes_per_cycle))
        background_count = max(1, total_active_span // interval)
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
    raster_mode: str,
    raster_total_lines: int,
) -> MachineResult:
    if line_buffers < 2:
        raise ValueError("machine capture requires at least two line buffers")
    if line_packet_words <= 0 or line_packet_words > VIDEO_LINE_WORDS:
        raise ValueError("line packet words must be in 1..1280")
    raster = machine_raster_timing(backend.freq_mhz, raster_mode, SOURCE_LINES, raster_total_lines)
    active_lines = lines if lines is not None else SOURCE_LINES * frames
    arrivals = build_machine_arrivals(
        backend, background_kind, background_target_mb_s, raster, frames, active_lines,
    )
    pending: list[DeadlineRequest] = []
    buffers = [LineBuffer() for _ in range(line_buffers)]
    buffers[0].state = BufferState.FILLING
    fill_buffer = 0
    state = BackendState()
    metrics = Metrics("machine_capture", backend.name, backend.freq_mhz)
    video_misses = 0
    buffer_conflicts = 0
    audio_misses = 0
    min_video_slack = 1 << 60
    min_audio_slack = 1 << 60
    video_lines_seen: set[int] = set()
    audio_chunks = 0
    max_queued_lines = 0
    max_latency = 0
    worst_video_drain_latency = 0
    background_done_bytes = 0
    line_requests = 0
    index = 0
    line_number = 0
    next_line_completion = raster.line_period

    def add_line_completion(cycle: int, line: int) -> None:
        nonlocal fill_buffer, video_misses, buffer_conflicts, line_requests
        current = buffers[fill_buffer]
        if current.state != BufferState.FILLING:
            raise AssertionError(f"buffer {fill_buffer} was {current.state}, not FILLING")
        current.state = BufferState.COMPLETE_AVAILABLE
        current.line = line
        current.completed_parts = 0
        current.total_parts = (VIDEO_LINE_WORDS + line_packet_words - 1) // line_packet_words
        current.drain_start = -1
        deadline = cycle + (line_buffers - 1) * raster.line_period
        pending.extend(packetize_line(line, fill_buffer, cycle, line_packet_words, deadline))
        line_requests += current.total_parts
        next_buffer = (fill_buffer + 1) % line_buffers
        if buffers[next_buffer].state != BufferState.FREE:
            video_misses += 1
            buffer_conflicts += 1
            pending[:] = [
                item for item in pending
                if not (item.klass == "video" and item.buffer == next_buffer)
            ]
        buffers[next_buffer].state = BufferState.FILLING
        buffers[next_buffer].line = line + 1
        buffers[next_buffer].completed_parts = 0
        buffers[next_buffer].total_parts = 0
        buffers[next_buffer].drain_start = -1
        fill_buffer = next_buffer

    while index < len(arrivals) or pending or line_number < active_lines:
        next_event = next_line_completion if line_number < active_lines else 1 << 60
        if index < len(arrivals):
            next_event = min(next_event, arrivals[index].request.cycle)
        if not pending and state.time < next_event:
            state.time = next_event
        while line_number < active_lines and next_line_completion <= state.time:
            add_line_completion(next_line_completion, line_number)
            line_number += 1
            frame_line = line_number % raster.active_lines
            if raster.mode == "blanked" and frame_line == 0:
                next_line_completion += (raster.total_lines - raster.active_lines + 1) * raster.line_period
            else:
                next_line_completion += raster.line_period
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
        if item.klass == "video":
            buffer = buffers[item.buffer]
            if buffer.state == BufferState.COMPLETE_AVAILABLE:
                buffer.state = BufferState.DRAINING_TO_SDRAM
                buffer.drain_start = start
            elif buffer.state != BufferState.DRAINING_TO_SDRAM:
                raise AssertionError(f"cannot drain buffer {item.buffer} from {buffer.state}")
        _first, latency = backend.service(state, item.request, metrics)
        max_latency = max(max_latency, latency + max(0, start - item.request.cycle))
        if item.klass == "video":
            video_lines_seen.add(item.line)
            buffer = buffers[item.buffer]
            buffer.completed_parts += 1
            if buffer.completed_parts == buffer.total_parts:
                slack = item.deadline - state.time
                min_video_slack = min(min_video_slack, slack)
                worst_video_drain_latency = max(worst_video_drain_latency, state.time - buffer.drain_start)
                if slack < 0:
                    video_misses += 1
                buffer.state = BufferState.FREE
                buffer.line = -1
                buffer.completed_parts = 0
                buffer.total_parts = 0
                buffer.drain_start = -1
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
        raster_mode=raster.mode,
        line_packet_words=line_packet_words,
        background_target_mb_s=background_target_mb_s,
        background_done_bytes=background_done_bytes,
        total_cycles=state.time,
        video_lines=len(video_lines_seen),
        video_misses=video_misses,
        buffer_conflicts=buffer_conflicts,
        min_video_slack=0 if min_video_slack == 1 << 60 else min_video_slack,
        worst_video_drain_latency=worst_video_drain_latency,
        line_requests=line_requests,
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
    line_packet_words_list: list[int],
    frames: int,
    lines: int | None,
    max_background_mb_s: int,
    raster_mode: str,
    raster_total_lines: int,
) -> list[MachineResult]:
    rows: list[MachineResult] = []
    for backend in machine_backends(freq_mode):
        for kind in background_kinds:
            for packet_words in line_packet_words_list:
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
                        packet_words, frames, lines, raster_mode, raster_total_lines,
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
        "workload", "backend", "freq", "raster", "packet_words",
        "background", "target_MB/s",
        "sustained_bg_MB/s", "cycles", "video_lines", "video_miss",
        "buffer_conflicts", "min_video_slack", "worst_video_drain",
        "line_requests", "audio_chunks", "audio_miss", "min_audio_slack",
        "max_queued_lines", "max_latency", "ACT", "PRE", "RD", "WR", "REF",
        "hits", "conflicts", "dirchg"
    )
    print(",".join(header))
    for row in rows:
        print(",".join([
            row.workload,
            row.backend,
            f"{row.freq_mhz:.1f}",
            row.raster_mode,
            str(row.line_packet_words),
            row.background_kind,
            f"{row.background_target_mb_s:.1f}",
            f"{row.background_mb_s:.2f}",
            str(row.total_cycles),
            str(row.video_lines),
            str(row.video_misses),
            str(row.buffer_conflicts),
            str(row.min_video_slack),
            str(row.worst_video_drain_latency),
            str(row.line_requests),
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
    parser.add_argument("--line-packet-words", type=int, action="append")
    parser.add_argument("--frames", type=int, default=1)
    parser.add_argument("--lines", type=int)
    parser.add_argument("--max-background-mb-s", type=int, default=250)
    parser.add_argument("--raster-mode", choices=["logical", "blanked"], default="logical")
    parser.add_argument("--raster-total-lines", type=int, default=SOURCE_LINES)
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
            args.line_packet_words or [8, 16, 32, 64, 128, 256, 640, 1280],
            args.frames,
            args.lines,
            args.max_background_mb_s,
            args.raster_mode,
            args.raster_total_lines,
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
