# SDRAM Backend Comparison Plan

Date: 2026-09-12

This note defines the next SDRAM experiment layer.  It is a measurement
framework, not a controller rewrite.

The comparison starts after these checkpoints:

- `38c2999 Preserve SDRAM controller sizing baseline`
- `f49b171 Stream SDRAM write packets through adapter`

After the packet-buffer fix, the reusable two-client controller is small enough
to compare on merit rather than treating area as an immediate blocker.

## Contenders

### 1. Simple permissive controller, close to stock

Use a permissively licensed SDR SDRAM controller, initially `agg23/sdram.sv`,
with only the minimum benchmark adaptation required.  This is the cheap physical
controller baseline.

The stock controller's natural interface is single-port and single-operation
oriented.  Do not hide that difference by adding a large request scheduler in
front of it for this contender.

### 2. Simple permissive controller behind our request layer

Use the same simple physical backend, but preserve the client-facing request,
completion, tag, streaming write-data, and streaming read-data shape we care
about.  This measures the cost of our abstraction separately from the custom
open-row backend.

Report at least:

- request/adapter layer resources;
- simple physical backend resources;
- total resources;
- behavioural metrics through the shared trace runner.

### 3. Current custom backend

Use the current implementation without optimizing it for the benchmark:

- request splitting;
- BL8 physical operations;
- explicit refresh handling;
- open-row tracking/scheduling;
- two-client support;
- deterministic completion behaviour.

Report at least:

- transaction/request layer resources;
- scheduler/timing resources;
- BL8 physical engine resources;
- total resources.

## Directory Layout

The benchmark infrastructure is intentionally outside production RTL:

```text
tools/sdram-backend-bench/
    README.md
    run_bench.py
    traces/
        generated deterministic workload traces
    results/
        generated CSV/JSON summaries, not committed by default

rtl/scanout-sdram-controller/tb/backend-bench/
    future SystemVerilog trace source and result collector
    future RTL wrappers for the three contenders

third_party/
    future vendored permissive controller copies with license text
```

The first committed executable slice is a deterministic command-level benchmark
model.  It establishes workload definitions, trace format, and output metrics.
It is not a substitute for RTL simulation or Quartus fitting.  The next slice
should bind the same traces to RTL wrappers and then to Quartus harnesses.

## Common Trace Format

CSV, one logical request per row:

```text
cycle,client,op,address,words,byte_enable,tag
```

- `cycle`: earliest cycle the request may be offered.
- `client`: client number, initially `0` or `1`.
- `op`: `R` or `W`.
- `address`: byte address, decimal or `0x` hex, 16-bit aligned.
- `words`: number of 16-bit words.
- `byte_enable`: two-bit write mask in hex; reads use `3`.
- `tag`: opaque request tag.

The shared logical interface is high enough to express the traffic we care
about, but the benchmark must not accidentally implement most of the custom
controller in front of the simple-stock contender.

## Adapter Boundaries

### Stock simple backend

Boundary:

```text
trace request -> minimal issue shim -> simple controller native request
```

The shim may split requests only when the simple controller cannot naturally
express the requested length or address.  That splitting cost is benchmark
infrastructure, not credited as a feature of the stock controller.

### Request layer plus simple backend

Boundary:

```text
trace request
    -> our clean request/completion semantics
    -> simple backend operation adapter
    -> simple controller
```

This contender is allowed to pay for request ownership, deterministic
completion, write/read streaming, and per-client arbitration.  It should not
inherit the custom open-row scheduler.

### Current custom backend

Boundary:

```text
trace request
    -> sdram_two_client_controller-style request interface
    -> initialized runtime
    -> open-row scheduler
    -> BL8 engine
```

The first RTL benchmark wrapper should expose internal counters rather than
changing production logic to optimize the benchmark.

## Workload Families

The framework must include hostile and representative traffic:

1. long sequential reads;
2. long sequential writes;
3. alternating reads and writes;
4. same-bank row thrashing;
5. bank interleaving;
6. chip interleaving;
7. very poor row locality;
8. very good row locality;
9. small awkward requests crossing BL8 boundaries;
10. row/bank/chip/mapping boundary cases;
11. maximum-size requests;
12. two-client saturated contention;
13. latency-sensitive client versus bandwidth hog;
14. sustained traffic under refresh pressure;
15. starvation attempts;
16. byte-enable stress;
17. mixed scanout/capture/audio-like traffic.

The set must include traces intended to make auto-precharge look good, open-row
scheduling look good, open-row scheduling look pointless, high clock rate
compensate for simple policy, and scheduling cleverness compensate for lower
clock rate.

## Real Machine Capture Topology

Do not model normal HDMI presentation as external SDRAM read traffic.

The steady-state presentation path is:

```text
machine raster
    -> BRAM line-buffer ping-pong
    -> HDMI scanout / scaling / repetition
```

The HDMI side may read or resample the completed source line multiple times,
but that is local BRAM traffic.  Repeated HDMI sampling must not become
repeated SDRAM traffic in this benchmark.

The independent capture path is:

```text
completed BRAM source line
    -> one SDRAM capture drain
```

For the baseline 1280x720 16-bit source format:

- source line size: 1280 pixels * 2 bytes = 2560 bytes;
- source lines/sec: 720 * 60 = 43,200;
- average capture bandwidth: 110.592 MB/s;
- source-line period: about 23.15 us.

