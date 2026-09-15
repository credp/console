`timescale 1ns/1ps

module tb_framebuffer_machine_line_source;
    localparam integer TEST_WIDTH = 4;
    localparam integer TEST_HEIGHT = 3;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic produce_pixel = 1'b0;
    logic [10:0] pixel_x;
    logic [9:0] line_y;
    logic [7:0] frame_index;
    logic [15:0] pixel;
    logic last_pixel_of_line;
    logic last_line_of_frame;

    always #5 clk = !clk;

    framebuffer_machine_line_source #(
        .FRAMEBUFFER_WIDTH(TEST_WIDTH),
        .FRAMEBUFFER_HEIGHT(TEST_HEIGHT)
    ) dut (
        .clk(clk),
        .reset(reset),
        .produce_pixel(produce_pixel),
        .pixel_x(pixel_x),
        .line_y(line_y),
        .frame_index(frame_index),
        .pixel(pixel),
        .last_pixel_of_line(last_pixel_of_line),
        .last_line_of_frame(last_line_of_frame)
    );

    task automatic check_position(
        input logic [10:0] expected_x,
        input logic [9:0] expected_y,
        input logic [7:0] expected_frame
    );
        begin
            #1;
            if (pixel_x !== expected_x || line_y !== expected_y ||
                frame_index !== expected_frame) begin
                $fatal(1, "position mismatch got x=%0d y=%0d frame=%0d expected x=%0d y=%0d frame=%0d",
                       pixel_x, line_y, frame_index,
                       expected_x, expected_y, expected_frame);
            end
        end
    endtask

    task automatic step_pixel;
        begin
            @(negedge clk);
            produce_pixel = 1'b1;
            @(posedge clk);
            #1;
            produce_pixel = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        reset = 1'b0;
        check_position(11'd0, 10'd0, 8'd0);

        step_pixel;
        check_position(11'd1, 10'd0, 8'd0);
        step_pixel;
        check_position(11'd2, 10'd0, 8'd0);
        step_pixel;
        check_position(11'd3, 10'd0, 8'd0);

        if (!last_pixel_of_line || last_line_of_frame) begin
            $fatal(1, "last flags wrong at end of first line");
        end

        step_pixel;
        check_position(11'd0, 10'd1, 8'd0);

        repeat (TEST_WIDTH * (TEST_HEIGHT - 1) - 1) begin
            step_pixel;
        end
        check_position(11'd3, 10'd2, 8'd0);

        if (!last_pixel_of_line || !last_line_of_frame) begin
            $fatal(1, "last flags wrong at end of frame");
        end

        step_pixel;
        check_position(11'd0, 10'd0, 8'd1);

        $display("PASS framebuffer_machine_line_source: machine counters and frame wrap");
        $finish;
    end

    initial begin
        repeat (200) @(posedge clk);
        $fatal(1, "machine line source watchdog");
    end
endmodule
