`timescale 1ns/1ps
module tb_bank_timing;
    localparam logic [2:0] ACT=3'd1, PRE=3'd2, READ=3'd3, WRITE=3'd4, REF=3'd5;
    logic clk=0,reset=1,command_fire,command_chip,command_all_banks,burst_done,burst_write,burst_chip;
    logic [2:0]command;logic[1:0]command_bank,burst_bank,target_bank;
    logic[12:0]command_row,target_row;logic target_chip;
    logic target_open,target_row_hit,can_activate,can_precharge,can_read,can_write,command_legal,timing_violation;
    logic idle0,idle1,can_precharge_all,can_refresh;
    always #5 clk=~clk;
    sdram_bank_timing #(.SDRAM_FREQ_HZ(130_000_000)) dut(
      .clk,.reset,.command_fire,.command,.command_chip,.command_bank,.command_row,.command_all_banks,
      .command_legal,.timing_violation,
      .burst_done,.burst_write,.burst_chip,.burst_bank,.target_chip,.target_bank,.target_row,
      .target_open,.target_row_hit,.can_activate,.can_precharge,.can_read,.can_write,
      .chip0_all_banks_idle(idle0),.chip1_all_banks_idle(idle1),
      .can_precharge_all_target(can_precharge_all),.can_refresh_target(can_refresh));

    task issue(input logic[2:0]cmd,input logic chip,input logic[1:0]bank,input logic[12:0]row);
      begin @(negedge clk);command=cmd;command_chip=chip;command_bank=bank;command_row=row;command_fire=1;
        @(negedge clk);command_fire=0;end
    endtask
    task finish_burst(input logic write,input logic chip,input logic[1:0]bank);
      begin @(negedge clk);burst_write=write;burst_chip=chip;burst_bank=bank;burst_done=1;
        @(negedge clk);burst_done=0;end
    endtask
    task clocks(input integer count); repeat(count) @(negedge clk); endtask

    initial begin
      command_fire=0;command=0;command_chip=0;command_bank=0;command_row=0;command_all_banks=0;
      burst_done=0;burst_write=0;burst_chip=0;burst_bank=0;
      target_chip=0;target_bank=0;target_row=13'h123;
      clocks(2);reset=0;#1;
      if(!idle0||!idle1||!can_activate||!can_refresh)$fatal(1,"reset eligibility");

      issue(ACT,0,0,13'h123);#1;
      if(!target_open||!target_row_hit||can_read||can_precharge)$fatal(1,"ACT state/tRCD/tRAS");
      clocks(2);#1;if(can_read)$fatal(1,"tRCD opened early");
      clocks(1);#1;if(!can_read||can_precharge)$fatal(1,"tRCD or tRAS boundary");

      issue(READ,0,0,13'h123);#1;if(can_read||can_precharge)$fatal(1,"read burst not reserved");
      finish_burst(0,0,0);#1;if(!can_read)$fatal(1,"read completion did not release bank");
      clocks(1);#1;if(!can_precharge)$fatal(1,"tRAS boundary");

      issue(WRITE,0,0,13'h123);finish_burst(1,0,0);#1;
      if(can_precharge)$fatal(1,"write recovery opened early");
      clocks(1);#1;if(can_precharge)$fatal(1,"tWR opened early");
      clocks(1);#1;if(!can_precharge)$fatal(1,"tWR boundary");

      issue(PRE,0,0,0);#1;if(target_open||can_activate||can_refresh)$fatal(1,"PRE/tRP state");
      clocks(2);#1;if(can_activate||can_refresh)$fatal(1,"tRP opened early");
      clocks(1);#1;if(!can_activate||!can_refresh)$fatal(1,"tRP boundary");

      target_chip=1;target_bank=2;target_row=13'h456;
      issue(ACT,1,2,13'h456);target_bank=3;#1;if(can_activate)$fatal(1,"tRRD opened early");
      clocks(1);#1;if(can_activate)$fatal(1,"tRRD opened early at one cycle");
      clocks(1);#1;if(!can_activate)$fatal(1,"tRRD boundary");

      target_bank=2;target_row=13'h456;clocks(4);issue(PRE,1,2,0);clocks(3);#1;
      if(!can_refresh)$fatal(1,"chip should be refresh eligible");
      issue(REF,1,0,0);#1;if(can_refresh||can_activate)$fatal(1,"tRFC opened early");
      clocks(8);#1;if(can_refresh||can_activate)$fatal(1,"tRFC opened early at eight cycles");
      clocks(1);#1;if(!can_refresh||!can_activate)$fatal(1,"tRFC boundary");

      // PRECHARGE ALL must update every bank, not merely command_bank.
      issue(ACT,0,0,13'h011);clocks(5);
      target_bank=1;target_row=13'h022;issue(ACT,0,1,13'h022);clocks(5);
      @(negedge clk);command=PRE;command_chip=0;command_bank=0;command_all_banks=1;command_fire=1;
      @(negedge clk);command_fire=0;command_all_banks=0;#1;
      if(!idle0)$fatal(1,"PRECHARGE ALL left a bank open");
      target_chip=0;target_bank=0;#1;if(can_refresh)$fatal(1,"PRECHARGE ALL ignored tRP");
      clocks(3);#1;if(!can_refresh)$fatal(1,"PRECHARGE ALL tRP boundary");

      // An illegal command is reported and must not mutate tracked state.
      reset=1;clocks(2);reset=0;target_chip=0;target_bank=0;target_row=13'h077;
      issue(ACT,0,0,13'h077);issue(READ,0,0,13'h077);#1;
      if(!timing_violation||!target_open||!target_row_hit)$fatal(1,"illegal command negative control");
      clocks(1);#1;if(!can_read)$fatal(1,"rejected READ incorrectly reserved a burst");
      $display("PASS bank timing eligibility");$finish;
    end
endmodule
