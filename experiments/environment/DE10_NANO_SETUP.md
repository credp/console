# DE10-Nano development host setup

This project expects a native 64-bit Debian or Ubuntu Linux computer. Quartus
also exists for Windows, but `setup.sh` is a Linux script. Native Linux makes
access to the board's built-in USB-Blaster and serial port straightforward.

## What to download first

### 1. Altera Quartus Prime Lite Edition 25.1std for Linux

Search for:

> Altera Quartus Prime Lite 25.1std Linux download

Choose **Lite Edition**, version **25.1std**, and **Linux**. Lite Edition
supports the Cyclone V used on the DE10-Nano and does not require a paid
Quartus licence. Do not download Quartus Pro Edition.

Download and install both:

- Quartus Prime Lite Edition software
- Cyclone V device support for the same Quartus release

Keep the installer and device-support file together if using the individual
downloads, and select **Cyclone V** during installation. The DE10-Nano FPGA part
is `5CSEBA6U23I7`, a Cyclone V SoC.

Older Terasic examples may have been created with Quartus 18.1 or earlier.
Treat those projects as reference material and allow 25.1 to upgrade a copy.
Install an old Quartus release separately only if a specific legacy project
cannot be migrated. Old releases contain known functional and security issues
and are not the default toolchain for this project.

### 2. Do not install the legacy SoC EDS 18.1

The old Intel SoC FPGA Embedded Development Suite is far behind Quartus 25.1.
The current Cyclone V Linux flow is published as versioned source repositories
and GSRD build recipes instead of one matching SoC EDS installer.

The important repositories are:

- [`altera-fpga/linux-socfpga`](https://github.com/altera-fpga/linux-socfpga) — Linux kernel
- [`altera-fpga/u-boot-socfpga`](https://github.com/altera-fpga/u-boot-socfpga) — SPL and U-Boot
- [`altera-fpga/cyclonev-ed-gsrd`](https://github.com/altera-fpga/cyclonev-ed-gsrd) — Cyclone V reference hardware design
- [`altera-fpga/gsrd-socfpga`](https://github.com/altera-fpga/gsrd-socfpga) — GSRD/Yocto build orchestration

Use repositories and tags from one GSRD release together. For the 25.1std
Cyclone V flow, start with the versions listed in the official
[Cyclone V GSRD 25.1 guide](https://altera-fpga.github.io/rel-25.1/embedded-designs/cyclone-v/sx/soc/gsrd/ug-gsrd-cve-soc/), including:

```text
Hardware reference: QPDS25.1STD_REL_GSRD_PR
Linux:             socfpga-6.12.33-lts / QPDS25.1STD_REL_GSRD_PR
U-Boot:            socfpga_v2025.07 / QPDS25.1STD_REL_GSRD_PR
```

`linux-socfpga` is only the kernel; it is not the entire embedded toolchain.
The final DOT image is expected to use a pinned Buildroot configuration while
borrowing the matched kernel, bootloader, device-tree, and HPS handoff work from
the Altera GSRD flow.

Do not confuse **Nios II EDS** with the old **SoC EDS**. Nios tooling targets a
soft processor in FPGA fabric; it is not the Cortex-A9 Linux SDK.

The ARM Linux C/C++ cross-compiler and device-tree compiler are installed by
`setup.sh` from the Ubuntu/Debian package repository.

### 3. Terasic DE10-Nano board files and documentation

Read the hardware revision printed on the DE10-Nano PCB, then search for:

> Terasic DE10-Nano resources CD-ROM revision E

Replace `E` with the revision on the board. Download the matching **DE10-Nano
CD-ROM** archive and the following documents from Terasic:

- DE10-Nano User Manual for the matching hardware revision
- DE10-Nano Getting Started Guide
- My First FPGA
- My First HPS

The Altera GSRD targets Altera's Cyclone V development kit, not the DE10-Nano.
Use it for the current software flow, but take board pin assignments, DDR/HPS
configuration, schematics, and board-specific peripherals from the matching
Terasic material. Never copy pin assignments from another board revision
without checking them against its schematic.

### 4. Optional SD-card imaging application

An SD-card tool is required only when writing a Linux image for the HPS. Use
Raspberry Pi Imager, balenaEtcher, or Linux `dd` carefully. No SD-card image is
needed for an FPGA-only design programmed over USB-Blaster.

## Install Quartus

Install Quartus 25.1std and Cyclone V device support under the same versioned
installation directory. A common current layout is:

```text
~/altera/25.1std/quartus/
```

The exact parent directory is selectable in the Altera installer, so pass its
actual `quartus` directory to `setup.sh`. You do not need a separate
USB-Blaster driver installer on Linux; the script installs a udev rule granting
non-root access to Intel/Altera USB devices.

## Run this repository's setup

After Quartus is installed:

```bash
./setup.sh --quartus-root "$HOME/altera/25.1std/quartus"
source ./de10-nano-env.sh
```

`setup.sh` installs host build, ARM cross-compilation, HDL simulation, serial,
and debug tools. It also configures USB-Blaster permissions, validates important
commands, and writes `de10-nano-env.sh`. Unplug and reconnect an attached board
after the udev rule is installed.

Basic checks after sourcing the environment are:

```bash
quartus_sh --version
arm-linux-gnueabihf-gcc --version
jtagconfig
```

With the board powered and its USB-Blaster connector attached, `jtagconfig`
should list the Cyclone V JTAG chain. The board exposes separate connectors for
USB-Blaster, UART, USB host/device, and power; consult the matching board manual
rather than assuming any micro-USB connector is the programming connector.

## Authoritative pages

- [Altera Quartus Prime product and downloads](https://www.intel.com/content/www/us/en/products/details/fpga/development-tools/quartus-prime/resource.html)
- [Altera FPGA software installation support](https://www.intel.com/content/www/us/en/support/programmable/licensing/installation-and-licensing.html)
- [Cyclone V GSRD 25.1 guide](https://altera-fpga.github.io/rel-25.1/embedded-designs/cyclone-v/sx/soc/gsrd/ug-gsrd-cve-soc/)
- [Terasic DE10-Nano resources](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&No=1046&PartNo=4)
