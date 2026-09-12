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

