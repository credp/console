# Codex handoff: SDRAM controller progress

Updated 2026-09-12 after the single-client transaction-adapter milestone.

## Read this first

The repository is healthy. The current Codex session was given a sandbox that
mounts `.git` read-only, so it could edit project files but could not create
`.git/index.lock`, commit, or push. This is a session-permission problem, not
repository corruption.

At the time of writing:

- branch `main` and `origin/main` both point to `804b031` (`Add bounded runtime
  refresh scheduling`);
- the seven paths listed below contain intentional, tested, **uncommitted**
  work;
- no generated simulation or formal result directories remain;
- there was no stale Git lock and file ownership was correct;
- the configured remote is named `origin` (not `upstream`).

Do not discard or recreate the working tree. In a session with writable Git
metadata, review and commit these paths:

```text
rtl/scanout-sdram-controller/Makefile
rtl/scanout-sdram-controller/README.md
rtl/scanout-sdram-controller/files.qip
rtl/scanout-sdram-controller/formal/single_client_adapter.sby
rtl/scanout-sdram-controller/formal/single_client_adapter_formal.sv
rtl/scanout-sdram-controller/rtl/sdram_single_client_adapter.sv
rtl/scanout-sdram-controller/tb/tb_single_client_adapter.sv
```

Suggested commit:

```bash
git add rtl/scanout-sdram-controller
git commit -m "Add single-client SDRAM transaction adapter"
git push origin main
```

This handoff file will itself also be uncommitted, so add it separately if it
is to become permanent project history.

## What has been built

The controller has grown bottom-up in deliberately reviewable layers:

```text
architecture request stream
        |
sdram_single_client_adapter       NEW, not yet committed
        |
atomic BL8 operation interface
        |
sdram_runtime_core                committed in 804b031
        |-- refresh deadline generator
        `-- sdram_open_row_core
              |-- open-row scheduler and timing tracker
              |-- DQ turnaround guard
              `-- bounded BL8 physical engine
                         |
                    SDRAM pins/model
```

The important separation is that the top layer speaks in useful words and
requests, while the lower layers speak in indivisible eight-word SDRAM bursts
and legal SDRAM commands.

### Existing committed runtime machinery

The committed RTL provides:

- all six address mappings, with `stripe-1k-bank-chip` as the default;
- splitting at BL8 wrap, chip, bank, and physical-row boundaries;
- per-bank open-row tracking and command qualification for tRCD, tRP, tRAS,
  tRC, tRRD, tWR, and tRFC;
- explicit DQ read/write turnaround exclusion;
- fixed-duration physical BL8 writes and reads that cannot be stretched by
  client backpressure;
- runtime refresh scheduling for both SDRAM chips, including early requests,
  staggered deadlines, and sticky late flags;
- a response holder that decouples physical completion from client completion
  backpressure;
- the earlier FIFO, arbitration, frame-publication, initialization, and BIST
  foundation described in `rtl/scanout-sdram-controller/README.md`.

Recent committed history, newest first:

```text
804b031 Add bounded runtime refresh scheduling
2166528 Integrate open-row scheduler with BL8 PHY
8f62a37 Add bounded BL8 physical engine
a93eff8 Enforce SDRAM DQ direction turnaround
326fe3c Add legal runtime refresh command arbitration
ee337fa Add open-row SDRAM command scheduler
e6a2958 Complete experiment 006.b end-to-end verification
0f3bb1f Updated to end-to-end testing, separated out BL8 engine from splitter, new client arch.
```

### New uncommitted transaction adapter

`sdram_single_client_adapter.sv` is the first directly usable
architecture-facing request interface. It accepts:

- read or write direction;
- a 27-bit byte address;
- a word count;
- a request tag;
- streamed 16-bit write data with two byte-enable bits;
- backpressured streamed 16-bit read data.

It does the following:

1. Validates that the request is non-empty, within configured capacity, and
   16-bit aligned.
2. Buffers a complete write request before touching SDRAM. This prevents a
   starved client stream from interrupting an already-started physical burst.
3. Uses the common mapping-aware splitter to produce operations of at most
   eight useful words without crossing an illegal physical boundary.
4. Packs useful write words into a 128-bit BL8 payload. Unused burst beats have
   their DQM byte enables cleared, so those SDRAM bytes are masked rather than
   modified.
5. Accepts a complete atomic 128-bit read response and serializes only the
   useful words. Client `read_ready` may stall without changing the duration
   of the physical SDRAM read.
6. Returns exactly one stable completion for the whole architecture request,
   preserving the tag and reporting the exact successful word count.
7. Rejects an invalid request locally with `completion_error=1` and
   `completion_words=0`; no SDRAM operation is issued.

Only one architecture request can be outstanding. That is intentional for
this milestone: it validates request semantics before adding arbitration and
several queues.

## Verification completed for the uncommitted work

The following all passed immediately before this document was written:

