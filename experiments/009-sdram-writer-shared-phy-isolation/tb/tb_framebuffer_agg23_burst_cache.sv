`timescale 1ns/1ps

module tb_framebuffer_agg23_burst_cache;
    logic clk = 0, reset = 1, req_valid = 0, req_ready, req_write = 0;
    logic [26:0] req_byte_address = '0; logic [15:0] req_words = '0; logic [7:0] req_tag = '0;
    logic read_valid, read_ready = 1, completion_valid, completion_ready = 0;
    logic [15:0] read_data, completion_words, p0_q; logic [7:0] completion_tag;
    logic completion_error; logic [24:0] p0_addr; logic p0_rd_req, p0_end_burst_req;
    logic p0_available, p0_ready, p0_data_available; integer i, starts;
    typedef enum logic [1:0] { N_IDLE, N_STREAM, N_READY } native_state_t;
    native_state_t native_state; logic [24:0] native_address;
    always #5 clk = ~clk;
    framebuffer_agg23_burst_cache dut (.*,.init_done(1'b1));
    assign p0_available = native_state == N_IDLE;
    assign p0_data_available = native_state == N_STREAM;
    assign p0_ready = native_state == N_READY;
    assign p0_q = 16'h8000 + native_address[15:0];
    always_ff @(posedge clk) begin
        if (reset) begin native_state <= N_IDLE; native_address <= '0; starts <= 0; end
        else case (native_state)
            N_IDLE: if (p0_rd_req) begin native_address <= p0_addr; starts <= starts + 1; native_state <= N_STREAM; end
            N_STREAM: if (p0_end_burst_req) native_state <= N_READY; else native_address <= native_address + 1'b1;
            N_READY: native_state <= N_IDLE;
        endcase
    end
    task automatic request_and_check(input integer word_address, input integer words, input logic [7:0] tag);
        begin
            @(negedge clk); req_byte_address = word_address * 2; req_words = words; req_tag = tag; req_valid = 1;
            wait(req_ready); @(posedge clk); @(negedge clk); req_valid = 0;
            for (i = 0; i < words; i = i + 1) begin
                wait(read_valid); if (read_data !== 16'h8000 + word_address + i) $fatal(1,"word %0d",i);
                @(posedge clk); @(negedge clk);
            end
            wait(completion_valid);
            if (completion_error || completion_tag != tag || completion_words != words) $fatal(1,"bad completion");
            @(negedge clk); completion_ready = 1; @(posedge clk); @(negedge clk); completion_ready = 0;
        end
    endtask
    initial begin
        repeat(2) @(negedge clk); reset = 0;
        request_and_check(768, 256, 8'h11);
        request_and_check(0, 256, 8'h12);
        if (starts != 1) $fatal(1,"same page should have one native fetch, got %0d",starts);
        request_and_check(1024, 256, 8'h13);
        if (starts != 2) $fatal(1,"second page fetch missing");
        $display("PASS agg23 burst cache: full-page capture, cache hit, paced reads"); $finish;
    end
    // The synchronous M10K read port deliberately adds a request cycle per
    // returned word, so leave room for three paced reads plus two page fills.
    initial begin repeat(8000) @(posedge clk); $fatal(1,"burst cache watchdog"); end
endmodule
