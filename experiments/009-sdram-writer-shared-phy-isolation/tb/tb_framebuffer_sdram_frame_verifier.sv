`timescale 1ns/1ps

module tb_framebuffer_sdram_frame_verifier;
    localparam integer WIDTH = 8;
    localparam integer HEIGHT = 4;
    localparam integer WORDS = 4;

    logic clk = 0;
    logic reset = 1;
    logic req_valid, req_ready, req_write;
    logic [26:0] req_byte_address;
    logic [15:0] req_words;
    logic [7:0] req_tag;
    logic read_valid, read_ready;
    logic [15:0] read_data;
    logic completion_valid, completion_ready;
    logic [7:0] completion_tag;
    logic [15:0] completion_words;
    logic completion_error, done, passed, failed;
    logic [31:0] mismatch_count;
    logic response_active, completion_pending;
    logic [15:0] response_word_index;
    logic [26:0] response_base_word;
    logic [7:0] response_tag;

    always #5 clk = ~clk;

    framebuffer_sdram_frame_verifier #(
        .FRAMEBUFFER_WIDTH(WIDTH), .FRAMEBUFFER_HEIGHT(HEIGHT), .READ_CHUNK_WORDS(WORDS)
    ) dut (.*);

    function automatic logic [15:0] frame_zero_word(input logic [26:0] word_address);
        logic [10:0] x;
        logic [9:0] y;
        begin
            x = word_address % WIDTH;
            y = word_address / WIDTH;
            frame_zero_word = ((x == 0) || (x == WIDTH - 1) || (y == 0) || (y == HEIGHT - 1)) ?
                              16'hffff : 16'h0000;
        end
    endfunction

    assign req_ready = !response_active && !completion_pending;
    assign read_valid = response_active;
    assign read_data = frame_zero_word(response_base_word + response_word_index);
    assign completion_valid = completion_pending;
    assign completion_tag = response_tag;
    assign completion_words = WORDS;
    assign completion_error = 1'b0;

    always_ff @(posedge clk) begin
        if (reset) begin
            response_active <= 1'b0;
            completion_pending <= 1'b0;
            response_word_index <= '0;
            response_base_word <= '0;
            response_tag <= '0;
        end else begin
            if (req_valid && req_ready) begin
                response_active <= 1'b1;
                response_word_index <= '0;
                response_base_word <= req_byte_address >> 1;
                response_tag <= req_tag;
            end
            if (response_active && read_ready) begin
                if (response_word_index == WORDS - 1) begin
                    response_active <= 1'b0;
                    completion_pending <= 1'b1;
                end else begin
                    response_word_index <= response_word_index + 1'b1;
                end
            end
            if (completion_pending && completion_ready)
                completion_pending <= 1'b0;
        end
    end

    initial begin
        repeat (2) @(posedge clk);
        reset = 1'b0;
        repeat (300) begin
            @(posedge clk);
            if (done) begin
                if (!passed || failed || mismatch_count != 0)
                    $fatal(1, "expected successful full-frame verification");
                $display("PASS framebuffer_sdram_frame_verifier: all frame words matched");
                $finish;
            end
        end
        $fatal(1, "frame verifier timed out");
    end
endmodule
