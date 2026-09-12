#!/usr/bin/env python3
"""Generate deterministic logical SDRAM request traces.

This generator describes machine demand only.  It does not model SDRAM command
scheduling, row hits, controller busy time, arbitration, or completion latency.
Those are responsibilities of the RTL backend and result collector.
"""

from __future__ import annotations

import argparse
import csv
import random
from dataclasses import dataclass
from pathlib import Path


TRACE_FIELDS = [
    "issue_time_ns",
    "client_id",
    "op",
    "address",
    "length_words",
    "byte_enable",
    "tag",
    "deadline_ns",
    "traffic_class",
]

VIDEO_WIDTH = 1280
VIDEO_LINES = 720
VIDEO_FPS = 60
VIDEO_WORDS_PER_LINE = VIDEO_WIDTH
VIDEO_BYTES_PER_LINE = VIDEO_WORDS_PER_LINE * 2
AUDIO_BYTES_PER_SEC = 48_000 * 2 * 2

VIDEO_BASE = 0x0020_0000
AUDIO_BASE = 0x0030_0000
BACKGROUND_BASE = 0x0040_0000


@dataclass(frozen=True)
class TraceRequest:
    issue_time_ns: int
    client_id: int
    op: str
    address: int
    length_words: int
    byte_enable: int
    tag: int
    deadline_ns: int
    traffic_class: str


