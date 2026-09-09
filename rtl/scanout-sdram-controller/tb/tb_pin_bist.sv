`timescale 1ns/1ps
module tb_pin_bist;
 logic clk=0,reset=1;always #25 clk=~clk;
 wire[12:0]a;wire[1:0]ba;wire cke,ncs,nras,ncas,nwe,dqml,dqmh;tri[15:0]dq;
 wire init_done,done,pass;wire[15:0]expected,observed,tested;
 sdram_rw_bist #(.SDRAM_FREQ_HZ(20_000_000),.TEST_WORDS(256),.POWERUP_US(1)) dut(
  .clk,.reset,.sdram_a(a),.sdram_ba(ba),.sdram_cke(cke),.sdram_ncs(ncs),
  .sdram_nras(nras),.sdram_ncas(ncas),.sdram_nwe(nwe),.sdram_dqml(dqml),.sdram_dqmh(dqmh),
  .sdram_dq(dq),.init_done,.test_done(done),.test_pass(pass),.expected_data(expected),
  .observed_data(observed),.tested_words(tested));
 sdram_pair_model mem(.clk,.cke,.ncs,.nras,.ncas,.nwe,.a,.ba,.dqml,.dqmh,.dq);
 initial begin repeat(3)@(posedge clk);reset=0;
   fork begin repeat(30000)@(posedge clk);$fatal(1,"timeout");end
        begin wait(done);if(!pass||tested!=256)$fatal(1,"BIST failed tested=%0d exp=%h got=%h",tested,expected,observed);
          $display("PASS pin BIST: %0d words across both chips and all banks",tested);$finish;end join
 end
endmodule
