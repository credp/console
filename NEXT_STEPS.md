# SDRAM Audio and Video Next Steps

The immediate goal is to prove the external SDRAM interface in small,
diagnosable stages, then build enough audio and video machinery to run a
roughly 440 Hz triangle wave while a bouncing Ainsley Harriott image is shown
on HDMI. Each stage should leave behind a reusable diagnostic mode and should
have an explicit pass condition before more variables are introduced.

This document is a sequencing and verification plan. It does not redefine the
architecture. The authoritative design requirements are:

- [`tools/sdram-model/IMPLEMENTATION_SPEC.md`](tools/sdram-model/IMPLEMENTATION_SPEC.md)
  for the presentation-memory controller, including hardware topology, timing,
  client interfaces, arbitration, refresh, observability, and acceptance;
- [`dot/FPGA_BRINGUP.md`](dot/FPGA_BRINGUP.md) for machine video, HDMI
  presentation, audio format, buffering, and clock-domain architecture;
- [`rtl/scanout-sdram-controller/README.md`](rtl/scanout-sdram-controller/README.md)
  for the current RTL implementation boundary and remaining integration work.

If this plan conflicts with either architecture document, the architecture
document takes precedence and this plan should be corrected.

The current controller RTL is a foundation rather than a complete controller.
Experiment 004 checks that the sources fit into the MiSTer project structure,
but it does not instantiate the controller or drive SDRAM. Experiment 005 is
the first hardware test: it performs a conservative BL1 write and read test at
20 MHz across both chip selects, all four banks, and multiple rows.

Keep three video concepts distinct throughout this work:

- the 1280 by 720 capture/replay workload used to validate the presentation
  controller;
- the machine's eventual source-plane representation, whose dimensions,
  format, and plane organization are not yet settled;
- the fixed 1920 by 1080 HDMI scanout raster.

The 640 by 360 source-plane design in `FPGA_BRINGUP.md` remains a useful current
proposal, not a decision made by this sequencing plan. Once the source-plane
contract is settled, update that architecture document and the client tests
together. Do not infer the source format from either the 720p controller stress
workload or the 1080p output timing.

## 1. Establish the experiment 005 baseline

Build and run experiment 005 on the target SDRAM board before branching the
work.

Pass criteria:

- `LED_USER` remains off while the test is running and becomes solid after it
  completes.
- Repeated resets and power cycles pass consistently.
- Failure indication is confirmed with a compile-time injected compare/data
  fault. Do not create the negative test by violating SDRAM electrical timing.
- The exact board revision, FPGA build, and SDRAM module are recorded with the
  result.

A pass establishes basic pin assignment, signal polarity, clock delivery,
initialization, bidirectional DQ operation, and low-speed reads and writes. It
does not establish production clock margin, BL8 behavior, sustained bandwidth,
or operation of the presentation controller.

