`timescale 1ns/1ps

// One-shot, headless SDRAM readback verification. It deliberately reuses the
// same finite request interface as scanout, but compares every returned word
// against the frame-zero producer pattern before scanout is enabled.
module framebuffer_sdram_frame_verifier #(
    parameter integer FRAMEBUFFER_WIDTH = 1280,
    parameter integer FRAMEBUFFER_HEIGHT = 720,
    parameter integer READ_CHUNK_WORDS = 256
) (
    input  logic        clk,
    input  logic        reset,
    output logic        req_valid,
    input  logic        req_ready,
    output logic        req_write,
    output logic [26:0] req_byte_address,
    output logic [15:0] req_words,
    output logic [7:0]  req_tag,
    input  logic        read_valid,
    output logic        read_ready,
    input  logic [15:0] read_data,
    input  logic        completion_valid,
    output logic        completion_ready,
    input  logic [7:0]  completion_tag,
    input  logic [15:0] completion_words,
    input  logic        completion_error,
    output logic        done,
    output logic        passed,
    output logic        failed,
    output logic [31:0] mismatch_count
);
    localparam integer CHUNKS_PER_LINE = FRAMEBUFFER_WIDTH / READ_CHUNK_WORDS;
    localparam integer CHUNK_INDEX_WIDTH = (CHUNKS_PER_LINE > 1) ? $clog2(CHUNKS_PER_LINE) : 1;
    typedef enum logic [1:0] { REQUEST, RECEIVE, COMPLETE, FINISHED } state_t;
    state_t state;
    logic [9:0] line_y;
    logic [CHUNK_INDEX_WIDTH-1:0] chunk_index;
    logic [15:0] word_index;
    logic chunk_mismatch, error_seen;
    logic [10:0] expected_x;
    logic [15:0] expected_pixel;
    logic last_word, last_chunk, last_line;

    assign expected_x = ({8'd0, chunk_index} << $clog2(READ_CHUNK_WORDS)) + word_index[10:0];
    assign last_word = (word_index == 16'(READ_CHUNK_WORDS - 1));
    assign last_chunk = (chunk_index == CHUNK_INDEX_WIDTH'(CHUNKS_PER_LINE - 1));
    assign last_line = (line_y == 10'(FRAMEBUFFER_HEIGHT - 1));

    framebuffer_pattern_pixel #(.FRAMEBUFFER_WIDTH(FRAMEBUFFER_WIDTH), .FRAMEBUFFER_HEIGHT(FRAMEBUFFER_HEIGHT)) expected (
        .x(expected_x), .y(line_y), .frame_index(8'd0), .pixel(expected_pixel)
    );
    framebuffer_line_chunk_address #(.FRAMEBUFFER_WIDTH(FRAMEBUFFER_WIDTH), .WRITE_CHUNK_WORDS(READ_CHUNK_WORDS)) address (
        .framebuffer_line_y(line_y), .chunk_index(7'(chunk_index)), .byte_address(req_byte_address)
    );

    assign req_valid = (state == REQUEST);
    assign req_write = 1'b0;
    assign req_words = 16'(READ_CHUNK_WORDS);
    assign req_tag = {1'b1, 7'(chunk_index)};
    assign read_ready = (state == RECEIVE);
    assign completion_ready = (state == COMPLETE);
    assign done = (state == FINISHED);

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= REQUEST;
            line_y <= '0;
            chunk_index <= '0;
            word_index <= '0;
            chunk_mismatch <= 1'b0;
            error_seen <= 1'b0;
            mismatch_count <= '0;
            passed <= 1'b0;
            failed <= 1'b0;
        end else begin
            case (state)
                REQUEST: if (req_ready) begin
                    word_index <= '0;
                    chunk_mismatch <= 1'b0;
                    state <= RECEIVE;
                end
                RECEIVE: if (read_valid) begin
                    if (read_data != expected_pixel) begin
                        chunk_mismatch <= 1'b1;
                        if (!(&mismatch_count)) mismatch_count <= mismatch_count + 1'b1;
                    end
                    if (last_word)
                        state <= COMPLETE;
                    else
                        word_index <= word_index + 1'b1;
                end
                COMPLETE: if (completion_valid) begin
                    if (completion_error || completion_tag != {1'b1, 7'(chunk_index)} ||
                        completion_words != 16'(READ_CHUNK_WORDS) || chunk_mismatch)
                        error_seen <= 1'b1;
                    if (last_chunk && last_line) begin
                        failed <= error_seen || completion_error || chunk_mismatch ||
                                  completion_tag != {1'b1, 7'(chunk_index)} ||
                                  completion_words != 16'(READ_CHUNK_WORDS) || mismatch_count != 0;
                        passed <= !(error_seen || completion_error || chunk_mismatch ||
                                    completion_tag != {1'b1, 7'(chunk_index)} ||
                                    completion_words != 16'(READ_CHUNK_WORDS) || mismatch_count != 0);
                        state <= FINISHED;
                    end else if (last_chunk) begin
                        line_y <= line_y + 1'b1;
                        chunk_index <= '0;
                        state <= REQUEST;
                    end else begin
                        chunk_index <= chunk_index + 1'b1;
                        state <= REQUEST;
                    end
                end
                FINISHED: begin end
                default: state <= REQUEST;
            endcase
        end
    end

    initial begin
        if ((FRAMEBUFFER_WIDTH % READ_CHUNK_WORDS) != 0)
            $error("frame verifier requires chunks to divide the line width");
        if (CHUNKS_PER_LINE > 128)
            $error("frame verifier request tag has only seven chunk bits");
    end
endmodule
