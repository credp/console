# Output SDRAM controller implementation specification

Status: implementation handoff, derived from the SDRAM exploration model and
its 2026-09-07 full-frame sweeps.

This document specifies the first RTL implementation of the controller for the
dedicated presentation-memory port. It is intentionally more prescriptive than
the exploration model. It records which decisions are fixed for this version,
which values remain parameters, which facts must always hold, and which claims
are assumptions awaiting hardware validation.

The controller described here is **not** the machine scratch-memory controller.
The machine architecture may terminate different pipelines at different memory
I/O ports. This controller owns the output-memory port so scratch traffic on a
separate port cannot block HDMI or audio presentation.

## 1. Requirement vocabulary

Every normative item has one of these labels:

- **[INV] Invariant** — an implementation or safety property that must hold in
  every supported configuration.
- **[PAR] Parameter** — a compile-time or run-time value deliberately exposed
  by the implementation.
- **[DEF] Chosen default** — the value to use in the first implementation and
  whenever a parameter is not overridden.
- **[ASM] Assumption** — an external fact or simplification on which this
  specification relies and which must be validated or revisited.
- **[MEAS] Measured** — a result from the cycle model. It motivates a decision
  but is not itself a hardware guarantee.
- **[REQ] Derived requirement** — an implementation requirement inferred from
  the architecture and measurements.

“Word” means one 16-bit SDRAM word. Byte addresses are used at client
interfaces unless explicitly stated otherwise. MB/s means decimal 1,000,000
bytes/s.

## 2. Scope and architectural boundary

- **[REQ]** Implement one controller for the XS-DS v2.9 output SDRAM board:
  two AS4C32M16SB-7TCN devices, eight banks in total, one shared 16-bit DQ bus.
- **[INV]** The controller is the sole owner of this SDRAM board's command,
  address, DQM, CKE, clock, chip-select, and DQ signals.
- **[ASM]** Machine scratch memory is connected to a different FPGA I/O port
  and a different controller. It contributes no traffic to this controller.
- **[REQ]** The normal presentation states are mutually exclusive:
  `CAPTURE` writes a newly generated frame while HDMI consumes the live raster
  directly; `REPLAY` reads the last published frame when a new frame was not
  ready. Normal operation shall not read and write the video framebuffer at the
  same time.
- **[INV]** A partially written capture buffer must never become visible to the
  replay side. Publication is atomic at frame granularity.
- **[REQ]** Audio playback and audio production remain active independently of
  the video state. Small audio reads/writes may therefore coexist with video
  capture or replay.
- **[PAR]** An optional best-effort/background client may use residual output
  memory bandwidth. It must be throttled and pre-emptible.
- **[INV]** Best-effort traffic must never be required for correct video or
  audio presentation.

Out of scope for this version: the second memory port, cache coherency, a
combined 32-bit rank, ECC, full-page SDRAM bursts, burst terminate, dynamic
clock switching, memory-test pattern generation, image scaling, compression,
and overlay generation. Those may be clients or later extensions; they are not
controller responsibilities.

## 3. Hardware facts and explicitly resolved discrepancies

- **[INV]** The two devices share DQ[15:0], address, bank address, clock, CKE,
  DQM, and command signals.
- **[INV]** XS-DS v2.9 chip selection is complementary: one device receives the
  incoming active-low chip select directly and the other through the board
  inverter. A command edge selects exactly one chip. The devices are not a
  32-bit-wide rank.
- **[INV]** Each chip has 8,192 rows, 1,024 16-bit columns per row, and four
  banks. A physical open row is therefore 2 KiB, not 1 KiB.
- **[INV]** The original exploration prompt described 512 columns/a 1 KiB
  physical row. That differs from the AS4C32M16SB datasheet and is superseded
  here. The selected 1 KiB mapping uses two logical half-rows within each real
  2 KiB row; it does not invent an extra row-address bit.
