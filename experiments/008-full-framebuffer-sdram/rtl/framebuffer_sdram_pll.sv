// Quartus 17 generated-PLL style wrapper for the proven experiment 006.a
// command-clock point. This is a local copy of the clock choice, not a link
// to another experiment: 008 can be built and characterized independently.
module framebuffer_sdram_pll (
    input  wire refclk,
    input  wire rst,
    output wire outclk,
    output wire locked
);
    altera_pll #(
        .fractional_vco_multiplier("false"),
        .reference_clock_frequency("50.0 MHz"),
        .operation_mode("direct"),
        .number_of_clocks(1),
        .output_clock_frequency0("142.857000 MHz"),
        .phase_shift0("0 ps"),
        .duty_cycle0(50),
        .pll_type("General"),
        .pll_subtype("General")
    ) pll (
        .rst(rst),
        .outclk(outclk),
        .locked(locked),
        .fboutclk(),
        .fbclk(1'b0),
        .refclk(refclk)
    );
endmodule
