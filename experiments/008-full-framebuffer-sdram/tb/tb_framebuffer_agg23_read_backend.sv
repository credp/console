`timescale 1ns/1ps

// Pin-level test for the complete read composition. The upstream MIT SDRAM
// model receives the forwarded SDRAM clock, command pins, and bidirectional DQ
// bus exactly as the board device will.
module tb_framebuffer_agg23_read_backend;
    localparam integer TEST_WORDS = 256;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic req_valid = 1'b0;
    logic req_ready;
    logic req_write = 1'b0;
    logic [26:0] req_byte_address = '0;
    logic [15:0] req_words = '0;
    logic [7:0] req_tag = '0;
    logic read_valid;
    logic read_ready = 1'b1;
    logic [15:0] read_data;
    logic completion_valid;
    logic completion_ready = 1'b0;
    logic [7:0] completion_tag;
    logic [15:0] completion_words;
    logic completion_error;
    logic init_done;
    wire [12:0] sdram_a;
    wire [1:0] sdram_ba;
    wire sdram_cke;
    wire sdram_ncs;
    wire sdram_nras;
    wire sdram_ncas;
    wire sdram_nwe;
    wire sdram_dqml;
    wire sdram_dqmh;
    wire [15:0] sdram_dq;
    wire [15:0] sdram_dq_out;
    wire sdram_dq_oe;
    wire sdram_clk;
    integer word_index;

    // 142.857 MHz nominal controller clock.
    always #3.5 clk = !clk;

    framebuffer_agg23_read_backend #(.SDRAM_FREQ_MHZ(143)) dut (
        .clk, .reset, .req_valid, .req_ready, .req_write,
        .req_byte_address, .req_words, .req_tag, .read_valid, .read_ready,
        .read_data, .completion_valid, .completion_ready, .completion_tag,
        .completion_words, .completion_error, .init_done,
        .SDRAM_A(sdram_a), .SDRAM_BA(sdram_ba), .SDRAM_CKE(sdram_cke),
        .SDRAM_nCS(sdram_ncs), .SDRAM_nRAS(sdram_nras),
        .SDRAM_nCAS(sdram_ncas), .SDRAM_nWE(sdram_nwe),
        .SDRAM_DQML(sdram_dqml), .SDRAM_DQMH(sdram_dqmh),
        .sdram_dq_in(sdram_dq), .sdram_dq_out, .sdram_dq_oe,
        .SDRAM_CLK(sdram_clk)
    );

    assign sdram_dq = sdram_dq_oe ? sdram_dq_out : 16'hzzzz;

    agg23_sdram_pin_model memory (
        .clk(sdram_clk), .cke(sdram_cke), .ncs(sdram_ncs),
        .nras(sdram_nras), .ncas(sdram_ncas), .nwe(sdram_nwe),
        .a(sdram_a), .ba(sdram_ba), .dqml(sdram_dqml), .dqmh(sdram_dqmh),
        .dq(sdram_dq)
    );

    initial begin
        // First page, bank zero, row zero. The cache fetches all 1024 words;
        // the test checks the requested first 256 words.
        for (word_index = 0; word_index < 1024; word_index = word_index + 1)
            memory.mem[0][0][word_index] = 16'h5000 + word_index[15:0];

        repeat (2) @(negedge clk);
        reset = 1'b0;
        wait(init_done);

        @(negedge clk);
        req_words = TEST_WORDS;
        req_tag = 8'h71;
        req_valid = 1'b1;
        wait(req_ready);
        @(posedge clk);
        @(negedge clk);
        req_valid = 1'b0;

        word_index = 0;
        while (word_index < TEST_WORDS) begin
            @(posedge clk);
            #1;
            if (read_valid) begin
                if (read_data !== 16'h5000 + word_index[15:0])
                    $fatal(1, "read word %0d got %h", word_index, read_data);
                word_index = word_index + 1;
            end
        end

        wait(completion_valid);
        if (completion_error || completion_tag != 8'h71 ||
            completion_words != TEST_WORDS)
            $fatal(1, "bad completion tag=%h words=%0d error=%b",
                   completion_tag, completion_words, completion_error);
        @(negedge clk);
        completion_ready = 1'b1;
        @(posedge clk);
        $display("PASS agg23 read backend: pin-level page capture and 256-word read");
        $finish;
    end

    initial begin
        repeat (40000) @(posedge clk);
        $fatal(1, "agg23 read backend watchdog");
    end
endmodule