- **[ASM]** “130 MHz guaranteed” means the official MiSTer project acceptance
  boundary (a board should pass MemTest at 130 MHz), not a component or signal-
  integrity guarantee under every voltage, temperature, assembly, and loading
  condition.
- **[INV]** The -7 device has a 7 ns minimum clock period at CL3. Exact 143 MHz
  has a 6.993 ns period and is therefore exploratory overclocking. It must not
  be labelled device-rated.

Source provenance and links are maintained in `SOURCES.md`.

## 4. Clock, reset, and SDRAM initialization

- **[DEF]** SDRAM clock: 130.000 MHz.
- **[PAR]** `SDRAM_FREQ_HZ`; supported characterized values are 100, 120, 130,
  and exploratory 143 MHz.
- **[DEF]** CAS latency: 3.
- **[INV]** CL2 may only be selected at 100 MHz or below.
- **[REQ]** All nanosecond minimum timing constraints shall be converted with
  ceiling division. Maximum intervals such as refresh spacing shall use floor
  division. RTL elaboration shall fail if a conversion or selected CAS/frequency
  combination is illegal.
- **[REQ]** Client interfaces crossing into the SDRAM clock domain shall use
  explicit asynchronous FIFOs or a proven clock-domain crossing protocol.
  FIFO level values used by arbitration must be synchronized or computed in the
  SDRAM domain; unsynchronized multi-bit levels are forbidden.
- **[REQ]** After reset, perform the datasheet initialization sequence before
  asserting `init_done` or accepting client requests: stable clock/CKE and the
  required power-up delay, PRECHARGE ALL, the required AUTO REFRESH commands,
  LOAD MODE REGISTER, then tMRD. The exact power-up delay and refresh count
  shall be taken from the current datasheet rather than inferred from the
  simulator, which did not model initialization.
- **[INV]** No client-visible request may complete before `init_done`.
- **[REQ]** Reset or loss of SDRAM clock invalidates open-row metadata and any
  unpublished capture buffer.

## 5. Central timing configuration

The first implementation shall centralize these datasheet values and expose
their derived cycle counts to assertions and the command engine:

| Symbol | -7 value used by model | Conversion |
|---|---:|---|
| tRCD | 21 ns | ceil |
| tRP | 21 ns | ceil |
| tRAS | 42 ns | ceil |
| tRC | 63 ns | ceil |
| tRRD | 14 ns | ceil |
| tWR | 14 ns | ceil |
| tRFC | 63 ns | ceil |
| tMRD | 14 ns | ceil |
| tREFI | 7.8 us | floor/max interval |

At the 130 MHz default these evaluate to tRCD=3, tRP=3, tRAS=6, tRC=9,
tRRD=2, tWR=2, tRFC=9, tMRD=2, and tREFI=1,014 clocks.

- **[ASM]** Read/write DQ direction reversal requires one additional empty
  clock beyond non-overlap. The datasheet expresses this through waveforms
  rather than a single tWTR number.
- **[PAR]** `DQ_TURNAROUND_CYCLES`, default 1, shall remain independently
  configurable until hardware testing confirms it.
- **[INV]** The command engine shall enforce command-bus exclusivity, DQ-bus
  exclusivity, tRCD, tRP, tRAS, tRC, tRRD, tWR, tRFC, CAS latency, and the
  selected turnaround interval.
- **[INV]** PRECHARGE may not truncate read data and may not occur before write
  recovery completes.
- **[INV]** ACTIVE requires an idle bank; READ/WRITE requires the addressed row
  to be open; AUTO REFRESH requires every bank of the selected chip to be idle.

## 6. Address space and selected mapping

- **[PAR]** Client-visible byte address width: 27 bits for 128 MiB.
- **[INV]** Odd byte addresses are only meaningful if byte masks are supported;
  video and audio clients shall issue naturally aligned 16-bit words.
- **[DEF]** Mapping: `stripe-1k-bank-chip`.
- **[REQ]** Keep mapping logic isolated in one combinational decoder so another
  mapping can be selected at synthesis without changing the scheduler or bank
  machines.

