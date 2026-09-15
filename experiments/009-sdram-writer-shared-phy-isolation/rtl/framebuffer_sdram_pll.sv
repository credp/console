// Quartus 17 generated-PLL style wrapper for the proven experiment 006.a
// command-clock point. This is a local copy of the clock choice, not a link
// to another experiment: 008 can be built and characterized independently.
module framebuffer_sdram_pll (
    input  wire refclk,
    input  wire rst,
    output wire outclk,
    output wire capture_clk,
    output wire locked
);
    altera_pll #(
        .fractional_vco_multiplier("false"),
        .reference_clock_frequency("50.0 MHz"),
        .operation_mode("direct"),
        .number_of_clocks(2),
        .output_clock_frequency0("142.857000 MHz"),
        .phase_shift0("0 ps"),
        .duty_cycle0(50),
        // Experiment 006.a swept this phase at 142.857 MHz. 2000 ps was the
        // characterized capture point meeting both DQ setup and hold.
        .output_clock_frequency1("142.857000 MHz"),
        .phase_shift1("2000 ps"),
        .duty_cycle1(50),
        .pll_type("General"),
        .pll_subtype("General")
    ) pll (
        .rst(rst),
        .outclk({capture_clk, outclk}),
        .locked(locked),
        .fboutclk(),
        .fbclk(1'b0),
        .refclk(refclk)
    );
endmodule
