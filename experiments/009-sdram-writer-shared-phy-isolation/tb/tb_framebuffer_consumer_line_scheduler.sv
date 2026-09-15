`timescale 1ns/1ps

module tb_framebuffer_consumer_line_scheduler;
    localparam integer TEST_HEIGHT = 4;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start_line_valid;
    logic start_line_ready;
    logic [9:0] start_line_y;
    logic line_fetch_done;
    logic scanout_line_advance;
    logic output_line_advance;
    logic [9:0] next_framebuffer_line_y;
    logic waiting_for_scanout;
    logic timing_error;
    integer expected_line_y;

    always #5 clk = !clk;

    framebuffer_consumer_line_scheduler #(
        .FRAMEBUFFER_HEIGHT(TEST_HEIGHT)
    ) dut (
        .clk(clk),
        .reset(reset),
        .start_line_valid(start_line_valid),
        .start_line_ready(start_line_ready),
        .start_line_y(start_line_y),
        .line_fetch_done(line_fetch_done),
        .scanout_line_advance(scanout_line_advance),
        .output_line_advance(output_line_advance),
        .next_framebuffer_line_y(next_framebuffer_line_y),
        .waiting_for_scanout(waiting_for_scanout),
        .timing_error(timing_error)
    );

    task automatic accept_line_request(input integer expected_y);
        begin
            wait(start_line_valid);
            if (start_line_y != expected_y) begin
                $fatal(1, "line request y=%0d expected=%0d", start_line_y, expected_y);
            end
            @(negedge clk); start_line_ready = 1'b1;
            @(posedge clk); #1; start_line_ready = 1'b0;
        end
    endtask

    task automatic finish_line_fetch;
        begin
            @(negedge clk); line_fetch_done = 1'b1;
            @(posedge clk); #1; line_fetch_done = 1'b0;
        end
    endtask

    task automatic advance_scanout;
        begin
            if (!waiting_for_scanout) $fatal(1, "scanout advance was not permitted");
            @(negedge clk); scanout_line_advance = 1'b1;
            #1;
            if (!output_line_advance) $fatal(1, "scheduler did not forward line advance");
            @(posedge clk); #1; scanout_line_advance = 1'b0;
        end
    endtask

    initial begin
        start_line_ready = 1'b0;
        line_fetch_done = 1'b0;
        scanout_line_advance = 1'b0;

        repeat (3) @(posedge clk);
        reset = 1'b0;

        // The first line becomes scanout output; the second is prefetched.
        accept_line_request(0);
        finish_line_fetch;
        accept_line_request(1);
        finish_line_fetch;

        for (expected_line_y = 2; expected_line_y < TEST_HEIGHT + 1;
             expected_line_y = expected_line_y + 1) begin
            advance_scanout;
            accept_line_request(expected_line_y % TEST_HEIGHT);
            finish_line_fetch;
        end

        if (timing_error) $fatal(1, "scheduler reported an unexpected timing error");
        $display("PASS framebuffer_consumer_line_scheduler: prefetch, advance, and line wrap");
        $finish;
    end

    initial begin
        repeat (500) @(posedge clk);
        $fatal(1, "consumer line scheduler watchdog");
    end
endmodule
