`timescale 1ns/1ps

module framebuffer_line_write_sequencer #(
    parameter integer FRAMEBUFFER_WIDTH = 1280,
    parameter integer LINE_ADDR_WIDTH = 11,
    parameter integer WRITE_CHUNK_WORDS = 1280
) (
    input  logic                       clk,
    input  logic                       reset,

    input  logic                       line_ready_valid,
    output logic                       line_ready_accept,
    input  logic                       line_ready_buffer,
    input  logic [9:0]                 line_ready_y,

    output logic                       line_release_valid,
    output logic                       line_release_buffer,
    // Pulses only after every chunk of the active line has completed. This is
    // the safe observation point for the temporary producer-to-reader cut.
    output logic                       line_write_complete,
    output logic [9:0]                 line_write_complete_y,

    output logic                       writer_read_buffer,
    output logic [LINE_ADDR_WIDTH-1:0] writer_read_x,
    input  logic [15:0]                writer_read_pixel,

    output logic                       req_valid,
    input  logic                       req_ready,
    output logic                       req_write,
    output logic [26:0]                req_byte_address,
    output logic [15:0]                req_words,
    output logic [7:0]                 req_tag,

    output logic                       write_valid,
    input  logic                       write_ready,
    output logic [15:0]                write_data,
    output logic [1:0]                 write_byte_enable,

    input  logic                       completion_valid,
    output logic                       completion_ready,
    input  logic [7:0]                 completion_tag,
    input  logic [15:0]                completion_words,
    input  logic                       completion_error,

    output logic                       busy,
    output logic                       error,
    // Sticky completion-contract detail for board bring-up:
    // bit 0: backend declared an error, bit 1: tag mismatch, bit 2: count mismatch.
    output logic [2:0]                 error_reason
);
    localparam integer CHUNKS_PER_LINE = FRAMEBUFFER_WIDTH / WRITE_CHUNK_WORDS;
    localparam integer CHUNK_INDEX_WIDTH = (CHUNKS_PER_LINE > 1) ? $clog2(CHUNKS_PER_LINE) : 1;

    typedef enum logic [2:0] {
        WRITER_IDLE,
        WRITER_REQUEST_CHUNK,
        WRITER_SET_READ_ADDRESS,
        WRITER_WAIT_FOR_BRAM,
        WRITER_CAPTURE_WORD,
        WRITER_STREAM_WORD,
        WRITER_WAIT_FOR_COMPLETION,
        WRITER_RELEASE_LINE
    } writer_state_t;

    writer_state_t state;

    logic active_buffer;
    logic [9:0] framebuffer_line_y;
    logic [CHUNK_INDEX_WIDTH-1:0] chunk_index;
    logic [15:0] word_index_in_chunk;
    logic [15:0] write_data_q;
    logic [6:0] chunk_index_for_address;
    logic [LINE_ADDR_WIDTH-1:0] chunk_start_x;
    logic [7:0] expected_completion_tag;
    logic last_word_in_chunk;
    logic last_chunk_in_line;

    assign busy = (state != WRITER_IDLE);
    assign line_ready_accept = (state == WRITER_IDLE) && line_ready_valid;

    assign req_valid = (state == WRITER_REQUEST_CHUNK);
    assign req_write = 1'b1;
    assign chunk_index_for_address = 7'(chunk_index);
    assign req_words = 16'(WRITE_CHUNK_WORDS);
    assign req_tag = expected_completion_tag;

    assign write_valid = (state == WRITER_STREAM_WORD);
    assign write_data = write_data_q;
    assign write_byte_enable = 2'b11;

    assign completion_ready = (state == WRITER_WAIT_FOR_COMPLETION);

    assign line_release_valid = (state == WRITER_RELEASE_LINE);
    assign line_release_buffer = active_buffer;
    assign line_write_complete = line_release_valid;
    assign line_write_complete_y = framebuffer_line_y;

    assign chunk_start_x = LINE_ADDR_WIDTH'(chunk_index * WRITE_CHUNK_WORDS);
    assign expected_completion_tag = {active_buffer, 7'(chunk_index)};
    assign last_word_in_chunk = (word_index_in_chunk == 16'(WRITE_CHUNK_WORDS - 1));
    assign last_chunk_in_line = (chunk_index == CHUNK_INDEX_WIDTH'(CHUNKS_PER_LINE - 1));

    framebuffer_line_chunk_address #(
        .FRAMEBUFFER_WIDTH(FRAMEBUFFER_WIDTH),
        .WRITE_CHUNK_WORDS(WRITE_CHUNK_WORDS)
    ) address (
        .framebuffer_line_y(framebuffer_line_y),
        .chunk_index(chunk_index_for_address),
        .byte_address(req_byte_address)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= WRITER_IDLE;
            active_buffer <= 1'b0;
            framebuffer_line_y <= '0;
            chunk_index <= '0;
            word_index_in_chunk <= '0;
            writer_read_buffer <= 1'b0;
            writer_read_x <= '0;
            write_data_q <= 16'h0000;
            error <= 1'b0;
            error_reason <= 3'b000;
        end else begin
            case (state)
                WRITER_IDLE: begin
                    if (line_ready_valid && line_ready_accept) begin
                        active_buffer <= line_ready_buffer;
                        framebuffer_line_y <= line_ready_y;
                        chunk_index <= '0;
                        word_index_in_chunk <= '0;
                        writer_read_buffer <= line_ready_buffer;
                        state <= WRITER_REQUEST_CHUNK;
                    end
                end

                WRITER_REQUEST_CHUNK: begin
                    if (req_valid && req_ready) begin
                        word_index_in_chunk <= '0;
                        state <= WRITER_SET_READ_ADDRESS;
                    end
                end

                WRITER_SET_READ_ADDRESS: begin
                    writer_read_buffer <= active_buffer;
                    writer_read_x <= chunk_start_x + LINE_ADDR_WIDTH'(word_index_in_chunk);
                    state <= WRITER_WAIT_FOR_BRAM;
                end

                WRITER_WAIT_FOR_BRAM: begin
                    state <= WRITER_CAPTURE_WORD;
                end

                WRITER_CAPTURE_WORD: begin
                    write_data_q <= writer_read_pixel;
                    state <= WRITER_STREAM_WORD;
                end

                WRITER_STREAM_WORD: begin
                    if (write_valid && write_ready) begin
                        if (last_word_in_chunk) begin
                            state <= WRITER_WAIT_FOR_COMPLETION;
                        end else begin
                            word_index_in_chunk <= word_index_in_chunk + 1'b1;
                            state <= WRITER_SET_READ_ADDRESS;
                        end
                    end
                end

                WRITER_WAIT_FOR_COMPLETION: begin
                    if (completion_valid && completion_ready) begin
                        if (completion_error ||
                            completion_tag != expected_completion_tag ||
                            completion_words != 16'(WRITE_CHUNK_WORDS)) begin
                            error <= 1'b1;
                            error_reason[0] <= error_reason[0] | completion_error;
                            error_reason[1] <= error_reason[1] |
                                               (completion_tag != expected_completion_tag);
                            error_reason[2] <= error_reason[2] |
                                               (completion_words != 16'(WRITE_CHUNK_WORDS));
                        end

                        if (last_chunk_in_line) begin
                            state <= WRITER_RELEASE_LINE;
                        end else begin
                            chunk_index <= chunk_index + 1'b1;
                            word_index_in_chunk <= '0;
                            state <= WRITER_REQUEST_CHUNK;
                        end
                    end
                end

                WRITER_RELEASE_LINE: begin
                    state <= WRITER_IDLE;
                end

                default: begin
                    state <= WRITER_IDLE;
                end
            endcase
        end
    end

    initial begin
        if (FRAMEBUFFER_WIDTH < 1) $error("framebuffer width must be positive");
        if (WRITE_CHUNK_WORDS < 1) $error("write chunk size must be positive");
        if ((FRAMEBUFFER_WIDTH % WRITE_CHUNK_WORDS) != 0)
            $error("v1 write sequencer requires chunks to divide the line evenly");
        if (CHUNKS_PER_LINE > 128) $error("request tag only leaves seven bits for the chunk index");
        if ((1 << LINE_ADDR_WIDTH) < FRAMEBUFFER_WIDTH) $error("line address width is too small");
    end
endmodule