The important property is the deadline shape, not the average bandwidth: one
completed 2560-byte line arrives about every 23.15 us and must be drained before
the corresponding BRAM line buffer is needed again.  The benchmark therefore
models periodic deadline traffic with gaps, not a uniform permanent 110 MB/s
stream.

The minimum topology is two line buffers:

```text
line A: currently being populated by the source raster
line B: previous completed line being presented locally and drained to SDRAM
```

Additional line-buffer elasticity is a stress parameter, not an assumed
requirement.  The command-level benchmark currently accepts `--line-buffers 2`,
`3`, or `4` and reports missed deadlines plus minimum slack.

The model now represents each BRAM line buffer explicitly.  A buffer moves
through these states:

```text
FREE -> FILLING -> COMPLETE_AVAILABLE -> DRAINING_TO_SDRAM -> FREE
```

At each source-line completion, the just-filled buffer becomes
`COMPLETE_AVAILABLE` and its SDRAM drain requests are enqueued exactly once.
The next ping-pong buffer must be `FREE` before it can become `FILLING`.  If it
is still `COMPLETE_AVAILABLE` or `DRAINING_TO_SDRAM`, the benchmark records a
hard video buffer conflict.  This is the real failure condition: the raster
producer cannot swap into a buffer still owned by capture.

The command-level model asserts impossible ownership transitions, such as
draining a buffer that is neither complete nor already draining.

Raster timing is also explicit:

- `--raster-mode logical` models exactly 720 active source lines per 1/60 sec
  frame, with one active line every about 23.15 us.  This deliberately does not
  assume physical HDMI blanking.
- `--raster-mode blanked --raster-total-lines N` models a frame with `N` total
  line periods and 720 active source lines, placing the extra time after the
  active region as vertical blanking.  This lets later sweeps test whether
  blanking materially changes SDRAM availability.

Audio capture is modelled as chunked FIFO-like writes.  The baseline is 48 kHz,
stereo, 16-bit samples, or 192,000 bytes/sec.  The current command-level model
uses 256-byte audio chunks with one chunk deadline period.

The primary machine-level question is:

```text
with video and audio capture deadlines met perfectly,
how much useful background SDRAM bandwidth remains?
```

The benchmark sweeps offered background traffic until video deadline miss,
audio deadline miss, or backend saturation.  Background variants include
sequential reads, sequential writes, mixed sequential traffic, random reads,
random writes, mixed random traffic, poor locality, good locality,
bank-conflict-heavy traffic, and read/write direction thrashing.

The line-drain packet size is a first-class sweep dimension.  A 2560-byte line
may be drained as one large transaction, several medium transactions, BL8-sized
chunks, or another implementation-natural size.  The standard command-level
sweep includes 8, 16, 32, 64, 128, 256, 640, and 1280 16-bit words.  This is
necessary because the simple high-Fmax controller may prefer larger sequential
chunks, while the custom backend may be less sensitive to packetization.

## Metrics

Collect these where available:

- useful bytes;
- cycles elapsed;
- useful MB/s at the tested SDRAM clock;
- request-to-first-response latency;
- request-to-completion latency;
- per-client latency distribution;
- max and percentile latencies;
- backend/client stall cycles;
- queue/FIFO occupancy;
- backpressure durations;
- ACTIVATE, PRECHARGE, READ, WRITE, REFRESH counts;
- row hits, row misses/conflicts;
- read/write direction changes;
- idle/bubble cycles;
- refresh-induced stalls;
- useful bus occupancy;
- ALMs, ALUTs, registers, M10Ks, DSPs, PLLs, slack, Fmax;
- important critical paths.

Unavailable metrics should be marked unavailable, not invented.

## Clock Comparisons

Report two views:

1. equal SDRAM clock rate where all contenders can run;
2. each contender at a realistic fitted Fmax-derived clock.

This separates policy efficiency per SDRAM cycle from complete implementation
throughput on this FPGA.

## Fairness Limits And Assumptions

- The simple stock contender is naturally single-port.  Two-client contention
  is driven through the smallest reasonable arbiter/shim and reported as such.
- The command-level model used by the first executable slice is a planning and
  trace-validation tool.  It does not replace RTL simulation or Quartus reports.
- The machine-capture model currently uses a strict priority order of video,
  then audio, then background when all are pending.  That is a deliberate
  deadline-safety assumption for the first command-level sweep and must be
  revisited when real RTL arbiters are compared.
- The command-level machine sweep reports only the last passing background
  load point.  If a backend has no passing point, it is omitted from that
  particular summary.  In practice this can happen when the baseline video
  capture workload already misses its deadlines under the selected clock,
  buffering, or line-packetization.
- Short `--lines` sweeps are smoke tests.  Full-frame sweeps should still be
  run before drawing architectural conclusions, especially for refresh-phase
  and long-tail latency behaviour.
- Current address mapping assumes the existing `stripe-1k-bank-chip` mapping
  used by the custom controller unless a workload explicitly says otherwise.
- Refresh modelling begins as periodic all-bank service time.  RTL wrappers
  should later count real refresh commands and stalls.
- The GPL MiSTer controller remains reference-only and is not copied here.

## Review Gates

1. Commit this benchmark plan.
2. Commit deterministic trace generator and command-level result collector.
3. Add RTL wrappers for stock simple, request-layer simple, and custom current.
4. Add Quartus sizing harnesses for each wrapper.
5. Only then make architectural recommendations.