def div_round(numerator: int, denominator: int) -> int:
    return (numerator + denominator // 2) // denominator


def line_time_ns(line: int) -> int:
    return div_round(line * 1_000_000_000, VIDEO_LINES * VIDEO_FPS)


def packetize_video_line(
    line: int,
    issue_time_ns: int,
    line_packet_words: int,
    line_buffers: int,
    tag_base: int,
) -> list[TraceRequest]:
    if line_packet_words <= 0 or line_packet_words > VIDEO_WORDS_PER_LINE:
        raise ValueError("line packet size must be in 1..1280 words")
    deadline_ns = line_time_ns(line + line_buffers)
    base = VIDEO_BASE + line * VIDEO_BYTES_PER_LINE
    remaining = VIDEO_WORDS_PER_LINE
    offset_words = 0
    part = 0
    out: list[TraceRequest] = []
    while remaining:
        words = min(remaining, line_packet_words)
        out.append(TraceRequest(
            issue_time_ns=issue_time_ns,
            client_id=0,
            op="W",
            address=base + offset_words * 2,
            length_words=words,
            byte_enable=0x3,
            tag=tag_base + part,
            deadline_ns=deadline_ns,
            traffic_class="video",
        ))
        remaining -= words
        offset_words += words
        part += 1
    return out


def generate_video(frames: int, lines: int | None, line_packet_words: int, line_buffers: int) -> list[TraceRequest]:
    if line_buffers < 2:
        raise ValueError("line_buffers must be at least 2 for ping-pong capture")
    total_lines = lines if lines is not None else frames * VIDEO_LINES
    out: list[TraceRequest] = []
    for line in range(total_lines):
        out.extend(packetize_video_line(
            line=line,
            issue_time_ns=line_time_ns(line),
            line_packet_words=line_packet_words,
            line_buffers=line_buffers,
            tag_base=0x1000_0000 + line * 0x100,
        ))
    return out


def generate_audio(duration_ns: int, chunk_bytes: int) -> list[TraceRequest]:
    if chunk_bytes <= 0 or chunk_bytes % 2:
        raise ValueError("audio chunk bytes must be positive and 16-bit aligned")
    period_ns = div_round(chunk_bytes * 1_000_000_000, AUDIO_BYTES_PER_SEC)
    chunks = max(1, duration_ns // period_ns)
    return [
        TraceRequest(
            issue_time_ns=chunk * period_ns,
            client_id=0,
            op="W",
            address=AUDIO_BASE + chunk * chunk_bytes,
            length_words=chunk_bytes // 2,
            byte_enable=0x3,
            tag=0x2000_0000 + chunk,
            deadline_ns=(chunk + 1) * period_ns,
            traffic_class="audio",
        )
        for chunk in range(chunks)
    ]


def background_address(kind: str, index: int, rng: random.Random) -> int:
    if "random" in kind:
        return BACKGROUND_BASE + rng.randrange(0, 1 << 20, 2)
    if kind == "good_row":
        return BACKGROUND_BASE + 0x20_0000 + (index % 256) * 64
    if kind == "poor_locality":
        return BACKGROUND_BASE + 0x40_0000 + (index * 37 % 1024) * 0x4000
    if kind == "same_bank_conflict":
        return BACKGROUND_BASE + 0x60_0000 + (index % 2) * 0x4000
    return BACKGROUND_BASE + index * 64


def background_op(kind: str, index: int) -> str:
    if kind in ("sequential_write", "random_write"):
        return "W"
    if kind in ("mixed_sequential", "mixed_random", "rw_thrash"):
        return "R" if index % 2 == 0 else "W"
    return "R"


def generate_background(
    kind: str,
    offered_mb_s: float,
    duration_ns: int,
    seed: int,
    request_words: int,
) -> list[TraceRequest]:
    if offered_mb_s <= 0:
        return []
    if request_words <= 0:
        raise ValueError("background request size must be positive")
    bytes_per_request = request_words * 2
    period_ns = max(1, round(bytes_per_request * 1_000 / offered_mb_s))
    count = max(1, duration_ns // period_ns)
    rng = random.Random(seed)
    out: list[TraceRequest] = []
    for index in range(count):
        issue = index * period_ns
        out.append(TraceRequest(
            issue_time_ns=issue,
            client_id=1,
            op=background_op(kind, index),
            address=background_address(kind, index, rng),
            length_words=request_words,
            byte_enable=0x3,
            tag=0x3000_0000 + index,
            deadline_ns=-1,
            traffic_class=f"background:{kind}",
        ))
    return out


def validate_trace(trace: list[TraceRequest]) -> None:
    previous_time = -1
    seen_tags: set[int] = set()
    for req in trace:
        if req.issue_time_ns < previous_time:
            raise ValueError("trace is not sorted by issue_time_ns")
        previous_time = req.issue_time_ns
        if req.tag in seen_tags:
            raise ValueError(f"duplicate tag {req.tag:#x}")
        seen_tags.add(req.tag)
        if req.op not in ("R", "W"):
            raise ValueError(f"bad op {req.op}")
        if req.address % 2:
            raise ValueError(f"unaligned address {req.address:#x}")
        if req.length_words <= 0:
            raise ValueError("zero-length request")
        if req.byte_enable < 0 or req.byte_enable > 3:
            raise ValueError(f"bad byte enable {req.byte_enable:#x}")
        if req.deadline_ns != -1 and req.deadline_ns < req.issue_time_ns:
            raise ValueError("deadline before issue time")


def write_trace(path: Path, trace: list[TraceRequest]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=TRACE_FIELDS)
        writer.writeheader()
        for req in trace:
            writer.writerow({
                "issue_time_ns": req.issue_time_ns,
                "client_id": req.client_id,
                "op": req.op,
                "address": f"0x{req.address:x}",
                "length_words": req.length_words,
                "byte_enable": f"0x{req.byte_enable:x}",
                "tag": f"0x{req.tag:x}",
                "deadline_ns": req.deadline_ns,
                "traffic_class": req.traffic_class,
            })


def read_trace(path: Path) -> list[TraceRequest]:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != TRACE_FIELDS:
            raise ValueError(f"{path}: expected {TRACE_FIELDS}, got {reader.fieldnames}")
        trace = [
            TraceRequest(
                issue_time_ns=int(row["issue_time_ns"], 0),
                client_id=int(row["client_id"], 0),
                op=row["op"],
                address=int(row["address"], 0),
                length_words=int(row["length_words"], 0),
                byte_enable=int(row["byte_enable"], 0),
                tag=int(row["tag"], 0),
                deadline_ns=int(row["deadline_ns"], 0),
                traffic_class=row["traffic_class"],
            )
            for row in reader
        ]
    validate_trace(trace)
    return trace


def generate(args: argparse.Namespace) -> list[TraceRequest]:
    duration_lines = args.lines if args.lines is not None else args.frames * VIDEO_LINES
    duration_ns = line_time_ns(duration_lines)
    trace = []
    if not args.no_video:
        trace.extend(generate_video(args.frames, args.lines, args.line_packet_words, args.line_buffers))
    if not args.no_audio:
        trace.extend(generate_audio(duration_ns, args.audio_chunk_bytes))
    trace.extend(generate_background(
        args.background_kind,
        args.background_mb_s,
        duration_ns,
        args.seed,
        args.background_words,
    ))
    trace.sort(key=lambda req: (req.issue_time_ns, req.client_id, req.tag))
    validate_trace(trace)
    return trace


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    parser.add_argument("--frames", type=int, default=1)
    parser.add_argument("--lines", type=int)
    parser.add_argument("--line-packet-words", type=int, default=1280)
    parser.add_argument("--line-buffers", type=int, default=2)
    parser.add_argument("--audio-chunk-bytes", type=int, default=256)
    parser.add_argument("--background-kind", choices=[
        "sequential_read",
        "sequential_write",
        "mixed_sequential",
        "random_read",
        "random_write",
        "mixed_random",
        "good_row",
        "poor_locality",
        "same_bank_conflict",
        "rw_thrash",
    ], default="sequential_read")
    parser.add_argument("--background-mb-s", type=float, default=0.0)
    parser.add_argument("--background-words", type=int, default=32)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--no-video", action="store_true")
    parser.add_argument("--no-audio", action="store_true")
    parser.add_argument("--validate-only", type=Path)
    args = parser.parse_args()

    if args.validate_only:
        read_trace(args.validate_only)
        print(f"valid trace: {args.validate_only}")
        return

    if args.output is None:
        raise SystemExit("--output is required unless --validate-only is used")

    trace = generate(args)
    write_trace(args.output, trace)
    print(f"wrote {len(trace)} requests to {args.output}")


if __name__ == "__main__":
    main()