For byte address `A[26:0]`, the default mapping is:

| Physical field | Byte-address bits |
|---|---|
| byte select | A[0] |
| column[8:0] | A[9:1] |
| chip | A[10] |
| bank[1:0] | A[12:11] |
| column[9] | A[13] |
| row[12:0] | A[26:14] |

Thus consecutive 1 KiB logical chunks visit chip 0/bank 0, chip 1/bank 0,
chip 0/bank 1, chip 1/bank 1, and so on through all eight chip/bank pairs.
After those eight chunks, column[9] selects the other half of the same physical
row before the row number advances.

- **[INV]** The mapping is bijective over 128 MiB and must never alias two byte
  addresses.
- **[INV]** No transfer may cross a physical 1,024-word row boundary. The
  transaction splitter shall shorten the last physical burst as needed and
  continue at the decoded next address.
- **[MEAS]** The mapping sweeps did not establish a universal winner. The
  selected mapping is a practical baseline because it exposes chip and bank
  interleaving at the desired 1 KiB granularity and performed safely in the
  complete-frame presentation tests.
- **[REQ]** Retain at least the six model mappings as verification options, or
  preserve decoder hooks sufficient to instantiate them in simulation:
  `row-chip-bank-column`, `row-bank-chip-column`, `linear`,
  `chip-row-bank-column`, `stripe-1k-chip-bank`, and
  `stripe-1k-bank-chip`.

## 7. Client request interface

The exact HDL naming may follow repository conventions, but each logical client
port shall carry the following information:

```
req_valid
req_ready
req_write
req_byte_address[26:0]
req_words                 // transaction length in 16-bit words
req_tag                    // returned unchanged, width is a parameter
write_valid/write_ready/write_data[15:0]/write_mask[1:0]
read_valid/read_ready/read_data[15:0]
completion_valid/completion_tag/completion_error
```

- **[INV]** A request is accepted exactly once on `req_valid && req_ready`.
- **[INV]** Requests within each mandatory presentation channel complete in
  acceptance order. Reordering between channels is permitted.
- **[INV]** Read data and completion tags must preserve request identity through
  request splitting, bank scheduling, and DQ latency.
- **[REQ]** Backpressure from a client must not corrupt SDRAM timing. If the
  read side cannot be stalled once READ is issued, the controller must reserve
  enough response-FIFO capacity for the entire physical burst before issuing
  it. Likewise, a WRITE may issue only when its complete physical burst is
  locally buffered.
- **[DEF]** Controller-level video and background transaction size: 256 words
  (512 bytes).
- **[DEF]** Audio transaction/grant size: 8 words.
- **[PAR]** Transaction sizes may be powers of two, but the command engine
  always decomposes them into legal SDRAM bursts.
- **[DEF]** Physical SDRAM burst length: BL8.
- **[INV]** Arbitration/pre-emption occurs only between physical BL8 commands,
  never in the middle of a burst.

## 8. Buffers and presentation protocol

### 8.1 Video capture

- **[DEF]** Stored baseline format: 1280 x 720 x 16 bits, tightly packed;
  921,600 words or 1,843,200 bytes per frame.
- **[PAR]** Stored width, height, stride, and bits per pixel. The controller
  transports words and does not interpret pixels.
- **[DEF]** Frame rate: 60 Hz.
- **[DEF]** Two capture buffer base addresses, aligned to at least 2 KiB and
  separated by at least one complete frame allocation.
- **[REQ]** At a frame tick, the producer chooses an unpublished target buffer.
  Incoming live pixels continue directly to HDMI and are also accumulated in a
  write-side BRAM FIFO.
- **[DEF]** Video write FIFO capacity: 2,048 words (4 KiB).
- **[INV]** FIFO overflow is a capture failure. It must be sticky and prevent
  publication of that frame.
- **[REQ]** The last buffered words must be flushed early enough to complete by
  the publication boundary; waiting solely for the high watermark is illegal.
