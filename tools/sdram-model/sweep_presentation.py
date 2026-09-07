#!/usr/bin/env python3
"""Sweep architectural capture/replay modes and residual port traffic."""

import argparse
import csv
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from sdram_model.mapping import MAPPINGS
from sdram_model.model import CL3_MAX_MHZ, Timing
from sdram_model.simulator import SCHEDULERS, metrics, run
from sdram_model.workloads import make_presentation


FORMATS = {
    "720p16": (1280, 720, 16),
    "1080p8": (1920, 1080, 8),
    "1080p16": (1920, 1080, 16),
}


def simulate(case):
    (frequency, mapping, format_name, mode, direction, background_mb_s,
     duration_us, deadline_guard, scheduler, low_watermark, high_watermark,
     video_fifo_words, active_fraction) = case
    width, height, bits = FORMATS[format_name]
    timing = Timing(frequency, 3, frequency > CL3_MAX_MHZ)
    requests, horizon = make_presentation(
        frequency_mhz=frequency, duration_us=duration_us, burst=8,
        width=width, height=height, bits_per_pixel=bits,
        refresh_hz=60, input_frame_hz=60,
        scanout_fifo_words=video_fifo_words, scanout_refill_words=256,
        audio_rate=48000, audio_channels=2, audio_bits=16,
        audio_fifo_words=512, video_write_buffer_words=video_fifo_words,
        audio_write_buffer_words=256, scanout_base=0,
        write_base=32*1024*1024, audio_base=60*1024*1024,
        audio_write_base=62*1024*1024, presentation_mode=mode,
        background_mb_s=background_mb_s, background_write=direction == "write",
        background_base=96*1024*1024, active_fraction=active_fraction,
        live_capture_timing=scheduler == "watermark")
    report = metrics(run(
        requests, timing, mapping, scheduler, "open", horizon=horizon,
        deadline_guard=deadline_guard, refresh_stagger=timing.refresh_interval//2,
        scheduler_lookahead=8,
        watermark_low_words=low_watermark,
        watermark_high_words=high_watermark,
        grant_words={"scanout":256, "frame-write":256, "audio":8,
                     "audio-write":8, "background":256}), timing)
    channels = report["channels"]
    mandatory = [name for name in ("scanout", "audio", "frame-write", "audio-write")
                 if name in channels]
    deadline_misses = sum(channels[name]["deadline_misses"] for name in mandatory)
    mandatory_service = min((channels[name]["service_pct"] for name in mandatory), default=100)
    background_service = channels.get("background", {}).get("service_pct", 100)
    # Short sweeps may not contain a complete frame boundary. Service ratios
    # catch a growing backlog there; full-frame sweeps additionally demand
    # successful publication/replay.
    presentation = report["presentation"]
    safe = (deadline_misses == 0 and background_service >= 99.5
            and presentation["failed_captures"] == 0
            and presentation["replay_underruns"] == 0)
    video_name = "frame-write" if mode == "capture" else "scanout"
    return {
        "frequency_mhz": frequency,
        "qualification": "board-acceptance" if frequency <= 130 else "exploratory-overclock",
        "mapping": mapping,
        "format": format_name,
        "width": width, "height": height, "bits_per_pixel": bits,
        "mode": mode, "background_direction": direction,
        "scheduler": scheduler,
        "low_watermark_words": low_watermark,
        "high_watermark_words": high_watermark,
        "video_fifo_words": video_fifo_words,
        "active_fraction": active_fraction,
        "deadline_guard_cycles": deadline_guard,
        "deadline_guard_us": deadline_guard/frequency,
        "background_offered_mb_s": background_mb_s,
        "safe": int(safe), "mandatory_deadline_misses": deadline_misses,
        "mandatory_min_service_pct": mandatory_service,
        "background_service_pct": background_service,
        "published_frames": presentation["published_frames"],
        "failed_captures": presentation["failed_captures"],
        "replay_safe_frames": presentation["replay_safe_frames"],
        "replay_underruns": presentation["replay_underruns"],
        "video_min_slack_us": channels[video_name]["min_deadline_slack_us"],
        "video_max_wait_us": channels[video_name]["max_wait_us"],
        "audio_deadline_misses": presentation["audio_deadline_misses"],
        "effective_mb_s": report["effective_mb_s"],
        "dq_util_pct": report["dq_util_pct"],
        "observed_idle_mb_s": report["leftover_mb_s"],
        "unserved_words": report["unserved_words"],
        "dq_turnarounds": report["dq_turnarounds"],
        "activates": report["activates"],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--duration-us", type=float, default=1_000_000/60,
                        help="use at least one frame when interpreting safe/headroom")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--frequencies", type=float, nargs="+", default=[100,120,130,143])
    parser.add_argument("--formats", choices=FORMATS, nargs="+", default=list(FORMATS))
    parser.add_argument("--modes", choices=("capture","replay"), nargs="+",
                        default=["capture","replay"])
    parser.add_argument("--directions", choices=("read","write"), nargs="+",
                        default=["read","write"])
    parser.add_argument("--background-rates", type=float, nargs="+",
                        default=[0,25,50,75,100,125,150])
    parser.add_argument("--deadline-guard", type=int, default=2048)
    parser.add_argument("--scheduler", choices=SCHEDULERS, default="edf-row-hit")
    parser.add_argument("--low-watermark", type=int, default=512)
    parser.add_argument("--high-watermark", type=int, default=1536)
    parser.add_argument("--video-fifo-words", type=int, default=2048)
    parser.add_argument("--active-fraction", type=float, default=1.0)
    parser.add_argument("--mappings", choices=MAPPINGS, nargs="+", default=list(MAPPINGS))
    parser.add_argument("--output", type=Path,
                        default=Path("tools/sdram-model/results/presentation-sweep.csv"))
    args = parser.parse_args()
    cases = [(f,m,fmt,mode,direction,rate,args.duration_us,args.deadline_guard,
              args.scheduler,args.low_watermark,args.high_watermark)
              + (args.video_fifo_words,args.active_fraction)
             for f in args.frequencies for m in args.mappings for fmt in args.formats
             for mode in args.modes for direction in args.directions
             for rate in args.background_rates]
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        rows = list(pool.map(simulate, cases))
    rows.sort(key=lambda r: (r["frequency_mhz"], r["format"], r["mode"],
                             r["background_direction"], r["mapping"],
                             r["background_offered_mb_s"]))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader(); writer.writerows(rows)
    summary_path = args.output.with_name(args.output.stem + "-headroom.csv")
    keys = ("frequency_mhz", "qualification", "mapping", "format", "mode",
            "background_direction", "scheduler", "low_watermark_words",
            "high_watermark_words", "deadline_guard_cycles")
    summaries = []
    groups = sorted({tuple(row[k] for k in keys) for row in rows})
    for group in groups:
        selected = [r for r in rows if tuple(r[k] for k in keys) == group]
        safe_rates = [r["background_offered_mb_s"] for r in selected if r["safe"]]
        summaries.append(dict(zip(keys, group)) | {
            "max_tested_safe_background_mb_s": max(safe_rates, default=""),
            "first_tested_unsafe_background_mb_s": min(
                (r["background_offered_mb_s"] for r in selected if not r["safe"]),
                default=""),
        })
    with summary_path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=summaries[0].keys())
        writer.writeheader(); writer.writerows(summaries)
    print(f"wrote {len(rows)} cases to {args.output}")
    print(f"wrote {len(summaries)} headroom rows to {summary_path}")


if __name__ == "__main__":
    main()
