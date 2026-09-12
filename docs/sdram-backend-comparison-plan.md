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
