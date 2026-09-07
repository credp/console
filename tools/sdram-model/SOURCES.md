# Hardware sources and provenance

This file records the evidence behind board-specific assumptions separately
from assumptions derived from the SDRAM component datasheet.

## XS-DS v2.9 chip selection

- Primary source: MiSTer-devel, `Hardware_MiSTer`,
  [`releases/sdram_xsds_2.9.pdf`](https://github.com/MiSTer-devel/Hardware_MiSTer/blob/master/releases/sdram_xsds_2.9.pdf),
  XS-DS v2.9 schematic, sheet 1 (accessed 2026-09-07).
- Observed wiring: the two AS4C32M16SB devices share the address, bank,
  command, clock, CKE, mask, and 16-bit DQ nets. One SDRAM `/CS` is driven by
  the incoming active-low chip-select net; the other is driven through the
  schematic's single inverter. Consequently, for a stable chip-select input,
  exactly one device sees `/CS` asserted on a command edge.
- Model consequence: the devices have separate bank/open-row/refresh state,
  but share one command path and one 16-bit DQ bus. A normal command targets
  one chip, not both chips as a 32-bit-wide rank.

## 130 MHz qualification boundary

- Primary project source: MiSTer-devel,
  [`MemTest_MiSTer/README.md`](https://github.com/MiSTer-devel/MemTest_MiSTer/blob/master/README.md)
  (accessed 2026-09-07).
- Project criterion: the README says a board should pass at least the 130 MHz
  clock test; it recommends a 10-minute quick test or 1–2 hours for greater
  confidence.
- Model consequence: results at or below 130 MHz are tagged
  `board_guaranteed` for compatibility with the exploration terminology.
  Strictly, this tag means **within the official MiSTer board acceptance-test
  boundary**. It is not a component-datasheet guarantee of signal integrity,
  PCB manufacture, assembly quality, temperature, voltage, or every clone.

## Component timing

- Primary source: Alliance Memory,
  [AS4C32M16SB Rev 1.4 (June 2024)](https://www.alliancememory.com/wp-content/uploads/AllianceMemory_512M_SDRAM_Bdie_AS4C32M16SB-7TXN-6TIN-7BIN__Rev1.4_June2024NK.pdf),
  especially the organization/pin tables and AC timing table 16. The simulator
  uses the `-7` speed-grade values listed in the README.
- The component's CL3 minimum clock period is 7 ns (142.857... MHz maximum).
  Therefore an exact 143 MHz run has a 6.993 ns period and is intentionally
  tagged as exploratory overclock, even though it differs by only about
  0.1 percent.
