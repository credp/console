`timescale 1ns/1ps

module framebuffer_machine_line_source #(
    parameter integer FRAMEBUFFER_WIDTH = 1280,
    parameter integer FRAMEBUFFER_HEIGHT = 720
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        produce_pixel,

    output logic [10:0] pixel_x,
    output logic [9:0]  line_y,
    output logic [7:0]  frame_index,
    output logic [15:0] pixel,
    output logic        last_pixel_of_line,
    output logic        last_line_of_frame
);
    framebuffer_pattern_pixel #(
        .FRAMEBUFFER_WIDTH(FRAMEBUFFER_WIDTH),
        .FRAMEBUFFER_HEIGHT(FRAMEBUFFER_HEIGHT)
    ) pattern (
        .x(pixel_x),
        .y(line_y),
        .frame_index(frame_index),
        .pixel(pixel)
    );

    assign last_pixel_of_line = (pixel_x == 11'(FRAMEBUFFER_WIDTH - 1));
    assign last_line_of_frame = (line_y == 10'(FRAMEBUFFER_HEIGHT - 1));

    always_ff @(posedge clk) begin
        if (reset) begin
            pixel_x <= '0;
            line_y <= '0;
            frame_index <= '0;
        end else if (produce_pixel) begin
            if (last_pixel_of_line) begin
                pixel_x <= '0;

                if (last_line_of_frame) begin
                    line_y <= '0;
                    frame_index <= frame_index + 1'b1;
                end else begin
                    line_y <= line_y + 1'b1;
                end
            end else begin
                pixel_x <= pixel_x + 1'b1;
            end
        end
    end

    initial begin
        if (FRAMEBUFFER_WIDTH < 2) $error("framebuffer width must include both border edges");
        if (FRAMEBUFFER_HEIGHT < 2) $error("framebuffer height must include both border edges");
    end
endmodule
