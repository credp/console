`timescale 1ns/1ps
module tb_runtime_core;
    logic clk=0,reset=1,runtime_enable=0,op_valid=0,op_ready,op_write=1,op_chip=0;
    logic[1:0]op_bank=0;logic[12:0]op_row=0;logic[9:0]op_column=0;
    logic[127:0]op_write_data=0,op_read_data;logic[15:0]op_write_byte_enable='1;
    logic op_read_data_valid,completion_valid,completion_ready=1;
    logic[12:0]sdram_a;logic[1:0]sdram_ba;logic sdram_cke,sdram_ncs,sdram_nras,sdram_ncas,sdram_nwe;
    logic sdram_dqml,sdram_dqmh;wire[15:0]dq;logic[15:0]sdram_dq_in,sdram_dq_out;
    logic sdram_dq_oe,late_refresh0,late_refresh1,refresh_pending;
    logic timing_violation,turnaround_blocked,row_hit,phy_busy;
    integer cycle=0,refs0=0,refs1=0,last_ref0=0,last_ref1=0,operations=0,i;
    assign dq=sdram_dq_oe?sdram_dq_out:16'hzzzz;
    assign sdram_dq_in=dq;
    always #5 clk=~clk;

    sdram_runtime_core #(.SDRAM_FREQ_HZ(10_000_000),
      .READ_CAPTURE_CYCLES(3),.MAX_REFRESH_SERVICE_CYCLES(24)) dut(.*);
    sdram_pair_model memory(.clk,.cke(sdram_cke),.ncs(sdram_ncs),.nras(sdram_nras),
      .ncas(sdram_ncas),.nwe(sdram_nwe),.a(sdram_a),.ba(sdram_ba),
      .dqml(sdram_dqml),.dqmh(sdram_dqmh),.dq);

    always @(posedge clk) begin
      cycle<=cycle+1;
      if(runtime_enable&&!sdram_nras&&!sdram_ncas&&sdram_nwe)begin
        if(sdram_ncs)begin
          if(refs1>0&&cycle-last_ref1>78)$fatal(1,"chip 1 REF interval %0d",cycle-last_ref1);
          last_ref1<=cycle;refs1<=refs1+1;
        end else begin
          if(refs0>0&&cycle-last_ref0>78)$fatal(1,"chip 0 REF interval %0d",cycle-last_ref0);
          last_ref0<=cycle;refs0<=refs0+1;
        end
      end
    end

    // Keep presenting row-conflicting writes. Refresh requests must wait for
    // an active operation, then win before this producer can start another.
    initial begin
      repeat(2)@(negedge clk);reset=0;runtime_enable=1;memory.burst_length[0]=8;memory.burst_length[1]=8;
      forever begin
        @(negedge clk);
        op_chip=operations[0];op_bank=operations[2:1];op_row=operations+1;op_column=10'h020;
        for(i=0;i<8;i=i+1)op_write_data[i*16+:16]=16'h8000+operations*8+i;
        op_valid=1;wait(op_ready);@(posedge clk);@(negedge clk);op_valid=0;
        wait(completion_valid);@(posedge clk);operations=operations+1;
      end
    end

    initial begin
      wait(refs0>=3&&refs1>=3);@(negedge clk);
      if(operations<4)$fatal(1,"traffic did not make progress");
      if(late_refresh0||late_refresh1)$fatal(1,"integrated refresh deadline missed");
      if(timing_violation)$fatal(1,"integrated command timing violation");
      $display("PASS runtime core: sustained operations with two-chip refresh deadlines");$finish;
    end
    // Stall one response across a refresh threshold. The internal scheduler
    // must still acknowledge the operation and remain available to refresh.
    initial begin
      wait(operations==2);@(negedge clk);completion_ready=0;
      repeat(50)@(negedge clk);
      if(!completion_valid)$fatal(1,"client response was not held under backpressure");
      completion_ready=1;
    end
    initial begin repeat(600)@(posedge clk);$fatal(1,"runtime core watchdog");end
endmodule
