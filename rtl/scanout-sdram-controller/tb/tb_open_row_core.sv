`timescale 1ns/1ps
module tb_open_row_core;
    logic clk=0,reset=1,op_valid,op_ready,op_write,op_chip;
    logic[1:0]op_bank;logic[12:0]op_row;logic[9:0]op_column;
    logic[127:0]op_write_data,op_read_data;logic[15:0]op_write_byte_enable;
    logic op_read_data_valid,completion_valid,completion_ready=1;
    logic refresh_valid=0,refresh_ready,refresh_chip=0,refresh_completion_valid;
    logic refresh_completion_ready=1;
    logic[12:0]sdram_a;logic[1:0]sdram_ba;logic sdram_cke,sdram_ncs,sdram_nras,sdram_ncas,sdram_nwe;
    logic sdram_dqml,sdram_dqmh;wire[15:0]dq;logic[15:0]sdram_dq_in,sdram_dq_out;
    logic sdram_dq_oe,timing_violation,turnaround_blocked,row_hit,phy_busy;
    integer i,completion_count=0;
    assign dq=sdram_dq_oe?sdram_dq_out:16'hzzzz;
    assign sdram_dq_in=dq;
    always #5 clk=~clk;
    always @(posedge clk)if(completion_valid&&completion_ready)completion_count<=completion_count+1;

    sdram_open_row_core #(.SDRAM_FREQ_HZ(130_000_000),.READ_CAPTURE_CYCLES(3)) dut(.*);
    sdram_pair_model memory(.clk,.cke(sdram_cke),.ncs(sdram_ncs),.nras(sdram_nras),
      .ncas(sdram_ncas),.nwe(sdram_nwe),.a(sdram_a),.ba(sdram_ba),
      .dqml(sdram_dqml),.dqmh(sdram_dqmh),.dq);

    task submit(input logic write,input logic[12:0]row,input logic[9:0]column,input integer base);
      begin
        @(negedge clk);op_write=write;op_chip=0;op_bank=1;op_row=row;op_column=column;
        for(i=0;i<8;i=i+1)op_write_data[i*16+:16]=base+i;
        op_valid=1;wait(op_ready);@(posedge clk);@(negedge clk);op_valid=0;
        wait(completion_valid);@(posedge clk);@(negedge clk);
      end
    endtask

    task check_read(input integer base);
      begin
        for(i=0;i<8;i=i+1)if(op_read_data[i*16+:16]!==base+i)
          $fatal(1,"read beat %0d: got %h expected %h",i,op_read_data[i*16+:16],base+i);
      end
    endtask

    initial begin
      op_valid=0;op_write=0;op_chip=0;op_bank=0;op_row=0;op_column=0;
      op_write_data=0;op_write_byte_enable='1;
      repeat(2)@(negedge clk);reset=0;memory.burst_length[0]=8;

      // Closed bank, then row hit.
      submit(1,13'h021,10'h040,16'h6100);
      submit(0,13'h021,10'h040,0);check_read(16'h6100);

      // Row conflict forces PRE/ACT, then still transfers the atomic payload.
      submit(1,13'h022,10'h058,16'h7200);
      submit(0,13'h022,10'h058,0);check_read(16'h7200);
      if(completion_count!=4)$fatal(1,"operation completion count %0d",completion_count);
      if(timing_violation)$fatal(1,"integrated scheduler emitted illegal timing");
      $display("PASS open-row core: scheduler plus bounded PHY through SDRAM model");$finish;
    end

    initial begin repeat(300)@(posedge clk);$fatal(1,"open-row core watchdog");end
endmodule
