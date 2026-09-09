module refresh_formal(input logic clk);
 (* anyseq *)logic idle0,idle1;logic reset=1,init_done,cke,dqm,valid,chip;
 logic[2:0]command;logic[12:0]address;logic block0,block1,late0,late1;logic past_valid=0;
 logic[4:0]gap0,gap1;
 sdram_init_refresh #(.SDRAM_FREQ_HZ(2_000_000),.POWERUP_US(1),.REFRESH_COUNT(2),.REFRESH_PHASE_CYCLES(7))dut(
  .clk,.reset,.chip0_all_banks_idle(idle0),.chip1_all_banks_idle(idle1),.command_accept(1'b1),
  .init_done,.cke,.dqm_hold(dqm),.command_valid(valid),.command_chip(chip),.command,
  .command_address(address),.refresh0_block(block0),.refresh1_block(block1),
  .late_refresh0(late0),.late_refresh1(late1));
 always_ff@(posedge clk)begin
  past_valid<=1;reset<=0;if(!past_valid)assume(reset);
  if(!reset)begin assert(!late0);assert(!late1);end
  if(!cke)assert(dqm);
  if(reset||!init_done)begin gap0<=0;gap1<=8;end
  else begin
   if(valid&&command==3'd2&&!chip)gap0<=0;else gap0<=gap0+1'b1;
   if(valid&&command==3'd2&&chip)gap1<=0;else gap1<=gap1+1'b1;
   assert(gap0<=15);assert(gap1<=15);
  end
 end
endmodule