- **[DEF]** Tail-flush lead: 4,096 SDRAM clocks, 31.508 us at 130 MHz.
- **[PAR]** `TAIL_FLUSH_GUARD_CYCLES`; retain a counter or timestamp based on the
  frame timing generator rather than a software deadline queue.
- **[INV]** Publish only if every word of the frame has completed on DQ, no FIFO
  overflow occurred, and no write error occurred before the frame boundary.
- **[INV]** Publication is a single atomic pointer/epoch update. On failure,
  retain the previously published buffer and expose a failed-capture counter.

### 8.2 Video replay

- **[DEF]** Replay read FIFO capacity: 2,048 words (4 KiB).
- **[DEF]** Refill block and soft video grant: 256 words.
- **[REQ]** A refill request becomes eligible when space exists for the full
  controller transaction. The read response FIFO must reserve that space before
  the first READ command is issued.
- **[INV]** FIFO underflow during active video is a presentation error and shall
  increment a sticky/event counter. The controller cannot repair the current
  output frame after underflow.
- **[REQ]** At replay frame start, the FIFO shall be primed before active pixels
  consume it. The display timing block shall expose active/blanking state and a
  frame/line position sufficient to derive consumption and tail-flush timing.

### 8.3 FIFO watermarks

- **[DEF]** Low watermark: 512 words.
- **[DEF]** High watermark: 1,536 words.
- **[INV]** `0 <= LOW < HIGH <= FIFO_CAPACITY`.
- **[REQ]** Replay urgency asserts when the estimated/actual read FIFO level is
  at or below LOW and remains asserted until level reaches HIGH.
- **[REQ]** Capture urgency asserts when the write FIFO level is at or above
  HIGH and remains asserted until level falls to LOW.
- **[REQ]** Use actual FIFO occupancy in RTL. The simulator reconstructed level
  from deadlines because it did not contain RTL FIFOs; hardware need not do so.
- **[MEAS]** At 130 MHz with a 120 MB/s background stream, LOW/HIGH pairs
  256/1024, 512/1024, 512/1536, and 768/1536 all passed the tested matrix;
  768/1792 failed with -2.069 us worst slack.
- **[REQ]** Do not raise the default high watermark above 1,536 without a new
  full-frame sweep and RTL-level verification.
- **[MEAS]** Increasing FIFO depth from 2,048 to 4,096 or 8,192 words did not
  make the deliberately overloaded 140 MB/s case safe. FIFO depth absorbs
  latency; it does not create bandwidth.

### 8.4 Audio

- **[DEF]** Playback format: 48 kHz, stereo, 16 bits/channel: 96,000 SDRAM words
  per second, 0.192 MB/s.
- **[DEF]** Audio playback FIFO: 512 words.
- **[DEF]** Audio write staging buffer: 256 words.
- **[REQ]** Audio playback and audio-write queues have the highest arbitration
  class because their bandwidth is tiny and underruns are audible.
- **[INV]** Audio playback underflow and audio production overrun shall each
  have separate sticky status and counters.
- **[ASM]** Audio production is delivered in frame-tick-sized epochs and is
  available on demand within the stated staging-buffer contract. Machine-side
  generation latency is not modeled.

## 9. Arbiter policy

Implement a bounded FIFO-watermark arbiter, not general EDF.

### 9.1 Priority classes

At every physical-command boundary, choose the first class that contains a
request able to make legal progress:

1. due refresh preparation or refresh command;
2. audio playback or audio-write request;
3. urgent video request for the current `CAPTURE` or `REPLAY` state;
4. admitted background request;
5. non-urgent maintenance work, if any.

- **[INV]** A blocked higher class must not idle the device when a lower class
  can issue a legal command without violating the higher class's reserved
  resources. This prevents head-of-line deadlock across chips, banks, or DQ
  direction changes.
- **[REQ]** Mandatory presentation requests are examined strictly in channel
  order. The first implementation need only inspect the head request of each
  video/audio channel.
