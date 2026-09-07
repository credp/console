#!/usr/bin/env python3
"""Sweep the implementable FIFO-watermark arbiter over full frames."""

import argparse
import csv
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from sweep_presentation import FORMATS, simulate
from sdram_model.mapping import MAPPINGS


def threshold(text):
    try:
        low, high = (int(value, 0) for value in text.split(":", 1))
    except (ValueError, TypeError):
        raise argparse.ArgumentTypeError("threshold must be LOW:HIGH")
    if not 0 <= low < high:
        raise argparse.ArgumentTypeError("threshold must satisfy 0 <= LOW < HIGH")
    return low, high


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--frequency", type=float, default=130)
    parser.add_argument("--format", choices=FORMATS, default="720p16")
    parser.add_argument("--mapping", choices=MAPPINGS, default="stripe-1k-bank-chip")
    parser.add_argument("--thresholds", type=threshold, nargs="+",
                        default=[(256,1024),(512,1536),(768,1792),(256,1792)])
    parser.add_argument("--guards", type=int, nargs="+", default=[2048,4096])
    parser.add_argument("--background-rates", type=float, nargs="+", default=[100])
    parser.add_argument("--fifo-words", type=int, nargs="+", default=[2048])
    parser.add_argument("--active-fraction", type=float,
                        default=(1920*1080)/(2200*1125),
                        help="defaults to the 1080p active/total pixel ratio")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--duration-us", type=float, default=1_000_000/60)
    parser.add_argument("--output", type=Path,
                        default=Path("tools/sdram-model/results/watermark-sweep.csv"))
    args = parser.parse_args()
    cases = [
        (args.frequency, args.mapping, args.format, mode, direction, rate,
         args.duration_us, guard, "watermark", low, high, fifo_words,
         args.active_fraction)
        for fifo_words in args.fifo_words
        for low, high in args.thresholds for guard in args.guards
        for mode in ("capture", "replay") for direction in ("read", "write")
        for rate in args.background_rates
    ]
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        rows = list(pool.map(simulate, cases))
    rows.sort(key=lambda r: (r["low_watermark_words"], r["high_watermark_words"],
                             r["deadline_guard_cycles"],
                             r["background_offered_mb_s"], r["mode"],
                             r["background_direction"]))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader(); writer.writerows(rows)

    group_keys = ("frequency_mhz", "mapping", "format", "active_fraction",
                  "video_fifo_words",
                  "low_watermark_words",
                  "high_watermark_words", "deadline_guard_cycles",
                  "background_offered_mb_s")
    summary = []
    for key in sorted({tuple(row[name] for name in group_keys) for row in rows}):
        group = [row for row in rows if tuple(row[name] for name in group_keys) == key]
        summary.append(dict(zip(group_keys, key)) | {
            "all_modes_directions_safe": int(all(row["safe"] for row in group)),
            "minimum_video_slack_us": min(float(row["video_min_slack_us"])
                                           for row in group),
            "maximum_video_wait_us": max(float(row["video_max_wait_us"])
                                           for row in group),
            "minimum_background_service_pct": min(float(row["background_service_pct"])
                                                     for row in group),
            "maximum_dq_turnarounds": max(int(row["dq_turnarounds"])
                                           for row in group),
        })
    summary_path = args.output.with_name(args.output.stem + "-summary.csv")
    with summary_path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=summary[0].keys())
        writer.writeheader(); writer.writerows(summary)
    print(f"wrote {len(rows)} cases to {args.output}")
    print(f"wrote {len(summary)} aggregated rows to {summary_path}")


if __name__ == "__main__":
    main()
