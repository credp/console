#!/usr/bin/env python3
"""Smoke tests for the logical SDRAM request trace generator."""

from __future__ import annotations

import argparse
import csv
import tempfile
from pathlib import Path

import generate_trace


def make_args(**overrides: object) -> argparse.Namespace:
    defaults = {
        "frames": 1,
        "lines": 4,
        "line_packet_words": 640,
        "line_buffers": 2,
        "audio_chunk_bytes": 256,
        "background_kind": "mixed_random",
        "background_mb_s": 20.0,
        "background_words": 32,
        "seed": 123,
        "no_video": False,
        "no_audio": False,
    }
    defaults.update(overrides)
    return argparse.Namespace(**defaults)


def main() -> None:
    trace_a = generate_trace.generate(make_args())
    trace_b = generate_trace.generate(make_args())
    assert trace_a == trace_b

    video = [req for req in trace_a if req.traffic_class == "video"]
    assert len(video) == 8
    assert video[0].issue_time_ns == 0
    assert video[0].address == generate_trace.VIDEO_BASE
    assert video[0].length_words == 640
    assert video[0].deadline_ns == generate_trace.line_time_ns(2)

    audio = [req for req in trace_a if req.traffic_class == "audio"]
    assert audio
    assert all(req.op == "W" for req in audio)

    background = [req for req in trace_a if req.traffic_class.startswith("background:")]
    assert background
    assert any(req.op == "R" for req in background)
    assert any(req.op == "W" for req in background)
    assert all(req.deadline_ns == -1 for req in background)

    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "trace.csv"
        generate_trace.write_trace(path, trace_a)
        assert generate_trace.read_trace(path) == trace_a
        with path.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            assert reader.fieldnames == generate_trace.TRACE_FIELDS
            assert "row_hit" not in reader.fieldnames
            assert "completion" not in ",".join(reader.fieldnames)
            assert "command" not in reader.fieldnames

    print(f"ok: generated and replayed {len(trace_a)} logical requests")


if __name__ == "__main__":
    main()
