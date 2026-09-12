# SDRAM Controller Resource Baseline

Date: 2026-09-12

This note preserves the Quartus resource/timing baseline taken before changing
the reusable SDRAM controller implementation.  The purpose of the measurement
was to compare the physical cost of our current controller against several
known working SDR SDRAM controllers, then identify why our implementation was
so large.

No controller RTL was modified for this baseline.

## Measurement Setup

- FPGA: Cyclone V `5CSEBA6U23I7`
- Toolchain: Quartus Prime Lite 17.0
- Main clock constraint: 130 MHz, `7.692 ns`
- Harness style: minimal standalone top modules exposing SDRAM pins and enough
  observable request/response pins to keep real read/write paths alive.
- Temporary project roots:
  - MiSTer/Sorgelig reference: `/tmp/mister-sdram-size`
  - agg23 ordinary: `/tmp/sdram-baseline/agg23`
  - agg23 burst: `/tmp/sdram-baseline/agg23_burst`
  - stffrdhrn: `/tmp/sdram-baseline/stffrdhrn`
  - AngeloJacobo optional: `/tmp/sdram-baseline/angelo`
  - Our controller: `/tmp/codex-sdram-size`

External references were used for measurement only:

- Sorgelig/MiSTer-style `sdram.sv`, GPL reference implementation.
- `agg23/sdram-controller`, MIT, ordinary and burst variants:
  <https://github.com/agg23/sdram-controller>
- `stffrdhrn/sdram-controller`, BSD-style Verilog controller physically tested
  on DE0-Nano:
  <https://github.com/stffrdhrn/sdram-controller>
- Optional `AngeloJacobo/FPGA_SDRAM_Controller`, MIT:
  <https://github.com/AngeloJacobo/FPGA_SDRAM_Controller>

The MiSTer/Sorgelig implementation is GPL and must remain a measurement
reference only.  Do not copy GPL implementation code into this controller.

## Resource And Timing Summary

All entries are fitted on `5CSEBA6U23I7` with Quartus 17.0.  Timing is from the
same 130 MHz clock constraint, except where a reference design naturally
contains board/vendor-specific clocking inside the measured block.

| Implementation | Interface shape | ALMs | Comb ALUTs | Registers | M10Ks | DSPs | PLLs | Timing |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Sorgelig/MiSTer `sdram.sv` | single SRAM-like port, no burst, auto-precharge | 70 | 105 | 136 | 0 | 0 | 0 | +2.752 ns, Fmax 204 MHz |
| agg23 `sdram.sv` | single port, timing-parameterized, BL1 | 127 | 213 | 163 | 0 | 0 | 0 | +1.621 ns, Fmax 165 MHz |
| agg23 `sdram_burst.sv` | single port, continuous/page burst read | 182 | 302 | 161 | 0 | 0 | 0 | +1.174 ns, Fmax 153 MHz |
| stffrdhrn `sdram_controller.v` | single-word host interface, auto-precharge | 53 | small, about 125 logic-cell class pre-fit | 80 | 0 | 0 | 0 | +3.460 ns, Fmax 236 MHz |
| AngeloJacobo optional | full-page burst controller, Quartus ODDR shim | 83 | 139 | 132 | 0 | 0 | 0 | +2.295 ns, Fmax 194 MHz |
| Our `sdram_two_client_controller` | two clients, request splitting, BL8 ops, open-row scheduler | 20,698 | 26,018 | 10,500 | 0 | 0 | 0 | -4.012 ns, Fmax 85.9 MHz |

## Our Controller Hierarchy

Corrected fit for `sdram_two_client_controller`:

| Hierarchy | ALMs | Comb ALUTs | Registers | Notes |
| --- | ---: | ---: | ---: | --- |
| `sdram_two_client_controller` | 20,681.4 | 26,018 | 10,500 | total reusable controller |
| `sdram_initialized_runtime` | 13,213.3 | 17,890 | 837 | runtime plus init |
| `sdram_runtime_core` | 13,045.5 | 17,617 | 736 | runtime backend |
| `sdram_open_row_core` | 13,013.8 | 17,559 | 707 | attribution sink for wide write-data mux path |
| `sdram_bl8_phy_engine` | 48.3 | 57 | 285 | sane physical BL8 engine cost |
| `sdram_open_row_scheduler` | 412.0 | 558 | 278 | includes timing tracker |
| `sdram_bank_timing` | 356.2 | 485 | 241 | explicit bank/timing legality tracker |
| `sdram_two_client_adapter` | 7,467.3 | 8,126 | 9,663 | dominated by two client staging buffers |
| `sdram_single_client_adapter:client0` | 3,627.5 | 4,056 | 4,701 | one client staging path |
| `sdram_single_client_adapter:client1` | 3,789.8 | 4,055 | 4,701 | one client staging path |

