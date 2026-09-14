`timescale 1ns/1ps

module framebuffer_producer_write_path #(
    parameter integer FRAMEBUFFER_WIDTH = 1280,
    parameter integer FRAMEBUFFER_HEIGHT = 720,
    parameter integer LINE_ADDR_WIDTH = 11,
    parameter integer WRITE_CHUNK_WORDS = 1280
) (
    input  logic       clk,
    input  logic       reset,

    output logic       req_valid,
    input  logic       req_ready,
    output logic       req_write,
    output logic [26:0] req_byte_address,
    output logic [15:0] req_words,
    output logic [7:0] req_tag,

    output logic       write_valid,
    input  logic       write_ready,
    output logic [15:0] write_data,
    output logic [1:0] write_byte_enable,

    input  logic       completion_valid,
    output logic       completion_ready,
    input  logic [7:0] completion_tag,
    input  logic [15:0] completion_words,
    input  logic       completion_error,

    output logic [10:0] producer_pixel_x,
    output logic [9:0]  producer_line_y,
    output logic [7:0]  producer_frame_index,
    output logic        producer_stalled_waiting_for_free_line,
    output logic        producer_stalled_waiting_for_writer,
    output logic        writer_busy,
    output logic        writer_error
);
    logic line_ready_valid;
    logic line_ready_accept;
    logic line_ready_buffer;
    logic [9:0] line_ready_y;
    logic line_release_valid;
    logic line_release_buffer;
    logic writer_read_buffer;
    logic [LINE_ADDR_WIDTH-1:0] writer_read_x;
    logic [15:0] writer_read_pixel;

    framebuffer_producer_lines #(
        .FRAMEBUFFER_WIDTH(FRAMEBUFFER_WIDTH),
        .FRAMEBUFFER_HEIGHT(FRAMEBUFFER_HEIGHT),
        .LINE_ADDR_WIDTH(LINE_ADDR_WIDTH)
    ) line_producer (
        .clk(clk),
        .reset(reset),
        .line_ready_valid(line_ready_valid),
        .line_ready_accept(line_ready_accept),
        .line_ready_buffer(line_ready_buffer),
        .line_ready_y(line_ready_y),
        .line_release_valid(line_release_valid),
        .line_release_buffer(line_release_buffer),
        .writer_read_buffer(writer_read_buffer),
        .writer_read_x(writer_read_x),
        .writer_read_pixel(writer_read_pixel),
        .producer_x(producer_pixel_x),
        .producer_y(producer_line_y),
        .frame_index(producer_frame_index),
        .stalled_waiting_for_free_line(producer_stalled_waiting_for_free_line),
        .stalled_waiting_for_writer(producer_stalled_waiting_for_writer)
    );

    framebuffer_line_write_sequencer #(
        .FRAMEBUFFER_WIDTH(FRAMEBUFFER_WIDTH),
        .LINE_ADDR_WIDTH(LINE_ADDR_WIDTH),
        .WRITE_CHUNK_WORDS(WRITE_CHUNK_WORDS)
    ) line_writer (
        .clk(clk),
        .reset(reset),
        .line_ready_valid(line_ready_valid),
        .line_ready_accept(line_ready_accept),
        .line_ready_buffer(line_ready_buffer),
        .line_ready_y(line_ready_y),
        .line_release_valid(line_release_valid),
        .line_release_buffer(line_release_buffer),
        .writer_read_buffer(writer_read_buffer),
        .writer_read_x(writer_read_x),
        .writer_read_pixel(writer_read_pixel),
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
        .busy(writer_busy),
        .error(writer_error)
    );
endmodule
