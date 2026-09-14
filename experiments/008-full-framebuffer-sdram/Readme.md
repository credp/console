# Experiment 008: full framebuffer SDRAM

This experiment is about producing and consuming a complete framebuffer in
SDRAM. It is deliberately not an HDMI-raster capture experiment.

The fixed canonical framebuffer for this experiment is:

```text
1280 x 720
16 bits per pixel
921,600 16-bit words
1,843,200 bytes
```

The design should be built in small, reviewable pieces. Do not collapse the
producer, SDRAM transfer machinery, and scanout consumer into one large state
machine.

## Architecture

Producer path:

```text
algorithmic pixel producer
    -> working-line BRAM
    -> completed/writing-line BRAM
    -> sequential BL8 SDRAM writes
    -> framebuffer in SDRAM
```

Consumer path:

```text
framebuffer in SDRAM
    -> sequential burst reads
    -> filling-line BRAM
    -> completed/output-line BRAM
    -> scanout
```

Each side uses exactly two line buffers. The producer owns a working line and a
writing line. The consumer owns a filling line and an output line. Ownership
changes only at explicit line handoff points.

The first pattern is intentionally simple and diagnostic:

- every pixel on the outside edge of the framebuffer is white;
- the interior is a coordinate-derived RGB565 colour field;
- the colour field drifts slowly with a frame counter.

The border should make cropping, off-by-one addresses, line delay, and HDMI
coupling mistakes visible. The drifting interior should make stale or repeated
frames visible without adding a complicated renderer.

## RTL style rules

Write RTL so it can be explained to a novice who knows basic digital logic and
SystemVerilog:

- small modules with block-diagram-shaped jobs;
- explicit state machines with descriptive state names;
- clear separation between state, counters, handshakes, and datapath;
- obvious ownership of every RAM port;
- obvious ownership transitions for ping-pong buffers;
- straightforward `always_ff` and `always_comb`;
- SystemVerilog that Quartus 17 handles comfortably.

Avoid interfaces, modports, dense generic frameworks, metaprogramming-like
tricks, hidden state transitions, and overloaded signals. Some duplication is
better than clever code in this experiment.

## Current implementation

The first implemented blocks are:

- `framebuffer_pattern_pixel`, a tiny combinational pixel function;
- `framebuffer_machine_line_source`, the explicit owner of machine-visible
  framebuffer counters: pixel X, line Y, frame index, and generated pixel data;
- `framebuffer_line_chunk_address`, the explicit framebuffer-address block that
  converts a line/chunk coordinate into a linear byte address;
- `framebuffer_producer_lines`, a two-line producer-side ownership prototype
  with no SDRAM backend yet;
- `framebuffer_line_write_sequencer`, a producer-side line drain that emits
  fixed-size write chunks. `WRITE_CHUNK_WORDS` is a synthesis-time parameter so
  the first hardware build can use whole-line writes or smaller chunks without
  changing the ownership logic. This block converts framebuffer coordinates
  into linear byte addresses; SDRAM chip/bank/row/column mapping belongs below
  the request interface;
- `framebuffer_producer_write_path`, a thin composition of the producer line
  buffers and chunked write sequencer. It is still tested against a fake sink,
  not real SDRAM;
- `framebuffer_consumer_lines`, a consumer-side two-line prototype. It fills
  one line from a stream, exposes only completed lines to scanout, and stalls
  instead of overwriting an output line that has not advanced;
- `framebuffer_line_read_sequencer`, a consumer-side line fill sequencer that
  emits fixed-size read chunks and turns returned read data into the fill
  stream. It still talks to a fake read source in simulation.
- `framebuffer_consumer_read_path`, the matching thin composition of the read
  sequencer, line scheduler, and consumer line buffers. Its only timing input
  is the physical scanout line-boundary event;
- `framebuffer_consumer_line_scheduler`, the explicit owner of consumer line
  order. It prefetches the next framebuffer line and only permits the scanout
  line transition after that fill is complete;
- `framebuffer_scanout_timing_adapter`, the small boundary block between an
  existing raster and framebuffer scanout. It forwards active-video X/Y and
  identifies active line starts; it does not generate timing itself.
- `framebuffer_transfer_statistics`, a separate machine-state block that owns
  saturating cycle counters. Producer idle means its write sequencer is idle;
  consumer idle means its read sequencer is idle. Producer stall combines a
  completed line waiting for the writer with both producer line buffers being
  occupied; consumer stall means its completed line is waiting for scanout to
  release the output buffer.

`tb_framebuffer_write_read_path` joins the producer and consumer request ports
to one simulated linear memory. It verifies every pixel after the round trip;
it is a simulation integration point, not the future SDRAM controller.

