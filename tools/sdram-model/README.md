# SDRAM exploration model

This is a readable implementation-design simulator, not RTL and not an
architectural specification. It is intended to compare hypotheses rather than
encode a preferred framebuffer layout or scheduler.

The modeled output board is the MiSTer XS-DS v2.9 with two Alliance Memory
**AS4C32M16SB-7TCN** devices. The devices share one 16-bit DQ bus and the
command/address pins. The board drives one device's CS directly and the other
through an inverter, so every command selects exactly one chip. Each chip has
four independently stateful banks. A separately pinned second SDRAM board is
outside this model and cannot consume output-board bus cycles.

Board-specific evidence and the distinction between the official 130 MHz
acceptance-test criterion and component guarantees are recorded in
[`SOURCES.md`](SOURCES.md).

## Timing and physical geometry

The source is Alliance Memory's AS4C32M16SB Rev 1.4 (June 2024), table 16.
The -7 values are tRCD=21 ns, tRP=21 ns, tRAS=42 ns, tRC=63 ns, tRRD=14 ns,
tWR=14 ns, tRFC=63 ns, tMRD=14 ns, and tREFI=7.8 us. Minimum delays use
`ceil(ns * MHz / 1000)`. The maximum refresh interval uses
`floor(ns * MHz / 1000)`. CL2 is rejected above 100 MHz; CL3 is the default.
The official MiSTer 130 MHz board acceptance-test boundary is treated
separately from the chip rating: results at <=130 MHz retain the concise label
board-guaranteed, while 130-142.857 MHz is device-rated but
board-unguaranteed, and >142.857 MHz exploratory overclocks. Such frequencies
require `--allow-overclock`; converting the other timing constraints does not
make the violated 7 ns minimum tCK valid.

The physical geometry is 8192 rows x 1024 16-bit columns x 4 banks per chip:
a physical open row is 2 KiB, row address is A0-A12, and column address is
A0-A9. The `stripe-1k-*` experiments remain valid mappings but expose two
logical half-rows within each real row instead of inventing a row pin.

READ data begins CL clocks after READ; WRITE data begins with WRITE. Fixed
bursts 1/2/4/8 and physical-row boundary splitting are modeled. Explicit
PRECHARGE makes page-policy costs visible. Each chip has its own refresh state:
one may receive commands while the other is within tRFC. DQ never overlaps.
A one-clock read/write turnaround is an explicit, configurable controller/board
assumption because the datasheet specifies the relationships in waveforms, not
with a single tWTR value.

## Run and compare

From the repository root:

```sh
make sdram-test
make sdram-sim

tools/sdram-model/sdram-sim --help
tools/sdram-model/sdram-sim --duration-us 1000 --timeline 192 --window-cycles 10000
tools/sdram-model/sdram-sim --frequency 130 --mapping linear \
  --scheduler edf-row-hit --page-policy open --burst 8
tools/sdram-model/sdram-sim --decode 0x2000 --mapping stripe-1k-chip-bank
tools/sdram-model/sdram-sim --format json > result.json
tools/sdram-model/sdram-sim --trace trace.csv --timeline 128
tools/sdram-model/sdram-sim --frequency 150 --allow-overclock
python3 tools/sdram-model/sweep_output.py --duration-us 100 --workers 4
```

The default `output` workload now follows the presentation architecture. Use
`--presentation-mode capture` (the default) for normal live operation, where
HDMI receives the generated raster directly and SDRAM is write-only. Use
`--presentation-mode replay` for a missed production deadline, where SDRAM is
read-only for video. `capture-replay` alternates those states at frame
boundaries. `stress` preserves the older, deliberately pessimistic simultaneous
scanout-and-capture experiment.

The output workload has independently paced channels:

- `scanout`: replay reads, with FIFO-derived deadlines; absent during capture.
- `audio`: 48 kHz stereo 16-bit, also with FIFO-derived deadlines.
- `frame-write`: ideal on-demand capture slots; absent during replay.
- `audio-write`: ideal on-demand delivery slots for the frame's audio epoch.

Video and audio input requests are governed by `--input-frame-hz`. The
`--video-write-buffer-words` and `--audio-write-buffer-words` controls determine
how far ahead of the nominal delivery pace the output side may request data.
This assumes requested data is immediately available: the resulting WRITE
times are a contract for the machine side, not a prediction of its production
latency. Set `--input-frame-hz 0` to measure the readout floor.

