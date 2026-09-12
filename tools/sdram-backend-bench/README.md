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

Run the generator smoke test:

```bash
python3 tools/sdram-backend-bench/test_generate_trace.py
```

Run the current RTL replay smoke matrix:

```bash
python3 tools/sdram-backend-bench/run_rtl_trace_smoke.py
```

Use `--frames 1` without `--lines` for a full 720-line frame trace.  Full-frame
high-load traces are intentionally larger than a smoke trace.

Sweep packetization by running the generator with different
`--line-packet-words` values, for example:

```text
8, 16, 32, 64, 128, 256, 640, 1280
```

Convert one trace to a `$readmemh`-friendly RTL fixture:

```bash
python3 tools/sdram-backend-bench/trace_to_mem.py \
  /tmp/machine-capture.csv \
  /tmp/machine-capture.mem
```

The packed `.mem` record is 224 bits:

```text
issue_time_ns[223:160] deadline_ns[159:96] client[95:92] write[91]
address[90:59] length_words[58:43] byte_enable[42:41] tag[40:9]
reserved[8:0]
```

`deadline_ns` is all ones when the CSV deadline is `-1`.

Replay a converted trace against the current custom RTL controller:

```bash
cd rtl/scanout-sdram-controller
TRACE_MEM=/tmp/machine-capture.mem TRACE_COUNT=123 make trace-current
```

Replay the same fixture against the stock agg23 controller:

```bash
cd rtl/scanout-sdram-controller
TRACE_MEM=/tmp/machine-capture.mem TRACE_COUNT=123 make trace-agg23-stock
```

Replay the same fixture against agg23 behind the clean request-layer wrapper:

```bash
cd rtl/scanout-sdram-controller
TRACE_MEM=/tmp/machine-capture.mem TRACE_COUNT=123 make trace-agg23-request-layer
```

This replay target is intentionally a result collector, not a controller model:
the testbench offers each trace request no earlier than `issue_time_ns`, obeys
the controller handshakes, and reports acceptance delay, completion latency,
and deadline misses observed from the RTL.  The stock agg23 target additionally
reports `native_ops`, because multi-word logical trace requests are replayed as
the simple controller's natural single-word operations.

The smoke matrix currently includes:

- `current_custom`: our existing two-client controller RTL;
- `agg23_stock`: the stock agg23 single-port controller, with only native
  single-word replay adaptation;
- `agg23_request_layer`: a two-client request/completion wrapper over the same
  stock agg23 single-word backend.
