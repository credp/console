# agg23 SDRAM burst controller

`agg23_sdram_burst.sv` is an unmodified local copy of the MIT-licensed
`sdram_burst.sv` from `agg23/sdram-controller`. Its license header is retained
at the start of the source file.

This controller performs continuous page reads through a single native port:

- pulse `p0_rd_req` once when `p0_available` is asserted;
- consume every asserted `p0_data_available` cycle from `p0_q`;
- assert `p0_end_burst_req` with the final wanted word to end a chunk early;
- wait for `p0_ready` before issuing the next page or chunk.

The consumer adapter must split a framebuffer request at 1024-word SDRAM page
boundaries. It must also provide the controller's expected captured SDRAM DQ
input before this source is connected to board pins. No top-level integration
uses this source yet.
