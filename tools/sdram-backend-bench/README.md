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

Trace files use the common CSV format documented in
`docs/sdram-backend-comparison-plan.md`:

```text
cycle,client,op,address,words,byte_enable,tag
```
