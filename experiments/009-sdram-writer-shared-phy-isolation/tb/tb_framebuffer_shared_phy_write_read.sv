`timescale 1ns/1ps

// End-to-end physical-pin round trip for the temporary one-shot architecture:
//
//   machine pixel producer -> BL8 writer -> shared PHY -> SDRAM model
//   SDRAM model -> shared PHY -> agg23 reader/cache -> checked read stream
//
// Eight complete 1280-word lines cross ten 1024-word SDRAM pages. Consequently
// framebuffer line starts repeatedly move within a physical page, which catches
// disagreement about byte/word, line, row, column, or bank address ownership.
module tb_framebuffer_shared_phy_write_read;
    localparam integer FRAMEBUFFER_WIDTH = 1280;
    localparam integer FRAMEBUFFER_HEIGHT = 8;
    localparam integer FRAMEBUFFER_WORDS = FRAMEBUFFER_WIDTH * FRAMEBUFFER_HEIGHT;
    localparam integer READ_CHUNK_WORDS = 256;

    logic clk = 1'b0;
    logic capture_clk = 1'b0;
    logic machine_clk = 1'b0;
    logic reset = 1'b1;

    wire writer_init_done, writer_error, write_completion, frame_write_complete;
    wire [2:0] writer_error_reason;
    wire [12:0] writer_a;
    wire [1:0] writer_ba;
    wire writer_cke, writer_ncs, writer_nras, writer_ncas, writer_nwe;
    wire writer_dqml, writer_dqmh, writer_dq_oe;
    wire [15:0] writer_dq_out;

    logic req_valid = 1'b0;
    wire req_ready;
    logic [26:0] req_byte_address = '0;
    logic [15:0] req_words = '0;
    logic [7:0] req_tag = '0;
    wire read_valid;
    logic read_ready = 1'b1;
    wire [15:0] read_data;
    wire completion_valid;
    logic completion_ready = 1'b0;
    wire [7:0] completion_tag;
    wire [15:0] completion_words;
    wire completion_error;
    wire reader_init_done;
    wire [12:0] reader_a;
    wire [1:0] reader_ba;
    wire reader_cke, reader_ncs, reader_nras, reader_ncas, reader_nwe;
    wire reader_dqml, reader_dqmh, reader_dq_oe;
    wire [15:0] reader_dq_out;

    wire producer_owns_sdram, reader_reset, reader_owns_sdram, framebuffer_ready;
    wire [12:0] sdram_a;
    wire [1:0] sdram_ba;
    wire sdram_cke, sdram_ncs, sdram_nras, sdram_ncas, sdram_nwe;
    wire sdram_dqml, sdram_dqmh, sdram_clk;
    wire [15:0] sdram_dq, dq_capture;

    integer checked_words;
    integer line_completion_count;

    always #3.5 clk = !clk;
    initial begin
        #2;
        forever #3.5 capture_clk = !capture_clk;
    end
    always #25 machine_clk = !machine_clk;

    framebuffer_producer_bl8_sdram_path #(
        .FRAMEBUFFER_WIDTH(FRAMEBUFFER_WIDTH),
        .FRAMEBUFFER_HEIGHT(FRAMEBUFFER_HEIGHT),
        .LINE_ADDR_WIDTH(11),
        .WRITE_CHUNK_WORDS(FRAMEBUFFER_WIDTH),
        .SDRAM_FREQ_HZ(142_857_000),
        .SDRAM_POWERUP_US(1),
        .STOP_AFTER_ONE_FRAME(1),
        .USE_INTERNAL_PHY(0)
    ) producer (
        .machine_clk, .sdram_clk(clk), .reset,
        .sdram_init_done(writer_init_done), .sdram_error(),
        .write_completion, .frame_write_complete,
        .producer_pixel_x(), .producer_line_y(), .producer_frame_index(),
        .producer_stalled_waiting_for_free_line(),
        .producer_stalled_waiting_for_writer(), .writer_busy(),
        .writer_error, .writer_error_reason,
        .protocol_a(writer_a), .protocol_ba(writer_ba),
        .protocol_cke(writer_cke), .protocol_ncs(writer_ncs),
        .protocol_nras(writer_nras), .protocol_ncas(writer_ncas),
        .protocol_nwe(writer_nwe), .protocol_dqml(writer_dqml),
        .protocol_dqmh(writer_dqmh), .protocol_dq_out(writer_dq_out),
        .protocol_dq_oe(writer_dq_oe),
        .SDRAM_A(), .SDRAM_BA(), .SDRAM_CKE(), .SDRAM_nCS(),
        .SDRAM_nRAS(), .SDRAM_nCAS(), .SDRAM_nWE(), .SDRAM_DQML(),
        .SDRAM_DQMH(), .SDRAM_DQ(), .SDRAM_CLK(),
        .sdram_dq_out(), .sdram_dq_oe()
    );

    framebuffer_one_shot_handoff handoff (
        .clk, .reset, .frame_write_complete, .reader_init_done,
        .producer_owns_sdram, .reader_reset, .reader_owns_sdram,
        .framebuffer_ready
    );

    framebuffer_agg23_read_backend #(
        .SDRAM_FREQ_MHZ(143),
        .PHY_DQ_CAPTURE_STAGES(1),
        .PHY_COMMAND_LAUNCH_STAGES(1)
    ) reader (
        .clk, .capture_clk, .reset(reset | reader_reset), .req_valid, .req_ready,
        .req_write(1'b0), .req_byte_address, .req_words, .req_tag,
        .read_valid, .read_ready, .read_data,
        .completion_valid, .completion_ready, .completion_tag,
        .completion_words, .completion_error, .init_done(reader_init_done),
        .SDRAM_A(reader_a), .SDRAM_BA(reader_ba), .SDRAM_CKE(reader_cke),
        .SDRAM_nCS(reader_ncs), .SDRAM_nRAS(reader_nras),
        .SDRAM_nCAS(reader_ncas), .SDRAM_nWE(reader_nwe),
        .SDRAM_DQML(reader_dqml), .SDRAM_DQMH(reader_dqmh),
        .sdram_dq_in(dq_capture), .sdram_dq_out(reader_dq_out),
        .sdram_dq_oe(reader_dq_oe), .SDRAM_CLK()
    );

    framebuffer_sdram_phy phy (
        .clk, .capture_clk, .producer_owns(producer_owns_sdram),
        .reader_owns(reader_owns_sdram),
        .producer_a(writer_a), .producer_ba(writer_ba),
        .producer_cke(writer_cke), .producer_ncs(writer_ncs),
        .producer_nras(writer_nras), .producer_ncas(writer_ncas),
        .producer_nwe(writer_nwe), .producer_dqml(writer_dqml),
        .producer_dqmh(writer_dqmh), .producer_dq_out(writer_dq_out),
        .producer_dq_oe(writer_dq_oe),
        .reader_a, .reader_ba, .reader_cke, .reader_ncs, .reader_nras,
        .reader_ncas, .reader_nwe, .reader_dqml, .reader_dqmh,
        .reader_dq_out, .reader_dq_oe, .dq_capture,
        .SDRAM_A(sdram_a), .SDRAM_BA(sdram_ba), .SDRAM_CKE(sdram_cke),
        .SDRAM_nCS(sdram_ncs), .SDRAM_nRAS(sdram_nras),
        .SDRAM_nCAS(sdram_ncas), .SDRAM_nWE(sdram_nwe),
        .SDRAM_DQML(sdram_dqml), .SDRAM_DQMH(sdram_dqmh),
        .SDRAM_DQ(sdram_dq), .SDRAM_CLK(sdram_clk)
    );

    agg23_sdram_pin_model memory (
        .clk(sdram_clk), .cke(sdram_cke), .ncs(sdram_ncs),
        .nras(sdram_nras), .ncas(sdram_ncas), .nwe(sdram_nwe),
        .a(sdram_a), .ba(sdram_ba), .dqml(sdram_dqml),
        .dqmh(sdram_dqmh), .dq(sdram_dq)
    );

    function automatic logic [15:0] expected_pixel(input integer word_address);
        integer x, y;
        logic [4:0] red, blue;
        logic [5:0] green;
        begin
            x = word_address % FRAMEBUFFER_WIDTH;
            y = word_address / FRAMEBUFFER_WIDTH;
            if (x == 0 || x == FRAMEBUFFER_WIDTH - 1 ||
                y == 0 || y == FRAMEBUFFER_HEIGHT - 1) begin
                expected_pixel = 16'hffff;
            end else begin
                red = {x[10:8], 2'b00};
                green = {y[9:7], 3'b000};
                blue = {(x[10:8] ^ y[9:7]), 2'b00};
                expected_pixel = {red, green, blue};
            end
        end
    endfunction

    task automatic request_and_check(input integer start_word,
                                     input logic [7:0] tag);
        integer chunk_index;
        logic [15:0] expected;
        begin
            @(negedge clk);
            req_byte_address = start_word * 2;
            req_words = READ_CHUNK_WORDS;
            req_tag = tag;
            req_valid = 1'b1;
            while (!req_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            req_valid = 1'b0;

            chunk_index = 0;
            while (chunk_index < READ_CHUNK_WORDS) begin
                @(posedge clk);
                #1;
                if (read_valid && read_ready) begin
                    expected = expected_pixel(start_word + chunk_index);
                    if (read_data !== expected)
                        $fatal(1, "round-trip mismatch word=%0d x=%0d y=%0d got=%h expected=%h",
                               start_word + chunk_index,
                               (start_word + chunk_index) % FRAMEBUFFER_WIDTH,
                               (start_word + chunk_index) / FRAMEBUFFER_WIDTH,
                               read_data, expected);
                    checked_words = checked_words + 1;
                    chunk_index = chunk_index + 1;
                end
            end

            wait (completion_valid);
            if (completion_error || completion_tag != tag ||
                completion_words != READ_CHUNK_WORDS)
                $fatal(1, "bad read completion tag=%h words=%0d error=%b",
                       completion_tag, completion_words, completion_error);
            @(negedge clk);
            completion_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            completion_ready = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (reset)
            line_completion_count <= 0;
        else if (write_completion)
            line_completion_count <= line_completion_count + 1;
    end

    integer chunk_start;
    initial begin
        checked_words = 0;
        line_completion_count = 0;
        repeat (5) @(negedge clk);
        reset = 1'b0;

        wait (framebuffer_ready);
        if (!writer_init_done || writer_error)
            $fatal(1, "writer failed before handoff error=%b reason=%b",
                   writer_error, writer_error_reason);
        if (line_completion_count != FRAMEBUFFER_HEIGHT)
            $fatal(1, "wrong write completion count got=%0d expected=%0d",
                   line_completion_count, FRAMEBUFFER_HEIGHT);

        for (chunk_start = 0; chunk_start < FRAMEBUFFER_WORDS;
             chunk_start = chunk_start + READ_CHUNK_WORDS)
            request_and_check(chunk_start, chunk_start / READ_CHUNK_WORDS);

        if (checked_words != FRAMEBUFFER_WORDS)
            $fatal(1, "wrong checked word count got=%0d expected=%0d",
                   checked_words, FRAMEBUFFER_WORDS);

        $display("PASS framebuffer_shared_phy_write_read: %0d produced words survived physical SDRAM round trip",
                 checked_words);
        $finish;
    end

    initial begin
        repeat (1_000_000) @(posedge clk);
        $fatal(1, "shared-PHY write/read watchdog checked=%0d", checked_words);
    end
endmodule
