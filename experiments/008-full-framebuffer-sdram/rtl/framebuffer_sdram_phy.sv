`timescale 1ns/1ps

// Temporary single physical SDRAM-pin owner. Client selection remains the
// one-shot policy for now, but no client is connected directly to board pins.
module framebuffer_sdram_phy (
    input logic clk, input logic capture_clk, input logic producer_owns, input logic reader_owns,
    input logic [12:0] producer_a, input logic [1:0] producer_ba,
    input logic producer_cke, producer_ncs, producer_nras, producer_ncas, producer_nwe,
    input logic producer_dqml, producer_dqmh, input logic [15:0] producer_dq_out, input logic producer_dq_oe,
    input logic [12:0] reader_a, input logic [1:0] reader_ba,
    input logic reader_cke, reader_ncs, reader_nras, reader_ncas, reader_nwe,
    input logic reader_dqml, reader_dqmh, input logic [15:0] reader_dq_out, input logic reader_dq_oe,
    (* useioff = 1 *) output logic [15:0] dq_capture,
    output logic [12:0] SDRAM_A, output logic [1:0] SDRAM_BA,
    output logic SDRAM_CKE, SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE,
    output logic SDRAM_DQML, SDRAM_DQMH, inout wire [15:0] SDRAM_DQ,
    output logic SDRAM_CLK
);
    logic [15:0] dq_out;
    logic dq_oe;

    // Explicitly instantiate the Cyclone V input-DDIO primitive. Quartus 17
    // did not honour inferred I/O-register placement here; this primitive is
    // the unambiguous physical capture boundary for the reader data stream.
    altddio_in #(
        .intended_device_family("Cyclone V"),
        .invert_input_clocks("OFF"),
        .lpm_hint("UNUSED"),
        .lpm_type("altddio_in"),
        .power_up_high("OFF"),
        .width(16)
    ) dq_input_ddr (
        .datain(SDRAM_DQ), .inclock(capture_clk), .inclocken(1'b1),
        .aclr(1'b0), .aset(1'b0), .dataout_h(), .dataout_l(dq_capture)
    );

    always_comb begin
        SDRAM_A='0; SDRAM_BA='0; SDRAM_CKE=0; SDRAM_nCS=1; SDRAM_nRAS=1;
        SDRAM_nCAS=1; SDRAM_nWE=1; SDRAM_DQML=1; SDRAM_DQMH=1; dq_out='0; dq_oe=0;
        if (producer_owns) begin
            SDRAM_A=producer_a; SDRAM_BA=producer_ba; SDRAM_CKE=producer_cke; SDRAM_nCS=producer_ncs;
            SDRAM_nRAS=producer_nras; SDRAM_nCAS=producer_ncas; SDRAM_nWE=producer_nwe;
            SDRAM_DQML=producer_dqml; SDRAM_DQMH=producer_dqmh; dq_out=producer_dq_out; dq_oe=producer_dq_oe;
        end else if (reader_owns) begin
            SDRAM_A=reader_a; SDRAM_BA=reader_ba; SDRAM_CKE=reader_cke; SDRAM_nCS=reader_ncs;
            SDRAM_nRAS=reader_nras; SDRAM_nCAS=reader_ncas; SDRAM_nWE=reader_nwe;
            SDRAM_DQML=reader_dqml; SDRAM_DQMH=reader_dqmh; dq_out=reader_dq_out; dq_oe=reader_dq_oe;
        end
    end
    assign SDRAM_DQ = dq_oe ? dq_out : 16'hzzzz;
    framebuffer_sdram_clock_forward clock_forward (.clk, .SDRAM_CLK);
endmodule
