`timescale 1ns/1ps

// The only DDIO primitive driving the physical SDRAM clock pin. Both temporary
// clients use clk_sdram, so the clock runs continuously while command/DQ
// ownership changes at a transaction boundary.
module framebuffer_sdram_clock_forward (
    input logic clk,
    output logic SDRAM_CLK
);
    altddio_out #(
        .extend_oe_disable("OFF"), .intended_device_family("Cyclone V"),
        .invert_output("OFF"), .lpm_hint("UNUSED"), .lpm_type("altddio_out"),
        .oe_reg("UNREGISTERED"), .power_up_high("OFF"), .width(1)
    ) sdramclk_ddr (
        .datain_h(1'b0), .datain_l(1'b1), .outclock(clk), .dataout(SDRAM_CLK),
        .oe(1'b1), .outclocken(1'b1)
    );
endmodule
