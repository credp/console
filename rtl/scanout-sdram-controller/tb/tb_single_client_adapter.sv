`timescale 1ns/1ps
module tb_single_client_adapter;
    logic clk=0,reset=1;
    logic req_valid=0,req_ready,req_write;logic[26:0]req_byte_address;
    logic[15:0]req_words;logic[7:0]req_tag;
    logic write_valid=0,write_ready;logic[15:0]write_data;logic[1:0]write_byte_enable;
    logic read_valid,read_ready=0;logic[15:0]read_data;
    logic completion_valid,completion_ready=0;logic[7:0]completion_tag;logic[15:0]completion_words;logic completion_error;
    logic op_valid,op_ready,op_write,op_chip;logic[1:0]op_bank;logic[12:0]op_row;
    logic[9:0]op_column;logic[127:0]op_write_data,op_read_data;
    logic[15:0]op_write_byte_enable;logic op_read_data_valid,op_completion_valid,op_completion_ready;
    logic[12:0]sdram_a;logic[1:0]sdram_ba;logic sdram_cke,sdram_ncs,sdram_nras,sdram_ncas,sdram_nwe;
    logic sdram_dqml,sdram_dqmh;wire[15:0]dq;logic[15:0]sdram_dq_in,sdram_dq_out;logic sdram_dq_oe;
    logic late_refresh0,late_refresh1,refresh_pending,timing_violation,turnaround_blocked,row_hit,phy_busy;
    integer i,read_count=0,op_count=0,stall_count=0;
    assign dq=sdram_dq_oe?sdram_dq_out:16'hzzzz;
    assign sdram_dq_in=dq;
    always #5 clk=~clk;
    always @(posedge clk)if(op_valid&&op_ready)op_count<=op_count+1;

    sdram_single_client_adapter #(.MAX_REQUEST_WORDS(32)) adapter(.*);
    sdram_runtime_core #(.SDRAM_FREQ_HZ(10_000_000),.READ_CAPTURE_CYCLES(3),
      .MAX_REFRESH_SERVICE_CYCLES(24)) core(
      .clk,.reset,.runtime_enable(1'b1),.op_valid,.op_ready,.op_write,.op_chip,.op_bank,.op_row,.op_column,
      .op_write_data,.op_write_byte_enable,.op_read_data,.op_read_data_valid,
      .completion_valid(op_completion_valid),.completion_ready(op_completion_ready),
      .sdram_a,.sdram_ba,.sdram_cke,.sdram_ncs,.sdram_nras,.sdram_ncas,.sdram_nwe,
      .sdram_dqml,.sdram_dqmh,.sdram_dq_in,.sdram_dq_out,.sdram_dq_oe,
      .late_refresh0,.late_refresh1,.refresh_pending,.timing_violation,
      .turnaround_blocked,.row_hit,.phy_busy);
    sdram_pair_model memory(.clk,.cke(sdram_cke),.ncs(sdram_ncs),.nras(sdram_nras),
      .ncas(sdram_ncas),.nwe(sdram_nwe),.a(sdram_a),.ba(sdram_ba),
      .dqml(sdram_dqml),.dqmh(sdram_dqmh),.dq);

    task request(input logic write,input logic[7:0]tag);
      begin
        @(negedge clk);req_write=write;req_byte_address=27'd2032;req_words=12;req_tag=tag;req_valid=1;
        wait(req_ready);@(posedge clk);@(negedge clk);req_valid=0;
      end
    endtask
    task accept_completion(input logic[7:0]tag);
      begin
        wait(completion_valid);@(negedge clk);
        if(completion_tag!=tag||completion_error||completion_words!=12)
          $fatal(1,"completion tag/error/words %h/%b/%0d",completion_tag,completion_error,completion_words);
        completion_ready=1;@(posedge clk);@(negedge clk);completion_ready=0;
      end
    endtask

    initial begin
      req_write=0;req_byte_address=0;req_words=0;req_tag=0;write_data=0;write_byte_enable='1;
      repeat(2)@(negedge clk);reset=0;memory.burst_length[0]=8;memory.burst_length[1]=8;

      request(1,8'ha1);
      for(i=0;i<12;i=i+1)begin
        @(negedge clk);write_data=16'h9000+i;write_byte_enable=2'b11;write_valid=1;
        wait(write_ready);@(posedge clk);@(negedge clk);write_valid=0;
      end
      accept_completion(8'ha1);
      if(op_count!=2)$fatal(1,"12-word write generated %0d physical ops",op_count);

      request(0,8'hb2);read_ready=1;
      while(read_count<12)begin
        @(negedge clk);
        // Exercise response backpressure without affecting the physical burst.
        read_ready=(stall_count%3)!=1;stall_count=stall_count+1;
        if(read_valid&&read_ready)begin
          if(read_data!==16'h9000+read_count)$fatal(1,"read word %0d got %h",read_count,read_data);
          read_count=read_count+1;
        end
      end
      // Preserve the final ready through the edge that performs its handshake.
      @(posedge clk);@(negedge clk);read_ready=0;accept_completion(8'hb2);
      if(op_count!=4)$fatal(1,"12-word round trip generated %0d physical ops",op_count);

      // A malformed request completes locally and cannot issue an SDRAM op.
      @(negedge clk);req_write=0;req_byte_address=27'd1;req_words=1;req_tag=8'hc3;req_valid=1;
      wait(req_ready);@(posedge clk);@(negedge clk);req_valid=0;
      wait(completion_valid);
      if(completion_tag!=8'hc3||!completion_error||completion_words!=0)
        $fatal(1,"invalid completion tag/error/words %h/%b/%0d",completion_tag,completion_error,completion_words);
      if(op_count!=4)$fatal(1,"invalid request issued an SDRAM operation");
      completion_ready=1;@(posedge clk);@(negedge clk);completion_ready=0;
      repeat(100)@(negedge clk);
      if(late_refresh0||late_refresh1||timing_violation)$fatal(1,"runtime diagnostic failure");
      $display("PASS single-client adapter: split, pack, stall, order, accounting, rejection");$finish;
    end
    initial begin repeat(600)@(posedge clk);$fatal(1,"single-client adapter watchdog state=%0d split_busy=%b core_state=%0d read_count=%0d completion=%b",
      adapter.state,adapter.splitter.busy,core.core.scheduler.state,read_count,completion_valid);end
endmodule