The timing tracker and BL8 PHY are not the problem.  They are in the hundreds
or tens of ALMs.  The pathological cost is in the transaction plumbing.

## Smoking Gun

The current client adapter represents a request of up to 256 words as a
256-word random-access object:

```systemverilog
logic [15:0] write_buffer [0:MAX_REQUEST_WORDS-1];
logic [1:0]  enable_buffer [0:MAX_REQUEST_WORDS-1];
```

The physical operation path then selects an arbitrary eight-word window
combinationally:

```systemverilog
word_index = int'(issued_words);
word_index = word_index + payload_index;
op_write_data[payload_index*16 +: 16] = write_buffer[word_index];
op_write_byte_enable[payload_index*2 +: 2] = enable_buffer[word_index];
```

This is natural as a software data structure, but it is a poor FPGA structure.
Quartus cannot infer M10Ks from an asynchronously read, variable-index,
eight-word sliding window.  It therefore implements:

- storage as flip-flops;
- a large combinational mux network to select the current BL8 window.

Each client contains 256 x 16 data bits plus 256 x 2 byte-enable bits, or 4,608
raw storage bits.  Two clients account for 9,216 raw staging bits, which aligns
with the fitted `9,663` registers in `sdram_two_client_adapter`.

The worst detailed setup paths confirm this.  The top failing paths go from the
client adapter/request splitter into the BL8 write payload latch:

```text
sdram_single_client_adapter:client1|sdram_request_splitter:splitter|address_q/remaining_q
  -> sdram_open_row_core|write_enable_q / write_data_q
```

Worst reported detailed setup path:

```text
slack      -3.949 ns
data delay 10.827 ns
from       client1 splitter address_q[2]
to         open_row_core write_enable_q[5]
```

The area failure and Fmax failure are the same mistake viewed from two angles:
flip-flop staging plus a giant sliding-window mux.

## Design Conclusions

The comparison does not argue for cloning a small reference controller.  Those
controllers expose much simpler interfaces and usually use auto-precharge fixed
sequences.  Our design still wants a clean request interface, deterministic
responses, verification-friendly state, refresh safety, and bounded physical
operations.

The comparison does show that a 256-word architecture-level request must not be
materialized as a 256-word random-access transaction object in flip-flops.
Instead, the physical implementation should stream the transaction:

```text
client request metadata
    -> small write FIFO / stream
    -> boundary splitter / packetizer
    -> one BL8 packet buffer
    -> scheduler
    -> BL8 engine
```

The request splitter only needs the current address, words remaining, and next
physical boundary.  The packetizer only needs enough storage for one BL8
operation, plus modest elasticity if required.

## Classification

Functionality genuinely required by our design:

- clean request/completion interface;
- bounded physical SDRAM operations;
- refresh safety;
- deterministic response behavior;
- enough buffering/flow control to decouple clients from the SDRAM bus.

Additional robustness / verification-related structure:

- explicit timing tracker;
- bank/open-row state;
- refresh deadline tracking;
- visible timing violation signals.

The measured cost of these parts is sane, especially `sdram_bank_timing` at
about 356 ALMs.

Implementation choices that are unnecessarily expensive:

- 256-word per-client write staging in flip-flops;
- combinational eight-word variable-index extraction;
- allowing the request representation to behave like a random-access array.

Experimental flexibility accidentally worth guarding against:

- address mapping should remain compile-time/elaboration-time specialized;
- experimenting with several mappings must not imply runtime hardware for all
  mappings at once.

Storage that should naturally map to memory or streams:

- write staging should be BRAM/FIFO-shaped, or avoided via streaming;
- a 256-word max request should become 256 words passing through the machine,
  not 256 words resident inside the machine.

Functionality present in our controller but absent from smaller references:

- two clients;
- request splitting across BL8, row, and mapping boundaries;
- open-row retention;
- per-client completion and response isolation;
- BL8 packet aggregation;
- explicit refresh deadline enforcement.

These features justify some additional area over the references, but not
20,000 ALMs.

## Next Measurement Plan

Before rewriting policy, preserve the existing useful pieces and measure the
replacement transaction shape in layers:

1. packetizer only, with a fake ready/valid sink;
2. packetizer plus simple auto-precharge backend;
3. packetizer plus current-style open-row backend;
4. one-client controller;
5. two-client controller.

The first implementation pass should be boring and explicit: one outstanding
transaction, one BL8 packet buffer, and one small FSM.  Clever scheduling should
wait until the physical representation is small and timing-clean.
