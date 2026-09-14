`timescale 1ns/1ps

// Two line buffers at the SDRAM-reader / scanout clock boundary.
//
// The fill side writes complete lines at fill_clk. The scanout side reads one
// completed line while holding the other for the next raster line. Ownership
// moves only through toggle handshakes, so neither side treats a raw signal
// from the other clock domain as an event.
module framebuffer_consumer_lines_dual_clock #(
    parameter integer FRAMEBUFFER_WIDTH = 1280,
    parameter integer LINE_ADDR_WIDTH = 11
) (
    input  logic                         fill_clk,
    input  logic                         fill_reset,
    output logic                         fill_ready,
    input  logic                         fill_valid,
    input  logic [15:0]                  fill_pixel,
    input  logic [9:0]                   fill_line_y,

    // A pulse in fill_clk when scanout has consumed the pending line and the
    // line scheduler may request another line from SDRAM.
    output logic                         fill_line_advance,
    output logic                         primed,
    output logic                         waiting_for_output_release,
    output logic                         overwrite_error,

    input  logic                         scanout_clk,
    input  logic                         scanout_reset,
    input  logic                         scanout_start,
    input  logic                         scanout_line_advance,
    input  logic [LINE_ADDR_WIDTH-1:0]   scanout_x,
    output logic [15:0]                  scanout_pixel,
    output logic                         scanout_pixel_valid,
    output logic [9:0]                   scanout_line_y,
    output logic                         scanout_underflow,
    // Temporary bring-up observation: counts raster lines intentionally
    // blanked because their replacement line was not ready in time.
    output logic [15:0]                  scanout_skipped_lines
);
    typedef enum logic { FILL_LINE, WAIT_FOR_RELEASE } fill_state_t;
    fill_state_t fill_state;

    (* ramstyle = "M10K" *) logic [15:0] line0_pixels [0:FRAMEBUFFER_WIDTH-1];
    (* ramstyle = "M10K" *) logic [15:0] line1_pixels [0:FRAMEBUFFER_WIDTH-1];

    logic filling_buffer;
    logic [LINE_ADDR_WIDTH-1:0] fill_x;
    logic display_buffer_fill;
    logic [9:0] display_line_y_fill;
    logic display_valid_fill;
    logic pending_buffer_fill;
    logic [9:0] pending_line_y_fill;
    logic pending_valid_fill;
    logic pending_publish_toggle;

    logic release_toggle_scanout;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic release_sync_1;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic release_sync_2;
    logic release_seen;

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic display_valid_sync_1;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic display_valid_sync_2;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic pending_toggle_sync_1;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic pending_toggle_sync_2;
    logic pending_seen_scanout;
    logic current_buffer_scanout;
    logic [9:0] current_line_y_scanout;
    logic current_valid_scanout;
    logic next_buffer_scanout;
    logic [9:0] next_line_y_scanout;
    logic next_valid_scanout;

    wire release_arrived = (release_sync_2 != release_seen);
    wire pending_arrived = (pending_toggle_sync_2 != pending_seen_scanout);
    wire last_fill_pixel = (fill_x == LINE_ADDR_WIDTH'(FRAMEBUFFER_WIDTH - 1));

    assign fill_ready = (fill_state == FILL_LINE);
    assign fill_line_advance = release_arrived;
    assign primed = display_valid_fill && pending_valid_fill;
    assign waiting_for_output_release = (fill_state == WAIT_FOR_RELEASE);

    // The fill-port writes are deliberately in the fast SDRAM-reader clock
    // domain. Quartus infers these as true dual-port M10K memories.
    always_ff @(posedge fill_clk) begin
        if (fill_reset) begin
            fill_state <= FILL_LINE;
            filling_buffer <= 1'b0;
            fill_x <= '0;
            display_buffer_fill <= 1'b0;
            display_line_y_fill <= '0;
            display_valid_fill <= 1'b0;
            pending_buffer_fill <= 1'b0;
            pending_line_y_fill <= '0;
            pending_valid_fill <= 1'b0;
            pending_publish_toggle <= 1'b0;
            release_sync_1 <= 1'b0;
            release_sync_2 <= 1'b0;
            release_seen <= 1'b0;
            overwrite_error <= 1'b0;
        end else begin
            release_sync_1 <= release_toggle_scanout;
            release_sync_2 <= release_sync_1;

            if (release_arrived) begin
                release_seen <= release_sync_2;
                if (!pending_valid_fill) begin
                    overwrite_error <= 1'b1;
                end else begin
                    // Scanout has switched to pending. The old display buffer
                    // is now free for the next reader fill.
                    display_buffer_fill <= pending_buffer_fill;
                    display_line_y_fill <= pending_line_y_fill;
                    pending_valid_fill <= 1'b0;
                    filling_buffer <= !pending_buffer_fill;
                    fill_state <= FILL_LINE;
                end
            end

            if (fill_valid && fill_ready) begin
                if (filling_buffer) line1_pixels[fill_x] <= fill_pixel;
                else                line0_pixels[fill_x] <= fill_pixel;

                if (last_fill_pixel) begin
                    fill_x <= '0;
                    if (!display_valid_fill) begin
                        display_buffer_fill <= filling_buffer;
                        display_line_y_fill <= fill_line_y;
                        display_valid_fill <= 1'b1;
                        filling_buffer <= !filling_buffer;
                    end else if (!pending_valid_fill) begin
                        pending_buffer_fill <= filling_buffer;
                        pending_line_y_fill <= fill_line_y;
                        pending_valid_fill <= 1'b1;
                        pending_publish_toggle <= !pending_publish_toggle;
                        fill_state <= WAIT_FOR_RELEASE;
                    end else begin
                        overwrite_error <= 1'b1;
                    end
                end else begin
                    fill_x <= fill_x + 1'b1;
                end
            end
        end
    end

    // The scanout port reads the same two memories from the slow video clock.
    always_ff @(posedge scanout_clk) begin
        if (scanout_reset) begin
            display_valid_sync_1 <= 1'b0;
            display_valid_sync_2 <= 1'b0;
            pending_toggle_sync_1 <= 1'b0;
            pending_toggle_sync_2 <= 1'b0;
            pending_seen_scanout <= 1'b0;
            current_buffer_scanout <= 1'b0;
            current_line_y_scanout <= '0;
            current_valid_scanout <= 1'b0;
            next_buffer_scanout <= 1'b0;
            next_line_y_scanout <= '0;
            next_valid_scanout <= 1'b0;
            release_toggle_scanout <= 1'b0;
            scanout_pixel <= 16'h0000;
            scanout_underflow <= 1'b0;
            scanout_skipped_lines <= '0;
        end else begin
            display_valid_sync_1 <= display_valid_fill;
            display_valid_sync_2 <= display_valid_sync_1;
            pending_toggle_sync_1 <= pending_publish_toggle;
            pending_toggle_sync_2 <= pending_toggle_sync_1;

            if (pending_arrived) begin
                pending_seen_scanout <= pending_toggle_sync_2;
                next_buffer_scanout <= pending_buffer_fill;
                next_line_y_scanout <= pending_line_y_fill;
                next_valid_scanout <= 1'b1;
            end

            if (scanout_start && display_valid_sync_2 && next_valid_scanout) begin
                current_buffer_scanout <= display_buffer_fill;
                current_line_y_scanout <= display_line_y_fill;
                current_valid_scanout <= 1'b1;
            end

            if (scanout_line_advance) begin
                if (next_valid_scanout) begin
                    current_buffer_scanout <= next_buffer_scanout;
                    current_line_y_scanout <= next_line_y_scanout;
                    current_valid_scanout <= 1'b1;
                    next_valid_scanout <= 1'b0;
                    // This acknowledges the previous display buffer. It is
                    // also correct after a blank line: that old buffer was
                    // held until a replacement had actually arrived.
                    release_toggle_scanout <= !release_toggle_scanout;
                end else begin
                    current_valid_scanout <= 1'b0;
                    scanout_underflow <= 1'b1;
                    if (&scanout_skipped_lines == 1'b0)
                        scanout_skipped_lines <= scanout_skipped_lines + 1'b1;
                end
            end

            if (current_buffer_scanout) scanout_pixel <= line1_pixels[scanout_x];
            else                        scanout_pixel <= line0_pixels[scanout_x];
        end
    end

    assign scanout_pixel_valid = current_valid_scanout;
    assign scanout_line_y = current_line_y_scanout;

    initial begin
        if (FRAMEBUFFER_WIDTH < 2) $error("framebuffer width must include both border edges");
        if ((1 << LINE_ADDR_WIDTH) < FRAMEBUFFER_WIDTH) $error("line address width is too small");
    end
endmodule