`--bits-per-pixel` models tightly packed presentation formats, so 1080p8 and
720p16 have approximately comparable traffic. A complete captured buffer is
reported as published only when every burst completes by the frame deadline;
partial buffers remain unpublished. Replay underruns and safe replay frames are
reported separately. `--background-mb-s` adds a paced read or write stream to
measure schedulable residual bandwidth instead of treating every observed idle
clock as usable. `sweep_presentation.py` compares capture/replay, the six
mappings, 720p16/1080p8/1080p16, both background directions, and the requested
clock frequencies.

`--scheduler watermark` is the small hardware-oriented arbiter. Audio is
fixed highest priority. Replay becomes urgent below `--video-low-watermark`;
capture becomes urgent above `--video-high-watermark`; urgency is hysteretic
until the opposite threshold is crossed. Presentation requests remain strictly
in order, urgency is reconsidered after every physical BL8 command, and
background requests may use the bounded row-hit lookahead. The active frame's
publication deadline supplies a separate tail-flush event.

`--active-fraction` separates active raster transfer from blanking. The normal
CLI default of 1.0 preserves older uniformly paced experiments. The watermark
sweep defaults to the 1080p60 active/total pixel ratio
`(1920*1080)/(2200*1125)`, so its presentation stream is faster during active
video and can drain during the physical blanking interval. Run the focused
full-frame sweep with:

```sh
python3 tools/sdram-model/sweep_watermark.py --background-rates 100 110 120 130
```

`--burst` is the physical SDRAM burst length. `--scanout-refill-words` controls
how much BRAM space accumulates before a block becomes ready to refill.
Per-channel `--*-grant-words` options are separate soft arbiter quanta: for
example, a 256-word refill/grant is built from 32 consecutive BL8 commands.
Larger grants
amortize read/write turnaround but create longer waits for the opposite
direction. The scheduler may temporarily use another channel while the
preferred grant cannot make legal progress. Reports include the resulting DQ
direction-change count, maximum no-service gap, and maximum contiguous service
run for every channel. They also show average/maximum queue wait (arrival to
first command) and completion latency in microseconds, so a refill sweep can be
judged by writer responsiveness instead of aggregate bandwidth alone.

Resolution, rates, FIFO depths and each channel's base address are command-line
parameters. Base addresses plus the selected mapping determine actual chip and
bank placement; no chip role is baked in. The simulation uses a fixed
`--duration-us` observation horizon,
so overload remains visible as pending requests and deadline misses instead of
being hidden by draining the queue after the workload ends.

Synthetic saturation, stride, conflict and mixed workloads remain available.
Mappings are `linear`, `chip-row-bank-column` (chip-isolated framebuffers with
2 KiB bank rotation), two 2 KiB chip/bank interleaves, and two experimental
1 KiB chip/bank interleaves. Arbitration (`--scheduler`) is independent of
page handling (`--page-policy`). Available schedulers are FIFO, row-hit-first,
EDF, deadline-guarded row-hit, fixed channel priority, and round-robin.
Scheduling inspects a bounded, arrival-ordered window per channel (64 requests
by default) rather than assuming an associative search of an entire frame
backlog; this is configurable with `--scheduler-lookahead`.

## Reading the output

Top-level DQ utilisation is split into useful bandwidth and truly unused
`leftover_mb_s`. This is spare bus opportunity within the observation window,
not a promise that every idle clock is usable without future turnaround or
deadline effects.

Each channel reports offered versus received MB/s, service percentage and
backlog, its percentage of all clock slots, completed requests, deadline
misses, maximum lateness, latency, first/last service, and the longest gap
between serviced words. The human report labels queue wait and completion
latency as `wait_us` and `lat_us`, each in average/maximum order. It also reports
the distribution of that channel's
words over both chips and all eight banks. These expose placement effects and
help size FIFOs even when average bandwidth looks safe.

`--timeline N` prints command and DQ lanes for the first N cycles. `--window-cycles
N` gives a slower-scale table of each channel's share and idle capacity. The
CSV trace contains every cycle with a command or DQ transfer, including channel,
direction, request, chip, bank, row and column, for plotting or inspection.

Per-chip and per-bank counters show whether an apparent scheduler result is
actually caused by placement or conflicts. Refresh counts are per chip and
`refresh_chip_cycles` is deliberately not labeled global downtime: work on the
other chip can hide it.

The model raises `CommandError` on illegal ACTIVE, READ/WRITE, PRECHARGE,
REFRESH, command-bus, tRCD, tRP, tRAS, tRC, tRRD, tWR, row-address, or shared-DQ
sequences. Full-page bursts, explicit BURST TERMINATE, initialization, and a
second independent board controller are intentionally not modeled yet.
