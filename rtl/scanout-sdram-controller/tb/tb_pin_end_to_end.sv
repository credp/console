`timescale 1ns/1ps
module end_to_end_case #(
 parameter longint unsigned FREQ=20_000_000,
 parameter real HALF_PERIOD=25.0
)(output logic finished=0);
 logic clk=0,reset=1;logic[1:0]test_mode=0;
 always #(HALF_PERIOD) clk=~clk;
 wire ov,ordy,ow,olast,wv,wrv,rv,rr,complete,init_done,done,pass;
 wire[26:0]oa,fail_addr;wire[3:0]owords;wire[15:0]wd,rd,fail_exp,fail_got;
 wire[1:0]wbe;wire[31:0]checked,errors;
 wire[12:0]bi_a;wire[1:0]bi_ba;wire bi_cke,bi_cs,bi_ras,bi_cas,bi_we,bi_ml,bi_mh,bi_oe;
 wire[15:0]bi_dqo;logic[12:0]a;logic[1:0]ba;logic cke,ncs,nras,ncas,nwe,dqml,dqmh,dq_oe;
 logic[15:0]dq_out,dq_in;tri[15:0]dq;assign dq=dq_oe?dq_out:16'hzzzz;
 logic[15:0]rng=16'hbeef;
 logic stalls=0,stall_reads=0;
 integer fault=0,received=0,mode,trial;
 wire allow_write=!stalls||rng[0];
 wire allow_read=!stall_reads&&(!stalls||rng[1]);
 wire transfer=rv&&rr&&allow_read;
 wire client_rv=rv&&allow_read&&!(fault==2&&received==0);
 wire[15:0]client_rd=rd^((fault==1&&received==57)?16'h0001:16'h0000);
 always @(posedge clk)begin
  if(reset)begin rng<=16'hbeef;received<=0;end
  else begin rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};if(transfer)received<=received+1;end
 end
 sdram_end_to_end_bist #(.SDRAM_FREQ_HZ(FREQ),.PERSIST_US(10)) client(
  .clk,.reset,.test_mode,.engine_init_done(init_done),.op_valid(ov),.op_ready(ordy),.op_write(ow),
  .op_byte_address(oa),.op_words(owords),.op_last(olast),.write_valid(wv),.write_ready(wrv&&allow_write),
  .write_data(wd),.write_byte_enable(wbe),.read_valid(client_rv),.read_ready(rr),.read_data(client_rd),
  .completion_valid(complete),.done,.pass,.checked_words(checked),.error_count(errors),
  .first_fail_address(fail_addr),.first_fail_expected(fail_exp),.first_fail_observed(fail_got));
 sdram_bl8_op_engine #(.SDRAM_FREQ_HZ(FREQ),.POWERUP_US(1)) engine(
  .clk,.reset,.op_valid(ov),.op_write(ow),.op_byte_address(oa),.op_words(owords),.op_ready(ordy),
  .write_valid(wv&&allow_write),.write_data(wd),.write_byte_enable(wbe),.write_ready(wrv),
  .read_valid(rv),.read_ready(rr&&allow_read),.read_data(rd),.completion_valid(complete),
  .sdram_a(bi_a),.sdram_ba(bi_ba),.sdram_cke(bi_cke),.sdram_ncs(bi_cs),
  .sdram_nras(bi_ras),.sdram_ncas(bi_cas),.sdram_nwe(bi_we),.sdram_dqml(bi_ml),.sdram_dqmh(bi_mh),
  .sdram_dq_in(dq_in),.sdram_dq_out(bi_dqo),.sdram_dq_oe(bi_oe),.init_done);
 always @(posedge clk)begin
  a<=bi_a;ba<=bi_ba;cke<=bi_cke;ncs<=bi_cs;nras<=bi_ras;ncas<=bi_cas;nwe<=bi_we;
  dqml<=bi_a[11];dqmh<=bi_a[12];dq_out<=bi_dqo;dq_oe<=bi_oe;dq_in<=dq;
 end
 // Functional cycle model, not an analogue PHY/phase-margin model. The latency
 // override preserves the previously hardware-qualified 20 MHz edge convention.
 sdram_pair_model #(.READ_LATENCY_EDGES(2)) mem(.clk(~clk),.cke,.ncs,.nras,.ncas,.nwe,.a,.ba,.dqml,.dqmh,.dq);

 logic was_stalled=0;logic[15:0]held_data;
 integer expected_beats=0,seen_beats=0;
 always @(posedge clk)begin
  if(reset)begin was_stalled<=0;expected_beats<=0;seen_beats<=0;end
  else begin
   if(was_stalled&&(!rv||rd!==held_data))$fatal(1,"response changed while stalled");
   was_stalled<=rv&&!allow_read;held_data<=rd;
   if(ov&&ordy)begin expected_beats<=ow?0:owords;seen_beats<=0;end
   if(transfer)seen_beats<=seen_beats+1;
   if(complete&&seen_beats!=expected_beats)$fatal(1,"premature completion or wrong response count");
   if(engine.state==engine.READ_BURST&&engine.beat<engine.words_q&&(^engine.dq_handoff===1'bx))
    $fatal(1,"unknown/high-impedance valid capture");
  end
 end
 always @(negedge clk)begin
  #0.001;
  if(!reset&&dq_oe&&mem.dq_oe)$fatal(1,"both devices driving DQ");
 end

 function automatic integer req_start(input integer n);
  case(n)0:req_start=14;1:req_start=1016;2:req_start=2040;3:req_start=8184;default:req_start=16376;endcase
 endfunction
 task automatic guard_words(input bit verify);
  integer n,addr,first_addr,last_addr,len;
  logic[26:0]g;
  begin
   for(n=0;n<5;n=n+1)begin
    len=(n==0)?10:12;first_addr=req_start(n)&~15;last_addr=(req_start(n)+2*len-1)|15;
    for(addr=first_addr;addr<=last_addr;addr=addr+2)if(addr<req_start(n)||addr>=req_start(n)+2*len)begin
     g=27'(addr);
     if(verify)begin
      if(mem.mem[g[10]][g[12:11]][g[18:14]][{g[13],g[9:1]}]!==16'h6db2)
       $fatal(1,"masked padding corrupted guard at %h",g);
     end else mem.mem[g[10]][g[12:11]][g[18:14]][{g[13],g[9:1]}]=16'h6db2;
    end
   end
  end
 endtask
 task automatic restart;
  begin @(negedge clk);reset=1;repeat(4)@(negedge clk);guard_words(0);reset=0;end
 endtask
 initial begin
  for(trial=0;trial<2;trial=trial+1)for(mode=0;mode<4;mode=mode+1)begin
   test_mode=2'(mode);stalls=(trial!=0);restart();
   // Hold ready low before the first read response and throughout capture.
   stall_reads=1;wait(rv);repeat(20)@(negedge clk);stall_reads=0;
   // Also stall the last word, when completion is particularly easy to get wrong.
   wait(received==57);@(negedge clk);stall_reads=1;repeat(20)@(negedge clk);stall_reads=0;
   wait(done);#0.01;
   if(!pass||checked!=58||errors||received!=58)$fatal(1,"F=%0d mode=%0d checked=%0d errors=%0d addr=%h exp=%h got=%h",FREQ,mode,checked,errors,fail_addr,fail_exp,fail_got);
   guard_words(1);
   $display("PASS end-to-end F=%0d mode=%0d stalls=%0d: 58 words and guards",FREQ,mode,stalls);
  end
  // Abort a buffered read under backpressure, then verify a fresh initialization.
  restart();stall_reads=1;wait(rv);repeat(4)@(negedge clk);restart();stall_reads=0;
  wait(done);#0.01;if(!pass)$fatal(1,"reset with pending response did not recover");
  fault=1;restart();wait(done);#0.01;
  if(pass||errors!=1||checked!=58||fail_addr!=16398||fail_got!==(fail_exp^16'h0001))
   $fatal(1,"last-word corruption escaped comparison pipeline");
  fault=2;restart();wait(done);#0.01;
  if(pass||checked!=57||!client.protocol_error)$fatal(1,"dropped response escaped accounting");
  $display("PASS F=%0d reset recovery and corruption/drop negative controls",FREQ);
  finished=1;
 end
endmodule

module tb_pin_end_to_end;
 wire low_done,high_done;
 end_to_end_case baseline(.finished(low_done));
 end_to_end_case #(.FREQ(142_857_000),.HALF_PERIOD(3.5)) target_cycles(.finished(high_done));
 initial begin wait(low_done&&high_done);$finish;end
 initial begin #10000000;$fatal(1,"end-to-end timeout");end
endmodule
