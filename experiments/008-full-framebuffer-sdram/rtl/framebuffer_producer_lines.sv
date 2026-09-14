`timescale 1ns/1ps

module framebuffer_producer_lines #(
    parameter integer FRAMEBUFFER_WIDTH = 1280,
    parameter integer FRAMEBUFFER_HEIGHT = 720,
    parameter integer LINE_ADDR_WIDTH = 11
) (
    input  logic                         clk,
    input  logic                         reset,

    output logic                         line_ready_valid,
    input  logic                         line_ready_accept,
    output logic                         line_ready_buffer,
    output logic [9:0]                   line_ready_y,

    input  logic                         line_release_valid,
    input  logic                         line_release_buffer,

    input  logic                         writer_read_buffer,
    input  logic [LINE_ADDR_WIDTH-1:0]   writer_read_x,
    output logic [15:0]                  writer_read_pixel,

    output logic [10:0]                  producer_x,
    output logic [9:0]                   producer_y,
    output logic [7:0]                   frame_index,
    output logic                         stalled_waiting_for_free_line
);
    typedef enum logic [1:0] {
        PRODUCER_RESET,
        PRODUCER_FILL_LINE,
        PRODUCER_HAND_OFF_LINE,
        PRODUCER_WAIT_FOR_FREE_LINE
    } producer_state_t;

    producer_state_t state;

    (* ramstyle = "M10K" *) logic [15:0] line0_pixels [0:FRAMEBUFFER_WIDTH-1];
    (* ramstyle = "M10K" *) logic [15:0] line1_pixels [0:FRAMEBUFFER_WIDTH-1];

    logic working_buffer;
    logic [1:0] buffer_owned_by_writer;
    logic [15:0] generated_pixel;
    logic fill_last_pixel_of_line;
    logic fill_last_line_of_frame;
    logic next_working_buffer_free;

    framebuffer_pattern_pixel #(
        .FRAMEBUFFER_WIDTH(FRAMEBUFFER_WIDTH),
        .FRAMEBUFFER_HEIGHT(FRAMEBUFFER_HEIGHT)
    ) pattern (
        .x(producer_x),
        .y(producer_y),
        .frame_index(frame_index),
        .pixel(generated_pixel)
    );

    assign fill_last_pixel_of_line = (producer_x == 11'(FRAMEBUFFER_WIDTH - 1));
    assign fill_last_line_of_frame = (producer_y == 10'(FRAMEBUFFER_HEIGHT - 1));
    assign next_working_buffer_free = !buffer_owned_by_writer[!working_buffer];
    assign stalled_waiting_for_free_line = (state == PRODUCER_WAIT_FOR_FREE_LINE);

    assign line_ready_valid = (state == PRODUCER_HAND_OFF_LINE);
    assign line_ready_buffer = working_buffer;
    assign line_ready_y = producer_y;

    always_ff @(posedge clk) begin
        if (reset) begin
            writer_read_pixel <= 16'h0000;
        end else if (writer_read_buffer) begin
            writer_read_pixel <= line1_pixels[writer_read_x];
        end else begin
            writer_read_pixel <= line0_pixels[writer_read_x];
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= PRODUCER_RESET;
            working_buffer <= 1'b0;
            buffer_owned_by_writer <= 2'b00;
            producer_x <= '0;
            producer_y <= '0;
            frame_index <= '0;
        end else begin
            if (line_release_valid) begin
                buffer_owned_by_writer[line_release_buffer] <= 1'b0;
            end

            case (state)
                PRODUCER_RESET: begin
                    state <= PRODUCER_FILL_LINE;
                end

                PRODUCER_FILL_LINE: begin
                    if (working_buffer) begin
                        line1_pixels[producer_x] <= generated_pixel;
                    end else begin
                        line0_pixels[producer_x] <= generated_pixel;
                    end

                    if (fill_last_pixel_of_line) begin
                        state <= PRODUCER_HAND_OFF_LINE;
                    end else begin
                        producer_x <= producer_x + 1'b1;
                    end
                end

                PRODUCER_HAND_OFF_LINE: begin
                    if (line_ready_valid && line_ready_accept) begin
                        buffer_owned_by_writer[working_buffer] <= 1'b1;
                        producer_x <= '0;

                        if (fill_last_line_of_frame) begin
                            producer_y <= '0;
                            frame_index <= frame_index + 1'b1;
                        end else begin
                            producer_y <= producer_y + 1'b1;
                        end

                        if (next_working_buffer_free) begin
                            working_buffer <= !working_buffer;
                            state <= PRODUCER_FILL_LINE;
                        end else begin
                            state <= PRODUCER_WAIT_FOR_FREE_LINE;
                        end
                    end
                end

                PRODUCER_WAIT_FOR_FREE_LINE: begin
                    if (next_working_buffer_free) begin
                        working_buffer <= !working_buffer;
                        state <= PRODUCER_FILL_LINE;
                    end
                end

                default: begin
                    state <= PRODUCER_RESET;
                end
            endcase
        end
    end

    initial begin
        if (FRAMEBUFFER_WIDTH < 2) $error("framebuffer width must include both border edges");
        if (FRAMEBUFFER_HEIGHT < 2) $error("framebuffer height must include both border edges");
        if ((1 << LINE_ADDR_WIDTH) < FRAMEBUFFER_WIDTH) $error("line address width is too small");
    end
endmodule
