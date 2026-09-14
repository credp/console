`timescale 1ns/1ps

// Thin consumer composition: request/read transfer on one side, scanout line
// ownership on the other. A later SDRAM backend connects to the request ports.
module framebuffer_consumer_read_path #(
    parameter integer FRAMEBUFFER_WIDTH = 1280,
    parameter integer LINE_ADDR_WIDTH = 11,
    parameter integer READ_CHUNK_WORDS = 1280
) (
    input  logic                         clk,
    input  logic                         reset,

    input  logic                         start_line_valid,
    output logic                         start_line_ready,
    input  logic [9:0]                   start_line_y,

    input  logic                         output_line_advance,
    output logic                         output_line_valid,
    output logic                         output_buffer,
    output logic [9:0]                   output_line_y,
    input  logic [LINE_ADDR_WIDTH-1:0]   scanout_x,
    output logic [15:0]                  scanout_pixel,
    output logic                         scanout_pixel_valid,

    output logic                         req_valid,
    input  logic                         req_ready,
    output logic                         req_write,
    output logic [26:0]                  req_byte_address,
    output logic [15:0]                  req_words,
    output logic [7:0]                   req_tag,
    input  logic                         read_valid,
    output logic                         read_ready,
    input  logic [15:0]                  read_data,
    input  logic                         completion_valid,
    output logic                         completion_ready,
    input  logic [7:0]                   completion_tag,
    input  logic [15:0]                  completion_words,
    input  logic                         completion_error,

    output logic                         reader_busy,
    output logic                         reader_error,
    output logic                         consumer_waiting_for_output_release,
    output logic                         consumer_overwrite_error
);
    logic fill_valid;
    logic fill_ready;
    logic [15:0] fill_pixel;
    logic [9:0] fill_line_y;
    logic line_done;

    framebuffer_line_read_sequencer #(
        .FRAMEBUFFER_WIDTH(FRAMEBUFFER_WIDTH),
        .READ_CHUNK_WORDS(READ_CHUNK_WORDS)
    ) line_reader (
        .clk(clk),
        .reset(reset),
        .start_line_valid(start_line_valid),
        .start_line_ready(start_line_ready),
        .start_line_y(start_line_y),
        .fill_valid(fill_valid),
        .fill_ready(fill_ready),
        .fill_pixel(fill_pixel),
        .fill_line_y(fill_line_y),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_write(req_write),
        .req_byte_address(req_byte_address),
        .req_words(req_words),
        .req_tag(req_tag),
        .read_valid(read_valid),
        .read_ready(read_ready),
        .read_data(read_data),
        .completion_valid(completion_valid),
        .completion_ready(completion_ready),
        .completion_tag(completion_tag),
        .completion_words(completion_words),
        .completion_error(completion_error),
        .busy(reader_busy),
        .line_done(line_done),
        .error(reader_error)
    );

    framebuffer_consumer_lines #(
        .FRAMEBUFFER_WIDTH(FRAMEBUFFER_WIDTH),
        .LINE_ADDR_WIDTH(LINE_ADDR_WIDTH)
    ) line_consumer (
        .clk(clk),
        .reset(reset),
        .fill_ready(fill_ready),
        .fill_valid(fill_valid),
        .fill_pixel(fill_pixel),
        .fill_line_y(fill_line_y),
        .output_line_advance(output_line_advance),
        .output_line_valid(output_line_valid),
        .output_buffer(output_buffer),
        .output_line_y(output_line_y),
        .scanout_x(scanout_x),
        .scanout_pixel(scanout_pixel),
        .scanout_pixel_valid(scanout_pixel_valid),
        .waiting_for_output_release(consumer_waiting_for_output_release),
        .overwrite_error(consumer_overwrite_error)
    );
endmodule
