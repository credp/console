`timescale 1ns/1ps
module tb_single_client_controller;
    logic clk=0,reset=1;
    logic req_valid=0,req_ready,req_write;logic[26:0]req_byte_address;
    logic[15:0]req_words;logic[7:0]req_tag;
    logic write_valid=0,write_ready;logic[15:0]write_data;logic[1:0]write_byte_enable;
    logic read_valid,read_ready=0;logic[15:0]read_data;
    logic completion_valid,completion_ready=0;logic[7:0]completion_tag;
    logic[15:0]completion_words;logic completion_error,init_done;
    logic[12:0]sdram_a;logic[1:0]sdram_ba;
    logic sdram_cke,sdram_ncs,sdram_nras,sdram_ncas,sdram_nwe,sdram_dqml,sdram_dqmh;
    wire[15:0]dq;logic[15:0]sdram_dq_in,sdram_dq_out;logic sdram_dq_oe;
    logic late_refresh0,late_refresh1,refresh_pending,timing_violation;
    logic turnaround_blocked,row_hit,phy_busy;
    integer i,read_count=0,stall_count=0,runtime_ops=0,runtime_refs0=0,runtime_refs1=0;

    assign dq=sdram_dq_oe?sdram_dq_out:16'hzzzz;
    assign sdram_dq_in=dq;
    always #5 clk=~clk;

    sdram_single_client_controller #(
      .SDRAM_FREQ_HZ(10_000_000),.POWERUP_US(1),.INIT_REFRESH_COUNT(2),
      .READ_CAPTURE_CYCLES(3),.MAX_REFRESH_SERVICE_CYCLES(24),
      .MAX_REQUEST_WORDS(32)
    ) dut(.*);
    sdram_pair_model memory(.clk,.cke(sdram_cke),.ncs(sdram_ncs),.nras(sdram_nras),
      .ncas(sdram_ncas),.nwe(sdram_nwe),.a(sdram_a),.ba(sdram_ba),
      .dqml(sdram_dqml),.dqmh(sdram_dqmh),.dq);

    always @(posedge clk) begin
      if(!init_done)begin
        if(req_ready)$fatal(1,"request admitted before initialization handoff");
        if((!sdram_nras&&sdram_ncas&&sdram_nwe) ||
           (sdram_nras&&!sdram_ncas))
          $fatal(1,"runtime ACT/READ/WRITE command before initialization handoff");
        if(sdram_dq_oe)$fatal(1,"DQ driven during initialization");
      end else begin
        if((!sdram_nras&&sdram_ncas&&sdram_nwe) ||
           (sdram_nras&&!sdram_ncas)) runtime_ops<=runtime_ops+1;
        if(!sdram_nras&&!sdram_ncas&&sdram_nwe)begin
          if(sdram_ncs)runtime_refs1<=runtime_refs1+1;
          else runtime_refs0<=runtime_refs0+1;
        end
      end
    end

    task request(input logic write,input logic[7:0]tag);
      begin
        @(negedge clk);req_write=write;req_byte_address=27'd2032;
        req_words=12;req_tag=tag;req_valid=1;
        wait(req_ready);@(posedge clk);@(negedge clk);req_valid=0;
      end
    endtask
    task accept_completion(input logic[7:0]tag);
      begin
        wait(completion_valid);@(negedge clk);
        if(completion_tag!=tag||completion_error||completion_words!=12)
          $fatal(1,"completion tag/error/words %h/%b/%0d",
                 completion_tag,completion_error,completion_words);
        completion_ready=1;@(posedge clk);@(negedge clk);completion_ready=0;
      end
    endtask

    initial begin
      req_write=1;req_byte_address=27'd2032;req_words=12;req_tag=8'ha1;
      write_data=0;write_byte_enable='1;
      repeat(2)@(negedge clk);reset=0;
      // Hold a request throughout initialization: the wrapper must apply
      // backpressure and accept it only after pin ownership changes hands.
      req_valid=1;
      wait(init_done);if(req_ready)$fatal(1,"handoff was not clock-aligned");
      wait(req_ready);@(posedge clk);@(negedge clk);req_valid=0;
      for(i=0;i<12;i=i+1)begin
        write_data=16'ha000+i;write_valid=1;wait(write_ready);
        @(posedge clk);@(negedge clk);write_valid=0;
      end
      accept_completion(8'ha1);

      request(0,8'hb2);read_ready=1;
      while(read_count<12)begin
        @(negedge clk);
        read_ready=(stall_count%3)!=1;stall_count=stall_count+1;
        if(read_valid&&read_ready)begin
          if(read_data!==16'ha000+read_count)
            $fatal(1,"read word %0d got %h",read_count,read_data);
          read_count=read_count+1;
        end
      end
      @(posedge clk);@(negedge clk);read_ready=0;
      accept_completion(8'hb2);
      wait(runtime_refs0>=1&&runtime_refs1>=1);repeat(5)@(negedge clk);
      if(runtime_ops<4)$fatal(1,"split transaction did not reach runtime core");
      if(late_refresh0||late_refresh1||timing_violation)
        $fatal(1,"runtime diagnostic failure after handoff");
      $display("PASS single-client controller: initialization handoff, split round trip, refresh epoch");
      $finish;
    end
    initial begin repeat(500)@(posedge clk);$fatal(1,"single-client controller watchdog");end
endmodule
