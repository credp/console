`timescale 1ns/1ps

module tb_framebuffer_scanout_timing_adapter;
    localparam integer TEST_WIDTH = 8;
    localparam integer TEST_HEIGHT = 4;
    localparam integer TEST_ADDR_WIDTH = 3;

    logic raster_de;
    logic [10:0] raster_x;
    logic [9:0] raster_y;
    logic scanout_active;
    logic [TEST_ADDR_WIDTH-1:0] scanout_x;
    logic [9:0] scanout_line_y;
    logic scanout_line_advance;

    framebuffer_scanout_timing_adapter #(
        .FRAMEBUFFER_WIDTH(TEST_WIDTH),
        .FRAMEBUFFER_HEIGHT(TEST_HEIGHT),
        .LINE_ADDR_WIDTH(TEST_ADDR_WIDTH)
    ) dut (
        .raster_de(raster_de),
        .raster_x(raster_x),
        .raster_y(raster_y),
        .scanout_active(scanout_active),
        .scanout_x(scanout_x),
        .scanout_line_y(scanout_line_y),
        .scanout_line_advance(scanout_line_advance)
    );

    task automatic sample_raster(
        input logic sample_de,
        input logic [10:0] sample_x,
        input logic [9:0] sample_y,
        input logic expected_advance
    );
        begin
            raster_de = sample_de;
            raster_x = sample_x;
            raster_y = sample_y;
            #1;
            if (scanout_active != sample_de || scanout_x != sample_x ||
                scanout_line_y != sample_y || scanout_line_advance != expected_advance) begin
                $fatal(1, "bad adapter result de=%b x=%0d y=%0d advance=%b",
                       scanout_active, scanout_x, scanout_line_y, scanout_line_advance);
            end
        end
    endtask

    initial begin
        sample_raster(1'b0, 11'd0, 10'd0, 1'b0);
        sample_raster(1'b1, 11'd0, 10'd0, 1'b0);
        sample_raster(1'b1, 11'd7, 10'd0, 1'b0);
        sample_raster(1'b0, 11'd0, 10'd1, 1'b0);
        sample_raster(1'b1, 11'd0, 10'd1, 1'b1);
        sample_raster(1'b1, 11'd3, 10'd1, 1'b0);
        sample_raster(1'b1, 11'd0, 10'd3, 1'b1);

        $display("PASS framebuffer_scanout_timing_adapter: active pixels and line starts");
        $finish;
    end
endmodule
