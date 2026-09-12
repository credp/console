`timescale 1ns/1ps
module tb_bl8_phy_engine;
    localparam logic [2:0] ACT=3'd1,READ=3'd3,WRITE=3'd4;
    logic clk=0,reset=1,command_valid,command_ready,command_chip,command_all_banks;
    logic[2:0]command;logic[1:0]command_bank;logic[12:0]command_row;logic[9:0]command_column;
    logic[127:0]write_burst_data,read_burst_data;logic[15:0]write_burst_byte_enable;
    logic read_burst_valid,burst_done;
    logic[12:0]sdram_a;logic[1:0]sdram_ba;logic sdram_cke,sdram_ncs,sdram_nras,sdram_ncas,sdram_nwe;
    logic sdram_dqml,sdram_dqmh;wire[15:0]dq;logic[15:0]sdram_dq_in,sdram_dq_out;logic sdram_dq_oe,busy;
    integer i,done_count=0;
    assign dq=sdram_dq_oe?sdram_dq_out:16'hzzzz;
    assign sdram_dq_in=dq;
    always #5 clk=~clk;
    always @(posedge clk)if(burst_done)done_count<=done_count+1;

    sdram_bl8_phy_engine #(.READ_CAPTURE_CYCLES(3)) dut(.*);
    sdram_pair_model memory(.clk,.cke(sdram_cke),.ncs(sdram_ncs),.nras(sdram_nras),
      .ncas(sdram_ncas),.nwe(sdram_nwe),.a(sdram_a),.ba(sdram_ba),
      .dqml(sdram_dqml),.dqmh(sdram_dqmh),.dq);

    task issue(input logic[2:0]cmd,input logic chip,input logic[1:0]bank,
               input logic[12:0]row,input logic[9:0]column);
      begin
        @(negedge clk);command=cmd;command_chip=chip;command_bank=bank;
        command_row=row;command_column=column;command_valid=1;
        wait(command_ready);@(posedge clk);@(negedge clk);command_valid=0;
      end
    endtask

    initial begin
      command_valid=0;command=0;command_chip=0;command_bank=0;command_row=0;
      command_column=0;command_all_banks=0;write_burst_byte_enable='1;
      for(i=0;i<8;i=i+1)write_burst_data[i*16+:16]=16'h5100+i;
      repeat(2)@(negedge clk);reset=0;
      // Initialization is outside this engine; model the already-programmed BL8 mode.
      memory.burst_length[0]=8;

      issue(ACT,0,2,13'h012,0);
      issue(WRITE,0,2,0,10'h028);
      wait(burst_done);@(posedge clk);@(negedge clk);
      if(done_count!=1||busy)$fatal(1,"write burst did not finish in eight beats");

      issue(READ,0,2,0,10'h028);
      wait(read_burst_valid);@(negedge clk);
      if(done_count!=2)$fatal(1,"read burst_done missing");
      for(i=0;i<8;i=i+1)if(read_burst_data[i*16+:16]!==16'h5100+i)
        $fatal(1,"read beat %0d: got %h",i,read_burst_data[i*16+:16]);
      $display("PASS BL8 PHY engine: fixed write/read bursts and capture");$finish;
    end
endmodule