- `make test` in `rtl/scanout-sdram-controller`;
- `make lint`;
- a dedicated Verilator lint run with `sdram_single_client_adapter` as the top;
- `make formal`, comprising 15 passing SymbiYosys tasks;
- the adapter's dedicated 40-cycle bounded assertion task and 60-cycle cover
  task.

The new pin-level test connects the adapter to `sdram_runtime_core` and the
two-chip SDRAM model. It writes and reads 12 words beginning at byte address
2032. That address deliberately forces the request into two physical
operations across a selected-mapping boundary. The test checks:

- exact word ordering on the round trip;
- exactly two physical operations per 12-word transaction;
- arbitrary read-response backpressure;
- stable tags and exact 12-word completion accounting;
- invalid odd-address rejection with no extra physical operation;
- no late-refresh or command-timing diagnostic failure.

Its final result is:

```text
PASS single-client adapter: split, pack, stall, order, accounting, rejection
```

Icarus printed its existing warnings about modules without explicit timescales
and incomplete constant-select sensitivity handling. These were warnings, not
test failures. The dedicated Verilator adapter lint was clean.

The formal adapter environment models a bounded atomic-operation peer and
holds read response data stable until consumed. It checks request/tag ownership,
direction, stalled read stability, stalled completion stability, and successful
word accounting. Its task called `prove` currently uses bounded model checking
to depth 40; do not describe that particular result as an unbounded inductive
proof.

## Where this sits in the roadmap

The project is near the end of `NEXT_STEPS.md` section 3, “Prove the SDRAM data
path”, at the reusable RTL/simulation level.

Substantial pieces of section 3 now exist: BL8 transfers, packing, DQM masks,
address mapping, boundary splitting, open-row timing, turnaround, runtime
refresh, and tagged exact completions. The important remaining distinction is
between components that exist independently and a complete multi-client system:

- FIFO primitives and policy logic exist, but the new transaction path is not
  yet connected to per-client request/data/response queues.
- The single-client adapter proves one request at a time; it is not the final
  multi-client admission and arbitration layer.
- The reusable runtime core is intentionally not wired into the
  hardware-qualified experiment 006.b yet.
- Initialization sequencing and the proven board-specific DQ input-register /
  capture-clock PHY remain outside this new runtime composition.
- Reusable first-failure capture and software-visible diagnostic counters are
  still needed before complex hardware bring-up.
- No full-frame bandwidth or 122 MB/s acceptance claim has been established.

Experiments 006.a and 006.b were reported passing on the current hardware work.
006.a established the clock/timing investigation. 006.b established pin-level
BL8 data-path behavior and has moved considerably beyond the original simple
BIST. Preserve those experiments as evidence; do not replace their working
engine with the new runtime core until the next integration experiment can be
compared against them.

## Recommended next step

First commit the tested adapter milestone unchanged. Then add a small composed
single-client controller wrapper rather than immediately introducing multiple
clients. The wrapper should connect:

```text
single-client request interface
    -> sdram_single_client_adapter
    -> sdram_runtime_core
    -> explicit initialization/runtime handoff
    -> board-facing PHY boundary
```

Keep the real board PHY as an explicit boundary. Simulation can initially use
the present direct pin/model connection, but production integration must retain
the output-register placement and capture-clock arrangement learned from
experiments 006.a/006.b.

The wrapper's first test should prove reset and initialization handoff followed
by the same split write/read transaction. It must demonstrate that no runtime
request reaches SDRAM before initialization completes and that refresh age
starts from a well-defined handoff point. Do not alter the already-tested
adapter or runtime-core semantics merely to make the wrapper convenient.

After that wrapper passes, the next architectural step is per-client queues and
admission/arbitration. Add those incrementally, beginning with two synthetic
clients and observable fairness/priority behavior, before connecting real video,
audio, or HPS/DMA traffic.

## Authoritative references

- `NEXT_STEPS.md` — staged learning and implementation sequence.
- `tools/sdram-model/IMPLEMENTATION_SPEC.md` — controller requirements and
  definition of done.
- `rtl/scanout-sdram-controller/README.md` — current implementation boundary.
- `dot/FPGA_BRINGUP.md` — clock domains, video, audio, and eventual system
  integration.
- `experiments/006.a-sdram-frequency-chasing/` — clock and TimeQuest work.
- `experiments/006.b-sdram-source-sink-build/` — qualified BL8 data-path
  experiment.

## Instructions for the next Codex session

1. Read this document, the three authoritative architecture documents above,
   and `git diff` before editing anything.
2. Confirm that `.git` is writable. If it is, commit and push the tested adapter
   milestone before beginning the wrapper.
3. Preserve all user changes and the passing 006.a/006.b history.
4. Re-run `make test`, dedicated adapter lint, and `make formal` after any
   semantic RTL change.
5. Explain changes in terms of the layer they belong to and the contract they
   establish; the user is deliberately learning how the logic, fitting, PHY,
   and external-device timing models relate.