- **[DEF]** Background row-hit lookahead: 8 requests.
- **[PAR]** `BACKGROUND_LOOKAHEAD`, bounded at synthesis. It must not imply an
  associative search over an entire framebuffer backlog.
- **[REQ]** Within the same priority class, prefer an already-open row, then the
  oldest arrival. Equal audio classes may use round-robin to prevent starvation.
- **[REQ]** Re-evaluate urgency and priority after every BL8 transfer. A
  256-word grant is a soft locality target, not 32 uninterruptible bursts.
- **[REQ]** When no mandatory request is urgent, background work may form
  row-local runs. It remains pre-emptible at the next BL8 boundary.
- **[REQ]** Capture tail flush independently forces video urgent when the frame
  boundary is within `TAIL_FLUSH_GUARD_CYCLES`, even when FIFO level has not
  crossed HIGH.

### 9.2 Open-page policy

- **[DEF]** Page policy: open page.
- **[REQ]** Track one open-row value and timing state per bank per chip.
- **[REQ]** Leave a row open after access unless a different row in that bank
  is selected or refresh requires closure.
- **[REQ]** If a candidate misses the open row, issue PRECHARGE only when legal,
  then ACTIVE only after tRP. Do not close a bank containing a visible useful
  row hit merely because another candidate is temporarily blocked.
- **[REQ]** ACTIVATE/PRECHARGE operations may be issued while DQ carries data
  for another bank/chip, provided command and timing constraints permit it.
- **[INV]** Sharing the DQ bus means accesses cannot run in parallel across
  chips; bank/chip interleaving only hides command/setup latency.

### 9.3 Why this policy was selected

- **[MEAS]** The hardware-oriented watermark scheduler sustained the full
  capture/replay/background-direction matrix at 130 MHz through 122 MB/s and
  first failed at 123 MB/s.
- **[MEAS]** The earlier EDF/row-hit model reached higher ideal limits (146
  MB/s safe, 148 MB/s unsafe for 720p16 at 130 MHz) but depended on broader
  deadline ordering and did not represent the desired simple RTL policy.
- **[MEAS]** A 256-word grant roughly halved DQ turnarounds versus 128 words in
  the older simultaneous stress test, with essentially unchanged useful DQ
  utilization, but needed earlier urgency to protect scanout tails.
- **[REQ]** The RTL must match the simple watermark policy before results from
  the more powerful EDF scheduler are used for capacity planning.

## 10. Refresh

- **[INV]** Refresh is tracked independently per chip. Refreshing one chip does
  not make the other chip's banks unavailable, although both still share the
  command and DQ buses.
- **[DEF]** Initial chip-1 refresh phase: half of tREFI after chip 0.
- **[PAR]** Refresh phase offset, constrained to less than tREFI.
- **[REQ]** Before a chip's refresh deadline, legally precharge all four of its
  banks and issue AUTO REFRESH no later than the allowed interval.
- **[INV]** Once a refresh is due, new accesses to that chip are blocked until
  refresh is issued; legal work on the other chip may continue.
- **[REQ]** A refresh-credit/postponement scheme may replace the simple deadline
  counter only if it obeys the datasheet's aggregate refresh rules and is proven
  with assertions. The default implementation uses no speculative refresh
  postponement.
- **[REQ]** Maintain per-chip refresh counters and a late-refresh fault flag.

## 11. Background admission and bandwidth requirements

The theoretical DQ ceiling is 2 bytes per SDRAM clock: 260 MB/s at 130 MHz.
That number excludes command gaps, refresh, row changes, and direction changes.

For the selected 720p16, 60 Hz representation, video traffic is 110.592 MB/s
in either capture or replay. Default audio playback plus write traffic is about
0.384 MB/s. Capture and replay video traffic are mutually exclusive.

