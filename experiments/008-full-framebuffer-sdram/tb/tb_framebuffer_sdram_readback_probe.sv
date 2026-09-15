`timescale 1ns/1ps

module tb_framebuffer_sdram_readback_probe;
    logic clk = 0, reset = 1;
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
    logic [7:0] status;
    logic [15:0] sample_word;

    always #5 clk = ~clk;

    framebuffer_sdram_readback_probe #(.EXPECTED_WORD(16'h1234)) dut (.*);

    task automatic reset_probe;
        begin
            reset = 1;
            req_ready = 0; read_valid = 0; read_data = 0;
            completion_valid = 0; completion_tag = 0;
            completion_words = 0; completion_error = 0;
            repeat (2) @(posedge clk);
            reset = 0;
        end
    endtask

    task automatic complete_probe(input logic [15:0] word);
        begin
            @(negedge clk); req_ready = 1;
            @(negedge clk); req_ready = 0;
            @(negedge clk); read_valid = 1; read_data = word;
            @(negedge clk); read_valid = 0;
            completion_valid = 1;
            completion_tag = 8'hf0;
            completion_words = 1;
            @(negedge clk); completion_valid = 0;
        end
    endtask

    initial begin
        reset_probe();
        complete_probe(16'h1234);
        @(posedge clk);
        if (!done || !passed || failed || status != 8'h01)
            $fatal(1, "expected successful readback probe");

        reset_probe();
        complete_probe(16'hffff);
        @(posedge clk);
        if (!done || passed || !failed || status != 8'hee)
            $fatal(1, "expected failed readback probe");

        $display("PASS framebuffer_sdram_readback_probe: known border readback");
        $finish;
    end
endmodule
