`timescale 1ns/1ps
module tb_two_client_adapter;
 logic clk=0,reset=1;always #5 clk=~clk;
 logic c0_req_valid=0,c0_req_ready,c0_req_write;logic[26:0]c0_req_byte_address;
 logic[15:0]c0_req_words;logic[7:0]c0_req_tag;logic c0_write_valid=0,c0_write_ready;
 logic[15:0]c0_write_data;logic[1:0]c0_write_byte_enable;logic c0_read_valid,c0_read_ready=0;
 logic[15:0]c0_read_data;logic c0_completion_valid,c0_completion_ready=0;
 logic[7:0]c0_completion_tag;logic[15:0]c0_completion_words;logic c0_completion_error;
 logic c1_req_valid=0,c1_req_ready,c1_req_write;logic[26:0]c1_req_byte_address;
 logic[15:0]c1_req_words;logic[7:0]c1_req_tag;logic c1_write_valid=0,c1_write_ready;
 logic[15:0]c1_write_data;logic[1:0]c1_write_byte_enable;logic c1_read_valid,c1_read_ready=0;
 logic[15:0]c1_read_data;logic c1_completion_valid,c1_completion_ready=0;
 logic[7:0]c1_completion_tag;logic[15:0]c1_completion_words;logic c1_completion_error;
 logic op_valid,op_ready,op_write,op_chip,op_client;logic[1:0]op_bank;logic[12:0]op_row;
 logic[9:0]op_column;logic[127:0]op_write_data,op_read_data;logic[15:0]op_write_byte_enable;
 logic op_read_data_valid,op_completion_valid,op_completion_ready;
 logic[12:0]sdram_a;logic[1:0]sdram_ba;logic sdram_cke,sdram_ncs,sdram_nras,sdram_ncas,sdram_nwe;
 logic sdram_dqml,sdram_dqmh;wire[15:0]dq;logic[15:0]sdram_dq_in,sdram_dq_out;logic sdram_dq_oe;
 logic late_refresh0,late_refresh1,refresh_pending,timing_violation,turnaround_blocked,row_hit,phy_busy;
 integer grants0=0,grants1=0,r0=0,r1=0,stall=0;logic c1_finished_while_c0_stalled=0;
 assign dq=sdram_dq_oe?sdram_dq_out:16'hzzzz;assign sdram_dq_in=dq;
 always@(posedge clk)if(op_valid&&op_ready)begin
   if(op_client)grants1<=grants1+1;else grants0<=grants0+1;
 end
 always@(posedge clk)if(c1_completion_valid&&!c0_completion_valid)c1_finished_while_c0_stalled<=1;

 sdram_two_client_adapter #(.MAX_REQUEST_WORDS(32))dut(.*);
 sdram_runtime_core #(.SDRAM_FREQ_HZ(10_000_000),.READ_CAPTURE_CYCLES(3),
   .MAX_REFRESH_SERVICE_CYCLES(24))core(.clk,.reset,.runtime_enable(1'b1),
   .op_valid,.op_ready,.op_write,.op_chip,.op_bank,.op_row,.op_column,
   .op_write_data,.op_write_byte_enable,.op_read_data,.op_read_data_valid,
   .completion_valid(op_completion_valid),.completion_ready(op_completion_ready),
   .sdram_a,.sdram_ba,.sdram_cke,.sdram_ncs,.sdram_nras,.sdram_ncas,.sdram_nwe,
   .sdram_dqml,.sdram_dqmh,.sdram_dq_in,.sdram_dq_out,.sdram_dq_oe,
   .late_refresh0,.late_refresh1,.refresh_pending,.timing_violation,
   .turnaround_blocked,.row_hit,.phy_busy);
 sdram_pair_model memory(.clk,.cke(sdram_cke),.ncs(sdram_ncs),.nras(sdram_nras),
   .ncas(sdram_ncas),.nwe(sdram_nwe),.a(sdram_a),.ba(sdram_ba),
   .dqml(sdram_dqml),.dqmh(sdram_dqmh),.dq);

 task req0(input logic wr,input logic[7:0]tag);
  begin @(negedge clk);c0_req_write=wr;c0_req_byte_address=2032;c0_req_words=12;
   c0_req_tag=tag;c0_req_valid=1;wait(c0_req_ready);@(posedge clk);@(negedge clk);c0_req_valid=0;end
 endtask
 task req1(input logic wr,input logic[7:0]tag);
  begin @(negedge clk);c1_req_write=wr;c1_req_byte_address=4080;c1_req_words=12;
   c1_req_tag=tag;c1_req_valid=1;wait(c1_req_ready);@(posedge clk);@(negedge clk);c1_req_valid=0;end
 endtask
 task done0(input logic[7:0]tag);
  begin wait(c0_completion_valid);if(c0_completion_tag!=tag||c0_completion_error||c0_completion_words!=12)$fatal(1,"client 0 completion");
   @(negedge clk);c0_completion_ready=1;@(posedge clk);@(negedge clk);c0_completion_ready=0;end
 endtask
 task done1(input logic[7:0]tag);
  begin wait(c1_completion_valid);if(c1_completion_tag!=tag||c1_completion_error||c1_completion_words!=12)$fatal(1,"client 1 completion");
   @(negedge clk);c1_completion_ready=1;@(posedge clk);@(negedge clk);c1_completion_ready=0;end
 endtask
 task data0;
  integer j;begin for(j=0;j<12;j=j+1)begin @(negedge clk);c0_write_data=16'h1000+j;
   c0_write_valid=1;wait(c0_write_ready);@(posedge clk);@(negedge clk);c0_write_valid=0;end end
 endtask
 task data1;
  integer j;begin for(j=0;j<12;j=j+1)begin @(negedge clk);c1_write_data=16'h2000+j;
   c1_write_valid=1;wait(c1_write_ready);@(posedge clk);@(negedge clk);c1_write_valid=0;end end
 endtask

 initial begin
  c0_req_write=0;c0_req_byte_address=0;c0_req_words=0;c0_req_tag=0;c0_write_data=0;c0_write_byte_enable='1;
  c1_req_write=0;c1_req_byte_address=0;c1_req_words=0;c1_req_tag=0;c1_write_data=0;c1_write_byte_enable='1;
  repeat(2)@(negedge clk);reset=0;memory.burst_length[0]=8;memory.burst_length[1]=8;
  fork req0(1,8'h10);req1(1,8'h20);join
  fork data0();data1();join
  fork done0(8'h10);done1(8'h20);join
  if(grants0!=2||grants1!=2)$fatal(1,"write fairness grants %0d/%0d",grants0,grants1);

  fork req0(0,8'h11);req1(0,8'h21);join
  c1_read_ready=1;
  while(r1<12)begin @(negedge clk);if(c1_read_valid)begin
   if(c1_read_data!==16'h2000+r1)$fatal(1,"client 1 read %0d",r1);r1=r1+1;end end
  // Client 0 remains stalled while client 1 drains and completes.
  done1(8'h21);if(!c1_finished_while_c0_stalled)$fatal(1,"stalled client blocked peer response");
  while(r0<12)begin @(negedge clk);c0_read_ready=(stall%3)!=1;stall=stall+1;
   if(c0_read_valid&&c0_read_ready)begin if(c0_read_data!==16'h1000+r0)$fatal(1,"client 0 read %0d",r0);r0=r0+1;end end
  @(posedge clk);@(negedge clk);c0_read_ready=0;done0(8'h11);
  if(grants0!=4||grants1!=4)$fatal(1,"total fairness grants %0d/%0d",grants0,grants1);
  repeat(100)@(negedge clk);
  if(late_refresh0||late_refresh1||timing_violation)$fatal(1,"runtime diagnostic failure");
  $display("PASS two-client adapter: interleaving, isolation, stalled-reader progress, accounting");$finish;
 end
 initial begin repeat(900)@(posedge clk);$fatal(1,"two-client watchdog r0=%0d r1=%0d",r0,r1);end
endmodule
