// Experiment 006.a build point. Change only these two definitions between
// characterization builds and record the resulting RBF and hardware result.
// Select exactly one. Supported frequencies are 20, 100, 120, 130, and the
// exploratory (not device-rated) 143 MHz point.
// `define SDRAM_FREQ_20
// `define SDRAM_FREQ_100
// `define SDRAM_FREQ_120
// `define SDRAM_FREQ_130
// `define SDRAM_FREQ_142
// `define SDRAM_FREQ_143
 `define SDRAM_FREQ_150
// `define SDRAM_FREQ_153

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
 `define SDRAM_FREQ_HZ 142_857_000
 `define SDRAM_PLL_FREQUENCY "142.857000 MHz"
 `define SDRAM_CAPTURE_PHASE "2000 ps"
`elsif SDRAM_FREQ_143
 `define SDRAM_FREQ_HZ 143_000_000
 `define SDRAM_PLL_FREQUENCY "143.000000 MHz"
`elsif SDRAM_FREQ_150
 `define SDRAM_FREQ_HZ 150_000_000
 `define SDRAM_PLL_FREQUENCY "150.000000 MHz"
// `define SDRAM_CAPTURE_PHASE "1905 ps" // not legal
// `define SDRAM_CAPTURE_PHASE "2083 ps" // legal // VIOLATES
// `define SDRAM_CAPTURE_PHASE "2500 ps" // legal  // violates
//`define SDRAM_CAPTURE_PHASE "1250 ps" // legal // violated
 `define SDRAM_CAPTURE_PHASE "1667 ps" // legal // 
`elsif SDRAM_FREQ_153
 `define SDRAM_FREQ_HZ 153_000_000
 `define SDRAM_PLL_FREQUENCY "153.000000 MHz"
 `define SDRAM_CAPTURE_PHASE "1867 ps"
`else
 `error "Select an SDRAM frequency in experiment_config.vh"
`endif

// Offset from the controller clock used by the capture register. The MiSTer
// reference forwards an inverted SDRAM clock, so 0 ps here samples half an
// SDRAM period after the external SDRAM rising edge.
//`define SDRAM_CAPTURE_PHASE "2000 ps"
//`define SDRAM_CAPTURE_PHASE "1905 ps"
//`define SDRAM_CAPTURE_PHASE "2000 ps"


// Notes on SDRAM timing and capture phase
// SDRAM_FREQ_HZ 142_857_000 matches with SDRAM_CAPTURE_PHASE "2000 ps" and meets timing for capture and hold

// We know that these boards work at 151MHz and 152MHz respectively. In order
// to validate the closure of timing at these high frequencies, I will test
// my model by building for 150Mhz with phase around 28% (1905) and 153Mhz with phase around 28% (1867).