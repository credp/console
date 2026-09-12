derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
set sdram_clock_source [get_pins {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
if {[get_collection_size $sdram_clock_source] != 1} {
    error "Expected exactly one SDRAM PLL clock source"
}
create_generated_clock \
    -name sdram_clk_out \
    -source $sdram_clock_source \
    -divide_by 1 \
    -invert \
    [get_ports {SDRAM_CLK}]

set sdram_output_ports [get_ports {
    SDRAM_A[*] SDRAM_BA[*] SDRAM_CKE
    SDRAM_nCS SDRAM_nRAS SDRAM_nCAS SDRAM_nWE
    SDRAM_DQML SDRAM_DQMH SDRAM_DQ[*]
}]

set_output_delay \
    -clock [get_clocks sdram_clk_out] \
    -max 1.5 \
    $sdram_output_ports

set_output_delay \
    -clock [get_clocks sdram_clk_out] \
    -min -0.8 \
    $sdram_output_ports

set_input_delay \
    -clock [get_clocks sdram_clk_out] \
    -max 5.4 \
    [get_ports {SDRAM_DQ[*]}]

set_input_delay \
    -clock [get_clocks sdram_clk_out] \
    -min 2.5 \
    [get_ports {SDRAM_DQ[*]}]

# At the 20 MHz baseline, capture is on the next controller rising edge,
# 25 ns after the nominal inverted SDRAM edge. No extra-cycle exception.
