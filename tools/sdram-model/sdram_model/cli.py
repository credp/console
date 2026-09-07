import argparse, csv, json, sys
from .mapping import MAPPINGS, decode_address
from .model import Timing
from .simulator import PAGE_POLICIES, SCHEDULERS, metrics, run
from .workloads import PRESENTATION_MODES, WORKLOADS, make, make_presentation


def integer(text): return int(text, 0)


def parser():
    p = argparse.ArgumentParser(description="AS4C32M16SB-7 x2 output-board exploration model")
    p.add_argument("--frequency", type=float, default=100)
    p.add_argument("--allow-overclock", action="store_true",
                   help="permit >142.857 MHz exploration and mark results outside the device rating")
    p.add_argument("--cas", type=int, default=3)
    p.add_argument("--mapping", choices=MAPPINGS, default="row-chip-bank-column")
    p.add_argument("--scheduler", choices=SCHEDULERS, default="edf-row-hit")
    p.add_argument("--page-policy", choices=PAGE_POLICIES, default="open")
    p.add_argument("--deadline-guard", type=int, default=64)
    p.add_argument("--scheduler-lookahead", type=int, default=64,
                   help="maximum queued requests inspected per channel")
    p.add_argument("--video-low-watermark", type=int, default=512)
    p.add_argument("--video-high-watermark", type=int, default=1536)
    p.add_argument("--refresh-stagger", type=int, default=0, help="chip 1 refresh phase in clocks")
    p.add_argument("--workload", choices=WORKLOADS, default="output")
    p.add_argument("--count", type=int, default=4096, help="request count for synthetic workloads")
    p.add_argument("--burst", type=int, choices=(1,2,4,8), default=8)
    p.add_argument("--working-set", type=integer, default=8*1024*1024)
    p.add_argument("--stride", type=integer, default=1024)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--duration-us", type=float, default=100, help="output workload horizon")
    p.add_argument("--width", type=int, default=1280)
    p.add_argument("--height", type=int, default=720)
    p.add_argument("--refresh-hz", type=float, default=60)
    p.add_argument("--input-frame-hz", "--producer-hz", type=float, default=60,
                   help="frame tick governing ideal on-demand video/audio write requests; 0 disables writes")
    p.add_argument("--presentation-mode", choices=PRESENTATION_MODES, default="capture",
                   help="capture/replay architecture; stress preserves the old simultaneous workload")
    p.add_argument("--bits-per-pixel", type=int, default=16,
                   help="tightly packed presentation-buffer format")
    p.add_argument("--background-mb-s", type=float, default=0,
                   help="paced residual traffic offered to the presentation-memory port")
    p.add_argument("--background-direction", choices=("read", "write"), default="write")
    p.add_argument("--background-base", type=integer, default=96*1024*1024)
    p.add_argument("--video-request-words", type=int, default=256,
                   help="controller-level video request/grant, split into physical bursts")
    p.add_argument("--background-request-words", type=int, default=256,
                   help="controller-level background request, split into physical bursts")
    p.add_argument("--active-fraction", type=float, default=1.0,
                   help="fraction of each frame occupied by active video")
    p.add_argument("--scanout-fifo-words", type=int, default=2048)
    p.add_argument("--scanout-refill-words", type=int, default=8,
                   help="BRAM space accumulated before releasing a scanout refill block")
    p.add_argument("--audio-rate", type=int, default=48000)
    p.add_argument("--audio-channels", type=int, default=2)
    p.add_argument("--audio-bits", type=int, default=16)
    p.add_argument("--audio-fifo-words", type=int, default=512)
    p.add_argument("--video-write-buffer-words", type=int, default=2048)
    p.add_argument("--audio-write-buffer-words", type=int, default=256)
    p.add_argument("--scanout-grant-words", type=int, default=8,
                   help="soft arbiter quantum; multiple physical bursts may fill one BRAM grant")
    p.add_argument("--frame-write-grant-words", type=int, default=8)
    p.add_argument("--audio-grant-words", type=int, default=8)
    p.add_argument("--audio-write-grant-words", type=int, default=8)
    p.add_argument("--scanout-base", type=integer, default=0)
    p.add_argument("--write-base", type=integer, default=64*1024*1024)
    p.add_argument("--audio-base", type=integer, default=60*1024*1024)
    p.add_argument("--audio-write-base", type=integer, default=62*1024*1024)
    p.add_argument("--format", choices=("human","json","csv"), default="human")
    p.add_argument("--timeline", type=int, default=0, metavar="CYCLES", help="print compact cycle timeline")
    p.add_argument("--window-cycles", type=int, default=0, help="print per-channel DQ use in time windows")
    p.add_argument("--trace", metavar="CSV", help="write cycle-level command/DQ trace ('-' for stdout)")
    p.add_argument("--decode", type=integer, help="decode one byte address and exit")
    return p


