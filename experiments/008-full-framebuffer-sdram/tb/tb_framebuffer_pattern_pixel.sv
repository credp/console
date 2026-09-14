`timescale 1ns/1ps

module tb_framebuffer_pattern_pixel;
    logic [10:0] x;
    logic [9:0]  y;
    logic [7:0]  frame_index;
    logic [15:0] pixel;

    framebuffer_pattern_pixel dut (
        .x(x),
        .y(y),
        .frame_index(frame_index),
        .pixel(pixel)
    );

    function automatic logic [15:0] expected_pixel(
        input logic [10:0] sample_x,
        input logic [9:0]  sample_y,
        input logic [7:0]  sample_frame
    );
        logic [4:0] red;
        logic [5:0] green;
        logic [4:0] blue;
        begin
            if ((sample_x == 11'd0) ||
                (sample_x == 11'd1279) ||
                (sample_y == 10'd0) ||
                (sample_y == 10'd719)) begin
                expected_pixel = 16'hffff;
            end else begin
                red = sample_x[7:3] + sample_frame[4:0];
                green = sample_y[7:2] + {1'b0, sample_frame[4:0]};
                blue = (sample_x[6:2] ^ sample_y[6:2]) + sample_frame[4:0];
                expected_pixel = {red, green, blue};
            end
        end
    endfunction

    task automatic check_pixel(
        input logic [10:0] sample_x,
        input logic [9:0]  sample_y,
        input logic [7:0]  sample_frame
    );
        begin
            x = sample_x;
            y = sample_y;
            frame_index = sample_frame;
            #1;
            if (pixel !== expected_pixel(sample_x, sample_y, sample_frame)) begin
                $fatal(1, "pixel mismatch x=%0d y=%0d frame=%0d got=%h expected=%h",
                       sample_x, sample_y, sample_frame,
                       pixel, expected_pixel(sample_x, sample_y, sample_frame));
            end
        end
    endtask

    initial begin
        check_pixel(11'd0,    10'd0,   8'd0);
        check_pixel(11'd1279, 10'd0,   8'd13);
        check_pixel(11'd0,    10'd719, 8'd29);
        check_pixel(11'd1279, 10'd719, 8'd31);
        check_pixel(11'd640,  10'd0,   8'd4);
        check_pixel(11'd640,  10'd719, 8'd5);
        check_pixel(11'd0,    10'd360, 8'd6);
        check_pixel(11'd1279, 10'd360, 8'd7);

        check_pixel(11'd1,    10'd1,   8'd0);
        check_pixel(11'd640,  10'd360, 8'd0);
        check_pixel(11'd640,  10'd360, 8'd1);
        check_pixel(11'd1278, 10'd718, 8'd63);

        x = 11'd640;
        y = 10'd360;
        frame_index = 8'd0;
        #1;
        if (pixel == 16'hffff) begin
            $fatal(1, "interior pixel unexpectedly matched the white border");
        end

        $display("PASS framebuffer_pattern_pixel: border and drifting interior");
        $finish;
    end
endmodule
