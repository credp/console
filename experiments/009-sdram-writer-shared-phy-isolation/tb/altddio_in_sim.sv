`timescale 1ns/1ps

// Functional model of the Cyclone V input-DDIO primitive used by the shared
// PHY. Keeping the rising and falling samples distinct is important: a
// combinational stub previously let a dataout_l/dataout_h wiring error pass
// every integration test even though it selected the wrong physical edge.
module altddio_in #(
    parameter intended_device_family = "Cyclone V",
    parameter invert_input_clocks = "OFF",
    parameter lpm_hint = "UNUSED",
    parameter lpm_type = "altddio_in",
    parameter power_up_high = "OFF",
    parameter integer width = 1
) (
    input  wire [width-1:0] datain,
    input  wire             inclock,
    input  wire             inclocken,
    input  wire             aclr,
    input  wire             aset,
    output logic [width-1:0] dataout_h,
    output logic [width-1:0] dataout_l
);
    always @(posedge inclock or posedge aclr or posedge aset) begin
        if (aclr)
            dataout_h <= '0;
        else if (aset)
            dataout_h <= '1;
        else if (inclocken)
            dataout_h <= datain;
    end

    always @(negedge inclock or posedge aclr or posedge aset) begin
        if (aclr)
            dataout_l <= '0;
        else if (aset)
            dataout_l <= '1;
        else if (inclocken)
            dataout_l <= datain;
    end
endmodule