- **[MEAS]** Full-frame watermark-scheduler safe/unsafe brackets were:

  | Clock | highest tested safe | first tested unsafe |
  |---:|---:|---:|
  | 100 MHz | 64 MB/s | 65 MB/s |
  | 120 MHz | 100 MB/s | 101 MB/s |
  | 130 MHz | 122 MB/s | 123 MB/s |
  | 143 MHz | 147 MB/s | 148 MB/s |

- **[MEAS]** At 130 MHz and 122 MB/s, worst tested video deadline slack was
  only 1.392 us. At 120 MB/s with the default band it was 1.592 us.
- **[INV]** These are simulator characterization points, not production
  guarantees. They assume ideal request availability, the modeled timing,
  correct active/blanking phasing, and no unmodeled CDC or PHY latency.
- **[DEF]** Initial production background admission cap at 130 MHz: 100 MB/s.
  This is an engineering default chosen below the measured knee, not a claim
  that 100 MB/s is safe before RTL and board validation.
- **[PAR]** `BACKGROUND_RATE_LIMIT`; it shall be implemented with a token bucket
  or equivalent paced admission mechanism rather than an unlimited backlog.
- **[REQ]** Rate-limit accounting uses DQ payload bytes admitted, not request
  headers or observed average completion bandwidth.
- **[REQ]** Background traffic shall be disabled automatically after any video
  underflow, capture overflow/deadline failure, audio fault, or late refresh,
  until software explicitly clears/re-enables it.
- **[REQ]** Provide separate limits for background reads and writes if later
  board measurements reveal asymmetric turnaround costs.
- **[REQ]** At clocks other than 130 MHz, do not scale the 100 MB/s default
  linearly. Use a characterized table; initial conservative caps are 50 MB/s at
  100 MHz, 80 MB/s at 120 MHz, 100 MB/s at 130 MHz, and zero by default at
  exploratory 143 MHz until that clock is explicitly enabled and qualified.

## 12. Higher-resolution modes

- **[MEAS]** With no residual traffic, all six mappings met modeled deadlines
  for 720p16 and tightly packed 1080p8 at 100, 120, 130, and 143 MHz.
- **[MEAS]** Native 1080p16 was unsafe at 100 and 120 MHz and completed at 130
  and 143 MHz only with no residual traffic.
- **[MEAS]** Under the more capable EDF/row-hit scheduler at 130 MHz, residual
  safe/unsafe brackets were 146/148 MB/s for 720p16, 130/135 MB/s for 1080p8,
  and only 8/10 MB/s for 1080p16.
- **[REQ]** 1080p16 is not a guaranteed mode of the first watermark-arbiter
  implementation. It may be exposed as experimental with background disabled.
- **[REQ]** 1080p8 requires a new full-frame watermark sweep and hardware test
  before being declared supported, despite its promising zero-background and
  EDF results.
- **[ASM]** A crisp 1080p overlay can be generated downstream or combined with
  a lower-bandwidth stored base image. Scaling, overlay composition, and any
  three-source-line/two-output-line buffering are outside this controller.
- **[ASM]** Lossless compression is an emergency architectural option only;
  no bandwidth guarantee may rely on it in this version.

## 13. Status, counters, and observability

The implementation shall expose enough information to reproduce the reasoning
performed with the simulator:

- **[REQ]** current presentation state and published/capture buffer indices;
- **[REQ]** actual FIFO levels, low/high crossings, urgent state, and minimum/
  maximum observed level for each FIFO;
- **[REQ]** accepted/completed words and maximum service gap per client;
- **[REQ]** video capture success/failure, replay underflow, audio underflow,
  audio overflow, and background throttling counters;
- **[REQ]** DQ read words, write words, idle clocks, and direction changes;
- **[REQ]** READ, WRITE, ACTIVE, PRECHARGE, and REFRESH command counts;
- **[REQ]** row-hit/row-conflict counts per chip and bank;
- **[REQ]** refresh count and late-refresh fault per chip;
- **[REQ]** maximum accepted-to-first-command and accepted-to-completion latency
  per client, using saturating counters;
- **[REQ]** sticky first-fault capture containing cycle/frame position, client,
  FIFO level, selected chip/bank, and fault reason where practical.

