`timescale 1ns/1ps

module tb_framebuffer_consumer_lines_dual_clock;
    logic fill_clk = 0, scanout_clk = 0;
    logic fill_reset = 1, scanout_reset = 1;
    logic fill_ready, fill_valid = 0;
    logic [15:0] fill_pixel = 0;
    logic [9:0] fill_line_y = 0;
    logic fill_line_advance, primed, waiting_for_output_release, overwrite_error;
    logic scanout_start = 0, scanout_line_advance = 0;
    logic [2:0] scanout_x = 0;
    logic [15:0] scanout_pixel;
    logic scanout_pixel_valid;
    logic [9:0] scanout_line_y;
    logic scanout_underflow;
    logic [15:0] scanout_skipped_lines;

    always #4 fill_clk = ~fill_clk;
    always #25 scanout_clk = ~scanout_clk;

    framebuffer_consumer_lines_dual_clock #(
        .FRAMEBUFFER_WIDTH(8), .LINE_ADDR_WIDTH(3)
    ) dut (.*);

    task automatic send_line(input [9:0] y, input [15:0] base);
        integer x;
        begin
            for (x = 0; x < 8; x = x + 1) begin
                while (!fill_ready) @(posedge fill_clk);
                @(negedge fill_clk);
                fill_valid = 1;
                fill_pixel = base + x;
                fill_line_y = y;
                @(negedge fill_clk);
                fill_valid = 0;
            end
        end
    endtask

    initial begin
        repeat (3) @(posedge fill_clk);
        fill_reset = 0;
        repeat (2) @(posedge scanout_clk);
        scanout_reset = 0;

        send_line(0, 16'h1000);
        send_line(1, 16'h2000);
        wait (primed);
        if (!waiting_for_output_release) $fatal(1, "two filled lines did not wait for scanout");

        // Allow the two synchronized publication signals to settle, then
        // start at a frame boundary with line zero selected.
        repeat (4) @(posedge scanout_clk);
        @(negedge scanout_clk); scanout_start = 1;
        @(negedge scanout_clk); scanout_start = 0;
        @(posedge scanout_clk);
        if (!scanout_pixel_valid || scanout_line_y != 0)
            $fatal(1, "scanout did not start on the first line");

        @(negedge scanout_clk); scanout_x = 3;
        @(posedge scanout_clk); #1;
        if (scanout_pixel != 16'h1003) $fatal(1, "wrong pixel from first line: %h", scanout_pixel);

        @(negedge scanout_clk); scanout_line_advance = 1;
        @(negedge scanout_clk); scanout_line_advance = 0;
        @(posedge scanout_clk); #1;
        if (!scanout_pixel_valid || scanout_line_y != 1)
            $fatal(1, "scanout did not take the published next line");

        // The release toggle must return to fill_clk and reopen its free line
        // buffer without reporting an ownership error.
        wait (fill_ready);
        if (overwrite_error)
            $fatal(1, "fill side did not receive the released buffer");
        send_line(2, 16'h3000);
        if (scanout_underflow || overwrite_error) $fatal(1, "unexpected line-buffer error");

        $display("PASS framebuffer_consumer_lines_dual_clock: clocked line ownership");
        $finish;
    end
endmodule
