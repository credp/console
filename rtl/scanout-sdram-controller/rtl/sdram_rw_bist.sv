module sdram_rw_bist #(
 parameter longint unsigned SDRAM_FREQ_HZ=20_000_000,parameter integer TEST_WORDS=256,POWERUP_US=200
)(input logic clk,reset,output logic[12:0]sdram_a,output logic[1:0]sdram_ba,
 output logic sdram_cke,sdram_ncs,sdram_nras,sdram_ncas,sdram_nwe,sdram_dqml,sdram_dqmh,
 inout wire[15:0]sdram_dq,output logic init_done,test_done,test_pass,
 output logic[15:0]expected_data,observed_data,tested_words);
 function automatic longint unsigned ceil_ns(input longint unsigned ns);
  ceil_ns=(ns*SDRAM_FREQ_HZ+64'd999_999_999)/64'd1_000_000_000;
 endfunction
 localparam longint unsigned POWERUP_CYCLES=(SDRAM_FREQ_HZ*POWERUP_US+999_999)/1_000_000;
 localparam longint unsigned TRCD=ceil_ns(21),TRP=ceil_ns(21),TWR=ceil_ns(14),TRFC=ceil_ns(63),TMRD0=ceil_ns(14),TMRD=(TMRD0<2)?2:TMRD0;
 localparam integer CL=3;localparam[12:0]MODE_REGISTER=(3<<4); // sequential BL1, CL3
 typedef enum logic[4:0]{PWR,CKE_WAIT,PRE0,PRE1,WAIT_RP,REF0,WAIT_RF0,REF1,WAIT_RF1,MRS0,MRS1,WAIT_MRD,
  WRITE_START,ACT_W,WAIT_RCD_W,WRITE_CMD,WAIT_WRITE,WRITE_NEXT,READ_START,ACT_R,WAIT_RCD_R,READ_CMD,WAIT_READ,CHECK,READ_NEXT,
  TEST_REF0,TEST_RFC0,TEST_REF1,TEST_RFC1,TEST_RESUME,DONE}state_t;
 state_t state;longint unsigned timer;integer refresh_count;logic[15:0]index,read_sample;logic refresh_resume_read;logic dq_oe;logic[15:0]dq_out;
 wire[15:0]dq_in=sdram_dq;assign sdram_dq=dq_oe?dq_out:16'hzzzz;
 function automatic[15:0]pattern(input[15:0]i);pattern=16'h5a3c^{i[7:0],i[15:8]}^(i*16'h1021);endfunction
 wire target_chip=index[7];wire[1:0]target_bank=index[6:5];
 wire[12:0]target_row={8'b0,index[4:0]};wire[9:0]target_column={9'b0,index[0]};
 always_comb begin
  sdram_a=0;sdram_ba=target_bank;sdram_cke=(state!=PWR);sdram_ncs=target_chip;
  sdram_nras=1;sdram_ncas=1;sdram_nwe=1;sdram_dqml=(state==PWR||state==CKE_WAIT);sdram_dqmh=sdram_dqml;
  dq_oe=0;dq_out=pattern(index);
  case(state)
   PRE0:begin sdram_ncs=0;sdram_nras=0;sdram_nwe=0;sdram_a[10]=1;end
   PRE1:begin sdram_ncs=1;sdram_nras=0;sdram_nwe=0;sdram_a[10]=1;end
   REF0:begin sdram_ncs=0;sdram_nras=0;sdram_ncas=0;end
   REF1:begin sdram_ncs=1;sdram_nras=0;sdram_ncas=0;end
   TEST_REF0:begin sdram_ncs=0;sdram_nras=0;sdram_ncas=0;end
   TEST_REF1:begin sdram_ncs=1;sdram_nras=0;sdram_ncas=0;end
   MRS0:begin sdram_ncs=0;sdram_nras=0;sdram_ncas=0;sdram_nwe=0;sdram_a=MODE_REGISTER;sdram_ba=0;end
   MRS1:begin sdram_ncs=1;sdram_nras=0;sdram_ncas=0;sdram_nwe=0;sdram_a=MODE_REGISTER;sdram_ba=0;end
   ACT_W,ACT_R:begin sdram_nras=0;sdram_a=target_row;end
   WRITE_CMD:begin sdram_ncas=0;sdram_nwe=0;sdram_a={2'b0,1'b1,target_column};dq_oe=1;end
   READ_CMD:begin sdram_ncas=0;sdram_a={2'b0,1'b1,target_column};end
   default:;
  endcase
 end
 assign init_done=(state>=WRITE_START);assign expected_data=pattern(index);
 // At 20 MHz, sampling on the falling edge after the CL3 return edge gives 25 ns tAC margin.
 always_ff@(negedge clk)begin if(reset)read_sample<=0;else if(state==CHECK)read_sample<=dq_in;end
 always_ff@(posedge clk)begin
  if(reset)begin state<=PWR;timer<=0;refresh_count<=0;index<=0;refresh_resume_read<=0;test_done<=0;test_pass<=1;observed_data<=0;tested_words<=0;end
  else case(state)
   PWR:if(timer+1>=POWERUP_CYCLES)begin state<=CKE_WAIT;timer<=0;end else timer<=timer+1;
   CKE_WAIT:state<=PRE0;
   PRE0:state<=PRE1;PRE1:begin state<=WAIT_RP;timer<=0;end
   WAIT_RP:if(timer+1>=TRP)begin state<=REF0;refresh_count<=0;end else timer<=timer+1;
   REF0:begin state<=WAIT_RF0;timer<=0;end
   WAIT_RF0:if(timer+1>=TRFC)begin if(refresh_count==7)begin state<=REF1;refresh_count<=0;end else begin refresh_count<=refresh_count+1;state<=REF0;end end else timer<=timer+1;
   REF1:begin state<=WAIT_RF1;timer<=0;end
   WAIT_RF1:if(timer+1>=TRFC)begin if(refresh_count==7)state<=MRS0;else begin refresh_count<=refresh_count+1;state<=REF1;end end else timer<=timer+1;
   MRS0:state<=MRS1;MRS1:begin state<=WAIT_MRD;timer<=0;end
   WAIT_MRD:if(timer+1>=TMRD)state<=WRITE_START;else timer<=timer+1;
   WRITE_START:begin index<=0;state<=ACT_W;end
   ACT_W:begin state<=WAIT_RCD_W;timer<=0;end
   WAIT_RCD_W:if(timer+1>=TRCD)state<=WRITE_CMD;else timer<=timer+1;
   WRITE_CMD:begin state<=WAIT_WRITE;timer<=0;end
   WAIT_WRITE:if(timer+1>=TWR+TRP)state<=WRITE_NEXT;else timer<=timer+1;
   WRITE_NEXT:if(index==TEST_WORDS-1)state<=READ_START;else begin index<=index+1;
     if(index[2:0]==7)begin refresh_resume_read<=0;state<=TEST_REF0;end else state<=ACT_W;end
   READ_START:begin index<=0;state<=ACT_R;end
   ACT_R:begin state<=WAIT_RCD_R;timer<=0;end
   WAIT_RCD_R:if(timer+1>=TRCD)state<=READ_CMD;else timer<=timer+1;
   READ_CMD:begin state<=WAIT_READ;timer<=0;end
   WAIT_READ:if(timer==CL-1)state<=CHECK;else timer<=timer+1;
   CHECK:begin observed_data<=read_sample;tested_words<=tested_words+1;if(read_sample!==pattern(index))test_pass<=0;state<=READ_NEXT;end
   READ_NEXT:if(index==TEST_WORDS-1)begin state<=DONE;test_done<=1;end else begin index<=index+1;
     if(index[2:0]==7)begin refresh_resume_read<=1;state<=TEST_REF0;end else state<=ACT_R;end
   TEST_REF0:begin state<=TEST_RFC0;timer<=0;end
   TEST_RFC0:if(timer+1>=TRFC)state<=TEST_REF1;else timer<=timer+1;
   TEST_REF1:begin state<=TEST_RFC1;timer<=0;end
   TEST_RFC1:if(timer+1>=TRFC)state<=TEST_RESUME;else timer<=timer+1;
   TEST_RESUME:state<=refresh_resume_read?ACT_R:ACT_W;
   DONE:test_done<=1;default:state<=PWR;
  endcase
 end
 initial if(TEST_WORDS<1||TEST_WORDS>256)$error("BIST TEST_WORDS must be 1..256");
endmodule
