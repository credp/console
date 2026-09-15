`timescale 1ns/1ps

// Reader-side composition for the temporary fast-SDRAM / slow-scanout mode.
// Only complete framebuffer lines cross into scanout through the dual-clock
// M10K pair; SDRAM requests and cache traffic stay entirely in fill_clk.
module framebuffer_consumer_read_path_dual_clock #(
    parameter integer FRAMEBUFFER_WIDTH = 1280,
    parameter integer FRAMEBUFFER_HEIGHT = 720,
    parameter integer LINE_ADDR_WIDTH = 11,
    parameter integer READ_CHUNK_WORDS = 256
) (
    input logic fill_clk, input logic fill_reset,
    input logic scanout_clk, input logic scanout_reset,
    input logic scanout_start, input logic scanout_line_advance,
    input logic [LINE_ADDR_WIDTH-1:0] scanout_x,
    output logic [15:0] scanout_pixel, output logic scanout_pixel_valid,
    output logic [9:0] scanout_line_y, output logic scanout_underflow,
    output logic [15:0] scanout_skipped_lines, output logic consumer_primed,

    output logic req_valid, input logic req_ready, output logic req_write,
    output logic [26:0] req_byte_address, output logic [15:0] req_words,
    output logic [7:0] req_tag, input logic read_valid, output logic read_ready,
    input logic [15:0] read_data, input logic completion_valid,
    output logic completion_ready, input logic [7:0] completion_tag,
    input logic [15:0] completion_words, input logic completion_error,
    output logic reader_busy, output logic reader_error,
    output logic consumer_waiting_for_output_release,
    output logic consumer_overwrite_error, output logic [9:0] next_framebuffer_line_y,
    output logic scheduler_waiting_for_scanout, output logic scheduler_timing_error
);
    logic fill_valid, fill_ready, line_done;
    logic [15:0] fill_pixel;
    logic [9:0] fill_line_y, start_line_y;
    logic start_line_valid, start_line_ready, fill_line_advance;

    framebuffer_consumer_line_scheduler #(
        .FRAMEBUFFER_HEIGHT(FRAMEBUFFER_HEIGHT)
    ) line_scheduler (
        .clk(fill_clk), .reset(fill_reset), .start_line_valid, .start_line_ready,
        .start_line_y, .line_fetch_done(line_done),
        .scanout_line_advance(fill_line_advance),
        .output_line_advance(), .next_framebuffer_line_y,
        .waiting_for_scanout(scheduler_waiting_for_scanout),
        .timing_error(scheduler_timing_error)
    );

    framebuffer_line_read_sequencer #(
        .FRAMEBUFFER_WIDTH(FRAMEBUFFER_WIDTH), .READ_CHUNK_WORDS(READ_CHUNK_WORDS)
    ) line_reader (
        .clk(fill_clk), .reset(fill_reset), .start_line_valid, .start_line_ready,
        .start_line_y, .fill_valid, .fill_ready, .fill_pixel, .fill_line_y,
        .req_valid, .req_ready, .req_write, .req_byte_address, .req_words, .req_tag,
        .read_valid, .read_ready, .read_data, .completion_valid, .completion_ready,
        .completion_tag, .completion_words, .completion_error, .busy(reader_busy),
        .line_done, .error(reader_error)
    );

    framebuffer_consumer_lines_dual_clock #(
        .FRAMEBUFFER_WIDTH(FRAMEBUFFER_WIDTH), .LINE_ADDR_WIDTH(LINE_ADDR_WIDTH)
    ) line_buffers (
        .fill_clk, .fill_reset, .fill_ready, .fill_valid, .fill_pixel, .fill_line_y,
        .fill_line_advance, .primed(consumer_primed),
        .waiting_for_output_release(consumer_waiting_for_output_release),
        .overwrite_error(consumer_overwrite_error), .scanout_clk, .scanout_reset,
        .scanout_start, .scanout_line_advance, .scanout_x, .scanout_pixel,
        .scanout_pixel_valid, .scanout_line_y, .scanout_underflow,
        .scanout_skipped_lines
    );
endmodule