Counters may be optional synthesis features, but fault flags, FIFO extrema,
frame publication status, and refresh-late detection are mandatory for bring-up.

## 14. Recommended RTL decomposition

The implementation should keep the same conceptual boundaries as the model:

1. `sdram_init_refresh` — initialization, per-chip refresh deadlines, and CKE.
2. `sdram_addr_decode` — selected mapping only; no arbitration state.
3. `sdram_bank_state` — eight bank records with open row and timing timestamps.
4. `sdram_request_splitter` — controller transactions to BL8/row-bounded ops.
5. `presentation_arbiter` — audio priority, watermark hysteresis, tail flush,
   background token admission, and bounded row-hit selection.
6. `sdram_command_engine` — legal ACT/PRE/READ/WRITE/REF command issue.
7. `sdram_dq_phy` — DQ direction, output enable, DQM, capture at CAS latency,
   and board timing constraints.
8. `frame_publish` — capture epoch, completeness/error tracking, and atomic
   published-buffer swap.
9. client CDC FIFOs and instrumentation.

- **[INV]** The arbiter proposes operations; the command engine remains the
  final authority on legality.
- **[INV]** Address decoding, scheduling, and timing enforcement must remain
  separable so each can be independently verified.

## 15. Assertions and verification plan

### 15.1 Unit/formal properties

At minimum assert:

- no two commands occupy one command edge;
- never drive and sample DQ simultaneously;
- DQ ownership is unique for every burst clock;
- all ACT/PRE/READ/WRITE/REFRESH timing inequalities hold;
- no refresh interval is exceeded;
- decoded chip/bank/row/column are in range and mapping is non-aliasing over
  representative boundaries plus exhaustive reduced-width configurations;
- request word accounting is exact across BL8 and row splits;
- per-channel completion ordering holds;
- response FIFO capacity was reserved before READ;
- complete write data was buffered before WRITE;
- watermark urgent state has correct hysteresis;
- background cannot issue ahead of audio or urgent video when those can make
  legal progress;
- a partial/failed frame cannot update the published pointer;
- capture and replay video transactions are mutually exclusive outside an
  explicit verification-only stress mode.

### 15.2 Simulation acceptance

- **[REQ]** Reuse the Python model's address and command traces as a reference
  oracle for directed cases, not as a cycle-identical arbiter oracle where RTL
  pipelining differs.
- **[REQ]** Run complete-frame tests over capture/replay, background read/write,
  refresh phases of 0, quarter, half, and three-quarter tREFI, and boundary
  addresses/row transitions.
- **[REQ]** Sweep producer/display phase, not only aligned frame ticks.
- **[REQ]** Inject downstream stalls permitted by each interface contract.
- **[REQ]** Verify at 100, 120, and 130 MHz timing configurations. Treat 143 MHz
  as an opt-in overclock test with explicit labelling.
- **[REQ]** First RTL acceptance target at 130 MHz: 720p16 capture and replay,
  audio read/write, and separately paced 100 MB/s background read or write,
  for at least 1,000 frames per phase combination with zero mandatory deadline,
  FIFO, refresh, or publication faults.
- **[REQ]** Then locate the RTL safe/unsafe boundary in 1 MB/s increments from
  100 through 125 MB/s and compare it with the model's 122/123 MB/s bracket.
  A lower RTL boundary is a result to investigate, not permission to relax a
  deadline.

### 15.3 Hardware acceptance

- **[REQ]** Run the board's existing memory test at 130 MHz before controller
  bandwidth qualification.
- **[REQ]** Exercise worst-case data patterns, both DQ directions, temperature
  range available in the lab, and long-duration video/audio playback.
- **[REQ]** Begin with background disabled, then 50, 75, and 100 MB/s. Do not
  enable a higher production cap until counters show zero faults with margin.
- **[REQ]** Measure FIFO extrema and service gaps on hardware; compare them with
  RTL simulation and the Python sweep rather than relying only on visible HDMI
  correctness.

