# SDRAM backend benchmark

This directory contains the first executable slice of the three-way SDRAM
backend comparison.

It is intentionally separate from production RTL.  The current runner is a
deterministic command-level model that exercises shared workload traces against
three contender policies:

- `stock_simple`: simple auto-precharge physical controller style;
- `request_simple`: same simple backend with request-layer overhead;
- `custom_current`: current open-row/custom-backend policy model.

This is not a replacement for RTL simulation or Quartus fitting.  Its job is to
make the trace format, workload families, and result tables concrete before the
same traces are bound to RTL wrappers.

Run:

```bash
python3 tools/sdram-backend-bench/run_bench.py
```

Optional:

```bash
python3 tools/sdram-backend-bench/run_bench.py --csv /tmp/sdram-bench.csv
```

Dump deterministic workload traces for RTL/testbench consumption:

```bash
python3 tools/sdram-backend-bench/run_bench.py --dump-traces /tmp/sdram-traces
```

Run the command-level models from previously dumped traces:

```bash
python3 tools/sdram-backend-bench/run_bench.py --trace-dir /tmp/sdram-traces
```

Convert one trace to a `$readmemh`-friendly RTL fixture:

```bash
python3 tools/sdram-backend-bench/trace_to_mem.py \
  /tmp/sdram-traces/boundary_cases.csv \
  /tmp/boundary_cases.mem
```

Trace files use the common CSV format documented in
`docs/sdram-backend-comparison-plan.md`:

```text
cycle,client,op,address,words,byte_enable,tag
```

The packed `.mem` record is 96 bits:

```text
cycle[95:64] client[63:62] write[61] address[60:34]
words[33:18] byte_enable[17:16] tag[15:0]
```
