`timescale 1ns/1ps
module tb_pin_bl8_bist;
 logic clk=0,reset=1;logic[1:0]test_mode=0;integer mode;always #25 clk=~clk;
 wire[12:0]bist_a;wire[1:0]bist_ba;
 wire bist_cke,bist_ncs,bist_nras,bist_ncas,bist_nwe,bist_dqml,bist_dqmh;
 logic[12:0]a;logic[1:0]ba;logic cke,ncs,nras,ncas,nwe,dqml,dqmh;tri[15:0]dq;
 wire init_done,done,pass;wire[31:0]tested,errors;
 wire[26:0]fail_address;wire[15:0]fail_expected,fail_observed;
 wire[5:0]fail_state;wire[2:0]fail_beat;
 logic[15:0]dq_captured,dq_out;logic dq_oe;
 wire[15:0]bist_dq_out;wire bist_dq_oe;
 assign dq=dq_oe?dq_out:16'hzzzz;
 always @(posedge clk)begin
  a<=bist_a;ba<=bist_ba;cke<=bist_cke;ncs<=bist_ncs;
  nras<=bist_nras;ncas<=bist_ncas;nwe<=bist_nwe;
  dqml<=bist_a[11];dqmh<=bist_a[12];dq_out<=bist_dq_out;dq_oe<=bist_dq_oe;
  dq_captured<=dq;
 end

 sdram_bl8_bist #(.SDRAM_FREQ_HZ(20_000_000),.POWERUP_US(1)) dut(
  .clk,.reset,.test_mode,.sdram_a(bist_a),.sdram_ba(bist_ba),.sdram_cke(bist_cke),.sdram_ncs(bist_ncs),
  .sdram_nras(bist_nras),.sdram_ncas(bist_ncas),.sdram_nwe(bist_nwe),.sdram_dqml(bist_dqml),.sdram_dqmh(bist_dqmh),
  .sdram_dq_in(dq_captured),.sdram_dq_out(bist_dq_out),.sdram_dq_oe(bist_dq_oe),
  .init_done,.test_done(done),.test_pass(pass),.tested_words(tested),
  .error_count(errors),.first_fail_address(fail_address),.first_fail_expected(fail_expected),
  .first_fail_observed(fail_observed),.first_fail_state(fail_state),.first_fail_beat(fail_beat));
 sdram_pair_model #(.READ_LATENCY_EDGES(2)) mem(
  .clk(~clk),.cke,.ncs,.nras,.ncas,.nwe,.a,.ba,.dqml,.dqmh,.dq);

 initial begin
  fork
   begin repeat(120000)@(posedge clk);$fatal(1,"timeout");end
   begin
    for(mode=0;mode<4;mode=mode+1)begin
     test_mode=mode;reset=1;repeat(3)@(posedge clk);reset=0;wait(done);
     if(!pass||tested!=384||errors!=0)$fatal(1,"BL8 mode %0d failed tested=%0d errors=%0d address=%h beat=%0d exp=%h got=%h",mode,tested,errors,fail_address,fail_beat,fail_expected,fail_observed);
     $display("PASS BL8 mode %0d: %0d ordered words",mode,tested);
    end
    $display("PASS BL8 pin BIST across both chips, all banks, row-end bursts, and all DQM modes");
    $finish;
   end
  join
 end
endmodule
