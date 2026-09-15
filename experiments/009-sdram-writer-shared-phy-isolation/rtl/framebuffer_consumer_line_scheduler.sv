`timescale 1ns/1ps

// Owns consumer-side framebuffer line order. It does not know about SDRAM
// transfers or scanout pixels; it only schedules line-fetch commands and
// permits scanout to advance once the following line has been filled.
module framebuffer_consumer_line_scheduler #(
    parameter integer FRAMEBUFFER_HEIGHT = 720
) (
    input  logic       clk,
    input  logic       reset,

    output logic       start_line_valid,
    input  logic       start_line_ready,
    output logic [9:0] start_line_y,
    input  logic       line_fetch_done,

    input  logic       scanout_line_advance,
    output logic       output_line_advance,

    output logic [9:0] next_framebuffer_line_y,
    output logic       waiting_for_scanout,
    output logic       timing_error
);
    typedef enum logic [1:0] {
        SCHEDULER_REQUEST_LINE,
        SCHEDULER_WAIT_FOR_FILL,
        SCHEDULER_WAIT_FOR_SCANOUT
    } scheduler_state_t;

    scheduler_state_t state;
    logic first_line_loaded;
    logic last_framebuffer_line;

    assign start_line_valid = (state == SCHEDULER_REQUEST_LINE);
    assign start_line_y = next_framebuffer_line_y;
    assign waiting_for_scanout = (state == SCHEDULER_WAIT_FOR_SCANOUT);
    assign output_line_advance = waiting_for_scanout && scanout_line_advance;
    assign last_framebuffer_line = (next_framebuffer_line_y == 10'(FRAMEBUFFER_HEIGHT - 1));

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= SCHEDULER_REQUEST_LINE;
            next_framebuffer_line_y <= '0;
            first_line_loaded <= 1'b0;
            timing_error <= 1'b0;
        end else begin
            if (scanout_line_advance && !waiting_for_scanout) begin
                timing_error <= 1'b1;
            end

            case (state)
                SCHEDULER_REQUEST_LINE: begin
                    if (start_line_valid && start_line_ready) begin
                        if (last_framebuffer_line) begin
                            next_framebuffer_line_y <= '0;
                        end else begin
                            next_framebuffer_line_y <= next_framebuffer_line_y + 1'b1;
                        end
                        state <= SCHEDULER_WAIT_FOR_FILL;
                    end
                end

                SCHEDULER_WAIT_FOR_FILL: begin
                    if (line_fetch_done) begin
                        if (!first_line_loaded) begin
                            first_line_loaded <= 1'b1;
                            state <= SCHEDULER_REQUEST_LINE;
                        end else begin
                            state <= SCHEDULER_WAIT_FOR_SCANOUT;
                        end
                    end
                end

                SCHEDULER_WAIT_FOR_SCANOUT: begin
                    if (scanout_line_advance) begin
                        state <= SCHEDULER_REQUEST_LINE;
                    end
                end

                default: begin
                    state <= SCHEDULER_REQUEST_LINE;
                end
            endcase
        end
    end

    initial begin
        if (FRAMEBUFFER_HEIGHT < 2) $error("framebuffer height must include both border edges");
        if (FRAMEBUFFER_HEIGHT > 1024) $error("framebuffer line Y is ten bits wide");
    end
endmodule