Use the initialization requirements in
[`IMPLEMENTATION_SPEC.md` section 4](tools/sdram-model/IMPLEMENTATION_SPEC.md#4-clock-reset-and-sdram-initialization)
and the board facts in
[`IMPLEMENTATION_SPEC.md` section 3](tools/sdram-model/IMPLEMENTATION_SPEC.md#3-hardware-facts-and-explicitly-resolved-discrepancies)
when judging what the BIST does and does not prove.

Tag or otherwise preserve the passing revision. Use it as the common baseline
for two independent experimental branches.

## 2. Characterize the SDRAM clock and PHY

Create a clock-speed experiment that keeps the simple BIST and its access
pattern stable. Only clocking, capture phase, and timing parameters should
change on this branch.

Keep complementary physical chip-select polarity in one explicit board adapter.
The controller and BIST should use a logical chip number; they should not spread
the board's unusual `nCS` convention through scheduling or timing logic.

Suggested progression:

1. Confirm the baseline at 20 MHz.
2. Add error counters and a continuous test mode so failures are visible over
   many passes rather than a single 256-word sweep.
3. Expand the patterns to include all zeroes, all ones, alternating bits,
   walking bits, address-derived data, and pseudorandom data.
4. Expand the address coverage to exercise column, row, bank, and chip
   transitions deliberately.
5. Test supported frequencies incrementally, including 100, 120, and 130 MHz.
   Treat 143 MHz as exploratory overclocking, not a rated operating point.
6. At each frequency, characterize the valid read-capture phase or sampling
   window and choose a setting with margin rather than merely finding one
   passing point.
7. Run long tests after warm-up and across repeated cold starts.

For each frequency, sweep the available capture-phase settings in both
directions, record the complete contiguous passing window, and select a point
near its centre. Record the distance from the selected point to each observed
failing edge. A production setting must retain at least one characterized
passing setting on either side; if the available phase resolution or window
does not permit that, record the limitation and do not describe the result as
having useful margin.

Frequency choices, CAS restrictions, ceiling and floor conversions, and the
status of 143 MHz are defined in
[`IMPLEMENTATION_SPEC.md` sections 3 through 5](tools/sdram-model/IMPLEMENTATION_SPEC.md#3-hardware-facts-and-explicitly-resolved-discrepancies).
Do not copy those values into a second independent timing definition.

Pass criteria for the production clock are zero detected data errors over the
chosen soak interval, repeatable initialization, and a documented sampling
window with useful margin. A single successful short sweep is insufficient.

## 3. Prove the SDRAM data path

Create a separate data-path experiment that initially retains the proven
20 MHz clock. This branch should introduce the production transfer machinery
without simultaneously changing the PHY operating point.

Add and verify the following in order:

1. BL8 mode-register setup and complete eight-word write and read bursts.
2. Burst packing and unpacking, including word ordering.
3. Both byte-mask bits and partial-word writes.
4. Address decoding for every supported mapping, with the selected
   `stripe-1k-bank-chip` mapping as the hardware default.
5. Request splitting at BL8 wrap, chip, bank, and physical row boundaries.
6. Open-row tracking and enforcement of tRCD, tRP, tRAS, tRC, tRRD, tWR,
   tRFC, CAS latency, and DQ turnaround.
7. Back-to-back reads, back-to-back writes, and read-to-write and write-to-read
   bus turnaround.
8. Refresh during sustained traffic, including deliberately stressful cases
   near the refresh deadline.
9. Request, write-data, and read-response FIFOs with backpressure.
10. Tagged completion and exact committed-word accounting.

Choose the reusable hardware diagnostic path before implementing the bank and
timing engine in step 6, so timing-engine failures can report useful evidence
during development. SignalTap, an HPS-readable status register block, an OSD
page, or a slow debug UART are all acceptable. First-failure capture and
saturating counters belong in reusable RTL; an experiment should only select
how they are exposed.

Keep arbitration policy, bank eligibility, and command legality explicit and
separate. The arbiter proposes a client operation. A bank-state eligibility
stage determines which proposed operations can currently make progress and
exposes row-hit and age information. The command engine remains the final
authority on whether ACTIVATE, PRECHARGE, READ, WRITE, or REFRESH is legal on a
given edge. A high-priority operation that is temporarily illegal must not
prevent an independent lower-priority operation from using another chip or
bank when doing so preserves all reserved resources and deadlines.

The required address mapping and split rules are specified in
[`IMPLEMENTATION_SPEC.md` section 6](tools/sdram-model/IMPLEMENTATION_SPEC.md#6-address-space-and-selected-mapping),
and the client handshake, buffering, and completion semantics are specified in
[`IMPLEMENTATION_SPEC.md` sections 7 and 8](tools/sdram-model/IMPLEMENTATION_SPEC.md#7-client-request-interface).
Command timing and turnaround requirements remain those in
[`IMPLEMENTATION_SPEC.md` section 5](tools/sdram-model/IMPLEMENTATION_SPEC.md#5-central-timing-configuration).

Use directed simulation and assertions for protocol and boundary cases, then
run the same operations on hardware. The hardware test should report the first
failing address, expected and observed data, operation type, and relevant
controller state instead of exposing only a pass or fail LED.

Pass criteria are correct BL8 transfers across every boundary, no FIFO loss or
duplication under backpressure, no refresh deadline violation, and sustained
error-free hardware operation at the conservative clock.

All supported address mappings must pass the decoder, splitter, and reduced-
configuration formal/simulation tests. Hardware qualification may concentrate
on the selected `stripe-1k-bank-chip` mapping; exercise other mappings on
hardware only when they remain selectable in the target build or are needed to
diagnose a mapping-dependent failure.

Formal verification is a phase exit condition, not an optional supplement. At
minimum, prove that every issued command satisfies the applicable timing rules;
accepted requests expand into exact, ordered physical operations; response and
write-data capacity is reserved before issuing a burst; no operation crosses an
illegal mapping or burst boundary; refresh commands meet their actual deadlines;
and DQ ownership remains exclusive through every read/write turnaround.
Pin-level simulation must additionally assert that the FPGA and SDRAM model
never drive DQ simultaneously and that DQ is neither unknown nor high impedance
when valid read data is sampled.

## 4. Integrate the proven clock and data path

Merge the characterized PHY settings and the proven data path into a new
integration experiment. Do not assume that two independently passing branches
will automatically pass together.

Repeat the long memory test at the selected production clock. Measure useful
read bandwidth, write bandwidth, mixed-traffic bandwidth, and refresh overhead.
Record underruns, overruns, corrected stalls, late refreshes, and data errors in
counters that remain accessible during later experiments.

The integrated controller is ready for clients only when it can sustain the
required traffic with margin and its failure counters remain at zero.

Use 1280 by 720 by 16-bit capture and replay here as the controller's synthetic
acceptance workload. Passing it establishes the specified controller envelope;
it does not select the machine source-plane format and does not imply storage of
a 1080p framebuffer.

Use the priority policy in
[`IMPLEMENTATION_SPEC.md` section 9](tools/sdram-model/IMPLEMENTATION_SPEC.md#9-arbiter-policy),
the refresh rules in
[`IMPLEMENTATION_SPEC.md` section 10](tools/sdram-model/IMPLEMENTATION_SPEC.md#10-refresh),
and the bandwidth requirements in
[`IMPLEMENTATION_SPEC.md` section 11](tools/sdram-model/IMPLEMENTATION_SPEC.md#11-background-admission-and-bandwidth-requirements)
as the integration acceptance basis. The full controller definition of done is
in [`IMPLEMENTATION_SPEC.md` section 16](tools/sdram-model/IMPLEMENTATION_SPEC.md#16-definition-of-done-for-the-first-controller).

## 5. Build known-good generators without SDRAM

Before routing media through memory, prove both ends of each path directly.
This work has no dependency on the SDRAM controller and may proceed in parallel
with phases 2 through 4. Attaching the generators to SDRAM must wait for the
integrated controller and CDC gates.

### Audio generator

Implement a phase-accumulator triangle-wave generator with an explicit sample
enable. The initial output should be signed 16-bit PCM at 48 kHz, duplicated to
left and right channels, at approximately 440 Hz. Use a phase accumulator so
the frequency does not depend on an integer number of system clocks per wave
cycle.

Connect it directly to the existing audio output path first. Confirm stable
pitch, correct sample rate, sensible amplitude, digital silence during reset,
and no clicks when enabling or disabling the generator.

The machine-facing sample representation and rate come from
[`FPGA_BRINGUP.md` Audio architecture](dot/FPGA_BRINGUP.md#audio-architecture).
The logical clock relationships are in
[`FPGA_BRINGUP.md` Clock model](dot/FPGA_BRINGUP.md#clock-model).

### Pixel generator

Implement a deterministic, parameterized logical-pixel generator. Begin with
color bars or a coordinate pattern, then add a sprite ROM and bouncing position
state. Clip the sprite at image boundaries and make the background visually
sensitive to dropped, repeated, or reordered pixels. A 640 by 360 configuration
may be retained as a diagnostic candidate, but the generator must not make that
the implicit machine source-plane contract.

Connect the generated pixels directly to a display path first. This provides a
known-good reference that does not depend on SDRAM.

Treat the current pixel format, plane ordering, and 640 by 360 proposal in
[`FPGA_BRINGUP.md` Video architecture](dot/FPGA_BRINGUP.md#video-architecture)
as inputs to the pending source-plane decision. Keep those parameters isolated
so this diagnostic remains useful if that contract changes.

## 6. Prove clock-domain crossings

Before attaching media clients, identify the source generator, audio cadence,
SDRAM, and HDMI clock domains and implement an explicit crossing for every
signal that moves between them. Bulk streams should normally use asynchronous
FIFOs; isolated controls may use a proven request/acknowledge or toggle
handshake.

Required verification includes:

- FIFO ordering and exact conservation with unrelated clocks and drifting phase;
- safe full/empty generation and reset release in either domain order;
- no unsynchronized multi-bit occupancy level entering the SDRAM arbiter;
- atomic transfer of frame pointers, epochs, and related control state;
- deterministic invalidation of unpublished work after either relevant reset.

Define the SDRAM-domain FIFO-status contract before connecting it to the
arbiter. Arbitration may use occupancy calculated locally from safely
synchronized Gray-code pointers, or conservative threshold flags generated by
a proven asynchronous FIFO. It must not use a multi-bit level passed directly
from another clock domain. Whichever representation is selected must preserve
the low/high-watermark hysteresis and provide conservative capacity reservation
for a complete read response or write burst.

Use formal proofs for the FIFO and handshake invariants and simulation with
non-harmonically-related clocks. This phase passes only when no functional
assumption depends on clocks retaining a convenient phase relationship.

## 7. Add memory sinks and replay clients

Treat audio and video as separate SDRAM clients with independent diagnostics.

### Audio path

Add an audio capture FIFO, a memory writer, a ring-buffer address generator, a
memory reader, and an audio replay FIFO. Preserve the 48 kHz output cadence
regardless of SDRAM scheduling. Define explicit overrun and underrun behavior;
an underrun should produce digital silence and increment a counter.

First write and replay the generated triangle wave through SDRAM. Listen for
clicks or pitch changes and verify counters over a long run. Then run audio
while hostile background memory traffic is active.

Use the canonical PCM format and initial ring-buffer sizing from
[`FPGA_BRINGUP.md` Audio architecture](dot/FPGA_BRINGUP.md#audio-architecture).
The controller-side audio FIFOs, transfer size, and service requirements are in
[`IMPLEMENTATION_SPEC.md` section 8.4](tools/sdram-model/IMPLEMENTATION_SPEC.md#84-audio).

### Video path

Add a video capture FIFO, burst writer, framebuffer address generator, burst
reader, and replay FIFO or line buffers. Carry frame and line boundaries
explicitly rather than reconstructing them from an unchecked word count.

This phase proves a parameterized video transport client and its SDRAM-facing
buffering, addressing, completion, and replay behavior using diagnostic test
geometry. It does not yet define the machine's source-plane ownership protocol
or select the final source-plane format; those are phase 8 entry decisions.

First capture and replay a static coordinate pattern using an explicitly chosen
test geometry. Then use the bouncing sprite generator. Verify stride, word
order, boundary splitting, and complete frame accounting before enabling buffer
publication. Keep this client parameterized until the real source-plane
contract is settled; do not silently substitute the 720p acceptance workload.

Video capture, replay, and FIFO-watermark behavior are specified in
[`IMPLEMENTATION_SPEC.md` sections 8.1 through 8.3](tools/sdram-model/IMPLEMENTATION_SPEC.md#81-video-capture).

## 8. Build machine display scanout

The machine display domain should generate the selected logical source raster
and the content of the next machine frame. It owns logical coordinates, line
and frame boundaries, sprite movement, and completion of the inactive dynamic
surface. Selecting the source-plane dimensions, format, organization, and
ownership contract is an explicit entry gate for this phase.

Unlike the transport proof in phase 7, this phase binds that generic client to
the chosen machine-facing surface contract. It defines which subsystem owns
each active or inactive surface, when ownership transfers, and how publication
and acknowledgement release the previous surface.

Implement:

- logical raster timing and pixel-valid signaling;
- the background and sprite compositor;
- double-buffer ownership for the generated dynamic surface;
- line-boundary register publication where raster-time changes are needed;
- exact committed-word counting before a frame is declared complete;
- a frame-ready request and acknowledgement handshake;
- counters for generated, published, repeated, and dropped frames.

A partial frame must never be made visible to presentation. If generation is
late, the machine may defer publication rather than corrupting the active
frame.

Surface ownership, logical-line register publication, and the distinction
between generation and presentation are defined in
[`FPGA_BRINGUP.md` Video architecture](dot/FPGA_BRINGUP.md#video-architecture).
The controller's exact commit and atomic publication requirements are defined
in [`IMPLEMENTATION_SPEC.md` section 8.1](tools/sdram-model/IMPLEMENTATION_SPEC.md#81-video-capture).

## 9. Build HDMI scanout

The HDMI side should run continuously at 1920 by 1080 and must not wait for the
machine. Its fetch, composition, line-buffer, and scaling design must consume
the source-plane contract selected in phase 8. If 640 by 360 is selected, the
current proposal of two 640-pixel ping-pong buffers and exact 3x replication is
preferred; otherwise re-derive buffer sizes and per-line deadlines before RTL
implementation.

Implement and verify:

- stable HDMI timing with a locally generated test image;
- line-buffer fill and replay with explicit readiness checks;
- reads from immutable, published source surfaces;
- atomic adoption of new surface pointers at an HDMI frame boundary;
- repeat-last-frame behavior when no new machine frame is ready;
- a visible diagnostic pattern and counter for line-buffer underrun;
- stable output during reset and controller reinitialization.

Prove the line-fetch deadline with worst-case concurrent audio, refresh, and
allowed background traffic. Average bandwidth alone is not sufficient.

Frame adoption and repeat-last-frame behavior must follow
[`FPGA_BRINGUP.md` Non-blocking presentation](dot/FPGA_BRINGUP.md#non-blocking-presentation).
Controller replay entry, refill, and underflow behavior must follow
[`IMPLEMENTATION_SPEC.md` section 8.2](tools/sdram-model/IMPLEMENTATION_SPEC.md#82-video-replay).

## 10. Run the combined demonstration

The demonstration is an integration milestone and diagnostic aid, not a
substitute for the quantitative simulation, formal, bandwidth, margin, and soak
criteria in the preceding phases.

The first useful end-to-end demonstration should contain:

- a roughly 440 Hz stereo triangle wave generated continuously and replayed
  through SDRAM;
- a bouncing Ainsley Harriott sprite generated into an inactive source surface;
- atomic frame publication;
- continuous 1080p HDMI scanout from the last published source state;
- refresh active throughout;
- live error, FIFO-watermark, repeated-frame, and underrun counters.

The counter set should implement the required observability in
[`IMPLEMENTATION_SPEC.md` section 13](tools/sdram-model/IMPLEMENTATION_SPEC.md#13-status-counters-and-observability),
not a new demo-specific status scheme.

Run increasingly hostile background traffic and confirm that mandatory audio
and video service retains priority. A successful demo has stable pitch with no
clicks, no visible tearing or corruption, continuous HDMI sync, repeatable
reset recovery, and zero unexplained memory or FIFO errors during a long run.

## 11. Preserve diagnostics and evidence

Do not discard the small experiments after integration. Keep the low-speed
BIST, clock-margin test, BL8 data-path test, direct audio generator, direct
video generator, and combined soak test buildable as regression targets.

For each hardware milestone, record:

- source revision and bitstream identifier;
- FPGA and SDRAM board revisions;
- PLL frequency and phase settings;
- test duration and pattern coverage;
- pass and error counts;
- known limitations and untested assumptions.

This evidence separates a feature that worked once from a controller whose
operating envelope is understood.

Formal, simulation, and hardware evidence should ultimately satisfy
[`IMPLEMENTATION_SPEC.md` section 15](tools/sdram-model/IMPLEMENTATION_SPEC.md#15-assertions-and-verification-plan),
especially its hardware acceptance criteria, rather than being judged only by
the visual demonstration.
