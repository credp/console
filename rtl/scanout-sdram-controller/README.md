# Scanout SDRAM controller

This directory is the first synthesizable RTL foundation derived from
`tools/sdram-model/IMPLEMENTATION_SPEC.md`. It uses the MiSTer-style
SystemVerilog and Quartus QIP conventions used by `experiments/`.

Implemented and independently testable:

- all six address mappings, defaulting to `stripe-1k-bank-chip`;
- mapping-aware splitting at BL8-wrap, chip, bank, and row boundaries;
- replay/capture watermark hysteresis, audio/refresh priority, and background gating;
- datasheet-style power-up, precharge-all, eight refreshes per chip, MRS, tMRD,
  staggered per-chip refresh tracking, and late-refresh flags;
- atomic frame publication after exact SDRAM-commit accounting and drain proof,
  with explicit version/pulse and a replay buffer latched only at frame start;
- a 4,096-cycle capture flush guard and mutually-exclusive presentation mode control;
- inferred on-chip block-RAM FIFOs: 2,048-word video capture, 2,048-word replay,
  512-word audio playback, and 256-word audio write staging. Write queues store
  two byte-mask bits with each 16-bit word;
- an additive, single-operation open-row scheduler and timing tracker. The
  tracker records the open row, read/write burst ownership, and command ages
  for all eight physical banks. It qualifies ACTIVATE, PRECHARGE, READ, WRITE,
  PRECHARGE ALL, and AUTO REFRESH against tRCD, tRP, tRAS, tRC, tRRD, tWR, and
  tRFC. The scheduler resolves closed-bank, row-hit, and row-conflict cases and
  holds a proposed command stable under command-bus backpressure. A refresh
  request has priority only between physical operations; it legally closes all
  banks of the selected chip, waits through tRP, and issues AUTO REFRESH without
  imposing that chip's tRFC recovery on operations targeting the other chip;
- a parameterized global DQ-direction guard. It timestamps the final physical
  burst beat and reserves the configured number of completely empty clocks
  before an opposite-direction column command. The current scheduler uses this
  conservative rule in both directions; a future PHY may safely recover some
  write-to-read command overlap from the configured CAS latency.

Run `make test` for directed tests, `make lint` for Verilator lint, and
`make formal` for SymbiYosys proofs of open-row command legality, splitter physical bounds, strict arbiter
priority and grant stability, frame ownership/publication (including simultaneous
publish/replay), FIFO ordering/conservation, and refresh-command deadlines for
both open- and closed-bank cases.

The new scheduler is deliberately not connected to the hardware-qualified 006.b
experiment or its conservative BL8 engine. Its refresh request port is not yet
a refresh deadline generator: bounding request-to-service latency requires the
physical burst engine to provide a bounded operation duration. Physical
data-beat integration, deadline generation, and multi-operation scheduling must be added
and verified before creating a successor hardware experiment. The production
board-facing DQ PHY, asynchronous CDC FIFOs, complete multi-client queues,
counters, and full-frame acceptance harness also remain integration work. The
modules here deliberately expose clean boundaries for those pieces; this is not
yet a complete presentation controller and no 122 MB/s claim applies to it.
