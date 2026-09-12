# SDRAM backend benchmark

This directory contains benchmark tooling for the three-way SDRAM backend
comparison.  It is intentionally separate from production RTL.

The primary artifact is now a deterministic logical request trace.  The trace
describes what the machine asks memory to do and when.  It does not predict
SDRAM commands, row hits, arbitration, completion latency, or controller
efficiency; those belong to RTL simulation and result collection.

Generate a machine-capture trace:

```bash
python3 tools/sdram-backend-bench/generate_trace.py \
  --output /tmp/machine-capture.csv \
  --frames 1 \
  --line-packet-words 1280 \
  --background-kind mixed_sequential \
  --background-mb-s 40
```

Validate an archived trace:

```bash
python3 tools/sdram-backend-bench/generate_trace.py \
  --validate-only /tmp/machine-capture.csv
```

Trace files use this CSV schema:

```text
issue_time_ns,client_id,op,address,length_words,byte_enable,tag,deadline_ns,traffic_class
```

`issue_time_ns` is a controller-independent integer nanosecond timebase.
`deadline_ns` is `-1` when the request has no deadline.  Video capture requests
use the line-buffer reuse deadline; audio capture requests use the next audio
chunk deadline; background requests have no deadline.  HDMI presentation is
not represented because normal scanout/resampling is BRAM traffic.

The older `run_bench.py` command-level runner remains available as a
synthetic/model-only smoke tool.  It exercises shared workload traces against
three placeholder policies:

- `stock_simple`: simple auto-precharge physical controller style;
- `request_simple`: same simple backend with request-layer overhead;
- `custom_current`: current open-row/custom-backend policy model.

It is not a replacement for RTL simulation or Quartus fitting, and its results
should not be used for architectural conclusions.

Run the synthetic model:

```bash
python3 tools/sdram-backend-bench/run_bench.py
```

Optional:

```bash
python3 tools/sdram-backend-bench/run_bench.py --csv /tmp/sdram-bench.csv
```

Dump legacy synthetic workload traces for RTL/testbench experiments:

```bash
python3 tools/sdram-backend-bench/run_bench.py --dump-traces /tmp/sdram-traces
```

Run the command-level models from previously dumped traces:

```bash
python3 tools/sdram-backend-bench/run_bench.py --trace-dir /tmp/sdram-traces
```

Run the legacy synthetic real-machine capture topology sweep:

```bash
python3 tools/sdram-backend-bench/run_bench.py \
  --machine-capture \
  --clock-mode fmax \
  --line-buffers 2 \
  --line-packet-words 128 \
  --lines 30
```

This mode models one 2560-byte video capture line arriving every source-line
period, chunked audio capture, and increasing background traffic through a
command-level policy model.  Treat its output as synthetic only.

Use `--frames 1` without `--lines` for a full 720-line frame sweep.  Full-frame
high-load sweeps are intentionally heavier than the smoke command above.

If `--line-packet-words` is omitted, machine-capture mode sweeps:

```text
8, 16, 32, 64, 128, 256, 640, 1280
```

Use repeated `--line-packet-words` options to choose a smaller packet matrix.
`--raster-mode logical` is the default and means 720 active source lines per
1/60 sec frame with no assumed HDMI blanking.  `--raster-mode blanked` uses
`--raster-total-lines` to insert vertical blanking after the active region.

Convert one trace to a `$readmemh`-friendly RTL fixture:

```bash
python3 tools/sdram-backend-bench/trace_to_mem.py \
  /tmp/sdram-traces/boundary_cases.csv \
  /tmp/boundary_cases.mem
```

Legacy `run_bench.py --dump-traces` files use the older CSV format documented
by that script:

```text
cycle,client,op,address,words,byte_enable,tag
```

The packed `.mem` record is 96 bits:

```text
cycle[95:64] client[63:62] write[61] address[60:34]
words[33:18] byte_enable[17:16] tag[15:0]
```