## 16. Definition of done for the first controller

The first implementation is complete when all of the following are true:

- the controller initializes both chips and refreshes each independently;
- the default mapping and BL8 transaction splitter pass assertions;
- 720p16 live capture publishes complete frames atomically;
- replay can repeat the last published frame without video FIFO underflow;
- audio playback/write meet their buffer contracts in both video states;
- the watermark arbiter implements the exact priority, hysteresis, and
  BL8-pre-emption rules above;
- background admission is paced and cannot compromise mandatory traffic;
- full-frame RTL acceptance passes at 130 MHz and 100 MB/s background in both
  directions;
- instrumentation makes every missed deadline, FIFO error, publication failure,
  or refresh fault diagnosable;
- hardware tests validate the chosen clock and initial production rate limit.

## 17. Parameters and defaults summary

| Parameter | Default | Classification/notes |
|---|---:|---|
| SDRAM frequency | 130 MHz | **[PAR][DEF]**, board acceptance boundary |
| CAS latency | 3 | **[PAR][DEF]** |
| physical burst | 8 words | **[PAR][DEF]**, supported 1/2/4/8 |
| mapping | stripe-1k-bank-chip | **[PAR][DEF]** |
| page policy | open | **[PAR][DEF]** |
| DQ turnaround | 1 clock | **[PAR][DEF][ASM]** |
| video format | 1280x720x16 | **[PAR][DEF]** |
| video/frame rate | 60 Hz | **[PAR][DEF]** |
| active fraction for 1080p timing | 0.8378181818 | **[PAR][DEF][ASM]** |
| video FIFO | 2,048 words | **[PAR][DEF]** per direction/use |
| video low/high | 512/1,536 words | **[PAR][DEF]** |
| video request/grant | 256 words | **[PAR][DEF]**, soft grant |
| tail-flush guard | 4,096 clocks | **[PAR][DEF]**, 31.508 us at 130 MHz |
| audio format | 48 kHz, 2 x 16-bit | **[PAR][DEF]** |
| audio playback FIFO | 512 words | **[PAR][DEF]** |
| audio write buffer | 256 words | **[PAR][DEF]** |
| audio grant | 8 words | **[PAR][DEF]** |
| background lookahead | 8 requests | **[PAR][DEF]**, bounded |
| refresh phase | tREFI/2 | **[PAR][DEF]** for chip 1 |
| 130 MHz background cap | 100 MB/s | **[PAR][DEF]**, provisional |

## 18. Open assumptions requiring an explicit future decision

These are deliberately not hidden in defaults:

1. **[ASM]** The FPGA pin timing and SDRAM PHY can close reliably at 130 MHz on
   every target board. The project acceptance rule supports trying this; it does
   not replace timing analysis and hardware test.
2. **[ASM]** One turnaround clock is sufficient in both directions.
3. **[ASM]** The display and producer timing blocks provide accurate frame,
   active-video, and FIFO-level information in the SDRAM domain.
4. **[ASM]** Machine production can honor the 2,048-word video staging contract
   and 256-word audio staging contract. Its latency was intentionally excluded
   from the model.
5. **[ASM]** The initial buffer bases do not overlap audio or background regions;
   final linker/register-map ownership is still required.
6. **[ASM]** A 100 MB/s background cap leaves sufficient unmodeled margin. Only
   RTL and board qualification can turn this into a supported guarantee.
7. **[ASM]** Refresh staggering is beneficial on the physical board and does
   not introduce an initialization or retention issue.
8. **[ASM]** The selected 1 KiB bank→chip ordering remains appropriate once
   real producer strides, overlays, and any scaler traffic are known.

Any change to an assumption that affects timing, traffic shape, or address
placement requires rerunning the complete-frame sweep and the corresponding RTL
acceptance matrix. Measurements should update this document by changing the
classification from **[ASM]** to a sourced fact or qualified requirement, not
by silently altering a default.
