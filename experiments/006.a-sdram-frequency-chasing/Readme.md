# Experiment 006.a: SDRAM frequency and capture-phase characterization

This branch deliberately retains the conservative BL1 transaction machinery
from experiment 005 while varying only the SDRAM clock and DQ capture phase.
It is for finding a stable PHY operating point; BL8 and the production data
path belong in experiment 006.b.

Set the build point in `rtl/experiment_config.vh`. Supported clock settings are
20, 100, 120, and 130 MHz, plus explicitly exploratory 143 MHz. Sweep
`SDRAM_CAPTURE_PHASE` in both directions at each frequency. Quartus can
quantize requested phase shifts, so use the implemented phase from its report,
not merely the requested value, in the results table below.

The MiSTer framework and demo video remain on their original 20 MHz clock.
Separate PLL outputs drive the BIST/SDRAM command clock and the phase-shifted
capture register, preventing framework timing from limiting the SDRAM sweep.
The pin-facing command, write-data, output-enable, and read-capture registers
form an explicit top-level PHY boundary and are packed into the FPGA I/O cells.
As in MiSTer MemTest, outputs launch on the controller rising edge and
`SDRAM_CLK` is inverted through a dedicated DDR output cell, giving commands a
half-cycle of setup. A capture-phase setting of 0 ps therefore samples half an
external SDRAM period after its rising edge; phase sweep results must be
reported in that external-clock frame of reference.

The continuous test writes and reads 65,536 addresses for each of 24 patterns:
zeroes, ones, alternating bits, address and inverted-address data, two
pseudorandom variants, and all sixteen walking-one positions. Address order
deliberately crosses columns, rows, all banks, and both complementary chip
selects. Refresh runs throughout. The BIST exposes saturating pass/error
counters and first-failure address/expected/observed registers; signals are
marked for preservation so they can be added to SignalTap.

`LED_USER` is off until the first complete 24-pattern sweep passes, remains
solid while the error count is zero, and flashes after the first compare error.
Qualify a setting from the counters and the test procedure, not from a brief
LED observation.

## Characterization procedure

1. Rebuild and confirm the experiment 005-equivalent 20 MHz, 25 ns
   falling-edge capture point after repeated reset and cold starts.
2. For 100, 120, and 130 MHz, sweep phase in both directions until both failing
   edges are observed. Build and test 143 MHz only as an overclock experiment.
3. At every point, allow board warm-up, clear counters with reset, and run the
   same soak interval. Record cold-start failures separately from data errors.
4. Record the complete contiguous passing window and choose a point near its
   centre. A production point needs at least one observed passing setting on
   either side.

invalid results - incorrect output pins

| Frequency | Requested phase | Implemented phase | Soak/passes | Errors | Cold starts | Result |
|---:|---:|---:|---:|---:|---:|:---|
| 20 MHz | 25000 ps | 25000 ps / 180 deg | >=1 | 0 indicated | not yet tested | pass: solid `LED_USER` |
| 100 MHz | 5000 ps | 5000 ps / 180 deg | 0 | >=1 indicated | not yet tested | fail: flashing `LED_USER` |
| 100 MHz | 7500 ps | 7500 ps / 270 deg | >=1 | 0 indicated | not yet tested | pass: solid `LED_USER` |
| 100 MHz | 6250 ps | ??? ps / 225 deg est | 1 | 0 indicated | untested | pass: solid `LED_USER` |
| 100 MHz | 5750 ps | ??? ps / 203 deg est | 1 | 0 indicated | untested |  pass: solid LED |
7500-10000 range for closing edge
at 100MHz, window is at least 5750-7500 ps

| 120 MHz | 4650 ps | 4650 ps / 200.77 deg | 0 | | | fail: flashing LED |
| 120 MHz | 5600 ps | 5599 / 241.875 deg target | 0 | x | untested | fail: flashing LED |
| 120 MHz | 5903 ps |  255 degrees | 0 | x | x | next test point |
| 120 MHz | 6944 ps | | | x  | | next test point |
-8333 range for closing edge

new results - corrected
| Frequency | Capture Offset | Effective external phase | Soak/passes | Errors | Cold starts | Result |
|---:|---:|---:|---:|---:|---:|:---|
| 20 MHz | 25000 ps | 25000 ps / 180 deg | >=1 | 0 indicated | not yet tested | pass: solid `LED_USER` |
| 120 Mhz | 0 ps| 180 degrees | 1 | 0 | 0 | pass: Solid LED |
| 120 Mhz | 3819 ps|  345 degrees   | 0 | x | x | fail: flashing LED |
| 120 Mhz | 2083 ps|  270 degrees   | 0 | 1 | x | pass: solid LED |
| 120 Mhz | 3125 ps|  315 degrees   | 0 | 0 | x | fail: flashing LED |
| 120 Mhz | 2778 ps|  300 degrees   | 0 | 1 | x | pass: solid LED |
| 120 Mhz | 2431 ps|   degrees   | 0 | 1 | x | pass: solid LED |
| 142 Mhz | 0 ps| 180 degrees | 1 | 0 | 0 | pass: Solid LED |



note:
Error: PLL Output Counter parameter 'phase_shift' is set to an illegal value of '5750 ps' on node 'emu:emu|pll:pll|pll_0002:pll_inst|altera_pll:altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER'. File: /home/chris/intelFPGA_lite/17.0/quartus/libraries/megafunctions/altera_pll.v Line: 749
    Info: "0 ps" is a legal value
    Info: "347 ps" is a legal value
    Info: "694 ps" is a legal value
    Info: "1042 ps" is a legal value
    Info: "1389 ps" is a legal value
    Info: "1736 ps" is a legal value
    Info: "2083 ps" is a legal value
    Info: "2431 ps" is a legal value
    Info: "2778 ps" is a legal value
    Info: "3125 ps" is a legal value
    Info: "3472 ps" is a legal value
    Info: "3819 ps" is a legal value
    Info: "4167 ps" is a legal value
    Info: "4514 ps" is a legal value
    Info: "4861 ps" is a legal value
    Info: "5208 ps" is a legal value
    Info: "5556 ps" is a legal value
    Info: "5903 ps" is a legal value
    Info: "6250 ps" is a legal value
    Info: "6597 ps" is a legal value
    Info: "6944 ps" is a legal value
    Info: "7292 ps" is a legal value
    Info: "7639 ps" is a legal value
    Info: "7986 ps" is a legal value


| | | | | | | next test point |
| | | | | | | next test point |
| | | | | | | next test point |

The current build point is 100 MHz with a 6.25 ns capture phase. The 20 MHz
baseline passed the expanded BIST on the target board as indicated by a solid
`LED_USER`; its soak duration and cold-start coverage remain unmeasured.
The 100 MHz, 5 ns point failed with the error flash at roughly 2--4 Hz as
observed by the user, while the 7.5 ns point passed.

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
