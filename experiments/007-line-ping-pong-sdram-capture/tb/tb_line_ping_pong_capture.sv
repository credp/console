`timescale 1ns/1ps
module tb_line_ping_pong_capture;
    logic clk = 0, reset = 1;
    always #5 clk = ~clk;

    logic [10:0] video_x = 0;
    logic [9:0] video_y = 0;
    logic video_de = 1;
    logic [15:0] video_pixel;
    logic video_buffer;

    logic req_valid, req_ready, req_write;
    logic [26:0] req_byte_address;
    logic [15:0] req_words;
    logic [7:0] req_tag;
    logic write_valid, write_ready;
    logic [15:0] write_data;
    logic [1:0] write_byte_enable;
    logic read_valid, read_ready = 1;
    logic [15:0] read_data;
    logic completion_valid, completion_ready;
    logic [7:0] completion_tag;
    logic [15:0] completion_words;
    logic completion_error, init_done;
    logic [12:0] sdram_a;
    logic [1:0] sdram_ba;
    logic sdram_cke, sdram_ncs, sdram_nras, sdram_ncas, sdram_nwe;
    logic sdram_dqml, sdram_dqmh;
    wire [15:0] dq;
    logic [15:0] sdram_dq_in, sdram_dq_out;
    logic sdram_dq_oe;
    logic [31:0] source_lines_generated, sdram_lines_submitted, sdram_lines_completed;
    logic reuse_before_drain_error;
    logic [15:0] worst_line_drain_cycles, current_line_drain_cycles;
    logic late_refresh0, late_refresh1, refresh_pending, timing_violation;
    logic turnaround_blocked, row_hit, phy_busy;

    assign dq = sdram_dq_oe ? sdram_dq_out : 16'hzzzz;
    assign sdram_dq_in = dq;

    line_ping_pong_capture dut (
        .clk_source(clk), .reset_source(reset | ~init_done),
        .clk_video(clk), .reset_video(reset | ~init_done),
        .video_x, .video_y, .video_de, .video_pixel, .video_buffer,
        .req_valid, .req_ready, .req_write, .req_byte_address, .req_words, .req_tag,
        .write_valid, .write_ready, .write_data, .write_byte_enable,
        .completion_valid, .completion_ready, .completion_tag, .completion_words,
        .completion_error, .source_lines_generated, .sdram_lines_submitted,
        .sdram_lines_completed, .reuse_before_drain_error,
        .worst_line_drain_cycles, .current_line_drain_cycles
    );

    sdram_single_client_controller #(
        .SDRAM_FREQ_HZ(100_000_000), .POWERUP_US(1), .INIT_REFRESH_COUNT(2),
        .READ_CAPTURE_CYCLES(3), .MAX_REFRESH_SERVICE_CYCLES(24),
        .MAX_REQUEST_WORDS(1280)
    ) controller (
        .clk, .reset, .req_valid, .req_ready, .req_write, .req_byte_address,
        .req_words, .req_tag, .write_valid, .write_ready, .write_data,
        .write_byte_enable, .read_valid, .read_ready, .read_data,
        .completion_valid, .completion_ready, .completion_tag, .completion_words,
        .completion_error, .init_done, .sdram_a, .sdram_ba, .sdram_cke,
        .sdram_ncs, .sdram_nras, .sdram_ncas, .sdram_nwe, .sdram_dqml,
        .sdram_dqmh, .sdram_dq_in, .sdram_dq_out, .sdram_dq_oe,
        .late_refresh0, .late_refresh1, .refresh_pending, .timing_violation,
        .turnaround_blocked, .row_hit, .phy_busy
    );

    sdram_pair_model memory (
        .clk, .cke(sdram_cke), .ncs(sdram_ncs), .nras(sdram_nras),
        .ncas(sdram_ncas), .nwe(sdram_nwe), .a(sdram_a), .ba(sdram_ba),
        .dqml(sdram_dqml), .dqmh(sdram_dqmh), .dq
    );

    function automatic [15:0] pattern(input int x, input int y, input int frame);
        pattern = {5'((x >> 6) + frame), 6'((y >> 3) ^ frame), 5'((x >> 1) ^ (y >> 3))};
    endfunction

    logic last_completed_lsb = 0;
    logic [31:0] previous_completed = 0;
    integer accepted_requests = 0;
    integer completed_chunks = 0;
    integer presented_from_buffer0 = 0;
    integer presented_from_buffer1 = 0;

    always_ff @(posedge clk) begin
        if (reset | ~init_done) begin
            video_x <= 0;
            video_y <= 0;
        end else begin
            video_de <= (video_x < 11'd1279);
            if (video_x == 11'd1649) begin
                video_x <= 0;
                video_y <= (video_y == 10'd719) ? 0 : video_y + 1'b1;
            end else begin
                video_x <= video_x + 1'b1;
            end
        end

        if (req_valid && req_ready) begin
            accepted_requests <= accepted_requests + 1;
            if (!req_write || req_words != 16'd1280 || req_byte_address[0])
                $fatal(1, "bad SDRAM request");
        end
        if (completion_valid && completion_ready) completed_chunks <= completed_chunks + 1;

        if (source_lines_generated > previous_completed) begin
            if (source_lines_generated > 1 && source_lines_generated[0] == last_completed_lsb)
                $fatal(1, "line buffers did not alternate");
            last_completed_lsb <= source_lines_generated[0];
            previous_completed <= source_lines_generated;
        end

        if (video_x == 11'd16 && source_lines_generated > 2) begin
            if (video_pixel !== pattern(15, source_lines_generated - 1, 0))
                $fatal(1, "presented pixel mismatch got=%h expected=%h",
                       video_pixel, pattern(15, source_lines_generated - 1, 0));
            if (video_buffer) presented_from_buffer1 <= presented_from_buffer1 + 1;
            else presented_from_buffer0 <= presented_from_buffer0 + 1;
        end
    end

    initial begin
        repeat (2) @(negedge clk);
        reset = 0;
        wait(sdram_lines_completed >= 4);
        repeat (20) @(posedge clk);
        if (sdram_lines_submitted < sdram_lines_completed ||
            sdram_lines_submitted > sdram_lines_completed + 1)
            $fatal(1, "unexpected submitted/completed distance %0d/%0d",
                   sdram_lines_submitted, sdram_lines_completed);
        if (completed_chunks != sdram_lines_completed)
            $fatal(1, "each completed line should complete one request");
        if (sdram_lines_submitted > source_lines_generated)
            $fatal(1, "submitted more lines than generated");
        if (reuse_before_drain_error)
            $fatal(1, "buffer reuse before SDRAM drain");
        if (!presented_from_buffer0 || !presented_from_buffer1)
            $fatal(1, "presentation did not observe both completed buffers");
        if (late_refresh0 || late_refresh1 || timing_violation)
            $fatal(1, "SDRAM controller diagnostic failure");
        $display("PASS line ping-pong capture: lines=%0d requests=%0d worst_drain=%0d",
                 sdram_lines_completed, accepted_requests, worst_line_drain_cycles);
        $finish;
    end

    initial begin
        repeat (30000) @(posedge clk);
        $fatal(1, "line ping-pong capture watchdog");
    end
endmodule
