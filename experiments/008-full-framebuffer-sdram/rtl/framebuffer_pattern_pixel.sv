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

    // The interior deliberately uses only coordinates and a slow frame
    // counter. Wrong line order, stale frames, or edge timing mistakes should
    // be visible without needing a complicated renderer.
    wire [4:0] red = x[7:3] + frame_index[4:0];
    wire [5:0] green = y[7:2] + {1'b0, frame_index[4:0]};
    wire [4:0] blue = (x[6:2] ^ y[6:2]) + frame_index[4:0];

    assign pixel = border_pixel ? PIXEL_WHITE : {red, green, blue};
endmodule
