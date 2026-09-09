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
  two byte-mask bits with each 16-bit word.

Run `make test` for directed tests, `make lint` for Verilator lint, and
`make formal` for SymbiYosys proofs of splitter physical bounds, strict arbiter
priority and grant stability, frame ownership/publication (including simultaneous
publish/replay), FIFO ordering/conservation, and refresh-command deadlines for
both open- and closed-bank cases.

The production board-facing DQ PHY, asynchronous CDC FIFOs, complete multi-client queues,
bank timing engine, counters, and full-frame acceptance harness remain integration
work. The modules here deliberately expose clean boundaries for those pieces; this
is not yet a complete presentation controller and no 122 MB/s claim applies to it.
