#!/usr/bin/env python3
"""Reproducible output-workload mapping/refill sweep and Pareto extraction."""

import argparse
import csv
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from sdram_model.mapping import MAPPINGS
from sdram_model.model import CL3_MAX_MHZ, Timing
from sdram_model.simulator import metrics, run
from sdram_model.workloads import make_output


FREQUENCIES = (100, 120, 130, 143)
REFILLS = (8, 16, 32, 64, 128, 256, 512, 1024)


def simulate(case):
    frequency, mapping, refill, duration_us = case
    timing = Timing(frequency, 3, frequency > CL3_MAX_MHZ)
    requests, horizon = make_output(
        frequency_mhz=frequency, duration_us=duration_us, burst=8,
        width=1280, height=720, refresh_hz=60, input_frame_hz=60,
        scanout_fifo_words=2048, scanout_refill_words=refill,
        audio_rate=48000, audio_channels=2, audio_bits=16,
        audio_fifo_words=512, video_write_buffer_words=2048,
        audio_write_buffer_words=256, scanout_base=0,
        write_base=64*1024*1024, audio_base=60*1024*1024,
        audio_write_base=62*1024*1024)
    report = metrics(run(
        requests, timing, mapping, "edf-row-hit", "open", horizon=horizon,
        deadline_guard=64, refresh_stagger=0,
        grant_words={"scanout": refill, "frame-write": 8,
                     "audio": 8, "audio-write": 8}), timing)
    channels = report["channels"]
    deadline_misses = sum(c["deadline_misses"] for c in channels.values())
    slacks = [channels[name]["min_deadline_slack_us"]
              for name in ("scanout", "audio")
              if channels[name]["min_deadline_slack_us"] is not None]
    writer_wait = max(channels[name]["max_wait_us"]
                      for name in ("frame-write", "audio-write"))
    return {
        "frequency_mhz": frequency,
        "qualification": ("board-acceptance" if frequency <= 130
                          else "exploratory-overclock"),
        "mapping": mapping,
        "refill_grant_words": refill,
        "duration_us": duration_us,
        "deadline_misses": deadline_misses,
        "incomplete_frames": report["incomplete_frames"],
        "minimum_read_deadline_slack_us": min(slacks) if slacks else "",
        "dq_util_pct": report["dq_util_pct"],
        "effective_mb_s": report["effective_mb_s"],
        "writer_max_wait_us": writer_wait,
        "frame_write_max_wait_us": channels["frame-write"]["max_wait_us"],
        "audio_write_max_wait_us": channels["audio-write"]["max_wait_us"],
        "unserved_words": report["unserved_words"],
        "dq_turnarounds": report["dq_turnarounds"],
        "activates": report["activates"],
        "command_util_pct": report["command_util_pct"],
    }


def dominates(a, b):
    """True when a is no worse in every requested objective and better in one."""
    av = (a["deadline_misses"], a["incomplete_frames"],
          -round(float(a["minimum_read_deadline_slack_us"]), 3),
          -round(a["dq_util_pct"], 3), round(a["writer_max_wait_us"], 3))
    bv = (b["deadline_misses"], b["incomplete_frames"],
          -round(float(b["minimum_read_deadline_slack_us"]), 3),
          -round(b["dq_util_pct"], 3), round(b["writer_max_wait_us"], 3))
    return all(x <= y for x, y in zip(av, bv)) and any(x < y for x, y in zip(av, bv))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--duration-us", type=float, default=1000)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--output", type=Path,
                        default=Path("tools/sdram-model/results/output-sweep.csv"))
    args = parser.parse_args()
    cases = [(f, m, q, args.duration_us) for f in FREQUENCIES
             for m in MAPPINGS for q in REFILLS]
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        rows = list(pool.map(simulate, cases))
    rows.sort(key=lambda r: (r["frequency_mhz"], r["mapping"], r["refill_grant_words"]))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader(); writer.writerows(rows)
    frontier = [row for row in rows
                if not any(other["frequency_mhz"] == row["frequency_mhz"]
                           and other is not row and dominates(other, row)
                           for other in rows)]
    frontier_path = args.output.with_name(args.output.stem + "-pareto.csv")
    with frontier_path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader(); writer.writerows(frontier)
    print(f"wrote {len(rows)} cases to {args.output}")
    print(f"wrote {len(frontier)} Pareto cases to {frontier_path}")


if __name__ == "__main__":
    main()
