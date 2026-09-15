`timescale 1ns/1ps

// Local composition of the MIT agg23 continuous-page reader and the
// framebuffer burst cache. The cache owns the native port; its client sees
// only finite, backpressured framebuffer reads.
module framebuffer_agg23_read_backend #(
    // Round up from the 142.857 MHz SDRAM clock so the MIT controller's
    // integer cycle delays are conservative rather than optimistic.
    parameter integer SDRAM_FREQ_MHZ = 143,
    parameter integer PHY_DQ_CAPTURE_STAGES = 0,
    // The shared PHY registers commands after client selection. That delays
    // the physical READ command, and hence the SDRAM response, without adding
    // another register to DQ itself. Keep this latency separate from capture
    // latency so the cache-valid marker remains aligned with the captured word.
    parameter integer PHY_COMMAND_LAUNCH_STAGES = 0
) (
    input  logic        clk,
    // Clock used by the PHY's DQ input register. It may be phase shifted from
    // clk, but has the same frequency.
    input  logic        capture_clk,
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
    logic [15:0] p0_q_captured_1;
    logic p0_data_available_captured_1, p0_data_available_captured_2;
    logic p0_data_available_captured_3;
    logic [15:0] cache_p0_q;
    logic cache_p0_data_available;
    logic [1:0] sdram_dqm;
    logic [15:0] controller_dq_out;
    logic controller_dq_oe;

    // Keep the first local DQ handoff on the PHY capture clock. This gives the
    // I/O register a complete 142.857 MHz period to reach ordinary fabric.
    // Moving directly to clk here leaves only the 5 ns phase relationship and
    // cannot route reliably across the spread-out SDRAM DQ pins. No reset is
    // needed: the cache ignores this data until the delayed valid bit arrives.
    always_ff @(posedge capture_clk)
        p0_q_captured_1 <= sdram_dq_in;

    // The MIT controller's predicted-valid marker remains in its own clock
    // domain. The fixed PLL phase makes the following data crossing related
    // and timed; this is not an asynchronous control crossing.
    always_ff @(posedge clk) begin
        if (reset) begin
            p0_data_available_captured_1 <= 1'b0;
            p0_data_available_captured_2 <= 1'b0;
            p0_data_available_captured_3 <= 1'b0;
        end else begin
            p0_data_available_captured_1 <= p0_data_available;
            p0_data_available_captured_2 <= p0_data_available_captured_1;
            p0_data_available_captured_3 <= p0_data_available_captured_2;
        end
    end

    // p0_q_captured_1 is the backend's normal handoff register. When a shared
    // PHY input register is present, its output feeds this same handoff; do not
    // add another data register here or the returned stream moves by one word.
    // The valid pipeline below accounts for both the physical capture and the
    // later physical command launch.
    assign cache_p0_q = p0_q_captured_1;
    assign cache_p0_data_available = PHY_COMMAND_LAUNCH_STAGES ?
        (PHY_DQ_CAPTURE_STAGES ? p0_data_available_captured_3 :
                                 p0_data_available_captured_2) :
        (PHY_DQ_CAPTURE_STAGES ? p0_data_available_captured_2 :
                                 p0_data_available_captured_1);

    framebuffer_agg23_burst_cache #(
        .P0_DATA_PIPELINE_STAGES(1 + PHY_DQ_CAPTURE_STAGES +
                                 PHY_COMMAND_LAUNCH_STAGES)
    ) cache (
        .clk, .reset, .init_done,
        .req_valid, .req_ready, .req_write, .req_byte_address, .req_words,
        .req_tag, .read_valid, .read_ready, .read_data, .completion_valid,
        .completion_ready, .completion_tag, .completion_words,
        .completion_error, .p0_addr, .p0_rd_req, .p0_end_burst_req,
        .p0_q(cache_p0_q), .p0_available, .p0_ready,
        .p0_data_available(cache_p0_data_available)
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
        .SDRAM_DQ_IN(sdram_dq_in), .SDRAM_DQ_OUT(controller_dq_out),
        .SDRAM_DQ_OE(controller_dq_oe), .SDRAM_A, .SDRAM_DQM(sdram_dqm), .SDRAM_BA,
        .SDRAM_nCS, .SDRAM_nWE, .SDRAM_nRAS, .SDRAM_nCAS, .SDRAM_CKE,
        .SDRAM_CLK
    );

    // This composition issues reads only. Do not let the copied generic
    // controller retain a physical DQ-drive path that this client cannot use.
    assign sdram_dq_out = '0;
    assign sdram_dq_oe = 1'b0;
    assign {SDRAM_DQMH, SDRAM_DQML} = sdram_dqm;

    initial begin
        if (PHY_DQ_CAPTURE_STAGES < 0 || PHY_DQ_CAPTURE_STAGES > 1)
            $error("read backend supports zero or one external DQ capture stage");
        if (PHY_COMMAND_LAUNCH_STAGES < 0 || PHY_COMMAND_LAUNCH_STAGES > 1)
            $error("read backend supports zero or one external command launch stage");
    end
endmodule
