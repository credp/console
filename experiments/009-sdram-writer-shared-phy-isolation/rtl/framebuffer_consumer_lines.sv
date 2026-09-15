`timescale 1ns/1ps

module framebuffer_consumer_lines #(
    parameter integer FRAMEBUFFER_WIDTH = 1280,
    parameter integer LINE_ADDR_WIDTH = 11
) (
    input  logic                         clk,
    input  logic                         reset,

    output logic                         fill_ready,
    input  logic                         fill_valid,
    input  logic [15:0]                  fill_pixel,
    input  logic [9:0]                   fill_line_y,

    input  logic                         output_line_advance,
    output logic                         output_line_valid,
    output logic                         output_buffer,
    output logic [9:0]                   output_line_y,

    input  logic [LINE_ADDR_WIDTH-1:0]   scanout_x,
    output logic [15:0]                  scanout_pixel,
    output logic                         scanout_pixel_valid,

    output logic                         waiting_for_output_release,
    output logic                         overwrite_error
);
    typedef enum logic [1:0] {
        CONSUMER_FILL_LINE,
        CONSUMER_WAIT_FOR_OUTPUT_RELEASE
    } consumer_state_t;

    consumer_state_t state;

    (* ramstyle = "M10K" *) logic [15:0] line0_pixels [0:FRAMEBUFFER_WIDTH-1];
    (* ramstyle = "M10K" *) logic [15:0] line1_pixels [0:FRAMEBUFFER_WIDTH-1];

    logic filling_buffer;
    logic [LINE_ADDR_WIDTH-1:0] fill_x;
    logic [9:0] filling_line_y;
    logic output_buffer_q;
    logic [9:0] output_line_y_q;
    logic output_line_valid_q;
    logic pending_buffer;
    logic [9:0] pending_line_y;
    logic pending_line_valid;
    logic next_filling_buffer_free;
    logic last_fill_pixel;

    assign fill_ready = (state == CONSUMER_FILL_LINE) && !pending_line_valid;
    assign last_fill_pixel = (fill_x == LINE_ADDR_WIDTH'(FRAMEBUFFER_WIDTH - 1));
    assign output_line_valid = output_line_valid_q;
    assign output_buffer = output_buffer_q;
    assign output_line_y = output_line_y_q;
    assign next_filling_buffer_free = !pending_line_valid;
    assign waiting_for_output_release = (state == CONSUMER_WAIT_FOR_OUTPUT_RELEASE);
    assign scanout_pixel_valid = output_line_valid_q;

    always_ff @(posedge clk) begin
        if (reset) begin
            scanout_pixel <= 16'h0000;
        end else if (output_buffer_q) begin
            scanout_pixel <= line1_pixels[scanout_x];
        end else begin
            scanout_pixel <= line0_pixels[scanout_x];
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= CONSUMER_FILL_LINE;
            filling_buffer <= 1'b0;
            fill_x <= '0;
            filling_line_y <= '0;
            output_buffer_q <= 1'b0;
            output_line_y_q <= '0;
            output_line_valid_q <= 1'b0;
            pending_buffer <= 1'b0;
            pending_line_y <= '0;
            pending_line_valid <= 1'b0;
            overwrite_error <= 1'b0;
        end else begin
            if (output_line_advance && pending_line_valid) begin
                output_buffer_q <= pending_buffer;
                output_line_y_q <= pending_line_y;
                output_line_valid_q <= 1'b1;
                pending_line_valid <= 1'b0;
            end else if (output_line_advance && !pending_line_valid) begin
                output_line_valid_q <= 1'b0;
            end

            case (state)
                CONSUMER_FILL_LINE: begin
                    if (fill_valid && fill_ready) begin
                        if (fill_x == '0) begin
                            filling_line_y <= fill_line_y;
                        end

                        if (filling_buffer) begin
                            line1_pixels[fill_x] <= fill_pixel;
                        end else begin
                            line0_pixels[fill_x] <= fill_pixel;
                        end

                        if (last_fill_pixel) begin
                            if (pending_line_valid) begin
                                overwrite_error <= 1'b1;
                            end
                            if (output_line_valid_q) begin
                                pending_buffer <= filling_buffer;
                                pending_line_y <= filling_line_y;
                                pending_line_valid <= 1'b1;
                            end else begin
                                output_buffer_q <= filling_buffer;
                                output_line_y_q <= filling_line_y;
                                output_line_valid_q <= 1'b1;
                            end
                            fill_x <= '0;

                            if (!output_line_valid_q && next_filling_buffer_free) begin
                                filling_buffer <= !filling_buffer;
                            end else begin
                                state <= CONSUMER_WAIT_FOR_OUTPUT_RELEASE;
                            end
                        end else begin
                            fill_x <= fill_x + 1'b1;
                        end
                    end
                end

                CONSUMER_WAIT_FOR_OUTPUT_RELEASE: begin
                    if (next_filling_buffer_free) begin
                        filling_buffer <= !filling_buffer;
                        state <= CONSUMER_FILL_LINE;
                    end
                end

                default: begin
                    state <= CONSUMER_FILL_LINE;
                end
            endcase
        end
    end

    initial begin
        if (FRAMEBUFFER_WIDTH < 1) $error("framebuffer width must be positive");
        if ((1 << LINE_ADDR_WIDTH) < FRAMEBUFFER_WIDTH) $error("line address width is too small");
    end
endmodule
