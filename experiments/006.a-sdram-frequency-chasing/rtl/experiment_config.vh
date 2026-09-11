// Experiment 006.a build point. Change only these two definitions between
// characterization builds and record the resulting RBF and hardware result.
// Select exactly one. Supported frequencies are 20, 100, 120, 130, and the
// exploratory (not device-rated) 143 MHz point.
// `define SDRAM_FREQ_20
// `define SDRAM_FREQ_100
// `define SDRAM_FREQ_120
// `define SDRAM_FREQ_130
`define SDRAM_FREQ_142
// `define SDRAM_FREQ_143

`ifdef SDRAM_FREQ_20
 `define SDRAM_FREQ_HZ 20_000_000
 `define SDRAM_PLL_FREQUENCY "20.000000 MHz"
`elsif SDRAM_FREQ_100
 `define SDRAM_FREQ_HZ 100_000_000
 `define SDRAM_PLL_FREQUENCY "100.000000 MHz"
`elsif SDRAM_FREQ_120
 `define SDRAM_FREQ_HZ 120_000_000
 `define SDRAM_PLL_FREQUENCY "120.000000 MHz"
`elsif SDRAM_FREQ_130
 `define SDRAM_FREQ_HZ 130_000_000
 `define SDRAM_PLL_FREQUENCY "130.000000 MHz"
`elsif SDRAM_FREQ_142
 `define SDRAM_FREQ_HZ 142_000_000
 `define SDRAM_PLL_FREQUENCY "142.857000 MHz"
`elsif SDRAM_FREQ_143
 `define SDRAM_FREQ_HZ 143_000_000
 `define SDRAM_PLL_FREQUENCY "143.000000 MHz"
`else
 `error "Select an SDRAM frequency in experiment_config.vh"
`endif

// Offset from the controller clock used by the capture register. The MiSTer
// reference forwards an inverted SDRAM clock, so 0 ps here samples half an
// SDRAM period after the external SDRAM rising edge.
`define SDRAM_CAPTURE_PHASE "0 ps"