`framebuffer_bl8_write_backend` is the experiment-local copy of experiment
007's small BL8 write engine, including the word-0 alignment correction proven
by the pin-model test. It services periodic refresh requests between safe BL8
write boundaries. `tb_framebuffer_producer_bl8_write_backend` directly
connects the producer to it and the SDRAM pin model. The backend is listed for
Quartus but is not yet connected to the experiment's hardware top level.

Run its simulation with:

```bash
cd experiments/008-full-framebuffer-sdram
make test
```

To run only the joined write/read test and produce its GTKWave-compatible VCD:

```bash
make waveform
gtkwave build/framebuffer_write_read_path.vcd
```

To run the physical BL8 write compatibility test and inspect its waveform:

```bash
make test-producer-bl8
gtkwave build/framebuffer_producer_bl8_write_backend.vcd
```

To force frequent runtime refreshes while checking that writes still complete:

```bash
make test-producer-bl8-refresh
```

To run the same test with real 1280-word lines, including SDRAM row crossings
and expected producer backpressure:

```bash
make test-producer-bl8-capacity
```

To split each 1280-word line into ten 128-word requests (each internally
transferred as sixteen BL8 writes):

```bash
make test-producer-bl8-chunks
```

## Upstream template notes

## General description
This core contains the latest version of framework and will be updated when framework is updated. There will be no releases. This core is only for developers. Besides the framework, core demonstrates the basic usage. New or ported cores should use it as a template.

It's highly recommended to follow the notes to keep it standardized for easier maintenance and collaboration with other developers.

## Source structure

### Legend:
* `<core_name>` - you have to use the same name where you see this in this manual. Basically it's your core name.

### Standard MiSTer core should have following folders:
* `sys` - the framework. Basically it's prohibited to change any files in this folder. Framework updates may erase any customization in this folder. All MiSTer cores have to include sys folder as is from this core.
* `rtl` - the actual source of core. It's up to the developer how to organize the inner structure of this folder. Exception is pll folder/files (see below).
* `releases` - the folder where rbf files should be placed. format of each rbf is: <core_name>_YYYYMMDD.rbf (YYYYMMDD is date code of release).

### Other standard files:
* `<core_name>.qpf`- quartus project file. Copy it as is and then modify the line `PROJECT_REVISION = "<core_name>"` according to your core name.
* `<core_name>.qsf` - quartus settings file. In most cases you don't need to modify anything inside (although you may wont to adjust some settings in quartus - this is fine, but keep changes minimal). You also need to watch this file before you make a commit. Quartus in some conditions may "spit" all settings from different files into this file so it will become large. If you see this, then simply revert it to original file.
* `<core_name>.srf` - optional file to disable some warnings which are safe to disable and make message list more clean, so you will have less chance to miss some important warnings. You are free to modify it.
* `<core_name>.sdc` - optional file for constraints in case if core require some special constraints. You are free to modify it.
* `<core_name>.sv` - glue logic between framework and core. This is where you adapt core specific signals to framework.
* `files.qip` - list of all core files. You need to edit it manually to add/remove files. Quartus will use this file but can't edit it. If you add files in Quartus IDE, then they will be added to `<core_name>.qsf` which is recommended manually move them to `files.qip`.
* `clean.bat` - windows batch file to clean the whole project from temporary files. In most cases you don't need to modify it.
* `.gitignore` - list of files should be ignored by git, so temporary files wont be included in commits.
* `jtag.cdf` - it will be produced when you compile the core. By clicking it in Quartus IDE, you will launch programmer where you can send the core to MiSTer over USB blaster cable (see manual for DE10-nano how to connect it). This file normally is not present on cleaned project and not included in commits.

### PLL:
Framework implies use of at least one PLL in the core. Framework doesn't contain this PLL but requires it to be placed in `rtl` folder, so `pll` folder and `pll.v`, `pll.qip` files must be present, however PLL settings are up to the core.

### Verilog Macros

The following macros can be defined and will affect the framework features:

Macro                    |   Effect
-------------------------|---------------------------------
MISTER_DEBUG_NOHDMI      | Disable HDMI-related modules. Speeds up compilation but only analogue/direct video is available
MISTER_DUAL_SDRAM        | Changes configuration of FPGA pins to work with dual SDRAM I/O boards
MISTER_FB                | Allows to use framebuffer from the core
MISTER_SMALL_VBUF        | Sets a smaller video buffer for the ASCAL
MISTER_DOWNSCALE_NN      | Ascal's downscale mode
MISTER_DISABLE_ADAPTIVE  | Disables adaptive scan lines
MISTER_FB_PALETTE        | Framebuffer palette


# Quartus version
Cores must be developed in **Quartus v17.0.x**. It's recommended to have updates, so it will be **v17.0.2**. Newer versions won't give any benefits to FPGA used in MiSTer, however they will introduce incompatibilities in project settings and it will make harder to maintain the core and collaborate with others. **So please stick to good old 17.0.x version.** You may use either Lite or Standard license.

