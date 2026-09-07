# SDRAM exploration results

## FIFO-watermark arbiter

The latest hardware-oriented sweep uses fixed audio priority, strict in-order
presentation requests, FIFO hysteresis, pre-emption at BL8 boundaries, and
background row-hit lookahead. The tested configuration is:

- `stripe-1k-bank-chip`, open page, BL8 physical commands;
- 256-word controller requests;
- 2,048-word video FIFO, low/high watermarks 512/1536;
- 4,096-cycle active-frame tail-flush lead;
- 720p16 storage at 60 Hz;
- 1080p timing active fraction `(1920*1080)/(2200*1125)`;
- half-period refresh staggering;
- safety required in capture/replay with background reads/writes.

The complete-frame residual-bandwidth brackets are:

| SDRAM clock | Highest tested safe | First tested unsafe |
|---:|---:|---:|
| 100 MHz | 64 MB/s | 65 MB/s |
| 120 MHz | 100 MB/s | 101 MB/s |
| 130 MHz | 122 MB/s | 123 MB/s |
| 143 MHz | 147 MB/s | 148 MB/s |

At 130 MHz and 122 MB/s residual load the worst tested video deadline slack is
1.392 us with the 512/1536 band. `watermark-threshold-sweep.csv` shows that
256/1024 and 512/1024 are also safe at 120 MB/s, while 768/1792 is not. The
wider 512/1536 band retains more margin at the final measured boundary.

These limits are lower than the earlier EDF figures because this arbiter does
not globally reorder presentation traffic for row hits, and because active
video is no longer incorrectly spread across blanking. Relevant raw data is in
`watermark-bandwidth-*-summary.csv`,
`watermark-bandwidth-boundary-*-summary.csv`, and
`watermark-threshold-sweep-summary.csv`.

## Architectural presentation workload

The current model treats live capture writes and missed-frame replay reads as
mutually exclusive. HDMI receives the live raster without reading SDRAM.
`presentation-baseline-full-frame.csv` is the complete-frame, zero-background
matrix for the six mappings, 100/120/130/143 MHz, capture/replay, and
720p16/1080p8/1080p16. The corresponding 1 ms diagnostic is
`presentation-mapping-sweep.csv`.

Every mapping is deadline-safe for 720p16 and 1080p8 at all four clocks. Native
1080p16 is unsafe at 100 and 120 MHz, but completes at 130 and exploratory
143 MHz with no residual traffic. This is an ideal controller/model result,
not additional evidence that every board exceeds its documented acceptance
conditions.

The full-frame residual-load sweeps use `stripe-1k-bank-chip`, BL8 physical
commands, 256-word controller requests/grants, a 2,048-word video FIFO, a
2,048-cycle EDF guard, half-interval chip-refresh staggering, and require every
tested capture/replay direction to remain safe. At 130 MHz they bracket usable
residual bandwidth as follows:

| Stored representation | Highest tested safe | First tested unsafe |
|---|---:|---:|
| 1280x720x16 | 146 MB/s | 148 MB/s |
| 1920x1080x8 | 130 MB/s | 135 MB/s |
| 1920x1080x16 | 8 MB/s | 10 MB/s |

For 720p16, complete-frame conservative lower bounds across all capture/replay
and background read/write combinations are:

| SDRAM clock | Highest tested safe | First tested unsafe |
|---:|---:|---:|
| 100 MHz | 85 MB/s | 90 MB/s |
| 120 MHz | 125 MB/s | 130 MB/s |
| 130 MHz | 146 MB/s | 148 MB/s |
| 143 MHz | 165 MB/s | 175 MB/s |

These are brackets over tested points rather than inferred exact maxima.
The raw files are `presentation-720p*-boundary.csv`,
`presentation-1080p8-130-boundary.csv`, and
`presentation-1080p16-130-*-boundary.csv`.

## Legacy simultaneous stress workload

The following earlier sweep intentionally combines scanout and capture. It is
retained as a controller stress test and is not the normal presentation-memory
architecture.

Generated 2026-09-07 with:

```sh
python3 tools/sdram-model/sweep_output.py --duration-us 1000 --workers 4
```

The matrix contains 192 cases: six mappings, 100/120/130/143 MHz, and equal
scanout refill/grant sizes of 8, 16, 32, 64, 128, 256, 512, and 1024 words.
All other output workload and controller parameters retain their CLI defaults.
Exact 143 MHz is an explicitly enabled and labeled exploratory overclock because
its 6.993 ns period is shorter than the component's 7 ns CL3 limit.

## Pareto definition

Frontiers are calculated independently at each frequency. A case dominates
another when it is no worse in every one of these objectives and better in at
least one (continuous values are compared after rounding to 0.001):

