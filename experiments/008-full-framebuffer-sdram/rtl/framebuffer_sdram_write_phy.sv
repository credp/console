`timescale 1ns/1ps

// Pin-facing half of the write-only SDRAM PHY. Keeping these registers next
// to the top-level pins gives Quartus 17 a clear opportunity to pack them
// into I/O cells, as in the experiment 006.a frequency characterization.
module framebuffer_sdram_write_phy (
    input  logic        clk,
    input  logic [12:0] protocol_a,
    input  logic [1:0]  protocol_ba,
    input  logic        protocol_cke,
    input  logic        protocol_ncs,
    input  logic        protocol_nras,
    input  logic        protocol_ncas,
    input  logic        protocol_nwe,
    input  logic        protocol_dqml,
    input  logic        protocol_dqmh,
    input  logic [15:0] protocol_dq_out,
    input  logic        protocol_dq_oe,

    output logic [12:0] SDRAM_A,
    output logic [1:0]  SDRAM_BA,
    output logic        SDRAM_CKE,
    output logic        SDRAM_nCS,
    output logic        SDRAM_nRAS,
    output logic        SDRAM_nCAS,
    output logic        SDRAM_nWE,
    output logic        SDRAM_DQML,
    output logic        SDRAM_DQMH,
    inout  wire  [15:0] SDRAM_DQ,
    output logic        SDRAM_CLK,
    // Registered bundle for the later shared-pin mux. The direct DQ port is
    // retained during the producer-only and one-shot bring-up stages.
    output logic [15:0] SDRAM_DQ_OUT,
    output logic        SDRAM_DQ_OE
);
    logic [15:0] sdram_dq_out_q;
    logic sdram_dq_oe_q;

    // The output registers launch a half SDRAM cycle before the inverted
    // forwarded clock samples the command and write data at the SDRAM pins.
    always_ff @(posedge clk) begin
        SDRAM_A <= protocol_a;
        SDRAM_BA <= protocol_ba;
        SDRAM_CKE <= protocol_cke;
        SDRAM_nCS <= protocol_ncs;
        SDRAM_nRAS <= protocol_nras;
        SDRAM_nCAS <= protocol_ncas;
        SDRAM_nWE <= protocol_nwe;
        SDRAM_DQML <= protocol_dqml;
        SDRAM_DQMH <= protocol_dqmh;
        sdram_dq_out_q <= protocol_dq_out;
        sdram_dq_oe_q <= protocol_dq_oe;
    end

    assign SDRAM_DQ_OUT = sdram_dq_out_q;
    assign SDRAM_DQ_OE = sdram_dq_oe_q;
    assign SDRAM_DQ = SDRAM_DQ_OE ? SDRAM_DQ_OUT : 16'hzzzz;

    // The board-level clock DDIO now lives after the producer/reader pin mux.
    // This retained raw clock marker keeps the local interface useful in the
    // standalone producer test without creating a second physical DDIO.
    assign SDRAM_CLK = ~clk;
endmodule
