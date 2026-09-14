`timescale 1ns/1ps

module tb_framebuffer_one_shot_handoff;
    logic clk = 0, reset = 1, frame_write_complete = 0, reader_init_done = 0;
    logic producer_owns_sdram, reader_reset, reader_owns_sdram, framebuffer_ready;
    always #5 clk = ~clk;
    framebuffer_one_shot_handoff dut (.*);
    initial begin
        repeat(2) @(posedge clk); reset = 0;
        if (!producer_owns_sdram || !reader_reset || reader_owns_sdram)
            $fatal(1, "wrong initial ownership");
        @(negedge clk); frame_write_complete = 1;
        @(posedge clk); @(negedge clk); frame_write_complete = 0;
        if (producer_owns_sdram || reader_reset || reader_owns_sdram)
            $fatal(1, "reader was not held through initialization");
        repeat(3) @(posedge clk);
        if (reader_owns_sdram) $fatal(1, "reader owned pins before init done");
        @(negedge clk); reader_init_done = 1;
        @(posedge clk); #1;
        if (!reader_owns_sdram || !framebuffer_ready || producer_owns_sdram)
            $fatal(1, "reader did not receive permanent ownership");
        $display("PASS one-shot handoff: final write, reader initialization, ownership");
        $finish;
    end
endmodule
