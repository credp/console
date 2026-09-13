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
```

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
BACKEND=all ./build.sh
```

Each successful build copies the generated RBF to a backend-specific name under
`output_files/Template-<backend>.rbf`. Backend selection is compile-time only;
there is no runtime controller switch.

`agg23-burst` uses `sdram_burst.sv`, but that controller is oriented around
continuous burst reads. Its write path still behaves as single-word write
traffic for this capture workload, so it is a useful physical comparison point
but not a line-burst write implementation.

The experiment targets the existing DE10-Nano / MiSTer template setup and keeps
the physical 720p raster timing from `raster_720p`.
