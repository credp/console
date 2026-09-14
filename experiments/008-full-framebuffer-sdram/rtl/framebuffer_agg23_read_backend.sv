`timescale 1ns/1ps

// Local composition of the MIT agg23 continuous-page reader and the
// framebuffer burst cache. The cache owns the native port; its client sees
// only finite, backpressured framebuffer reads.
module framebuffer_agg23_read_backend #(
    // Round up from the 142.857 MHz SDRAM clock so the MIT controller's
    // integer cycle delays are conservative rather than optimistic.
    parameter integer SDRAM_FREQ_MHZ = 143
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        req_valid,
    output logic        req_ready,
    input  logic        req_write,
    input  logic [26:0] req_byte_address,
    input  logic [15:0] req_words,
    input  logic [7:0]  req_tag,
    output logic        read_valid,
    input  logic        read_ready,
    output logic [15:0] read_data,
    output logic        completion_valid,
    input  logic        completion_ready,
    output logic [7:0]  completion_tag,
    output logic [15:0] completion_words,
    output logic        completion_error,
    output logic        init_done,
    output logic [12:0] SDRAM_A,
    output logic [1:0]  SDRAM_BA,
    output logic        SDRAM_CKE,
    output logic        SDRAM_nCS,
    output logic        SDRAM_nRAS,
    output logic        SDRAM_nCAS,
    output logic        SDRAM_nWE,
    output logic        SDRAM_DQML,
    output logic        SDRAM_DQMH,
    input  logic [15:0] sdram_dq_in,
    output logic [15:0] sdram_dq_out,
    output logic        sdram_dq_oe,
    output logic        SDRAM_CLK
);
    logic [24:0] p0_addr;
    logic p0_rd_req;
    logic p0_end_burst_req;
    logic [15:0] p0_q;
    logic p0_available;
    logic p0_ready;
    logic p0_data_available;
    logic [1:0] sdram_dqm;

    framebuffer_agg23_burst_cache cache (
        .clk, .reset, .init_done,
        .req_valid, .req_ready, .req_write, .req_byte_address, .req_words,
        .req_tag, .read_valid, .read_ready, .read_data, .completion_valid,
        .completion_ready, .completion_tag, .completion_words,
        .completion_error, .p0_addr, .p0_rd_req, .p0_end_burst_req, .p0_q,
        .p0_available, .p0_ready, .p0_data_available
    );

    sdram_burst #(
        .CLOCK_SPEED_MHZ(SDRAM_FREQ_MHZ),
        .CAS_LATENCY(3),
        .WRITE_BURST(0)
    ) controller (
        .clk, .reset, .init_complete(init_done),
        .p0_addr, .p0_data(16'h0000), .p0_byte_en(2'b00), .p0_q,
        .p0_wr_req(1'b0), .p0_rd_req, .p0_end_burst_req,
        .p0_available, .p0_ready, .p0_data_available,
        .SDRAM_DQ_IN(sdram_dq_in), .SDRAM_DQ_OUT(sdram_dq_out),
        .SDRAM_DQ_OE(sdram_dq_oe), .SDRAM_A, .SDRAM_DQM(sdram_dqm), .SDRAM_BA,
        .SDRAM_nCS, .SDRAM_nWE, .SDRAM_nRAS, .SDRAM_nCAS, .SDRAM_CKE,
        .SDRAM_CLK
    );

    assign {SDRAM_DQMH, SDRAM_DQML} = sdram_dqm;
endmodule
