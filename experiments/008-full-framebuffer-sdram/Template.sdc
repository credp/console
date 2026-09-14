derive_pll_clocks
derive_clock_uncertainty

# The single board-level SDRAM clock is an inverted, forwarded copy of the
# 142.857 MHz framebuffer PLL. These are the source/sink constraints proven
# in experiment 006.b, updated for this experiment's PLL hierarchy.
set sdram_clock_source [get_pins {emu|sdram_pll|pll|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
if {[get_collection_size $sdram_clock_source] != 1} {
    error "Expected exactly one framebuffer SDRAM PLL clock source"
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

set_output_delay -clock [get_clocks sdram_clk_out] -max 1.5 $sdram_output_ports
set_output_delay -clock [get_clocks sdram_clk_out] -min -0.8 $sdram_output_ports
set_input_delay -clock [get_clocks sdram_clk_out] -max 5.4 [get_ports {SDRAM_DQ[*]}]
set_input_delay -clock [get_clocks sdram_clk_out] -min 2.5 [get_ports {SDRAM_DQ[*]}]

# reset enters the SDRAM domain only through the first stage of this explicit
# two-register synchronizer. The second stage and all functional SDRAM logic
# remain timed normally.
set_false_path -to [get_keepers {*framebuffer_producer_bl8_sdram_path*|sdram_reset_sync_meta}]
set_false_path -to [get_keepers {*framebuffer_bl8_write_backend*|reset_sync_meta}]
set_false_path -to [get_keepers {*sdram_reset_sync_meta}]
set_false_path -to [get_keepers {*framebuffer_ready_sync_meta}]

# core specific constraints
