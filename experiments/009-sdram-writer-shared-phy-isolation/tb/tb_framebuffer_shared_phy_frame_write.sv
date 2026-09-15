`timescale 1ns/1ps

// Full-frame writer isolation test.
//
// Unlike the older producer test, this test does not stop at the writer's
// internal protocol bundle. It observes the board-facing command and DQ pins
// after the shared PHY registers, on the rising edge of the forwarded SDRAM
// clock. A small pin-level scoreboard reconstructs each physical word address
// and compares all 921,600 writes with the intended framebuffer image.
module tb_framebuffer_shared_phy_frame_write;
    localparam integer FRAMEBUFFER_WIDTH = 1280;
    localparam integer FRAMEBUFFER_HEIGHT = 720;
    localparam integer FRAMEBUFFER_WORDS = FRAMEBUFFER_WIDTH * FRAMEBUFFER_HEIGHT;

    logic sdram_logic_clk = 1'b0;
    logic machine_clk = 1'b0;
    logic reset = 1'b1;

    wire sdram_init_done;
    wire sdram_error;
    wire write_completion;
    wire frame_write_complete;
    wire writer_error;
    wire [2:0] writer_error_reason;
    wire [12:0] producer_a;
    wire [1:0] producer_ba;
    wire producer_cke, producer_ncs, producer_nras, producer_ncas, producer_nwe;
    wire producer_dqml, producer_dqmh, producer_dq_oe;
    wire [15:0] producer_dq_out;

    wire [12:0] sdram_a;
    wire [1:0] sdram_ba;
    wire sdram_cke, sdram_ncs, sdram_nras, sdram_ncas, sdram_nwe;
    wire sdram_dqml, sdram_dqmh;
    wire sdram_clk;
    wire [15:0] sdram_dq;

    integer physical_word_count;
    integer completion_count;
    logic [12:0] open_row [0:3];
    logic [3:0] open_valid;
    logic [2:0] burst_beats_remaining;
    logic [1:0] burst_bank;
    logic [12:0] burst_row;
    logic [9:0] burst_column;

    // 142.857 MHz SDRAM mechanism clock and the approximately 20 MHz machine
    // clock used by the fitted experiment.
    always #3.5 sdram_logic_clk = !sdram_logic_clk;
    always #25 machine_clk = !machine_clk;

    framebuffer_producer_bl8_sdram_path #(
        .FRAMEBUFFER_WIDTH(FRAMEBUFFER_WIDTH),
        .FRAMEBUFFER_HEIGHT(FRAMEBUFFER_HEIGHT),
        .LINE_ADDR_WIDTH(11),
        .WRITE_CHUNK_WORDS(1280),
        .SDRAM_FREQ_HZ(142_857_000),
        .SDRAM_POWERUP_US(1),
        .STOP_AFTER_ONE_FRAME(1),
        .USE_INTERNAL_PHY(0)
    ) producer (
        .machine_clk, .sdram_clk(sdram_logic_clk), .reset,
        .sdram_init_done, .sdram_error, .write_completion,
        .frame_write_complete,
        .producer_pixel_x(), .producer_line_y(), .producer_frame_index(),
        .producer_stalled_waiting_for_free_line(),
        .producer_stalled_waiting_for_writer(),
        .writer_busy(), .writer_error, .writer_error_reason,
        .protocol_a(producer_a), .protocol_ba(producer_ba),
        .protocol_cke(producer_cke), .protocol_ncs(producer_ncs),
        .protocol_nras(producer_nras), .protocol_ncas(producer_ncas),
        .protocol_nwe(producer_nwe), .protocol_dqml(producer_dqml),
        .protocol_dqmh(producer_dqmh), .protocol_dq_out(producer_dq_out),
        .protocol_dq_oe(producer_dq_oe),
        .SDRAM_A(), .SDRAM_BA(), .SDRAM_CKE(), .SDRAM_nCS(),
        .SDRAM_nRAS(), .SDRAM_nCAS(), .SDRAM_nWE(), .SDRAM_DQML(),
        .SDRAM_DQMH(), .SDRAM_DQ(), .SDRAM_CLK(),
        .sdram_dq_out(), .sdram_dq_oe()
    );

    framebuffer_sdram_phy phy (
        .clk(sdram_logic_clk), .capture_clk(sdram_logic_clk),
        .producer_owns(1'b1), .reader_owns(1'b0),
        .producer_a, .producer_ba, .producer_cke, .producer_ncs,
        .producer_nras, .producer_ncas, .producer_nwe,
        .producer_dqml, .producer_dqmh, .producer_dq_out, .producer_dq_oe,
        .reader_a('0), .reader_ba('0), .reader_cke(1'b0),
        .reader_ncs(1'b1), .reader_nras(1'b1), .reader_ncas(1'b1),
        .reader_nwe(1'b1), .reader_dqml(1'b1), .reader_dqmh(1'b1),
        .reader_dq_out('0), .reader_dq_oe(1'b0), .dq_capture(),
        .SDRAM_A(sdram_a), .SDRAM_BA(sdram_ba), .SDRAM_CKE(sdram_cke),
        .SDRAM_nCS(sdram_ncs), .SDRAM_nRAS(sdram_nras),
        .SDRAM_nCAS(sdram_ncas), .SDRAM_nWE(sdram_nwe),
        .SDRAM_DQML(sdram_dqml), .SDRAM_DQMH(sdram_dqmh),
        .SDRAM_DQ(sdram_dq), .SDRAM_CLK(sdram_clk)
    );

    function automatic logic [15:0] expected_pixel(input integer x, input integer y);
        logic [4:0] red;
        logic [5:0] green;
        logic [4:0] blue;
        begin
            if (x == 0 || x == FRAMEBUFFER_WIDTH - 1 ||
                y == 0 || y == FRAMEBUFFER_HEIGHT - 1) begin
                expected_pixel = 16'hffff;
            end else if (x >= 632 && x < 648 && y >= 352 && y < 368 &&
                         (x[3:0] == 4'd7 || y[3:0] == 4'd7)) begin
                expected_pixel = 16'hf81f;
            end else begin
                red = {x[10:8], 2'b00};
                green = {y[9:7], 3'b000};
                blue = {(x[10:8] ^ y[9:7]), 2'b00};
                expected_pixel = {red, green, blue};
            end
        end
    endfunction

    task automatic check_physical_word(
        input logic [24:0] physical_address,
        input logic [15:0] observed
    );
        integer expected_x;
        integer expected_y;
        logic [15:0] expected;
        begin
            expected_x = physical_word_count % FRAMEBUFFER_WIDTH;
            expected_y = physical_word_count / FRAMEBUFFER_WIDTH;
            expected = expected_pixel(expected_x, expected_y);

            if (physical_address !== 25'(physical_word_count))
                $fatal(1, "physical address discontinuity word=%0d got=%0d expected=%0d",
                       physical_word_count, physical_address, physical_word_count);
            if ({sdram_dqmh, sdram_dqml} !== 2'b00)
                $fatal(1, "unexpected DQM word=%0d dqm=%b", physical_word_count,
                       {sdram_dqmh, sdram_dqml});
            if (observed !== expected)
                $fatal(1, "physical DQ mismatch word=%0d x=%0d y=%0d got=%h expected=%h",
                       physical_word_count, expected_x, expected_y, observed, expected);

            physical_word_count = physical_word_count + 1;
        end
    endtask

    // The PHY forwards an inverted clock. Sampling this physical clock checks
    // the half-cycle launch convention as the SDRAM device sees it.
    always @(posedge sdram_clk) begin
        if (reset) begin
            physical_word_count = 0;
            open_valid = '0;
            burst_beats_remaining = '0;
            burst_bank = '0;
            burst_row = '0;
            burst_column = '0;
        end else if (sdram_cke) begin
            if (burst_beats_remaining != 0) begin
                check_physical_word({burst_bank, burst_row, burst_column}, sdram_dq);
                burst_column = {burst_column[9:3], burst_column[2:0] + 3'd1};
                burst_beats_remaining = burst_beats_remaining - 1'b1;
            end

            case ({sdram_nras, sdram_ncas, sdram_nwe})
                3'b011: begin
                    open_row[sdram_ba] = sdram_a;
                    open_valid[sdram_ba] = 1'b1;
                end
                3'b100: begin
                    if (!open_valid[sdram_ba])
                        $fatal(1, "WRITE issued without an open row at word=%0d",
                               physical_word_count);
                    if (burst_beats_remaining != 0)
                        $fatal(1, "overlapping WRITE bursts at word=%0d",
                               physical_word_count);
                    check_physical_word({sdram_ba, open_row[sdram_ba], sdram_a[9:0]},
                                        sdram_dq);
                    burst_bank = sdram_ba;
                    burst_row = open_row[sdram_ba];
                    burst_column = {sdram_a[9:3], 3'd1};
                    burst_beats_remaining = 3'd7;
                end
                3'b010: begin
                    if (sdram_a[10])
                        open_valid = '0;
                    else
                        open_valid[sdram_ba] = 1'b0;
                end
                default: begin
                end
            endcase
        end
    end

    always @(posedge sdram_logic_clk) begin
        if (reset)
            completion_count <= 0;
        else if (write_completion)
            completion_count <= completion_count + 1;
    end

    initial begin
        physical_word_count = 0;
        completion_count = 0;
        open_valid = '0;
        burst_beats_remaining = '0;

        repeat (5) @(posedge sdram_logic_clk);
        reset = 1'b0;

        wait (frame_write_complete);
        repeat (4) @(posedge sdram_clk);

        if (writer_error || sdram_error)
            $fatal(1, "writer reported an error writer=%b reason=%b sdram=%b",
                   writer_error, writer_error_reason, sdram_error);
        if (completion_count != FRAMEBUFFER_HEIGHT)
            $fatal(1, "wrong line completion count got=%0d expected=%0d",
                   completion_count, FRAMEBUFFER_HEIGHT);
        if (physical_word_count != FRAMEBUFFER_WORDS)
            $fatal(1, "wrong physical word count got=%0d expected=%0d",
                   physical_word_count, FRAMEBUFFER_WORDS);

        $display("PASS framebuffer_shared_phy_frame_write: all %0d physical words match",
                 physical_word_count);
        $finish;
    end

    initial begin
        #100_000_000;
        $fatal(1, "shared-PHY full-frame writer watchdog");
    end
endmodule
