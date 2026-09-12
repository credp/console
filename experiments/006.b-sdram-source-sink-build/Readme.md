# SDRAM BL8 source/sink experiment

Generated from Template_MiSTer revision 14d9ed0. The hardware baseline remains
20 MHz, with packed rising-edge I/O registers and an inverted forwarded clock.
After initialization the engine uses sequential BL8 and CAS latency 3. Hardware
capture probing established the current CL+0 registered return position at
20 MHz; increasing the clock still requires qualifying the PHY/beat alignment.

The client performs a complete address-derived write pass, an optional masked
overwrite pass, a 1 ms dwell, then a separate read pass. `LED_USER` is solid only
after exactly 58 logical words have been checked, the comparison pipeline has
drained, and both data and operation-accounting checks pass. It flashes on a
completed failed test and remains off while the test runs. The BIST exposes a
saturating data-error count and first failing logical address/expected/observed
values; these fields are not yet exported by the LED-only frontend. A stalled
test has no hardware watchdog yet.

The `SDRAM test` option selects the unmasked BL8 baseline, alternating low and
high byte overwrites, low-byte-only overwrites, or high-byte-only overwrites.
Changing the option automatically resets and reruns SDRAM initialization. DQM
is carried in the CAS-cycle `SDRAM_A[12:11]` bits and launched from that same
packed vector, matching established MiSTer SDRAM controllers.

The hardware BIST is now a client rather than part of the memory sequencer. It
submits five logical requests through `sdram_request_splitter`; every emitted
operation is accepted by `sdram_bl8_op_engine`, which independently decodes its
address and performs the physical command and data sequence. The requests cross
an unaligned BL8 boundary (1+8+1 words), a chip stripe, a bank stripe, the 1 KiB
half-row transition, and a 2 KiB physical-row transition (4+8 words each).
Partial writes mask unused physical beats and partial reads discard them. The
BIST verifies the resulting 58-word logical response stream in request order.
Expected values and write payloads use an independent logical cursor, and every
emitted address, length, last marker, and completion count is checked against
that cursor. They are not derived from the splitter's emitted address.

The engine captures all eight physical read beats into a private burst buffer
before presenting useful words with `read_valid/read_ready`. It holds data and
valid under backpressure and completes only after the last useful word is
accepted. There is one outstanding operation, so buffer capacity is reserved
implicitly. Comparison and diagnostic updates are separate pipeline stages.
Startup, command waits, and BIST dwell use bounded counters rather than 64-bit
runtime counters. At 142.857 MHz these require 15, 4, and 18 bits respectively.

This is still the conservative auto-precharge engine. Open-bank scheduling,
runtime refresh (including during dwell or indefinite client stalls), queued
transactions, and tagged completion remain future steps. It is not a sustained
traffic or long-retention test yet.

The same pins are tested by `make test` in
`../../rtl/scanout-sdram-controller` against a behavioral two-chip model. That
test suite also retains the prior BL1/BL8 tests as regressions. The integrated
test runs the 20 MHz and 142.857 MHz cycle-count configurations, all four mask
modes, random write/read stalls, first/final-word stalls, and reset while a read
is buffered. It checks untouched guard words around partial bursts, exclusive
DQ ownership, and non-X/Z useful captures. Corrupting the last response and
dropping a response must both fail. The model implements BL8 column wrapping;
its legacy `READ_LATENCY_EDGES=2` override is a functional convention, not proof
of analogue timing or high-frequency capture alignment.

`make formal` includes an inductive proof of burst capture/delivery conservation,
arbitrary watched-word preservation, stable stalled responses, and completion
only after all useful words are accepted. This is not yet a proof of all SDRAM
command timing rules.

After fitting, run `quartus_sta -t report_sdram_timing.tcl` here to produce
separate input, capture-to-buffer, output, and internal setup/hold reports in
`output_files/`. The baseline SDC uses PLL output 0 and fails explicitly if that
clock source is missing. It has no extra-cycle input exception at 20 MHz.
Reports use the default slow corner; full operating-corner qualification and
board-delay validation remain necessary before high-speed sign-off.

## Upstream template documentation

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

