`timescale 1ns/1ps

// The machine fills a line at machine_clk. The SDRAM writer drains a completed
// line at sdram_clk. Each buffer has its own release toggle, so buffer identity
// crosses the clock boundary as a one-bit event rather than bundled data.
module framebuffer_producer_lines_dual_clock #(
    parameter integer FRAMEBUFFER_WIDTH = 1280,
    parameter integer FRAMEBUFFER_HEIGHT = 720,
    parameter integer LINE_ADDR_WIDTH = 11,
    // Temporary first-picture mode. Remove this cut point when the completed
    // experiment's transaction-boundary arbiter owns the producer schedule.
    parameter integer STOP_AFTER_ONE_FRAME = 0
) (
    input  logic                         machine_clk,
    input  logic                         sdram_clk,
    input  logic                         machine_reset,
    input  logic                         sdram_reset,

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
    typedef enum logic [2:0] {
        PRODUCER_RESET,
        PRODUCER_FILL_LINE,
        PRODUCER_HAND_OFF_LINE,
        PRODUCER_WAIT_FOR_FREE_LINE,
        // The final line is already owned by the SDRAM writer. Do not begin a
        // new frame while the temporary one-shot handoff is pending.
        PRODUCER_STOPPED
    } producer_state_t;

    producer_state_t machine_state;

    // Each array has a machine-clock write port and an SDRAM-clock read port.
    (* ramstyle = "M10K" *) logic [15:0] line0_pixels [0:FRAMEBUFFER_WIDTH-1];
    (* ramstyle = "M10K" *) logic [15:0] line1_pixels [0:FRAMEBUFFER_WIDTH-1];

    logic working_buffer;
    logic [1:0] buffer_owned_by_writer;
    logic [1:0] line_ready_toggle;
    logic [1:0] line_release_toggle;
    logic [1:0] line_release_sync_1;
    logic [1:0] line_release_sync_2;
    logic [1:0] line_release_seen;
    logic line_accept_toggle;
    logic line_accept_sync_1;
    logic line_accept_sync_2;
    logic line_accept_seen;
    logic handoff_sent;
    logic [9:0] completed_line_y;
    logic [15:0] machine_pixel;
    logic machine_produce_pixel;
    logic machine_last_pixel_of_line;
    logic machine_last_line_of_frame;
    logic next_working_buffer_free;

    logic [1:0] line_ready_sync_1;
    logic [1:0] line_ready_sync_2;
    logic [1:0] line_ready_seen;
    logic [9:0] line_ready_y_sync_1;
    logic [9:0] line_ready_y_sync_2;
    logic sdram_pending_line;
    logic sdram_pending_buffer;
    logic [9:0] sdram_pending_y;

    framebuffer_machine_line_source #(
        .FRAMEBUFFER_WIDTH(FRAMEBUFFER_WIDTH),
        .FRAMEBUFFER_HEIGHT(FRAMEBUFFER_HEIGHT)
    ) machine_source (
        .clk(machine_clk),
        .reset(machine_reset),
        .produce_pixel(machine_produce_pixel),
        .pixel_x(producer_x),
        .line_y(producer_y),
        .frame_index(frame_index),
        .pixel(machine_pixel),
        .last_pixel_of_line(machine_last_pixel_of_line),
        .last_line_of_frame(machine_last_line_of_frame)
    );

    assign machine_produce_pixel = (machine_state == PRODUCER_FILL_LINE);
    assign next_working_buffer_free = !buffer_owned_by_writer[!working_buffer];
    assign stalled_waiting_for_free_line = (machine_state == PRODUCER_WAIT_FOR_FREE_LINE);
    assign stalled_waiting_for_writer = (machine_state == PRODUCER_HAND_OFF_LINE);

    // SDRAM-side presentation of one completed-line handoff to the existing
    // line writer. The Y coordinate is held unchanged until acceptance.
    assign line_ready_valid = sdram_pending_line;
    assign line_ready_buffer = sdram_pending_buffer;
    assign line_ready_y = sdram_pending_y;

    // Read port B of the true dual-port line RAMs.
    always_ff @(posedge sdram_clk) begin
        if (writer_read_buffer)
            writer_read_pixel <= line1_pixels[writer_read_x];
        else
            writer_read_pixel <= line0_pixels[writer_read_x];
    end

    // Machine-clock port A plus producer ownership state.
    always_ff @(posedge machine_clk) begin
        if (machine_reset) begin
            machine_state <= PRODUCER_RESET;
            working_buffer <= 1'b0;
            buffer_owned_by_writer <= 2'b00;
            line_ready_toggle <= 2'b00;
            line_release_sync_1 <= 2'b00;
            line_release_sync_2 <= 2'b00;
            line_release_seen <= 2'b00;
            line_accept_sync_1 <= 1'b0;
            line_accept_sync_2 <= 1'b0;
            line_accept_seen <= 1'b0;
            handoff_sent <= 1'b0;
            completed_line_y <= '0;
        end else begin
            line_release_sync_1 <= line_release_toggle;
            line_release_sync_2 <= line_release_sync_1;
            line_accept_sync_1 <= line_accept_toggle;
            line_accept_sync_2 <= line_accept_sync_1;

            if (line_release_sync_2 != line_release_seen) begin
                if (line_release_sync_2[0] != line_release_seen[0])
                    buffer_owned_by_writer[0] <= 1'b0;
                if (line_release_sync_2[1] != line_release_seen[1])
                    buffer_owned_by_writer[1] <= 1'b0;
                line_release_seen <= line_release_sync_2;
            end

            case (machine_state)
                PRODUCER_RESET: machine_state <= PRODUCER_FILL_LINE;

                PRODUCER_FILL_LINE: begin
                    if (working_buffer)
                        line1_pixels[producer_x] <= machine_pixel;
                    else
                        line0_pixels[producer_x] <= machine_pixel;

                    if (machine_last_pixel_of_line) begin
                        completed_line_y <= producer_y;
                        handoff_sent <= 1'b0;
                        machine_state <= PRODUCER_HAND_OFF_LINE;
                    end
                end

                PRODUCER_HAND_OFF_LINE: begin
                    if (!handoff_sent) begin
                        // completed_line_y was registered on the prior cycle,
                        // before this event can reach the SDRAM clock domain.
                        line_ready_toggle[working_buffer] <=
                            !line_ready_toggle[working_buffer];
                        handoff_sent <= 1'b1;
                    end else if (line_accept_sync_2 != line_accept_seen) begin
                        line_accept_seen <= line_accept_sync_2;
                        buffer_owned_by_writer[working_buffer] <= 1'b1;
                        if (STOP_AFTER_ONE_FRAME &&
                            completed_line_y == 10'(FRAMEBUFFER_HEIGHT - 1)) begin
                            machine_state <= PRODUCER_STOPPED;
                        end else if (next_working_buffer_free) begin
                            working_buffer <= !working_buffer;
                            machine_state <= PRODUCER_FILL_LINE;
                        end else begin
                            machine_state <= PRODUCER_WAIT_FOR_FREE_LINE;
                        end
                    end
                end

                PRODUCER_WAIT_FOR_FREE_LINE: begin
                    if (next_working_buffer_free) begin
                        working_buffer <= !working_buffer;
                        machine_state <= PRODUCER_FILL_LINE;
                    end
                end

                PRODUCER_STOPPED: begin
                    // The writer still drains the final handed-off line in
                    // the SDRAM domain. Its completion is the later cut point.
                end

                default: machine_state <= PRODUCER_RESET;
            endcase
        end
    end

    // SDRAM-clock control and the release event sent back to the machine.
    always_ff @(posedge sdram_clk) begin
        if (sdram_reset) begin
            line_ready_sync_1 <= 2'b00;
            line_ready_sync_2 <= 2'b00;
            line_ready_seen <= 2'b00;
            line_ready_y_sync_1 <= '0;
            line_ready_y_sync_2 <= '0;
            sdram_pending_line <= 1'b0;
            sdram_pending_buffer <= 1'b0;
            sdram_pending_y <= '0;
            line_accept_toggle <= 1'b0;
            line_release_toggle <= 2'b00;
        end else begin
            line_ready_sync_1 <= line_ready_toggle;
            line_ready_sync_2 <= line_ready_sync_1;
            line_ready_y_sync_1 <= completed_line_y;
            line_ready_y_sync_2 <= line_ready_y_sync_1;

            if (!sdram_pending_line && (line_ready_sync_2 != line_ready_seen)) begin
                if (line_ready_sync_2[0] != line_ready_seen[0])
                    sdram_pending_buffer <= 1'b0;
                else
                    sdram_pending_buffer <= 1'b1;
                sdram_pending_y <= line_ready_y_sync_2;
                sdram_pending_line <= 1'b1;
                line_ready_seen <= line_ready_sync_2;
            end

            if (sdram_pending_line && line_ready_accept) begin
                sdram_pending_line <= 1'b0;
                line_accept_toggle <= !line_accept_toggle;
            end

            if (line_release_valid)
                line_release_toggle[line_release_buffer] <=
                    !line_release_toggle[line_release_buffer];
        end
    end

    initial begin
        if (FRAMEBUFFER_WIDTH < 2) $error("framebuffer width must include both border edges");
        if (FRAMEBUFFER_HEIGHT < 2) $error("framebuffer height must include both border edges");
        if ((1 << LINE_ADDR_WIDTH) < FRAMEBUFFER_WIDTH) $error("line address width is too small");
    end
endmodule
