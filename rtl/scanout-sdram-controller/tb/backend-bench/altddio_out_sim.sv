`timescale 1ns/1ps

module altddio_out #(
    parameter extend_oe_disable = "OFF",
    parameter intended_device_family = "Cyclone V",
    parameter invert_output = "OFF",
    parameter lpm_hint = "UNUSED",
    parameter lpm_type = "altddio_out",
    parameter oe_reg = "UNREGISTERED",
    parameter power_up_high = "OFF",
    parameter width = 1
) (
    input logic datain_h,
    input logic datain_l,
    input logic outclock,
    output logic dataout,
    input logic oe,
    input logic outclocken
);
    always_comb begin
        if (!oe || !outclocken)
            dataout = 1'b0;
        else
            dataout = outclock ? datain_h : datain_l;
    end
endmodule