def write_trace(path, result, mapping):
    stream = sys.stdout if path == "-" else open(path, "w", newline="")
    try:
        w = csv.writer(stream)
        w.writerow(("cycle","command","command_channel","command_request_id",
                    "dq","dq_channel","dq_request_id","dq_chip","dq_bank","dq_row","dq_column"))
        by_id = {r.id:r for r in result.requests}
        interesting = sorted(set(result.memory.commands) | {c for c in result.memory.dq if c < result.cycles})
        for cycle in interesting:
            data = result.memory.dq.get(cycle)
            command_rid = result.memory.command_requests.get(cycle)
            command_channel = by_id[command_rid].requester if command_rid is not None else ""
            if data:
                direction, rid, chip, bank = data
                req = by_id[rid]; address = decode_address(req.address, mapping)
                channel, row, column = req.requester, address.row, address.column
            else:
                direction = channel = ""; rid = chip = bank = row = column = ""
            w.writerow((cycle, result.memory.commands.get(cycle,""), command_channel,
                        command_rid if command_rid is not None else "", direction, channel,
                        rid, chip, bank, row, column))
    finally:
        if stream is not sys.stdout: stream.close()


def timeline(result, count):
    by_id = {r.id:r for r in result.requests}
    names = sorted({r.requester for r in result.requests})
    preferred = {"scanout":"S", "audio":"A", "frame-write":"W"}
    symbols = {name:preferred.get(name, str((i+1)%10)) for i,name in enumerate(names)}
    print("timeline legend:", " ".join(f"{symbols[n]}={n}" for n in names), ".=idle")
    for base in range(0, min(count, result.cycles), 64):
        end = min(base+64, count, result.cycles)
        dq = "".join(symbols[by_id[result.memory.dq[c][1]].requester] if c in result.memory.dq else "." for c in range(base,end))
        cmdchars = {"ACT":"A", "PRE":"P", "READ":"R", "WRITE":"W", "REFRESH":"F"}
        cmd = "".join(next((v for k,v in cmdchars.items() if result.memory.commands.get(c,"").startswith(k)), ".") for c in range(base,end))
        owner = "".join(symbols[by_id[result.memory.command_requests[c]].requester]
                        if result.memory.command_requests.get(c) is not None else "." for c in range(base,end))
        print(f"  {base:8d} DQ  {dq}")
        print(f"  {'':8s} CMD {cmd}")
        print(f"  {'':8s} OWN {owner}")


def windows(result, size):
    by_id = {r.id:r for r in result.requests}
    names = sorted({r.requester for r in result.requests})
    print(f"service windows ({size} clocks):")
    print("  cycles".ljust(22) + " ".join(f"{n:>14s}" for n in names) + "          idle")
    for base in range(0, result.cycles, size):
        end = min(base+size, result.cycles); total=end-base
        counts = {n:0 for n in names}
        for c in range(base,end):
            if c in result.memory.dq: counts[by_id[result.memory.dq[c][1]].requester] += 1
        used=sum(counts.values())
        print(f"  {base:8d}-{end-1:<8d}" + " ".join(f"{100*counts[n]/total:13.1f}%" for n in names) + f" {100*(total-used)/total:13.1f}%")


