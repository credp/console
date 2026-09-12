`timescale 1ns/1ps

module tb_two_client_controller;
    logic clk = 0;
    logic reset = 1;
    always #5 clk = ~clk;

    logic c0_req_valid = 0;
    logic c0_req_ready;
    logic c0_req_write = 0;
    logic [26:0] c0_req_byte_address = 1;
    logic [15:0] c0_req_words = 1;
    logic [7:0] c0_req_tag = 8'hc0;
    logic c0_write_valid = 0;
    logic c0_write_ready;
    logic [15:0] c0_write_data = 0;
    logic [1:0] c0_write_byte_enable = 2'b11;
    logic c0_read_valid;
    logic c0_read_ready = 0;
    logic [15:0] c0_read_data;
    logic c0_completion_valid;
    logic c0_completion_ready = 0;
    logic [7:0] c0_completion_tag;
    logic [15:0] c0_completion_words;
    logic c0_completion_error;

    logic c1_req_valid = 0;
    logic c1_req_ready;
    logic c1_req_write = 0;
    logic [26:0] c1_req_byte_address = 3;
    logic [15:0] c1_req_words = 1;
    logic [7:0] c1_req_tag = 8'hc1;
    logic c1_write_valid = 0;
    logic c1_write_ready;
    logic [15:0] c1_write_data = 0;
    logic [1:0] c1_write_byte_enable = 2'b11;
    logic c1_read_valid;
    logic c1_read_ready = 0;
    logic [15:0] c1_read_data;
    logic c1_completion_valid;
    logic c1_completion_ready = 0;
    logic [7:0] c1_completion_tag;
    logic [15:0] c1_completion_words;
    logic c1_completion_error;

    logic init_done;
    logic granted_client;
    logic [12:0] sdram_a;
    logic [1:0] sdram_ba;
    logic sdram_cke;
    logic sdram_ncs;
    logic sdram_nras;
    logic sdram_ncas;
    logic sdram_nwe;
    logic sdram_dqml;
    logic sdram_dqmh;
    wire [15:0] dq;
    logic [15:0] sdram_dq_in;
    logic [15:0] sdram_dq_out;
    logic sdram_dq_oe;
    logic late_refresh0;
    logic late_refresh1;
    logic refresh_pending;
    logic timing_violation;
    logic turnaround_blocked;
    logic row_hit;
    logic phy_busy;

    integer runtime_refs0 = 0;
    integer runtime_refs1 = 0;

    assign dq = sdram_dq_oe ? sdram_dq_out : 16'hzzzz;
    assign sdram_dq_in = dq;

    sdram_two_client_controller #(
        .SDRAM_FREQ_HZ(10_000_000),
        .POWERUP_US(1),
        .INIT_REFRESH_COUNT(2),
        .READ_CAPTURE_CYCLES(3),
        .MAX_REFRESH_SERVICE_CYCLES(24),
        .MAX_REQUEST_WORDS(32)
    ) dut (.*);

    sdram_pair_model memory (
        .clk,
        .cke(sdram_cke),
        .ncs(sdram_ncs),
        .nras(sdram_nras),
        .ncas(sdram_ncas),
        .nwe(sdram_nwe),
        .a(sdram_a),
        .ba(sdram_ba),
        .dqml(sdram_dqml),
        .dqmh(sdram_dqmh),
        .dq
    );

    always @(posedge clk) begin
        if (!init_done) begin
            if (c0_req_ready || c1_req_ready)
                $fatal(1, "client request admitted before initialization");
            if (sdram_dq_oe)
                $fatal(1, "DQ driven during initialization");
        end else if (!sdram_nras && !sdram_ncas && sdram_nwe) begin
            if (sdram_ncs)
                runtime_refs1 <= runtime_refs1 + 1;
            else
                runtime_refs0 <= runtime_refs0 + 1;
        end
    end

    initial begin
        repeat (2) @(negedge clk);
        reset = 0;

        // Both malformed requests are held throughout initialization. They
        // must be accepted independently after handoff and rejected locally,
        // without issuing an SDRAM operation.
        c0_req_valid = 1;
        c1_req_valid = 1;
        wait(c0_req_ready && c1_req_ready);
        @(posedge clk);
        @(negedge clk);
        c0_req_valid = 0;
        c1_req_valid = 0;

        wait(c0_completion_valid && c1_completion_valid);
        if (!c0_completion_error || c0_completion_tag != 8'hc0 ||
            c0_completion_words != 0)
            $fatal(1, "client 0 invalid-request completion mismatch");
        if (!c1_completion_error || c1_completion_tag != 8'hc1 ||
            c1_completion_words != 0)
            $fatal(1, "client 1 invalid-request completion mismatch");

        c0_completion_ready = 1;
        c1_completion_ready = 1;
        @(posedge clk);
        @(negedge clk);
        c0_completion_ready = 0;
        c1_completion_ready = 0;

        wait(runtime_refs0 >= 1 && runtime_refs1 >= 1);
        if (late_refresh0 || late_refresh1 || timing_violation)
            $fatal(1, "runtime diagnostic failure after two-client handoff");

        $display("PASS two-client controller: shared initialization handoff and refresh epoch");
        $finish;
    end

    initial begin
        repeat (400) @(posedge clk);
        $fatal(1, "two-client controller watchdog");
    end
endmodule
