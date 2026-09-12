`timescale 1ns/1ps

module tb_trace_agg23_stock;
    localparam integer MAX_TRACE = 4096;
    localparam integer CLK_PERIOD_NS = 10;

    logic clk = 0;
    logic reset = 1;
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    logic [223:0] trace [0:MAX_TRACE-1];
    integer trace_count;
    integer accepted;
    integer completed;
    integer native_ops;
    integer deadline_misses;
    integer max_accept_delay_ns;
    integer max_completion_latency_ns;
    integer min_deadline_slack_ns;
    string trace_mem;

    logic init_complete;
    logic [24:0] p0_addr = '0;
    logic [15:0] p0_data = '0;
    logic [1:0] p0_byte_en = 2'b11;
    logic [15:0] p0_q;
    logic p0_wr_req = 0;
    logic p0_rd_req = 0;
    logic p0_available;
    logic p0_ready;

    wire [15:0] dq;
    logic [12:0] sdram_a;
    logic [1:0] sdram_dqm;
    logic [1:0] sdram_ba;
    logic sdram_cke;
    logic sdram_ncs;
    logic sdram_nwe;
    logic sdram_nras;
    logic sdram_ncas;
    logic sdram_clk;

    sdram #(
        .CLOCK_SPEED_MHZ(100),
        .BURST_LENGTH(1),
        .CAS_LATENCY(3),
        .P0_BURST_LENGTH(1)
    ) dut (
        .clk,
        .reset,
        .init_complete,
        .p0_addr,
        .p0_data,
        .p0_byte_en,
        .p0_q,
        .p0_wr_req,
        .p0_rd_req,
        .p0_available,
        .p0_ready,
        .SDRAM_DQ(dq),
        .SDRAM_A(sdram_a),
        .SDRAM_DQM(sdram_dqm),
        .SDRAM_BA(sdram_ba),
        .SDRAM_nCS(sdram_ncs),
        .SDRAM_nWE(sdram_nwe),
        .SDRAM_nRAS(sdram_nras),
        .SDRAM_nCAS(sdram_ncas),
        .SDRAM_CKE(sdram_cke),
        .SDRAM_CLK(sdram_clk)
    );

    sdram_pair_model memory (
        .clk,
        .cke(sdram_cke),
        .ncs(sdram_ncs),
        .nras(sdram_nras),
        .ncas(sdram_ncas),
        .nwe(sdram_nwe),
        .a(sdram_a),
        .ba(sdram_ba),
        .dqml(sdram_dqm[0]),
        .dqmh(sdram_dqm[1]),
        .dq
    );

    function automatic longint unsigned field_issue(input logic [223:0] row);
        field_issue = row[223:160];
    endfunction

    function automatic longint unsigned field_deadline(input logic [223:0] row);
        field_deadline = row[159:96];
    endfunction

    function automatic logic field_write(input logic [223:0] row);
        field_write = row[91];
    endfunction

    function automatic logic [31:0] field_address(input logic [223:0] row);
        field_address = row[90:59];
    endfunction

    function automatic logic [15:0] field_words(input logic [223:0] row);
        field_words = row[58:43];
    endfunction

    function automatic logic [1:0] field_byte_enable(input logic [223:0] row);
        field_byte_enable = row[42:41];
    endfunction

    function automatic logic [31:0] field_tag(input logic [223:0] row);
        field_tag = row[40:9];
    endfunction

    task automatic native_word_op(
        input logic write,
        input logic [31:0] byte_address,
        input logic [15:0] data,
        input logic [1:0] byte_enable
    );
        begin
            @(negedge clk);
            wait(p0_available);
            p0_addr = byte_address[25:1];
            p0_data = data;
            p0_byte_en = byte_enable;
            p0_wr_req = write;
            p0_rd_req = !write;
            @(posedge clk);
            @(negedge clk);
            p0_wr_req = 0;
            p0_rd_req = 0;
            wait(p0_ready);
            @(posedge clk);
            wait(!p0_ready);
            native_ops = native_ops + 1;
        end
    endtask

    task automatic replay_request(input integer index);
        logic [223:0] row;
        integer word_index;
        integer issue_ns;
        integer accept_ns;
        integer completion_ns;
        integer latency_ns;
        integer slack_ns;
        logic [15:0] data_seed;
        begin
            row = trace[index];
            data_seed = field_tag(row);
            issue_ns = field_issue(row);
            while ($time < issue_ns) @(posedge clk);
            accept_ns = $time;
            accepted = accepted + 1;
            if (accept_ns - issue_ns > max_accept_delay_ns)
                max_accept_delay_ns = accept_ns - issue_ns;

            for (word_index = 0; word_index < field_words(row); word_index = word_index + 1) begin
                native_word_op(
                    field_write(row),
                    field_address(row) + word_index * 2,
                    data_seed ^ word_index[15:0],
                    field_byte_enable(row)
                );
            end

            completion_ns = $time;
            latency_ns = completion_ns - issue_ns;
            if (latency_ns > max_completion_latency_ns)
                max_completion_latency_ns = latency_ns;
            if (field_deadline(row) != 64'hffff_ffff_ffff_ffff) begin
                slack_ns = field_deadline(row) - completion_ns;
                if (slack_ns < min_deadline_slack_ns)
                    min_deadline_slack_ns = slack_ns;
                if (slack_ns < 0)
                    deadline_misses = deadline_misses + 1;
            end
            completed = completed + 1;
        end
    endtask

    initial begin
        if (!$value$plusargs("trace_mem=%s", trace_mem))
            $fatal(1, "missing +trace_mem=<path>");
        if (!$value$plusargs("trace_count=%d", trace_count))
            $fatal(1, "missing +trace_count=<rows>");
        if (trace_count <= 0 || trace_count > MAX_TRACE)
            $fatal(1, "bad trace_count %0d", trace_count);
        $readmemh(trace_mem, trace, 0, trace_count - 1);

        accepted = 0;
        completed = 0;
        native_ops = 0;
        deadline_misses = 0;
        max_accept_delay_ns = 0;
        max_completion_latency_ns = 0;
        min_deadline_slack_ns = 32'h7fff_ffff;

        repeat (2) @(negedge clk);
        reset = 0;
        wait(init_complete);

        for (integer index = 0; index < trace_count; index = index + 1)
            replay_request(index);

        $display("TRACE_RESULT backend=agg23_stock requests=%0d accepted=%0d completed=%0d native_ops=%0d deadline_misses=%0d max_accept_delay_ns=%0d max_completion_latency_ns=%0d min_deadline_slack_ns=%0d",
                 trace_count, accepted, completed, native_ops, deadline_misses,
                 max_accept_delay_ns, max_completion_latency_ns,
                 min_deadline_slack_ns);
        $finish;
    end

    initial begin
        repeat (2000000) @(posedge clk);
        $fatal(1, "agg23 stock trace replay watchdog completed=%0d native_ops=%0d",
               completed, native_ops);
    end
endmodule