def main(argv=None):
    a = parser().parse_args(argv)
    if a.decode is not None:
        print(json.dumps(decode_address(a.decode, a.mapping).__dict__, sort_keys=True)); return
    timing = Timing(a.frequency, a.cas, a.allow_overclock)
    if a.workload == "output":
        reqs, horizon = make_presentation(frequency_mhz=a.frequency, duration_us=a.duration_us,
            burst=a.burst, width=a.width, height=a.height, refresh_hz=a.refresh_hz,
            input_frame_hz=a.input_frame_hz, scanout_fifo_words=a.scanout_fifo_words,
            scanout_refill_words=a.scanout_refill_words,
            audio_rate=a.audio_rate, audio_channels=a.audio_channels, audio_bits=a.audio_bits,
            audio_fifo_words=a.audio_fifo_words,
            video_write_buffer_words=a.video_write_buffer_words,
            audio_write_buffer_words=a.audio_write_buffer_words,
            scanout_base=a.scanout_base, write_base=a.write_base,
            audio_base=a.audio_base, audio_write_base=a.audio_write_base,
            presentation_mode=a.presentation_mode, bits_per_pixel=a.bits_per_pixel,
            background_mb_s=a.background_mb_s,
            background_write=a.background_direction == "write",
            background_base=a.background_base,
            video_request_words=a.video_request_words,
            background_request_words=a.background_request_words,
            active_fraction=a.active_fraction,
            live_capture_timing=a.scheduler == "watermark")
    else:
        reqs = make(a.workload, a.count, a.burst, a.working_set, a.stride, a.seed); horizon = None
    result = run(reqs, timing, a.mapping, a.scheduler, a.page_policy, horizon=horizon,
                 deadline_guard=a.deadline_guard, refresh_stagger=a.refresh_stagger,
                 scheduler_lookahead=a.scheduler_lookahead,
                 watermark_low_words=a.video_low_watermark,
                 watermark_high_words=a.video_high_watermark,
                 grant_words={"scanout":a.scanout_grant_words,
                              "frame-write":a.frame_write_grant_words,
                              "audio":a.audio_grant_words,
                              "audio-write":a.audio_write_grant_words,
                              "background":a.frame_write_grant_words})
    m = metrics(result, timing)
    if a.trace: write_trace(a.trace, result, a.mapping)
    if a.format == "json": print(json.dumps(m, sort_keys=True)); return
    flat = {k:v for k,v in m.items() if not isinstance(v,(dict,list))}
    if a.format == "csv":
        w=csv.DictWriter(sys.stdout, fieldnames=flat); w.writeheader(); w.writerow(flat); return
    print(f"AS4C32M16SB-7 x2  {a.frequency:g} MHz  CL{a.cas}  map={a.mapping}")
    qualification = "board-guaranteed" if timing.board_guaranteed else ("device-rated/board-unguaranteed" if timing.device_rated else "OVERCLOCK: outside device and board ratings")
    print(f"qualification={qualification}")
    print(f"scheduler={a.scheduler} page={a.page_policy} workload={a.workload} burst={a.burst}")
    if a.workload == "output":
        print(f"presentation={a.presentation_mode} stored={a.width}x{a.height}x{a.bits_per_pixel} "
              f"active={a.active_fraction:.6f} "
              f"background={a.background_mb_s:g}MB/s-{a.background_direction}")
    for k,v in flat.items(): print(f"{k:24s} {v:.3f}" if isinstance(v,float) else f"{k:24s} {v}")
    print("channels")
    for name,v in m["channels"].items():
        print(f"  {name:14s} words={v['words']:7d} bus={v['dq_share_pct']:6.2f}% "
              f"MB/s={v['mb_s']:7.2f}/{v['offered_mb_s']:.2f} offered "
              f"served={v['service_pct']:6.2f}% miss={v['deadline_misses']} "
              f"min_slack_us={v['min_deadline_slack_us'] if v['min_deadline_slack_us'] is not None else 'n/a'} "
              f"wait_us={v['avg_wait_us']:.3f}/{v['max_wait_us']:.3f} avg/max "
              f"lat_us={v['avg_latency_us']:.3f}/{v['max_latency_us']:.3f} avg/max "
              f"max_gap/run={v['max_service_gap']}/{v['max_service_run']} "
              f"cmd={v['command_cycles']} chips={v['chip_words']}")
    print("presentation", json.dumps(m["presentation"], separators=(",",":")))
    print("chips", json.dumps(m["chips"], separators=(",",":")))
    if a.timeline: timeline(result, a.timeline)
    if a.window_cycles: windows(result, a.window_cycles)
