`timescale 1ns/1ps

// Compatibility test: experiment 008 producer request ports connect directly
// to the proven experiment 007 BL8 write backend and its SDRAM pin model.
module tb_framebuffer_producer_bl8_write_backend #(
    parameter integer TEST_WIDTH = 8,
    parameter integer TEST_HEIGHT = 4,
    parameter integer TEST_ADDR_WIDTH = 3,
    parameter integer TEST_CHUNK_WORDS = 8,
    parameter integer REQUIRE_PRODUCER_STALL = 0,
    parameter integer REFRESH_INTERVAL_CYCLES = 700,
    parameter integer REQUIRE_RUNTIME_REFRESH = 0
);
    localparam integer CHUNKS_PER_LINE = TEST_WIDTH / TEST_CHUNK_WORDS;
    localparam integer COMPLETIONS_TO_CHECK = (TEST_HEIGHT + 1) * CHUNKS_PER_LINE;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic producer_reset;
    logic init_done;
    logic backend_error;
    logic req_valid;
    logic req_ready;
    logic req_write;
    logic [26:0] req_byte_address;
    logic [15:0] req_words;
    logic [7:0] req_tag;
    logic write_valid;
    logic write_ready;
    logic [15:0] write_data;
    logic [1:0] write_byte_enable;
    logic completion_valid;
    logic completion_ready;
    logic [7:0] completion_tag;
    logic [15:0] completion_words;
    logic completion_error;
    logic [10:0] producer_pixel_x;
    logic [9:0] producer_line_y;
    logic [7:0] producer_frame_index;
    logic producer_stalled_waiting_for_free_line;
    logic producer_stalled_waiting_for_writer;
    logic writer_busy;
    logic writer_error;
    logic [12:0] sdram_a;
    logic [1:0] sdram_ba;
    logic sdram_cke;
    logic sdram_ncs;
    logic sdram_nras;
    logic sdram_ncas;
    logic sdram_nwe;
    logic sdram_dqml;
    logic sdram_dqmh;
    wire [15:0] sdram_dq;
    logic sdram_clk;
    integer completion_count;
    integer producer_stall_cycle_count;
    integer runtime_refresh_count;
    integer line_index;
    integer word_index;
    logic [15:0] expected;
    logic [24:0] expected_sdram_word_address;
    logic saw_producer_stall;

    always #5 clk = !clk;
    assign producer_reset = reset || !init_done;

    framebuffer_producer_write_path #(
        .FRAMEBUFFER_WIDTH(TEST_WIDTH),
        .FRAMEBUFFER_HEIGHT(TEST_HEIGHT),
        .LINE_ADDR_WIDTH(TEST_ADDR_WIDTH),
        .WRITE_CHUNK_WORDS(TEST_CHUNK_WORDS)
    ) producer (
        .clk(clk),
        .reset(producer_reset),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_write(req_write),
        .req_byte_address(req_byte_address),
        .req_words(req_words),
        .req_tag(req_tag),
        .write_valid(write_valid),
        .write_ready(write_ready),
        .write_data(write_data),
        .write_byte_enable(write_byte_enable),
        .completion_valid(completion_valid),
        .completion_ready(completion_ready),
        .completion_tag(completion_tag),
        .completion_words(completion_words),
        .completion_error(completion_error),
        .producer_pixel_x(producer_pixel_x),
        .producer_line_y(producer_line_y),
        .producer_frame_index(producer_frame_index),
        .producer_stalled_waiting_for_free_line(producer_stalled_waiting_for_free_line),
        .producer_stalled_waiting_for_writer(producer_stalled_waiting_for_writer),
        .writer_busy(writer_busy),
        .writer_error(writer_error)
    );

    framebuffer_bl8_write_backend #(
        .SDRAM_FREQ_HZ(100_000_000),
        .POWERUP_US(1),
        .REFRESH_INTERVAL_CYCLES(REFRESH_INTERVAL_CYCLES)
    ) backend (
        .clk(clk),
        .reset(reset),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_write(req_write),
        .req_byte_address(req_byte_address),
        .req_words(req_words),
        .req_tag(req_tag),
        .write_valid(write_valid),
        .write_ready(write_ready),
        .write_data(write_data),
        .write_byte_enable(write_byte_enable),
        .read_valid(),
        .read_ready(1'b1),
        .read_data(),
        .completion_valid(completion_valid),
        .completion_ready(completion_ready),
        .completion_tag(completion_tag),
        .completion_words(completion_words),
        .completion_error(completion_error),
        .init_done(init_done),
        .diagnostic_error(backend_error),
        .SDRAM_A(sdram_a),
        .SDRAM_BA(sdram_ba),
        .SDRAM_CKE(sdram_cke),
        .SDRAM_nCS(sdram_ncs),
        .SDRAM_nRAS(sdram_nras),
        .SDRAM_nCAS(sdram_ncas),
        .SDRAM_nWE(sdram_nwe),
        .SDRAM_DQML(sdram_dqml),
        .SDRAM_DQMH(sdram_dqmh),
        .SDRAM_DQ(sdram_dq),
        .SDRAM_CLK(sdram_clk)
    );

    sdram_pair_model memory (
        .clk(clk),
        .cke(sdram_cke),
        .ncs(sdram_ncs),
        .nras(sdram_nras),
        .ncas(sdram_ncas),
        .nwe(sdram_nwe),
        .a(sdram_a),
        .ba(sdram_ba),
        .dqml(sdram_dqml),
        .dqmh(sdram_dqmh),
        .dq(sdram_dq)
    );

    function automatic logic [15:0] expected_pixel(
        input logic [10:0] sample_x,
        input logic [9:0] sample_y,
        input logic [7:0] sample_frame
    );
        logic [4:0] red;
        logic [5:0] green;
        logic [4:0] blue;
        begin
            if ((sample_x == 11'd0) || (sample_x == 11'(TEST_WIDTH - 1)) ||
                (sample_y == 10'd0) || (sample_y == 10'(TEST_HEIGHT - 1))) begin
                expected_pixel = 16'hffff;
            end else begin
                red = sample_x[7:3] + sample_frame[4:0];
                green = sample_y[7:2] + {1'b0, sample_frame[4:0]};
                blue = (sample_x[6:2] ^ sample_y[6:2]) + sample_frame[4:0];
                expected_pixel = {red, green, blue};
            end
        end
    endfunction

    always_ff @(posedge clk) begin
        if (producer_reset) begin
            completion_count <= 0;
            saw_producer_stall <= 1'b0;
            producer_stall_cycle_count <= 0;
            runtime_refresh_count <= 0;
        end else begin
            if (completion_valid && completion_ready)
                completion_count <= completion_count + 1;
            if (producer_stalled_waiting_for_free_line || producer_stalled_waiting_for_writer) begin
                saw_producer_stall <= 1'b1;
                producer_stall_cycle_count <= producer_stall_cycle_count + 1;
            end
            if ({sdram_nras, sdram_ncas, sdram_nwe} == 3'b001)
                runtime_refresh_count <= runtime_refresh_count + 1;
        end
    end

    initial begin
        $dumpfile("build/framebuffer_producer_bl8_write_backend.vcd");
        $dumpvars(0, tb_framebuffer_producer_bl8_write_backend);
    end

    initial begin
        repeat (2) @(negedge clk);
        reset = 1'b0;

        // Four lines create frame zero; a fifth overwrites line zero in frame one.
        wait(completion_count == COMPLETIONS_TO_CHECK);
        repeat (20) @(posedge clk);

        if (writer_error || backend_error || completion_error) begin
            $fatal(1, "write error writer=%b backend=%b completion=%b",
                   writer_error, backend_error, completion_error);
        end

        for (line_index = 0; line_index < TEST_HEIGHT; line_index = line_index + 1) begin
            for (word_index = 0; word_index < TEST_WIDTH; word_index = word_index + 1) begin
                expected = expected_pixel(11'(word_index), 10'(line_index),
                                          (line_index == 0) ? 8'd1 : 8'd0);
                expected_sdram_word_address = line_index * TEST_WIDTH + word_index;
                if (memory.mem[0][expected_sdram_word_address[24:23]]
                               [expected_sdram_word_address[22:10]]
                               [expected_sdram_word_address[9:0]] !== expected) begin
                    $fatal(1, "SDRAM mismatch x=%0d y=%0d got=%h expected=%h",
                           word_index, line_index,
                           memory.mem[0][expected_sdram_word_address[24:23]]
                                     [expected_sdram_word_address[22:10]]
                                     [expected_sdram_word_address[9:0]], expected);
                end
            end
        end

        if (REQUIRE_PRODUCER_STALL && !saw_producer_stall)
            $fatal(1, "expected the producer to stall behind the BL8 backend");
        if (REQUIRE_RUNTIME_REFRESH && runtime_refresh_count == 0)
            $fatal(1, "expected at least one runtime refresh command");

        $display("PASS framebuffer_producer_bl8_write_backend: producer writes through BL8 SDRAM backend stall_cycles=%0d runtime_refreshes=%0d",
                 producer_stall_cycle_count, runtime_refresh_count);
        $finish;
    end

    initial begin
        repeat (100_000) @(posedge clk);
        $fatal(1, "producer BL8 write backend watchdog");
    end

    initial begin
        if ((TEST_WIDTH % TEST_CHUNK_WORDS) != 0)
            $fatal(1, "test chunk size must divide the line width evenly");
        if ((TEST_CHUNK_WORDS % 8) != 0)
            $fatal(1, "BL8 backend requires a request length divisible by eight");
    end
endmodule
