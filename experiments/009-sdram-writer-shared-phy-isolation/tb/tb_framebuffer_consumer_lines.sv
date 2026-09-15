`timescale 1ns/1ps

module tb_framebuffer_consumer_lines;
    localparam integer TEST_WIDTH = 8;
    localparam integer TEST_ADDR_WIDTH = 3;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic fill_ready;
    logic fill_valid;
    logic [15:0] fill_pixel;
    logic [9:0] fill_line_y;
    logic output_line_advance;
    logic output_line_valid;
    logic output_buffer;
    logic [9:0] output_line_y;
    logic [TEST_ADDR_WIDTH-1:0] scanout_x;
    logic [15:0] scanout_pixel;
    logic scanout_pixel_valid;
    logic waiting_for_output_release;
    logic overwrite_error;

    integer x_index;

    always #5 clk = !clk;

    framebuffer_consumer_lines #(
        .FRAMEBUFFER_WIDTH(TEST_WIDTH),
        .LINE_ADDR_WIDTH(TEST_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .reset(reset),
        .fill_ready(fill_ready),
        .fill_valid(fill_valid),
        .fill_pixel(fill_pixel),
        .fill_line_y(fill_line_y),
        .output_line_advance(output_line_advance),
        .output_line_valid(output_line_valid),
        .output_buffer(output_buffer),
        .output_line_y(output_line_y),
        .scanout_x(scanout_x),
        .scanout_pixel(scanout_pixel),
        .scanout_pixel_valid(scanout_pixel_valid),
        .waiting_for_output_release(waiting_for_output_release),
        .overwrite_error(overwrite_error)
    );

    task automatic fill_line(input logic [9:0] line_y, input logic [15:0] base_value);
        begin
            for (x_index = 0; x_index < TEST_WIDTH; x_index = x_index + 1) begin
                wait(fill_ready);
                @(negedge clk);
                fill_line_y = line_y;
                fill_pixel = base_value + 16'(x_index);
                fill_valid = 1'b1;
                @(posedge clk);
                #1;
                fill_valid = 1'b0;
            end
        end
    endtask

    task automatic check_output_line(
        input logic [9:0] expected_y,
        input logic [15:0] expected_base
    );
        begin
            if (!output_line_valid || output_line_y != expected_y || !scanout_pixel_valid) begin
                $fatal(1, "output descriptor mismatch valid=%b y=%0d expected_y=%0d scanout_valid=%b",
                       output_line_valid, output_line_y, expected_y, scanout_pixel_valid);
            end

            for (x_index = 0; x_index < TEST_WIDTH; x_index = x_index + 1) begin
                scanout_x = TEST_ADDR_WIDTH'(x_index);
                @(posedge clk);
                #1;
                if (scanout_pixel !== expected_base + 16'(x_index)) begin
                    $fatal(1, "scanout pixel mismatch x=%0d got=%h expected=%h",
                           x_index, scanout_pixel, expected_base + 16'(x_index));
                end
            end
        end
    endtask

    task automatic release_output_line;
        begin
            @(negedge clk);
            output_line_advance = 1'b1;
            @(posedge clk);
            #1;
            output_line_advance = 1'b0;
        end
    endtask

    initial begin
        fill_valid = 1'b0;
        fill_pixel = 16'h0000;
        fill_line_y = 10'd0;
        output_line_advance = 1'b0;
        scanout_x = '0;

        repeat (3) @(posedge clk);
        reset = 1'b0;

        fill_line(10'd0, 16'h1000);
        check_output_line(10'd0, 16'h1000);

        fill_line(10'd1, 16'h2000);
        repeat (TEST_WIDTH + 2) @(posedge clk);
        if (!waiting_for_output_release) begin
            $fatal(1, "consumer did not stall when both output/filling buffers were occupied");
        end

        release_output_line;
        check_output_line(10'd1, 16'h2000);

        release_output_line;
        fill_line(10'd2, 16'h3000);
        check_output_line(10'd2, 16'h3000);

        if (overwrite_error) begin
            $fatal(1, "unexpected overwrite error");
        end

        $display("PASS framebuffer_consumer_lines: fill/output ping-pong ownership");
        $finish;
    end

    initial begin
        repeat (1000) @(posedge clk);
        $fatal(1, "consumer lines watchdog");
    end
endmodule
