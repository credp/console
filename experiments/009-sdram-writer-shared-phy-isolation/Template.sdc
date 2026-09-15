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

# SDRAM returns read data after its forwarded-clock edge. At 142.857 MHz the
# 5.4 ns board/device return budget cannot fit the same-cycle PHY capture;
# capture is intentionally on the following phased clock opportunity. This is
# the narrow two-cycle relationship characterized in experiment 006.a.
set_multicycle_path 2 -setup \
    -from [get_ports {SDRAM_DQ[*]}] \
    -to [get_registers {*framebuffer_sdram_phy*|*dq_input_ddr*}]

# reset enters the SDRAM domain only through the first stage of this explicit
# two-register synchronizer. The second stage and all functional SDRAM logic
# remain timed normally.
set_false_path -to [get_keepers {*framebuffer_producer_bl8_sdram_path*|sdram_reset_sync_meta}]
set_false_path -to [get_keepers {*framebuffer_bl8_write_backend*|reset_sync_meta}]
set_false_path -to [get_keepers {*sdram_reset_sync_meta}]
set_false_path -to [get_keepers {*sdram_reset_meta}]

# Producer line ownership crosses between the machine and SDRAM clocks with a
# bundled-data/toggle protocol. The source holds the line number and ownership
# state stable until the destination has observed the synchronized toggle.
# Only these named first-stage capture registers are asynchronous; their second
# stages and all logic which consumes them are still checked by TimeQuest.
set_false_path -to [get_keepers {*framebuffer_producer_lines_dual_clock*|line_ready_sync_1[*]}]
set_false_path -to [get_keepers {*framebuffer_producer_lines_dual_clock*|line_ready_y_sync_1[*]}]
set_false_path -to [get_keepers {*framebuffer_producer_lines_dual_clock*|line_release_sync_1[*]}]
set_false_path -to [get_keepers {*framebuffer_producer_lines_dual_clock*|line_accept_sync_1}]

# SDRAM initialization completion uses the same explicit two-register crossing
# on its way back to the machine clock.
set_false_path -to [get_keepers {*framebuffer_producer_bl8_sdram_path*|sdram_init_done_machine_sync_1}]

# Sticky write/read verification state crosses only into the diagnostic-video
# colour register. The second register is local to clk_video and remains timed.
set_false_path -to [get_keepers {*verify_state_meta[*]}]

# core specific constraints
