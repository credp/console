module line_ping_pong_capture #(
    parameter integer LINE_WORDS = 1280,
    parameter integer SOURCE_LINE_CYCLES = 4096,
    parameter integer ADDR_WIDTH = 11,
    parameter integer MAX_REQUEST_WORDS = 1280,
    parameter integer DRAIN_WARN_CYCLES = 4095
) (
    input  logic        clk,
    input  logic        reset,

    input  logic [10:0] video_x,
    input  logic [9:0]  video_y,
    input  logic        video_de,
    output logic [15:0] video_pixel,
    output logic        video_buffer,

    output logic        req_valid,
    input  logic        req_ready,
    output logic        req_write,
    output logic [26:0] req_byte_address,
    output logic [15:0] req_words,
    output logic [7:0]  req_tag,

    output logic        write_valid,
    input  logic        write_ready,
    output logic [15:0] write_data,
    output logic [1:0]  write_byte_enable,

    input  logic        completion_valid,
    output logic        completion_ready,
    input  logic [7:0]  completion_tag,
    input  logic [15:0] completion_words,
    input  logic        completion_error,

    output logic [31:0] source_lines_generated,
    output logic [31:0] sdram_lines_submitted,
    output logic [31:0] sdram_lines_completed,
    output logic        reuse_before_drain_error,
    output logic [15:0] worst_line_drain_cycles,
    output logic [15:0] current_line_drain_cycles
);
    localparam integer CHUNKS_PER_LINE = LINE_WORDS / MAX_REQUEST_WORDS;
    localparam integer CHUNK_WORDS = MAX_REQUEST_WORDS;
    localparam integer CHUNK_INDEX_WIDTH = (CHUNKS_PER_LINE > 1) ? $clog2(CHUNKS_PER_LINE) : 1;

    initial begin
        if (LINE_WORDS != 1280) $fatal(1, "experiment 007 expects 1280-word lines");
        if ((LINE_WORDS % MAX_REQUEST_WORDS) != 0) $fatal(1, "line must split evenly");
        if (CHUNKS_PER_LINE > 128) $fatal(1, "tag format only leaves 7 bits for chunk");
    end

    logic [15:0] line0 [0:LINE_WORDS-1];
    logic [15:0] line1 [0:LINE_WORDS-1];

    logic fill_buffer;
    logic display_buffer;
    logic [ADDR_WIDTH-1:0] fill_x;
    logic [11:0] source_h;
    logic [9:0] source_y;
    logic [15:0] frame_number;
    logic line_valid;
    logic [1:0] pending_drain;
    logic [15:0] drain_cycles [0:1];
    logic [9:0] completed_y [0:1];

    typedef enum logic [1:0] {CAP_IDLE, CAP_REQ, CAP_WRITE, CAP_WAIT_COMPLETE} cap_state_t;
    cap_state_t cap_state;
    logic cap_buffer;
    logic [9:0] cap_line_y;
    logic [CHUNK_INDEX_WIDTH-1:0] cap_chunk;
    wire [6:0] cap_chunk_tag = 7'(cap_chunk);
    logic [ADDR_WIDTH-1:0] cap_word;
    logic [15:0] cap_drain_cycles;

    wire source_active = (source_h < 12'(LINE_WORDS));
    wire fill_last = (source_h == 12'(SOURCE_LINE_CYCLES - 1));
    wire [15:0] generated_pixel = {
        fill_x[10:6] + frame_number[4:0],
        source_y[8:3] ^ frame_number[5:0],
        fill_x[5:1] ^ source_y[7:3]
    };

    wire [ADDR_WIDTH-1:0] video_addr = video_x[ADDR_WIDTH-1:0];
    logic [15:0] video_pixel_next;

    always_comb begin
        if (!video_de || video_x >= 11'd1280 || !line_valid) begin
            video_pixel_next = 16'h0000;
        end else if (display_buffer == 1'b0) begin
            video_pixel_next = line0[video_addr];
        end else begin
            video_pixel_next = line1[video_addr];
        end
    end

    always_ff @(posedge clk) begin
        video_pixel <= video_pixel_next;
        video_buffer <= display_buffer;
    end

    assign req_write = 1'b1;
    assign req_byte_address = ((27'(cap_line_y) * 27'(LINE_WORDS)) +
                               (27'(cap_chunk) * 27'(CHUNK_WORDS))) << 1;
    assign req_words = 16'(CHUNK_WORDS);
    assign req_tag = {cap_buffer, cap_chunk_tag};
    assign write_byte_enable = 2'b11;
    assign completion_ready = 1'b1;

    always_comb begin
        req_valid = (cap_state == CAP_REQ);
        write_valid = (cap_state == CAP_WRITE);
        if (cap_buffer == 1'b0) write_data = line0[cap_chunk * CHUNK_WORDS + cap_word];
        else write_data = line1[cap_chunk * CHUNK_WORDS + cap_word];
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            fill_buffer <= 1'b0;
            display_buffer <= 1'b1;
            fill_x <= '0;
            source_h <= '0;
            source_y <= '0;
            frame_number <= '0;
            line_valid <= 1'b0;
            pending_drain <= '0;
            drain_cycles[0] <= '0;
            drain_cycles[1] <= '0;
            completed_y[0] <= '0;
            completed_y[1] <= '0;
            cap_state <= CAP_IDLE;
            cap_buffer <= 1'b0;
            cap_line_y <= '0;
            cap_chunk <= '0;
            cap_word <= '0;
            cap_drain_cycles <= '0;
            source_lines_generated <= '0;
            sdram_lines_submitted <= '0;
            sdram_lines_completed <= '0;
            reuse_before_drain_error <= 1'b0;
            worst_line_drain_cycles <= '0;
            current_line_drain_cycles <= '0;
        end else begin
            if (pending_drain[0] && drain_cycles[0] != 16'hffff) drain_cycles[0] <= drain_cycles[0] + 1'b1;
            if (pending_drain[1] && drain_cycles[1] != 16'hffff) drain_cycles[1] <= drain_cycles[1] + 1'b1;

            if (source_active) begin
                if (fill_buffer == 1'b0) line0[fill_x] <= generated_pixel;
                else line1[fill_x] <= generated_pixel;
            end

            if (fill_last) begin
                source_lines_generated <= source_lines_generated + 1'b1;
                display_buffer <= fill_buffer;
                line_valid <= 1'b1;
                pending_drain[fill_buffer] <= 1'b1;
                drain_cycles[fill_buffer] <= '0;
                completed_y[fill_buffer] <= source_y;
                if (pending_drain[!fill_buffer]) reuse_before_drain_error <= 1'b1;
                fill_buffer <= !fill_buffer;
                fill_x <= '0;
                source_h <= '0;
                if (source_y == 10'd719) begin
                    source_y <= '0;
                    frame_number <= frame_number + 1'b1;
                end else begin
                    source_y <= source_y + 1'b1;
                end
            end else begin
                source_h <= source_h + 1'b1;
                if (source_active) fill_x <= fill_x + 1'b1;
            end

            case (cap_state)
                CAP_IDLE: begin
                    cap_drain_cycles <= '0;
                    cap_chunk <= '0;
                    cap_word <= '0;
                    if (pending_drain[0]) begin
                        cap_buffer <= 1'b0;
                        cap_line_y <= completed_y[0];
                        cap_state <= CAP_REQ;
                        sdram_lines_submitted <= sdram_lines_submitted + 1'b1;
                    end else if (pending_drain[1]) begin
                        cap_buffer <= 1'b1;
                        cap_line_y <= completed_y[1];
                        cap_state <= CAP_REQ;
                        sdram_lines_submitted <= sdram_lines_submitted + 1'b1;
                    end
                end
                CAP_REQ: begin
                    cap_drain_cycles <= cap_drain_cycles + 1'b1;
                    if (req_valid && req_ready) begin
                        cap_word <= '0;
                        cap_state <= CAP_WRITE;
                    end
                end
                CAP_WRITE: begin
                    cap_drain_cycles <= cap_drain_cycles + 1'b1;
                    if (write_valid && write_ready) begin
                        if (cap_word == ADDR_WIDTH'(CHUNK_WORDS - 1)) begin
                            cap_word <= '0;
                            cap_state <= CAP_WAIT_COMPLETE;
                        end else begin
                            cap_word <= cap_word + 1'b1;
                        end
                    end
                end
                CAP_WAIT_COMPLETE: begin
                    cap_drain_cycles <= cap_drain_cycles + 1'b1;
                    if (completion_valid && completion_ready) begin
                        if (completion_error || completion_words != 16'(CHUNK_WORDS) ||
                            completion_tag != {cap_buffer, cap_chunk_tag}) begin
                            reuse_before_drain_error <= 1'b1;
                        end
                        if (cap_chunk == CHUNK_INDEX_WIDTH'(CHUNKS_PER_LINE - 1)) begin
                            pending_drain[cap_buffer] <= 1'b0;
                            sdram_lines_completed <= sdram_lines_completed + 1'b1;
                            current_line_drain_cycles <= cap_drain_cycles;
                            if (cap_drain_cycles > worst_line_drain_cycles)
                                worst_line_drain_cycles <= cap_drain_cycles;
                            cap_state <= CAP_IDLE;
                        end else begin
                            cap_chunk <= cap_chunk + 1'b1;
                            cap_state <= CAP_REQ;
                        end
                    end
                end
                default: cap_state <= CAP_IDLE;
            endcase

            if (cap_drain_cycles > 16'(DRAIN_WARN_CYCLES)) reuse_before_drain_error <= 1'b1;
        end
    end
endmodule
