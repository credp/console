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
    parameter longint unsigned REFRESH_INTERVAL_CYCLES = (SDRAM_FREQ_HZ * 70) / 10_000_000
) (
    input  logic        clk,
    input  logic        reset,

    output logic        sdram_init_done,
    output logic        sdram_error,
    output logic        write_completion,

    output logic [10:0] producer_pixel_x,
    output logic [9:0]  producer_line_y,
    output logic [7:0]  producer_frame_index,
    output logic        producer_stalled_waiting_for_free_line,
    output logic        producer_stalled_waiting_for_writer,
    output logic        writer_busy,
    output logic        writer_error,

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
    output logic        SDRAM_CLK
);
    logic producer_reset;
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

    // The producer begins only after the backend has completed SDRAM setup.
    assign producer_reset = reset || !sdram_init_done;
    assign write_completion = completion_valid && completion_ready;

    framebuffer_producer_write_path #(
        .FRAMEBUFFER_WIDTH(FRAMEBUFFER_WIDTH),
        .FRAMEBUFFER_HEIGHT(FRAMEBUFFER_HEIGHT),
        .LINE_ADDR_WIDTH(LINE_ADDR_WIDTH),
        .WRITE_CHUNK_WORDS(WRITE_CHUNK_WORDS)
    ) producer (
        .clk(clk),
        .reset(producer_reset),
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
        .writer_error(writer_error)
    );

    framebuffer_bl8_write_backend #(
        .SDRAM_FREQ_HZ(SDRAM_FREQ_HZ),
        .POWERUP_US(SDRAM_POWERUP_US),
        .REFRESH_INTERVAL_CYCLES(REFRESH_INTERVAL_CYCLES)
    ) backend (
        .clk(clk),
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
        .SDRAM_A(SDRAM_A),
        .SDRAM_BA(SDRAM_BA),
        .SDRAM_CKE(SDRAM_CKE),
        .SDRAM_nCS(SDRAM_nCS),
        .SDRAM_nRAS(SDRAM_nRAS),
        .SDRAM_nCAS(SDRAM_nCAS),
        .SDRAM_nWE(SDRAM_nWE),
        .SDRAM_DQML(SDRAM_DQML),
        .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_DQ(SDRAM_DQ),
        .SDRAM_CLK(SDRAM_CLK)
    );
endmodule
