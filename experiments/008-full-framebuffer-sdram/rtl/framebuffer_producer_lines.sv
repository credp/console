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
    output logic                         stalled_waiting_for_free_line,
    output logic                         stalled_waiting_for_writer
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
    logic [15:0] machine_pixel;
    logic machine_produce_pixel;
    logic machine_last_pixel_of_line;
    logic machine_last_line_of_frame;
    logic next_working_buffer_free;
    logic [9:0] completed_line_y;

    framebuffer_machine_line_source #(
        .FRAMEBUFFER_WIDTH(FRAMEBUFFER_WIDTH),
        .FRAMEBUFFER_HEIGHT(FRAMEBUFFER_HEIGHT)
    ) machine_source (
        .clk(clk),
        .reset(reset),
        .produce_pixel(machine_produce_pixel),
        .pixel_x(producer_x),
        .line_y(producer_y),
        .frame_index(frame_index),
        .pixel(machine_pixel),
        .last_pixel_of_line(machine_last_pixel_of_line),
        .last_line_of_frame(machine_last_line_of_frame)
    );

    assign next_working_buffer_free = !buffer_owned_by_writer[!working_buffer];
    assign stalled_waiting_for_free_line = (state == PRODUCER_WAIT_FOR_FREE_LINE);
    assign stalled_waiting_for_writer = (state == PRODUCER_HAND_OFF_LINE) && !line_ready_accept;
    assign machine_produce_pixel = (state == PRODUCER_FILL_LINE);

    assign line_ready_valid = (state == PRODUCER_HAND_OFF_LINE);
    assign line_ready_buffer = working_buffer;
    assign line_ready_y = completed_line_y;

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
            completed_line_y <= '0;
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
                        line1_pixels[producer_x] <= machine_pixel;
                    end else begin
                        line0_pixels[producer_x] <= machine_pixel;
                    end

                    if (machine_last_pixel_of_line) begin
                        completed_line_y <= producer_y;
                        state <= PRODUCER_HAND_OFF_LINE;
                    end
                end

                PRODUCER_HAND_OFF_LINE: begin
                    if (line_ready_valid && line_ready_accept) begin
                        buffer_owned_by_writer[working_buffer] <= 1'b1;

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
