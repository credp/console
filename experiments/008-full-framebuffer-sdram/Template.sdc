derive_pll_clocks
derive_clock_uncertainty

# reset enters the SDRAM domain only through the first stage of this explicit
# two-register synchronizer. The second stage and all functional SDRAM logic
# remain timed normally.
set_false_path -to [get_keepers {*framebuffer_producer_bl8_sdram_path*|sdram_reset_sync_meta}]
set_false_path -to [get_keepers {*framebuffer_bl8_write_backend*|reset_sync_meta}]

# core specific constraints
