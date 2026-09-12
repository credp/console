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
- a bounded BL8 physical command engine. It translates accepted scheduler
  commands to SDRAM pins, drives all eight write beats from an atomic 128-bit
  payload, captures all eight read beats into an atomic payload, and pulses
  `burst_done` on physical beat seven. Once a READ or WRITE command is accepted
  it cannot be stretched by client backpressure; its bound is seven remaining
  write clocks or `READ_CAPTURE_CYCLES + 8` read clocks. Initialization and the
  board-specific input register/capture phase intentionally remain outside this
  engine.
- an additive open-row core integrating that engine with the scheduler. It
  latches a complete write payload at operation acceptance, keeps it stable
  across any PRECHARGE/ACTIVATE work, and returns reads as complete atomic BL8
  payloads. Directed pin-model tests cover closed-bank, row-hit, and
  row-conflict write/read round trips.
- a two-chip runtime refresh deadline generator. It converts the 7.8 us
  datasheet interval into clocks, staggers the chips by half an interval,
  raises each persistent request early by the configured downstream service
  bound plus a registration margin, and resets a chip's age only after the
  scheduler reports that AUTO REFRESH was issued. Sticky late flags make a
  violated integration contract observable.
- a runtime core composing the deadline generator, open-row scheduler, and
  bounded BL8 engine. Its pin-model test keeps offering row-conflicting writes
  while checking that useful traffic progresses, refresh preempts only between
  operations, both chips receive REF within tREFI, and every emitted command
  remains legal. A one-entry response holder removes client completion
  backpressure from the physical-operation bound, while still preventing a new
  client operation from overwriting an unconsumed response.
- a single-client transaction adapter for the architecture-level request
  shape: byte address, word count, direction, and tag plus streamed write/read
  data. It collects a complete write request before issue, uses the common
  boundary splitter, packs useful words and DQM enables into atomic BL8
  operations, serializes useful read words under arbitrary backpressure, and
  returns exactly one stable tagged completion with the number of successfully
  committed words. Invalid zero-length,
  over-capacity, and odd-address requests complete with an error without
  touching SDRAM.
- a composed single-client controller wrapper that owns the explicit
  initialization/runtime handoff. Architecture requests remain backpressured
  until the power-up, precharge-all, refresh, and mode-register sequence has
  completed. At that edge the runtime core leaves reset and begins its own
  staggered refresh-age accounting from a defined zero point. Pin ownership is
  multiplexed between the initialization sequencer and runtime core; the
  board-specific registered DQ capture boundary remains external.
  The client-independent initialization and pin multiplexer is factored into
  `sdram_initialized_runtime`, leaving the controller wrapper as a small
  composition of the request adapter and atomic runtime boundary.
- an incremental two-client transaction layer. Each client independently owns
  one admitted request, a complete write staging buffer, a splitter, tagged
  completion state, and a reserved atomic read-response slot. Round-robin
  arbitration occurs only between physical BL8 operations. A stalled reader
  cannot retain the runtime core's response holder or prevent the peer and
  refresh machinery from progressing. The directed pin-model test interleaves
  two boundary-splitting writes and reads, checks exact per-client ordering and
  accounting, and demonstrates peer completion while the other read stream is
  deliberately stalled.

Run `make test` for directed tests, `make lint` for Verilator lint, and
`make formal` for SymbiYosys proofs of open-row command legality, bounded BL8
pin transactions, refresh deadline policy, bounded single-client handshake and
completion-accounting checks,
splitter physical bounds, strict arbiter
priority and grant stability, frame ownership/publication (including simultaneous
publish/replay), FIFO ordering/conservation, and refresh-command deadlines for
both open- and closed-bank cases.

The new scheduler is deliberately not connected to the hardware-qualified 006.b
experiment or its conservative BL8 engine. Its refresh request port is not yet
a refresh deadline generator: bounding request-to-service latency requires the
physical burst engine to provide a bounded operation duration. The new BL8
engine and open-row core establish that local bound, and the deadline generator
uses it as an explicit contract. Their runtime composition is tested under
sustained traffic. The composed wrapper provides the first directly usable,
initialization-aware request interface. The first two-client transaction and
response-reservation layer is independently tested; deeper multi-entry queues,
priority policy, and integration with initialization must be added
and verified before creating a successor hardware experiment. The production
board-facing DQ PHY, asynchronous CDC FIFOs, complete multi-client queues,
counters, and full-frame acceptance harness also remain integration work. The
modules here deliberately expose clean boundaries for those pieces; this is not
yet a complete presentation controller and no 122 MB/s claim applies to it.
