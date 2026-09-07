#!/usr/bin/env python3
"""Full-frame validation of the 1 KiB bank->chip 128/256-word candidates."""

import argparse
import csv
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from sdram_model.model import Timing
from sdram_model.simulator import metrics, run
from sdram_model.workloads import make_output


FREQUENCY_MHZ = 130
DURATION_US = 1_000_000 / 60
REFILLS = (128, 256)


def simulate(case):
    refill, phase_name, refresh_stagger, deadline_guard = case
    timing = Timing(FREQUENCY_MHZ, 3)
    requests, horizon = make_output(
        frequency_mhz=FREQUENCY_MHZ, duration_us=DURATION_US, burst=8,
        width=1280, height=720, refresh_hz=60, input_frame_hz=60,
        scanout_fifo_words=2048, scanout_refill_words=refill,
        audio_rate=48000, audio_channels=2, audio_bits=16,
        audio_fifo_words=512, video_write_buffer_words=2048,
        audio_write_buffer_words=256, scanout_base=0,
        write_base=64*1024*1024, audio_base=60*1024*1024,
        audio_write_base=62*1024*1024)
    report = metrics(run(
        requests, timing, "stripe-1k-bank-chip", "edf-row-hit", "open",
        horizon=horizon, deadline_guard=deadline_guard, refresh_stagger=refresh_stagger,
        grant_words={"scanout": refill, "frame-write": 8,
                     "audio": 8, "audio-write": 8}), timing)
    channels = report["channels"]
    late_scanout = [r for r in requests if r.requester == "scanout"
                    and r.deadline is not None and r.deadline <= horizon
                    and (r.completed is None or r.completed > r.deadline)]
    return {
        "frequency_mhz": FREQUENCY_MHZ,
        "duration_us": DURATION_US,
        "mapping": "stripe-1k-bank-chip",
        "refill_grant_words": refill,
        "refresh_phase": phase_name,
        "refresh_stagger_cycles": refresh_stagger,
        "deadline_guard_cycles": deadline_guard,
        "deadline_guard_us": deadline_guard / FREQUENCY_MHZ,
        "deadline_misses": sum(c["deadline_misses"] for c in channels.values()),
        "scanout_deadline_misses": channels["scanout"]["deadline_misses"],
        "scanout_max_lateness_us": channels["scanout"]["max_lateness"] / FREQUENCY_MHZ,
        "first_missed_deadline_us": (min(r.deadline for r in late_scanout) / FREQUENCY_MHZ
                                     if late_scanout else ""),
        "last_missed_deadline_us": (max(r.deadline for r in late_scanout) / FREQUENCY_MHZ
                                    if late_scanout else ""),
        "frame_write_deadline_misses": channels["frame-write"]["deadline_misses"],
        "incomplete_frames": report["incomplete_frames"],
        "scanout_min_slack_us": channels["scanout"]["min_deadline_slack_us"],
        "scanout_max_wait_us": channels["scanout"]["max_wait_us"],
        "frame_write_max_wait_us": channels["frame-write"]["max_wait_us"],
        "audio_write_max_wait_us": channels["audio-write"]["max_wait_us"],
        "effective_mb_s": report["effective_mb_s"],
        "dq_util_pct": report["dq_util_pct"],
        "unserved_words": report["unserved_words"],
        "dq_turnarounds": report["dq_turnarounds"],
        "activates": report["activates"],
        "precharges": report["precharges"],
        "refresh_command_cycles": report["refresh_command_cycles"],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--guards", type=int, nargs="+", default=[64])
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--output", type=Path,
                        default=Path("tools/sdram-model/results/candidate-full-frame.csv"))
    args = parser.parse_args()
    interval = Timing(FREQUENCY_MHZ, 3).refresh_interval
    phases = (("aligned", 0), ("quarter", interval // 4),
              ("half", interval // 2), ("three-quarter", 3 * interval // 4))
    cases = [(refill, name, stagger, guard) for refill in REFILLS
             for guard in args.guards for name, stagger in phases]
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        rows = list(pool.map(simulate, cases))
    rows.sort(key=lambda r: (r["refill_grant_words"], r["deadline_guard_cycles"],
                             r["refresh_stagger_cycles"]))
    destination = args.output
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader(); writer.writerows(rows)
    print(f"wrote {len(rows)} cases to {destination}")
    for refill in REFILLS:
        for guard in args.guards:
            group = [r for r in rows if r["refill_grant_words"] == refill
                     and r["deadline_guard_cycles"] == guard]
            print(
                f"q={refill:3d} guard={guard:4d} ({guard/FREQUENCY_MHZ:.3f}us) "
                f"miss_max={max(r['deadline_misses'] for r in group):4d} "
                f"slack_min={min(r['scanout_min_slack_us'] for r in group):7.3f}us "
                f"scan_wait_max={max(r['scanout_max_wait_us'] for r in group):7.3f}us "
                f"write_wait_max={max(r['frame_write_max_wait_us'] for r in group):7.3f}us "
                f"dq={min(r['dq_util_pct'] for r in group):.3f}-"
                f"{max(r['dq_util_pct'] for r in group):.3f}% "
                f"turns={min(r['dq_turnarounds'] for r in group)}-"
                f"{max(r['dq_turnarounds'] for r in group)}")


if __name__ == "__main__":
    main()