- fewer total channel deadline misses;
- fewer incomplete frames;
- greater minimum read-channel deadline slack;
- greater useful DQ utilisation;
- lower worst writer queue wait, taking the maximum of frame-write and
  audio-write.

The full 192 cases are in `output-sweep.csv`; the 104 nondominated cases are in
`output-sweep-pareto.csv`.

## Frontier summary

| MHz | Frontier cases | Slack range (us) | DQ utilisation range | Writer max-wait range (us) |
|---:|---:|---:|---:|---:|
| 100 | 13 | -7.28–36.55 | 75.31–98.49% | 225.06–644.25 |
| 120 | 30 | 17.95–36.63 | 87.15–92.31% | 26.24–149.12 |
| 130 | 29 | 18.19–36.66 | 84.43–85.21% | 22.42–50.64 |
| 143 | 32 | 18.24–36.66 | 76.76–77.47% | 17.37–29.76 |

At 100 MHz, cases range from zero to 4050 read deadline misses during the 1 ms
window. Even zero-miss cases are not sustainable indefinitely: the default
221.568 MB/s offered load exceeds the 200 MB/s raw DQ ceiling, so some backlog
must grow.

## Objective extremes

These are landmarks on the frontier, not recommendations or winners.

| MHz | Objective | Mapping | Refill | Min slack (us) | DQ util. | Writer max wait (us) |
|---:|---|---|---:|---:|---:|---:|
| 100 | greatest slack | linear | 8 | 36.55 | 82.88% | 541.35 |
| 100 | greatest DQ use | row-bank-chip-column | 8 | -7.28 | 98.49% | 225.06 |
| 100 | lowest writer wait | row-bank-chip-column | 8 | -7.28 | 98.49% | 225.06 |
| 120 | greatest slack | linear | 8 | 36.63 | 87.31% | 145.64 |
| 120 | greatest DQ use | row-bank-chip-column | 8 | 27.18 | 92.31% | 34.00 |
| 120 | lowest writer wait | row-bank-chip-column | 1024 | 18.25 | 91.47% | 26.24 |
| 130 | greatest slack | linear | 8 | 36.66 | 84.74% | 48.18 |
| 130 | greatest DQ use | row-bank-chip-column | 8 | 27.93 | 85.21% | 30.21 |
| 130 | lowest writer wait | row-bank-chip-column | 1024 | 18.27 | 84.43% | 22.42 |
| 143 | greatest slack | linear | 8 | 36.66 | 77.47% | 29.76 |
| 143 | greatest DQ use (tie) | chip-row-bank-column | 8 | 36.02 | 77.47% | 29.49 |
| 143 | lowest writer wait | row-bank-chip-column | 1024 | 18.28 | 76.76% | 17.37 |

## Interpretation limits

The final scanout refill is released in complete blocks. At a fixed 1 ms
horizon, a larger refill can leave more not-yet-due words beyond the boundary,
lowering measured useful DQ utilisation. This phase/endpoint effect is real for
the finite observation but should not be mistaken for lower steady-state
bandwidth. The raw CSV includes `unserved_words`, turnarounds, ACT count, and
command utilisation so such cases can be identified.

Likewise, minimum deadline slack carries information even when the miss count
is zero. Longer targeted simulations are
needed to validate selected frontier regions over complete frame periods,
especially at 100 MHz.

## Full-frame candidate validation

`candidate-full-frame.csv` contains a targeted 16.667 ms validation at 130 MHz
for `stripe-1k-bank-chip` with 128- and 256-word scanout refill/grants. Each was
run with aligned, quarter-period, half-period, and three-quarter-period chip-1
refresh offsets.

Neither candidate is deadline-safe with the current 64-cycle EDF guard. The
128-word candidate records 13–37 scanout misses and -4.19 to -4.35 us minimum
slack; the 256-word candidate records 29–126 misses and -6.49 to -6.67 us
minimum slack. There are no incomplete frame writes. The 256-word candidate
roughly halves DQ turnarounds (about 7,100 versus 14,300) and reduces ACT count,
but the 128-word candidate has the better scanout tail behavior in every tested
refresh phase.

`candidate-guard-sweep.csv` extends that validation across EDF guards of 32,
64, 128, 256, 512, and 1024 cycles. The first tested guard safe across all four
refresh phases is 1024 cycles (7.877 us at 130 MHz) for the 128-word refill and
512 cycles (3.938 us) for the 256-word refill. Thus the transition is bracketed
to 512–1024 and 256–512 cycles respectively; intermediate guards were not
tested. At those first safe points, worst-phase minimum scanout slack is 3.454
us for 128 words and 1.146 us for 256 words. Useful DQ utilisation remains
85.213% and 85.207%, so earlier urgency does not cost measurable throughput in
this workload.
