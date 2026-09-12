`timescale 1ns/1ps

module tb_trace_current_controller;
    localparam integer LEN_WIDTH = 16;
    localparam integer TAG_WIDTH = 32;
    localparam integer MAX_TRACE = 4096;
    localparam integer CLK_PERIOD_NS = 10;

    logic clk = 0;
    logic reset = 1;
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    logic [223:0] trace [0:MAX_TRACE-1];
    integer trace_count;
    integer issued;
    integer completed;
    integer accepted;
    integer deadline_misses;
    integer max_accept_delay_ns;
    integer max_completion_latency_ns;
    integer min_deadline_slack_ns;
    integer request_issue_time_ns [0:MAX_TRACE-1];
    integer request_accept_time_ns [0:MAX_TRACE-1];
    logic [TAG_WIDTH-1:0] request_tag [0:MAX_TRACE-1];

    string trace_mem;

    logic c0_req_valid = 0;
    logic c0_req_ready;
    logic c0_req_write = 0;
    logic [26:0] c0_req_byte_address = '0;
    logic [LEN_WIDTH-1:0] c0_req_words = '0;
    logic [TAG_WIDTH-1:0] c0_req_tag = '0;
    logic c0_write_valid = 0;
    logic c0_write_ready;
    logic [15:0] c0_write_data = '0;
    logic [1:0] c0_write_byte_enable = 2'b11;
    logic c0_read_valid;
    logic c0_read_ready = 1;
    logic [15:0] c0_read_data;
    logic c0_completion_valid;
    logic c0_completion_ready = 1;
    logic [TAG_WIDTH-1:0] c0_completion_tag;
    logic [LEN_WIDTH-1:0] c0_completion_words;
    logic c0_completion_error;

    logic c1_req_valid = 0;
    logic c1_req_ready;
    logic c1_req_write = 0;
    logic [26:0] c1_req_byte_address = '0;
    logic [LEN_WIDTH-1:0] c1_req_words = '0;
    logic [TAG_WIDTH-1:0] c1_req_tag = '0;
    logic c1_write_valid = 0;
    logic c1_write_ready;
    logic [15:0] c1_write_data = '0;
    logic [1:0] c1_write_byte_enable = 2'b11;
    logic c1_read_valid;
    logic c1_read_ready = 1;
    logic [15:0] c1_read_data;
    logic c1_completion_valid;
    logic c1_completion_ready = 1;
    logic [TAG_WIDTH-1:0] c1_completion_tag;
    logic [LEN_WIDTH-1:0] c1_completion_words;
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

    assign dq = sdram_dq_oe ? sdram_dq_out : 16'hzzzz;
    assign sdram_dq_in = dq;

    sdram_two_client_controller #(
        .SDRAM_FREQ_HZ(100_000_000),
        .POWERUP_US(1),
        .INIT_REFRESH_COUNT(2),
        .READ_CAPTURE_CYCLES(3),
        .MAX_REFRESH_SERVICE_CYCLES(24),
        .LEN_WIDTH(LEN_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .MAX_REQUEST_WORDS(256)
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

    function automatic longint unsigned field_issue(input logic [223:0] row);
        field_issue = row[223:160];
    endfunction

    function automatic longint unsigned field_deadline(input logic [223:0] row);
        field_deadline = row[159:96];
    endfunction

    function automatic logic [3:0] field_client(input logic [223:0] row);
        field_client = row[95:92];
    endfunction

    function automatic logic field_write(input logic [223:0] row);
        field_write = row[91];
    endfunction

    function automatic logic [26:0] field_address(input logic [223:0] row);
        field_address = row[85:59];
    endfunction

    function automatic logic [15:0] field_words(input logic [223:0] row);
        field_words = row[58:43];
    endfunction

    function automatic logic [1:0] field_byte_enable(input logic [223:0] row);
        field_byte_enable = row[42:41];
    endfunction

    function automatic logic [TAG_WIDTH-1:0] field_tag(input logic [223:0] row);
        field_tag = row[40:9];
    endfunction

    task automatic drive_request(input integer index);
        logic [223:0] row;
        logic [15:0] data_seed;
        integer word_index;
        integer now_ns;
        begin
            row = trace[index];
            data_seed = field_tag(row);
            while ($time < field_issue(row)) @(posedge clk);
            @(negedge clk);

            if (field_client(row) == 0) begin
                c0_req_write = field_write(row);
                c0_req_byte_address = field_address(row);
                c0_req_words = field_words(row);
                c0_req_tag = field_tag(row);
                c0_write_byte_enable = field_byte_enable(row);
                c0_req_valid = 1;
                wait(c0_req_ready);
                @(posedge clk);
                now_ns = $time;
                @(negedge clk);
                c0_req_valid = 0;
                request_accept_time_ns[index] = now_ns;
                accepted = accepted + 1;
                if (now_ns - request_issue_time_ns[index] > max_accept_delay_ns)
                    max_accept_delay_ns = now_ns - request_issue_time_ns[index];
                if (field_write(row)) begin
                    for (word_index = 0; word_index < field_words(row); word_index = word_index + 1) begin
                        @(negedge clk);
                        c0_write_data = data_seed ^ word_index[15:0];
                        c0_write_valid = 1;
                        wait(c0_write_ready);
                        @(posedge clk);
                        @(negedge clk);
                        c0_write_valid = 0;
                    end
                end
            end else if (field_client(row) == 1) begin
                c1_req_write = field_write(row);
                c1_req_byte_address = field_address(row);
                c1_req_words = field_words(row);
                c1_req_tag = field_tag(row);
                c1_write_byte_enable = field_byte_enable(row);
                c1_req_valid = 1;
                wait(c1_req_ready);
                @(posedge clk);
                now_ns = $time;
                @(negedge clk);
                c1_req_valid = 0;
                request_accept_time_ns[index] = now_ns;
                accepted = accepted + 1;
                if (now_ns - request_issue_time_ns[index] > max_accept_delay_ns)
                    max_accept_delay_ns = now_ns - request_issue_time_ns[index];
                if (field_write(row)) begin
                    for (word_index = 0; word_index < field_words(row); word_index = word_index + 1) begin
                        @(negedge clk);
                        c1_write_data = data_seed ^ word_index[15:0];
                        c1_write_valid = 1;
                        wait(c1_write_ready);
                        @(posedge clk);
                        @(negedge clk);
                        c1_write_valid = 0;
                    end
                end
            end else begin
                $fatal(1, "unsupported client %0d in trace row %0d", field_client(row), index);
            end
            issued = issued + 1;
        end
    endtask

    task automatic observe_completion(
        input logic [TAG_WIDTH-1:0] tag,
        input logic [LEN_WIDTH-1:0] words,
        input logic error
    );
        integer index;
        integer completion_ns;
        integer latency_ns;
        integer slack_ns;
        logic found;
        logic [223:0] row;
        begin
            found = 0;
            for (index = 0; index < trace_count; index = index + 1) begin
                if (request_tag[index] == tag && request_accept_time_ns[index] >= 0) begin
                    row = trace[index];
                    request_accept_time_ns[index] = -1;
                    found = 1;
                    if (error)
                        $fatal(1, "request tag %h completed with error", tag);
                    if (words != field_words(row))
                        $fatal(1, "request tag %h completed %0d words, expected %0d",
                               tag, words, field_words(row));
                    completion_ns = $time;
                    latency_ns = completion_ns - request_issue_time_ns[index];
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
            end
            if (!found)
                $fatal(1, "completion for unknown or duplicate-live tag %h", tag);
        end
    endtask

    always @(posedge clk) begin
        if (c0_completion_valid && c0_completion_ready)
            observe_completion(c0_completion_tag, c0_completion_words, c0_completion_error);
        if (c1_completion_valid && c1_completion_ready)
            observe_completion(c1_completion_tag, c1_completion_words, c1_completion_error);
        if (timing_violation)
            $fatal(1, "SDRAM timing violation");
    end

    initial begin
        if (!$value$plusargs("trace_mem=%s", trace_mem))
            $fatal(1, "missing +trace_mem=<path>");
        if (!$value$plusargs("trace_count=%d", trace_count))
            $fatal(1, "missing +trace_count=<rows>");
        if (trace_count <= 0 || trace_count > MAX_TRACE)
            $fatal(1, "bad trace_count %0d", trace_count);

        $readmemh(trace_mem, trace, 0, trace_count - 1);

        issued = 0;
        accepted = 0;
        completed = 0;
        deadline_misses = 0;
        max_accept_delay_ns = 0;
        max_completion_latency_ns = 0;
        min_deadline_slack_ns = 32'h7fff_ffff;

        for (integer index = 0; index < trace_count; index = index + 1) begin
            request_issue_time_ns[index] = field_issue(trace[index]);
            request_accept_time_ns[index] = -2;
            request_tag[index] = field_tag(trace[index]);
        end

        repeat (2) @(negedge clk);
        reset = 0;
        wait(init_done);

        for (integer index = 0; index < trace_count; index = index + 1)
            drive_request(index);

        while (completed < trace_count) @(posedge clk);

        $display("TRACE_RESULT backend=current_custom requests=%0d accepted=%0d completed=%0d deadline_misses=%0d max_accept_delay_ns=%0d max_completion_latency_ns=%0d min_deadline_slack_ns=%0d",
                 trace_count, accepted, completed, deadline_misses,
                 max_accept_delay_ns, max_completion_latency_ns,
                 min_deadline_slack_ns);
        $finish;
    end

    initial begin
        repeat (200000) @(posedge clk);
        $fatal(1, "trace replay watchdog issued=%0d completed=%0d", issued, completed);
    end
endmodule
