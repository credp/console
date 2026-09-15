`timescale 1ns/1ps

module framebuffer_line_read_sequencer #(
    parameter integer FRAMEBUFFER_WIDTH = 1280,
    // Keep the default page-contained for the agg23 continuous-burst reader.
    parameter integer READ_CHUNK_WORDS = 256
) (
    input  logic        clk,
    input  logic        reset,

    input  logic        start_line_valid,
    output logic        start_line_ready,
    input  logic [9:0]  start_line_y,

    output logic        fill_valid,
    input  logic        fill_ready,
    output logic [15:0] fill_pixel,
    output logic [9:0]  fill_line_y,

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

    output logic        busy,
    output logic        line_done,
    output logic        error
);
    localparam integer CHUNKS_PER_LINE = FRAMEBUFFER_WIDTH / READ_CHUNK_WORDS;
    localparam integer CHUNK_INDEX_WIDTH = (CHUNKS_PER_LINE > 1) ? $clog2(CHUNKS_PER_LINE) : 1;

    typedef enum logic [2:0] {
        READER_IDLE,
        READER_REQUEST_CHUNK,
        READER_STREAM_WORDS,
        READER_WAIT_FOR_COMPLETION,
        READER_LINE_DONE
    } reader_state_t;

    reader_state_t state;

    logic [9:0] framebuffer_line_y;
    logic [CHUNK_INDEX_WIDTH-1:0] chunk_index;
    logic [15:0] word_index_in_chunk;
    logic [6:0] chunk_index_for_address;
    logic [7:0] expected_completion_tag;
    logic last_word_in_chunk;
    logic last_chunk_in_line;

    assign busy = (state != READER_IDLE);
    assign start_line_ready = (state == READER_IDLE);

    assign req_valid = (state == READER_REQUEST_CHUNK);
    assign req_write = 1'b0;
    assign req_words = 16'(READ_CHUNK_WORDS);
    assign req_tag = expected_completion_tag;

    assign read_ready = (state == READER_STREAM_WORDS) && fill_ready;
    assign fill_valid = (state == READER_STREAM_WORDS) && read_valid;
    assign fill_pixel = read_data;
    assign fill_line_y = framebuffer_line_y;

    assign completion_ready = (state == READER_WAIT_FOR_COMPLETION);
    assign line_done = (state == READER_LINE_DONE);

    assign chunk_index_for_address = 7'(chunk_index);
    assign expected_completion_tag = {1'b0, 7'(chunk_index)};
    assign last_word_in_chunk = (word_index_in_chunk == 16'(READ_CHUNK_WORDS - 1));
    assign last_chunk_in_line = (chunk_index == CHUNK_INDEX_WIDTH'(CHUNKS_PER_LINE - 1));

    framebuffer_line_chunk_address #(
        .FRAMEBUFFER_WIDTH(FRAMEBUFFER_WIDTH),
        .WRITE_CHUNK_WORDS(READ_CHUNK_WORDS)
    ) address (
        .framebuffer_line_y(framebuffer_line_y),
        .chunk_index(chunk_index_for_address),
        .byte_address(req_byte_address)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= READER_IDLE;
            framebuffer_line_y <= '0;
            chunk_index <= '0;
            word_index_in_chunk <= '0;
            error <= 1'b0;
        end else begin
            case (state)
                READER_IDLE: begin
                    if (start_line_valid && start_line_ready) begin
                        framebuffer_line_y <= start_line_y;
                        chunk_index <= '0;
                        word_index_in_chunk <= '0;
                        state <= READER_REQUEST_CHUNK;
                    end
                end

                READER_REQUEST_CHUNK: begin
                    if (req_valid && req_ready) begin
                        word_index_in_chunk <= '0;
                        state <= READER_STREAM_WORDS;
                    end
                end

                READER_STREAM_WORDS: begin
                    if (read_valid && read_ready) begin
                        if (last_word_in_chunk) begin
                            state <= READER_WAIT_FOR_COMPLETION;
                        end else begin
                            word_index_in_chunk <= word_index_in_chunk + 1'b1;
                        end
                    end
                end

                READER_WAIT_FOR_COMPLETION: begin
                    if (completion_valid && completion_ready) begin
                        if (completion_error ||
                            completion_tag != expected_completion_tag ||
                            completion_words != 16'(READ_CHUNK_WORDS)) begin
                            error <= 1'b1;
                        end

                        if (last_chunk_in_line) begin
                            state <= READER_LINE_DONE;
                        end else begin
                            chunk_index <= chunk_index + 1'b1;
                            word_index_in_chunk <= '0;
                            state <= READER_REQUEST_CHUNK;
                        end
                    end
                end

                READER_LINE_DONE: begin
                    state <= READER_IDLE;
                end

                default: begin
                    state <= READER_IDLE;
                end
            endcase
        end
    end

    initial begin
        if (FRAMEBUFFER_WIDTH < 1) $error("framebuffer width must be positive");
        if (READ_CHUNK_WORDS < 1) $error("read chunk size must be positive");
        if ((FRAMEBUFFER_WIDTH % READ_CHUNK_WORDS) != 0)
            $error("v1 read sequencer requires chunks to divide the line evenly");
        if (CHUNKS_PER_LINE > 128) $error("request tag only leaves seven bits for the chunk index");
    end
endmodule
