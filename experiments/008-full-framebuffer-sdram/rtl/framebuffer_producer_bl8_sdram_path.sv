`timescale 1ns/1ps

// Complete producer-side hardware path. Framebuffer line ownership remains in
// the producer blocks; SDRAM command timing remains in the BL8 backend.
module framebuffer_producer_bl8_sdram_path #(
    parameter integer FRAMEBUFFER_WIDTH = 1280,
    parameter integer FRAMEBUFFER_HEIGHT = 720,
    parameter integer LINE_ADDR_WIDTH = 11,
    parameter integer WRITE_CHUNK_WORDS = 1280,
    parameter longint unsigned SDRAM_FREQ_HZ = 100_000_000,
    parameter integer SDRAM_POWERUP_US = 200,
    parameter longint unsigned REFRESH_INTERVAL_CYCLES = (SDRAM_FREQ_HZ * 70) / 10_000_000,
    parameter integer STOP_AFTER_ONE_FRAME = 0,
    // Keep the proven direct-PHY arrangement for standalone writer tests.
    // The experiment top disables it and sends this protocol bundle to the
    // sole shared physical PHY instead.
    parameter integer USE_INTERNAL_PHY = 1
) (
    input  logic        machine_clk,
    input  logic        sdram_clk,
    input  logic        reset,

    output logic        sdram_init_done,
    output logic        sdram_error,
    output logic        write_completion,
    output logic        frame_write_complete,

    output logic [10:0] producer_pixel_x,
    output logic [9:0]  producer_line_y,
    output logic [7:0]  producer_frame_index,
    output logic        producer_stalled_waiting_for_free_line,
    output logic        producer_stalled_waiting_for_writer,
    output logic        writer_busy,
    output logic        writer_error,
    output logic [2:0]  writer_error_reason,

    output logic [12:0] protocol_a,
    output logic [1:0]  protocol_ba,
    output logic        protocol_cke, protocol_ncs, protocol_nras, protocol_ncas, protocol_nwe,
    output logic        protocol_dqml, protocol_dqmh,
    output logic [15:0] protocol_dq_out,
    output logic        protocol_dq_oe,

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
    output logic [15:0] sdram_dq_out,
    output logic        sdram_dq_oe
);
    logic machine_producer_reset;
    logic sdram_producer_reset;
    (* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *) logic sdram_reset_sync_meta = 1'b1;
    (* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *) logic sdram_reset_sync = 1'b1;
    logic sdram_init_done_machine_sync_1;
    logic sdram_init_done_machine_sync_2;
    logic req_valid;
    logic req_ready;
    logic req_write;
    logic [26:0] req_byte_address;
    logic [15:0] req_words;
    logic [7:0] req_tag;
    logic write_valid;
    logic write_ready;
    logic [15:0] write_data;
    logic [1:0] write_byte_enable;
    logic completion_valid;
    logic completion_ready;
    logic [7:0] completion_tag;
    logic [15:0] completion_words;
    logic completion_error;
    logic [12:0] phy_a;
    logic [1:0] phy_ba;
    logic phy_cke, phy_ncs, phy_nras, phy_ncas, phy_nwe;
    logic phy_dqml, phy_dqmh, phy_dq_oe;
    logic [15:0] phy_dq_out;
    logic line_write_complete;
    logic [9:0] line_write_complete_y;
    logic frame_write_complete_latched;

    // init_done is generated in the SDRAM clock domain. Its synchronized copy
    // is the only reset-release information used by machine-clock logic.
    always_ff @(posedge machine_clk) begin
        if (reset) begin
            sdram_init_done_machine_sync_1 <= 1'b0;
            sdram_init_done_machine_sync_2 <= 1'b0;
        end else begin
            sdram_init_done_machine_sync_1 <= sdram_init_done;
            sdram_init_done_machine_sync_2 <= sdram_init_done_machine_sync_1;
        end
    end

    // status[0] and the board reset originate outside sdram_clk. Only this
    // synchronizer sees that asynchronous reset request on the SDRAM side.
    always_ff @(posedge sdram_clk) begin
        sdram_reset_sync_meta <= reset;
        sdram_reset_sync <= sdram_reset_sync_meta;
    end

    assign machine_producer_reset = reset || !sdram_init_done_machine_sync_2;
    assign sdram_producer_reset = sdram_reset_sync || !sdram_init_done;
    assign write_completion = completion_valid && completion_ready;

    framebuffer_producer_write_path_dual_clock #(
        .FRAMEBUFFER_WIDTH(FRAMEBUFFER_WIDTH),
        .FRAMEBUFFER_HEIGHT(FRAMEBUFFER_HEIGHT),
        .LINE_ADDR_WIDTH(LINE_ADDR_WIDTH),
        .WRITE_CHUNK_WORDS(WRITE_CHUNK_WORDS),
        .STOP_AFTER_ONE_FRAME(STOP_AFTER_ONE_FRAME)
    ) producer (
        .machine_clk(machine_clk),
        .sdram_clk(sdram_clk),
        .machine_reset(machine_producer_reset),
        .sdram_reset(sdram_producer_reset),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_write(req_write),
        .req_byte_address(req_byte_address),
        .req_words(req_words),
        .req_tag(req_tag),
        .write_valid(write_valid),
        .write_ready(write_ready),
        .write_data(write_data),
        .write_byte_enable(write_byte_enable),
        .completion_valid(completion_valid),
        .completion_ready(completion_ready),
        .completion_tag(completion_tag),
        .completion_words(completion_words),
        .completion_error(completion_error),
        .producer_pixel_x(producer_pixel_x),
        .producer_line_y(producer_line_y),
        .producer_frame_index(producer_frame_index),
        .producer_stalled_waiting_for_free_line(producer_stalled_waiting_for_free_line),
        .producer_stalled_waiting_for_writer(producer_stalled_waiting_for_writer),
        .writer_busy(writer_busy),
        .writer_error(writer_error),
        .writer_error_reason(writer_error_reason),
        .line_write_complete(line_write_complete),
        .line_write_complete_y(line_write_complete_y)
    );

    // The final line has completed its final SDRAM request. Keep that fact
    // asserted for the one-shot handoff, which observes it from machine_clk.
    // A one-sdram-clock pulse would be too short to cross that boundary.
    always_ff @(posedge sdram_clk) begin
        if (sdram_reset_sync) begin
            frame_write_complete_latched <= 1'b0;
        end else if (line_write_complete &&
                     line_write_complete_y == 10'(FRAMEBUFFER_HEIGHT - 1)) begin
            frame_write_complete_latched <= 1'b1;
        end
    end
    assign frame_write_complete = frame_write_complete_latched;

    framebuffer_bl8_write_backend #(
        .SDRAM_FREQ_HZ(SDRAM_FREQ_HZ),
        .POWERUP_US(SDRAM_POWERUP_US),
        .REFRESH_INTERVAL_CYCLES(REFRESH_INTERVAL_CYCLES)
    ) backend (
        .clk(sdram_clk),
        .reset(reset),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_write(req_write),
        .req_byte_address(req_byte_address),
        .req_words(req_words),
        .req_tag(req_tag),
        .write_valid(write_valid),
        .write_ready(write_ready),
        .write_data(write_data),
        .write_byte_enable(write_byte_enable),
        .read_valid(),
        .read_ready(1'b1),
        .read_data(),
        .completion_valid(completion_valid),
        .completion_ready(completion_ready),
        .completion_tag(completion_tag),
        .completion_words(completion_words),
        .completion_error(completion_error),
        .init_done(sdram_init_done),
        .diagnostic_error(sdram_error),
        .phy_a(phy_a),
        .phy_ba(phy_ba),
        .phy_cke(phy_cke),
        .phy_ncs(phy_ncs),
        .phy_nras(phy_nras),
        .phy_ncas(phy_ncas),
        .phy_nwe(phy_nwe),
        .phy_dqml(phy_dqml),
        .phy_dqmh(phy_dqmh),
        .phy_dq_out(phy_dq_out),
        .phy_dq_oe(phy_dq_oe)
    );

    assign protocol_a = phy_a;
    assign protocol_ba = phy_ba;
    assign protocol_cke = phy_cke;
    assign protocol_ncs = phy_ncs;
    assign protocol_nras = phy_nras;
    assign protocol_ncas = phy_ncas;
    assign protocol_nwe = phy_nwe;
    assign protocol_dqml = phy_dqml;
    assign protocol_dqmh = phy_dqmh;
    assign protocol_dq_out = phy_dq_out;
    assign protocol_dq_oe = phy_dq_oe;

    generate
        if (USE_INTERNAL_PHY) begin : g_direct_writer_phy
            framebuffer_sdram_write_phy phy (
                .clk(sdram_clk),
                .protocol_a(phy_a), .protocol_ba(phy_ba), .protocol_cke(phy_cke),
                .protocol_ncs(phy_ncs), .protocol_nras(phy_nras), .protocol_ncas(phy_ncas),
                .protocol_nwe(phy_nwe), .protocol_dqml(phy_dqml), .protocol_dqmh(phy_dqmh),
                .protocol_dq_out(phy_dq_out), .protocol_dq_oe(phy_dq_oe),
                .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA), .SDRAM_CKE(SDRAM_CKE),
                .SDRAM_nCS(SDRAM_nCS), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
                .SDRAM_nWE(SDRAM_nWE), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
                .SDRAM_DQ(SDRAM_DQ), .SDRAM_CLK(SDRAM_CLK),
                .SDRAM_DQ_OUT(sdram_dq_out), .SDRAM_DQ_OE(sdram_dq_oe)
            );
        end else begin : g_shared_writer_phy
            // These compatibility ports are deliberately inert in shared-PHY
            // mode. The protocol bundle above is the only path to board pins.
            assign SDRAM_A = '0;
            assign SDRAM_BA = '0;
            assign SDRAM_CKE = 1'b0;
            assign SDRAM_nCS = 1'b1;
            assign SDRAM_nRAS = 1'b1;
            assign SDRAM_nCAS = 1'b1;
            assign SDRAM_nWE = 1'b1;
            assign SDRAM_DQML = 1'b1;
            assign SDRAM_DQMH = 1'b1;
            assign SDRAM_DQ = 16'hzzzz;
            assign SDRAM_CLK = 1'b0;
            assign sdram_dq_out = phy_dq_out;
            assign sdram_dq_oe = phy_dq_oe;
        end
    endgenerate
endmodule
