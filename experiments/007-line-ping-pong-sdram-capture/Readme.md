# Experiment 007: two-line ping-pong capture

This experiment is a small hardware prototype derived from experiment 003.
It keeps the 1280x720 HDMI raster path and replaces the preloaded PPM BRAM
image with a deterministic generated source line.

## Topology

```text
deterministic pixel generator
        |
        v
two 1280 x 16-bit BRAM line buffers
        |
        +--> completed line to HDMI presentation
        |
        +--> completed line to SDRAM write/capture
```

Only two line buffers are used. One buffer is filled while the other contains
the most recently completed line. At line completion the roles swap. The
completed line is displayed from BRAM and submitted once to SDRAM as one
sequential 1280-word write request through a narrow SDRAM backend wrapper.

The pattern is a simple function of X, Y, and frame count. It is meant to make
stale or corrupted line reuse visible, not to be pretty.

The source line cadence is intentionally slower than the HDMI line cadence:
one 1280-pixel source line is completed every 4096 pixel-clock cycles. HDMI may
therefore read the same completed source line more than once while SDRAM drains,
which is the specific slack condition this prototype is meant to expose.

## Instrumentation

`line_ping_pong_capture` exposes:

- `source_lines_generated`
- `sdram_lines_submitted`
- `sdram_lines_completed`
- `reuse_before_drain_error`
- `worst_line_drain_cycles`
- `current_line_drain_cycles`

On hardware, `LED_USER` is solid once SDRAM initialization completes and flashes
if `reuse_before_drain_error` or a backend diagnostic error is set.

## Simulation

Run:

```bash
cd experiments/007-line-ping-pong-sdram-capture
make test
```

The test uses actual RTL SDRAM controller paths with the repo's SDRAM pair
model. It checks buffer alternation, deterministic presented data, one SDRAM
request per completed line, and request/completion matching. The custom backend
keeps no-reuse-before-drain as a hard assertion. The comparison backends report
reuse-before-drain as a capacity result so the whole matrix can finish.

Available backends:

```bash
make test-custom
make test-agg23-word
make test-agg23-burst
make test-agg23-bl8-write
```

Current simulation results at 100 MHz SDRAM clock:

| Backend | Result | Worst drain |
| --- | --- | --- |
| custom | PASS | 3094 cycles |
| agg23-word | CAPACITY_FAIL | 11633 cycles |
| agg23-burst | CAPACITY_FAIL | 11633 cycles |
| agg23-bl8-write | PASS | 2751 cycles |

## Build

Build like the earlier experiments:

```bash
cd experiments/007-line-ping-pong-sdram-capture
./build.sh
```

Build a specific SDRAM backend with:

```bash
BACKEND=custom ./build.sh
BACKEND=agg23-word ./build.sh
BACKEND=agg23-burst ./build.sh
BACKEND=agg23-bl8-write ./build.sh
BACKEND=007-bl8-hwtest ./build.sh
BACKEND=all ./build.sh
```

Each successful build copies the generated RBF to a backend-specific name under
`output_files/Template-<backend>.rbf`. Backend selection is compile-time only;
there is no runtime controller switch.

`agg23-burst` uses `sdram_burst.sv`, but that controller is oriented around
continuous burst reads. Its write path still behaves as single-word write
traffic for this capture workload, so it is a useful physical comparison point
but not a line-burst write implementation.

`agg23-bl8-write` is a tiny sequential-write backend for this experiment's
single client. It initializes SDRAM for BL8 writes, keeps only the current row
open, streams each collected group of eight line words as one WRITE burst, and
precharges at row boundaries or line completion. It has no scheduler,
arbitration, read path, large FIFO, or transaction reordering.

Backend selection deliberately uses plain nested `ifdef` blocks rather than
SystemVerilog `elsif`, because Quartus 17 did not reliably elaborate the
selected backend from the QSF macro when `elsif` was used.

Current DE10-Nano / MiSTer Quartus measurements for the two passing backends:

| Backend | ALMs | Registers | Block memory bits | SDRAM Fmax | Worst SDRAM setup slack | SDRAM output setup slack |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| custom | 8,182 | 12,374 | 425,217 | 86.73 MHz | -1.530 ns | +1.958 ns |
| agg23-bl8-write | 7,398 | 11,807 | 425,217 | 110.62 MHz | +0.960 ns | +1.958 ns |

The custom backend also includes a local output-enable timing experiment: the
SDRAM DQ output-enable register is replicated per bit and packed into the fast
I/O output-enable registers. Quartus confirms this in the fitter report, but
the internal SDRAM clock domain still fails setup.

The `agg23-bl8-write` backend is timing-clean at 100 MHz after synchronizing
the external reset into the SDRAM clock domain. The previous `-0.237 ns` setup
miss was a reset crossing from `reset_req` into BL8 SDRAM output/control
registers, not a functional write datapath problem.

## Hardware test

Build the dedicated hardware-test bitstream with:

```bash
BACKEND=007-bl8-hwtest ./build.sh
```

Load `output_files/Template-007-bl8-hwtest.rbf`.

Expected HDMI output is a stable animated 720p deterministic pattern with
visible horizontal, vertical, and frame-dependent variation. `LED_USER` is solid
after SDRAM initialization. If `LED_USER` flashes, a sticky reuse-before-drain
or backend diagnostic error occurred.

PASS:

- stable HDMI output with the expected animated pattern;
- no obvious tearing, stale repeated lines, or corrupt line artifacts;
- output continues indefinitely;
- `LED_USER` remains solid after initialization.

FAIL:

- unstable or corrupt HDMI output;
- periodic stale-line or tearing artifacts;
- output stops or loses sync;
- `LED_USER` flashes.

Current hardware-test build measurements:

| RBF | ALMs | Registers | Block memory bits | SDRAM Fmax | Worst SDRAM setup slack | SDRAM output setup slack | Worst line drain |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Template-007-bl8-hwtest.rbf | 7,398 | 11,807 | 425,217 | 110.62 MHz | +0.960 ns | +1.958 ns | 2751 cycles |

The experiment targets the existing DE10-Nano / MiSTer template setup and keeps
the physical 720p raster timing from `raster_720p`.
