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
    generate_trace.py
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

The primary benchmark artifact is a deterministic logical request trace.  It
establishes workload demand only.  The existing command-level model is retained
as a synthetic smoke tool while RTL wrappers are being built; it is not a
source of architectural performance evidence.

## Common Trace Format

CSV, one logical request per row:

```text
issue_time_ns,client_id,op,address,length_words,byte_enable,tag,deadline_ns,traffic_class
```

- `issue_time_ns`: earliest controller-independent time the request may be
  offered, in integer nanoseconds.
- `client_id`: logical client number, initially `0` for capture traffic and
  `1` for arbitrary background traffic.
- `op`: `R` or `W`.
- `address`: byte address, decimal or `0x` hex, 16-bit aligned.
- `length_words`: number of 16-bit words.
- `byte_enable`: two-bit write mask in hex; reads use `3`.
- `tag`: opaque request tag, unique within the trace.
- `deadline_ns`: hard completion deadline in integer nanoseconds, or `-1` when
  the request has no deadline.
- `traffic_class`: inspectable label such as `video`, `audio`, or
  `background:mixed_random`.

The trace must not include SDRAM/backend-derived fields such as ACTIVATE,
PRECHARGE, row-hit classification, predicted latency, predicted completion
time, controller busy time, or arbitration decisions.  Those are measured from
RTL and result instrumentation.

The shared logical interface is high enough to express the traffic we care
about, but the benchmark must not accidentally implement most of the custom
controller in front of the simple-stock contender.  A replay driver may queue
requests that have reached `issue_time_ns` until the controller's real
handshake accepts them, but it must record that queueing rather than silently
moving request arrival times.

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
completed 2560-byte line arrives about every 23.15 us and must be captured
before the corresponding BRAM line buffer is needed again.  The logical trace
therefore emits periodic line-write demand with deadlines, not a uniform
permanent 110 MB/s stream.

The minimum topology is two line buffers:

```text
line A: currently being populated by the source raster
line B: previous completed line being presented locally and drained to SDRAM
```

The trace generator does not run a generalized line-buffer simulator.  For the
minimum two-buffer ping-pong topology, it represents the ownership requirement
as deadlines: a line capture request becomes available when the source line is
complete and must complete before that buffer would be reused.  With the
default `--line-buffers 2`, line `N` uses deadline `line_time(N + 2)`.
Additional line-buffer elasticity is represented by increasing the deadline
offset; the RTL result collector is responsible for reporting actual deadline
misses and slack.

Raster timing is also explicit:

- `--raster-mode logical` models exactly 720 active source lines per 1/60 sec
  frame, with one active line every about 23.15 us.  This deliberately does not
  assume physical HDMI blanking.
- `--raster-mode blanked --raster-total-lines N` models a frame with `N` total
  line periods and 720 active source lines, placing the extra time after the
  active region as vertical blanking.  This lets later sweeps test whether
  blanking materially changes SDRAM availability.

Audio capture is generated as chunked FIFO-like writes.  The baseline is 48
kHz, stereo, 16-bit samples, or 192,000 bytes/sec.  The default logical trace
uses 256-byte audio chunks with one chunk deadline period.

The primary machine-level question is:

```text
with video and audio capture deadlines met perfectly,
how much useful background SDRAM bandwidth remains?
```

The trace generator can emit background traffic at a configured offered load.
Background variants include sequential reads, sequential writes, mixed
sequential traffic, random reads, random writes, mixed random traffic, poor
locality, good locality, same-bank-conflict-style addressing, and read/write
direction thrashing.  Random variants are deterministic from an explicit seed.
Finding the maximum sustainable load is an RTL replay/result-collection task.

The line-drain packet size is a first-class trace-generation parameter.  A
2560-byte line may be requested as one large logical transaction or several
smaller logical transactions.  This is application request packetization only;
the generator does not emulate internal SDRAM burst splitting.  Useful sweep
points include 8, 16, 32, 64, 128, 256, 640, and 1280 16-bit words.

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
- The trace generator describes demand only.  It does not choose arbitration
  order, schedule SDRAM commands, classify row hits, or model refresh.
- The command-level model is synthetic/model-only and should not be used for
  final performance conclusions.
- Short generated traces are smoke tests.  Full-frame traces should still be
  replayed before drawing architectural conclusions, especially for refresh
  phase and long-tail latency behaviour.
- Background locality labels are address-pattern hints, not row-hit claims.
  RTL instrumentation must measure the actual SDRAM behaviour.
- The GPL MiSTer controller remains reference-only and is not copied here.

## Review Gates

1. Commit this benchmark plan.
2. Commit deterministic trace generator and command-level result collector.
3. Add RTL wrappers for stock simple, request-layer simple, and custom current.
4. Add Quartus sizing harnesses for each wrapper.
5. Only then make architectural recommendations.
