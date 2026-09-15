`timescale 1ns/1ps

// Read-side isolation at the real integration boundary. The MIT controller
// drives commands through the shared PHY output registers; a full-page SDRAM
// model drives the physical DQ pins; and returned words travel back through
// the shared PHY capture port, backend capture pipeline, and burst cache.
module tb_framebuffer_shared_phy_page_read;
    localparam integer REQUEST_WORDS = 256;
    localparam integer PAGES_TO_INITIALIZE = 4;

    logic clk = 1'b0;
    logic capture_clk = 1'b0;
    logic reset = 1'b1;
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
    wire init_done;

    wire [12:0] reader_a;
    wire [1:0] reader_ba;
    wire reader_cke, reader_ncs, reader_nras, reader_ncas, reader_nwe;
    wire reader_dqml, reader_dqmh, reader_dq_oe;
    wire [15:0] reader_dq_out;
    wire [15:0] dq_capture;

    wire [12:0] sdram_a;
    wire [1:0] sdram_ba;
    wire sdram_cke, sdram_ncs, sdram_nras, sdram_ncas, sdram_nwe;
    wire sdram_dqml, sdram_dqmh, sdram_clk;
    wire [15:0] sdram_dq;

    integer page_index;
    integer column_index;
    integer checked_words;
    integer mismatch_count;

    always #3.5 clk = !clk;
    initial begin
        #2;
        forever #3.5 capture_clk = !capture_clk;
    end

    framebuffer_agg23_read_backend #(
        .SDRAM_FREQ_MHZ(143),
        .PHY_DQ_CAPTURE_STAGES(1),
        .PHY_COMMAND_LAUNCH_STAGES(1)
    ) reader (
        .clk, .capture_clk, .reset, .req_valid, .req_ready, .req_write(1'b0),
        .req_byte_address, .req_words, .req_tag,
        .read_valid, .read_ready, .read_data,
        .completion_valid, .completion_ready, .completion_tag,
        .completion_words, .completion_error, .init_done,
        .SDRAM_A(reader_a), .SDRAM_BA(reader_ba), .SDRAM_CKE(reader_cke),
        .SDRAM_nCS(reader_ncs), .SDRAM_nRAS(reader_nras),
        .SDRAM_nCAS(reader_ncas), .SDRAM_nWE(reader_nwe),
        .SDRAM_DQML(reader_dqml), .SDRAM_DQMH(reader_dqmh),
        .sdram_dq_in(dq_capture), .sdram_dq_out(reader_dq_out),
        .sdram_dq_oe(reader_dq_oe), .SDRAM_CLK()
    );

    framebuffer_sdram_phy phy (
        .clk, .capture_clk, .producer_owns(1'b0), .reader_owns(1'b1),
        .producer_a('0), .producer_ba('0), .producer_cke(1'b0),
        .producer_ncs(1'b1), .producer_nras(1'b1), .producer_ncas(1'b1),
        .producer_nwe(1'b1), .producer_dqml(1'b1), .producer_dqmh(1'b1),
        .producer_dq_out('0), .producer_dq_oe(1'b0),
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

    function automatic logic [15:0] expected_word(input integer word_address);
        expected_word = 16'h4000 ^ word_address[15:0];
    endfunction

    task automatic request_and_check(
        input integer start_word,
        input integer word_count,
        input logic [7:0] tag
    );
        integer request_word_index;
        begin
            @(negedge clk);
            req_byte_address = start_word * 2;
            req_words = word_count;
            req_tag = tag;
            req_valid = 1'b1;
            while (!req_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            req_valid = 1'b0;

            request_word_index = 0;
            while (request_word_index < word_count) begin
                @(posedge clk);
                #1;
                if (read_valid && read_ready) begin
                    if (request_word_index < 3 ||
                        request_word_index >= word_count - 2)
                        $display("READ_EDGE start=%0d index=%0d got=%h expected=%h",
                                 start_word, request_word_index, read_data,
                                 expected_word(start_word + request_word_index));
                    if (read_data !== expected_word(start_word + request_word_index)) begin
                        if (mismatch_count < 16)
                            $display("READ_MISMATCH absolute_word=%0d request_word=%0d got=%h expected=%h",
                                     start_word + request_word_index,
                                     request_word_index, read_data,
                                     expected_word(start_word + request_word_index));
                        mismatch_count = mismatch_count + 1;
                    end
                    request_word_index = request_word_index + 1;
                    checked_words = checked_words + 1;
                end
            end

            wait (completion_valid);
            if (completion_error || completion_tag != tag ||
                completion_words != word_count)
                $fatal(1, "bad completion tag=%h expected_tag=%h words=%0d expected_words=%0d error=%b",
                       completion_tag, tag, completion_words, word_count,
                       completion_error);
            @(negedge clk);
            completion_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            completion_ready = 1'b0;
        end
    endtask

    initial begin
        // Each physical SDRAM row is one 1024-word cache page. Address-unique
        // contents make a one-word slip visible immediately instead of merely
        // checking that some plausible colour reached the cache.
        for (page_index = 0; page_index < PAGES_TO_INITIALIZE;
             page_index = page_index + 1)
            for (column_index = 0; column_index < 1024;
                 column_index = column_index + 1)
                memory.mem[0][page_index][column_index] =
                    expected_word(page_index * 1024 + column_index);

        checked_words = 0;
        mismatch_count = 0;
        repeat (5) @(negedge clk);
        reset = 1'b0;
        wait (init_done);

        // Two requests share page zero, then later requests cross physical
        // rows. The 1280 and 2560 starts are real framebuffer line starts.
        request_and_check(0, REQUEST_WORDS, 8'h10);
        request_and_check(768, REQUEST_WORDS, 8'h11);
        request_and_check(1024, REQUEST_WORDS, 8'h12);
        request_and_check(1280, REQUEST_WORDS, 8'h13);
        request_and_check(2048, REQUEST_WORDS, 8'h14);
        request_and_check(2560, REQUEST_WORDS, 8'h15);

        if (mismatch_count != 0)
            $fatal(1, "shared-PHY page reader returned %0d mismatched words out of %0d",
                   mismatch_count, checked_words);

        $display("PASS framebuffer_shared_phy_page_read: checked %0d words across four physical pages",
                 checked_words);
        $finish;
    end

    initial begin
        repeat (100_000) @(posedge clk);
        $display("WATCHDOG cache_state=%0d fetch_index=%0d controller_state=%0d p0_ready=%b",
                 reader.cache.state, reader.cache.fetch_index,
                 reader.controller.state, reader.p0_ready);
        $display("WATCHDOG valid raw=%b d1=%b d2=%b d3=%b cache=%b",
                 reader.p0_data_available,
                 reader.p0_data_available_captured_1,
                 reader.p0_data_available_captured_2,
                 reader.p0_data_available_captured_3,
                 reader.cache_p0_data_available);
        $fatal(1, "shared-PHY page-reader watchdog");
    end
endmodule
