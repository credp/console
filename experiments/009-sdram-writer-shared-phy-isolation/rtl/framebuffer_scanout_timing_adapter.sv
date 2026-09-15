`timescale 1ns/1ps

// Adapts an existing raster's active-video coordinates to the framebuffer
// consumer. The input contract is that raster_x, raster_y, and raster_de
// describe the same pixel clock.
module framebuffer_scanout_timing_adapter #(
    parameter integer FRAMEBUFFER_WIDTH = 1280,
    parameter integer FRAMEBUFFER_HEIGHT = 720,
    parameter integer LINE_ADDR_WIDTH = 11
) (
    input  logic                         raster_de,
    input  logic [10:0]                  raster_x,
    input  logic [9:0]                   raster_y,

    output logic                         scanout_active,
    output logic [LINE_ADDR_WIDTH-1:0]   scanout_x,
    output logic [9:0]                   scanout_line_y,
    output logic                         scanout_line_advance
);
    assign scanout_active = raster_de;
    assign scanout_x = raster_x[LINE_ADDR_WIDTH-1:0];
    assign scanout_line_y = raster_y;

    // Line 0 is already the consumer's initial output line after reset.
    assign scanout_line_advance = raster_de && (raster_x == 11'd0) &&
                                  (raster_y != 10'd0);

    initial begin
        if (FRAMEBUFFER_WIDTH < 2) $error("framebuffer width must include both border edges");
        if (FRAMEBUFFER_HEIGHT < 2) $error("framebuffer height must include both border edges");
        if ((1 << LINE_ADDR_WIDTH) < FRAMEBUFFER_WIDTH) $error("line address width is too small");
    end
endmodule
