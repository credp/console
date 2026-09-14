`timescale 1ns/1ps

module framebuffer_line_chunk_address #(
    parameter integer FRAMEBUFFER_WIDTH = 1280,
    parameter integer WRITE_CHUNK_WORDS = 1280
) (
    input  logic [9:0]  framebuffer_line_y,
    input  logic [6:0]  chunk_index,

    output logic [26:0] byte_address
);
    logic [26:0] line_start_word;
    logic [26:0] chunk_start_word;
    logic [26:0] word_address;

    always_comb begin
        line_start_word = 27'(framebuffer_line_y) * 27'(FRAMEBUFFER_WIDTH);
        chunk_start_word = 27'(chunk_index) * 27'(WRITE_CHUNK_WORDS);
        word_address = line_start_word + chunk_start_word;
        byte_address = word_address << 1;
    end

    initial begin
        if (FRAMEBUFFER_WIDTH < 1) $error("framebuffer width must be positive");
        if (WRITE_CHUNK_WORDS < 1) $error("write chunk size must be positive");
    end
endmodule
