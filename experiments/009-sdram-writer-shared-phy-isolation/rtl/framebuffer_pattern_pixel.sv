`timescale 1ns/1ps

module framebuffer_pattern_pixel #(
    parameter integer FRAMEBUFFER_WIDTH = 1280,
    parameter integer FRAMEBUFFER_HEIGHT = 720
) (
    input  logic [10:0] x,
    input  logic [9:0]  y,
    input  logic [7:0]  frame_index,

    output logic [15:0] pixel
);
    localparam logic [10:0] FRAMEBUFFER_LAST_X = 11'(FRAMEBUFFER_WIDTH - 1);
    localparam logic [9:0]  FRAMEBUFFER_LAST_Y = 10'(FRAMEBUFFER_HEIGHT - 1);
    localparam logic [15:0] PIXEL_WHITE = 16'hffff;

    wire border_pixel = (x == 11'd0) ||
                        (x == FRAMEBUFFER_LAST_X) ||
                        (y == 10'd0) ||
                        (y == FRAMEBUFFER_LAST_Y);
    // A shared raster/framebuffer locator. It makes a coordinate slip visible
    // immediately when comparing the direct raster source with SDRAM scanout.
    wire center_locator = (x >= 11'd632) && (x < 11'd648) &&
                          (y >= 10'd352) && (y < 10'd368) &&
                          ((x[3:0] == 4'd7) || (y[3:0] == 4'd7));

    // Use coarse coordinate cells, rather than fine stripes, so a missing or
    // repeated raster coordinate is visible at a glance. The small frame
    // term keeps the interior slowly moving without obscuring that grid.
    wire [4:0] red = {x[10:8], 2'b00} + frame_index[4:0];
    wire [5:0] green = {y[9:7], 3'b000} + {frame_index[4:0], 1'b0};
    wire [4:0] blue = {(x[10:8] ^ y[9:7]), 2'b00} + frame_index[4:0];

    assign pixel = border_pixel ? PIXEL_WHITE : center_locator ? 16'hf81f : {red, green, blue};
endmodule
