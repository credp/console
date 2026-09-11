derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
create_generated_clock \
    -name sdram_clk_out \
    -source emu|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk \
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

set_multicycle_path 2 -setup \
    -from [get_ports {SDRAM_DQ[*]}] \
    -to [get_registers {*phy_sdram_dq_in*}]

