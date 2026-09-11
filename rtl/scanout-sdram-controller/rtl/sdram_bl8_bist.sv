module sdram_bl8_bist #(
 parameter longint unsigned SDRAM_FREQ_HZ=20_000_000,
 parameter integer POWERUP_US=200,
 parameter integer PERSIST_US=1000
)(
 input logic clk,reset,input logic[1:0]test_mode,
 output logic[12:0]sdram_a,output logic[1:0]sdram_ba,
 output logic sdram_cke,sdram_ncs,sdram_nras,sdram_ncas,sdram_nwe,
 output logic sdram_dqml,sdram_dqmh,
 input logic[15:0]sdram_dq_in,output logic[15:0]sdram_dq_out,output logic sdram_dq_oe,
 output logic init_done,test_done,test_pass,
 output logic[31:0]tested_words,error_count,
 output logic[26:0]first_fail_address,
 output logic[15:0]first_fail_expected,first_fail_observed,
 output logic[5:0]first_fail_state,
 output logic[2:0]first_fail_beat
);
 function automatic longint unsigned ceil_ns(input longint unsigned ns);
  ceil_ns=(ns*SDRAM_FREQ_HZ+64'd999_999_999)/64'd1_000_000_000;
 endfunction
 localparam longint unsigned POWERUP_CYCLES=(SDRAM_FREQ_HZ*POWERUP_US+999_999)/1_000_000;
 localparam longint unsigned PERSIST_RAW=(SDRAM_FREQ_HZ*PERSIST_US+999_999)/1_000_000;
 localparam longint unsigned PERSIST_CYCLES=(PERSIST_RAW<1)?1:PERSIST_RAW;
 localparam longint unsigned TRCD=ceil_ns(21),TRP=ceil_ns(21),TWR=ceil_ns(14);
 localparam longint unsigned TRFC=ceil_ns(63),TMRD_RAW=ceil_ns(14),TMRD=(TMRD_RAW<2)?2:TMRD_RAW;
 localparam logic[12:0] MODE_REGISTER=13'b000_0_00_011_0_011; // BL8, sequential, CL3, programmed write burst
 localparam integer CL=3;

 typedef enum logic[5:0]{
  PWR,CKE_WAIT,PRE0,PRE1,WAIT_RP,REF0,WAIT_RF0,REF1,WAIT_RF1,MRS0,MRS1,WAIT_MRD,
  CASE_START,BASE_ACT,BASE_RCD,BASE_CMD,BASE_B1,BASE_B2,BASE_B3,BASE_B4,BASE_B5,BASE_B6,BASE_B7,BASE_REC,
  MASK_ACT,MASK_RCD,MASK_CMD,MASK_B1,MASK_B2,MASK_B3,MASK_B4,MASK_B5,MASK_B6,MASK_B7,MASK_REC,
  READ_ACT,READ_RCD,READ_CMD,READ_WAIT,READ_SAMPLE,READ_ADVANCE,NEXT_CASE,PERSIST_WAIT,DONE
 }state_t;
 state_t state;
 longint unsigned timer;
 integer refresh_count;
 logic[4:0]case_index;
 logic[2:0]beat;
 logic[1:0]pass_phase;

 wire target_chip=(case_index>=12);
 wire[3:0]case_within_chip=target_chip?(case_index-12):case_index;
 wire[1:0]target_bank=case_within_chip/3;
 wire[1:0]column_case=case_within_chip%3;
 wire[9:0]base_column=(column_case==0)?10'd0:(column_case==1)?10'd8:10'd1016;
 wire[12:0]target_row={8'b0,case_index};
 wire[9:0]current_column=base_column+beat;
 wire[26:0]current_byte_address={1'b0,target_chip,target_bank,target_row,current_column};

 function automatic[15:0]base_pattern(input[4:0]c,input[2:0]b);
  base_pattern=16'h39c5^{c,3'b0,b,c}^{8'h00,{c,b}};
 endfunction
 function automatic[15:0]overlay_pattern(input[4:0]c,input[2:0]b);
  overlay_pattern=16'ha61e^{b,c,3'b0}^{8'h5a,{b,c}};
 endfunction
 function automatic[15:0]expected_pattern(input[4:0]c,input[2:0]b,input[1:0]mode);
  reg[15:0]base,over;
  begin
   base=base_pattern(c,b);over=overlay_pattern(c,b);
   case(mode)
    0:expected_pattern=base;
    1:expected_pattern=b[0]?{over[15:8],base[7:0]}:{base[15:8],over[7:0]};
    2:expected_pattern={base[15:8],over[7:0]};
    default:expected_pattern={over[15:8],base[7:0]};
   endcase
  end
 endfunction

 always_comb begin
  sdram_a=0;sdram_ba=target_bank;sdram_cke=(state!=PWR);sdram_ncs=target_chip;
  sdram_nras=1;sdram_ncas=1;sdram_nwe=1;sdram_dqml=0;sdram_dqmh=0;
  sdram_dq_oe=0;sdram_dq_out=base_pattern(case_index,beat);
  case(state)
   PRE0:begin sdram_ncs=0;sdram_nras=0;sdram_nwe=0;sdram_a[10]=1;end
   PRE1:begin sdram_ncs=1;sdram_nras=0;sdram_nwe=0;sdram_a[10]=1;end
   REF0:begin sdram_ncs=0;sdram_nras=0;sdram_ncas=0;end
   REF1:begin sdram_ncs=1;sdram_nras=0;sdram_ncas=0;end
   MRS0:begin sdram_ncs=0;sdram_nras=0;sdram_ncas=0;sdram_nwe=0;sdram_a=MODE_REGISTER;sdram_ba=0;end
   MRS1:begin sdram_ncs=1;sdram_nras=0;sdram_ncas=0;sdram_nwe=0;sdram_a=MODE_REGISTER;sdram_ba=0;end
   BASE_ACT,MASK_ACT,READ_ACT:begin sdram_nras=0;sdram_a=target_row;end
   BASE_CMD:begin sdram_ncas=0;sdram_nwe=0;sdram_a={2'b0,1'b1,base_column};sdram_dq_oe=1;end
   BASE_B1,BASE_B2,BASE_B3,BASE_B4,BASE_B5,BASE_B6,BASE_B7:begin sdram_dq_oe=1;end
   MASK_CMD,MASK_B1,MASK_B2,MASK_B3,MASK_B4,MASK_B5,MASK_B6,MASK_B7:begin
    sdram_dq_oe=1;sdram_dq_out=overlay_pattern(case_index,beat);
    case(test_mode)
     1:begin sdram_dqml=beat[0];sdram_dqmh=!beat[0];end
     2:begin sdram_dqml=0;sdram_dqmh=1;end
     default:begin sdram_dqml=1;sdram_dqmh=0;end
    endcase
    if(state==MASK_CMD)begin sdram_ncas=0;sdram_nwe=0;sdram_a={2'b0,1'b1,base_column};end
   end
   READ_CMD:begin sdram_ncas=0;sdram_a={2'b0,1'b1,base_column};end
   default:;
  endcase
  // MiSTer SDRAM controllers carry DQM in the otherwise-unused A12:A11 CAS
  // bits so address and byte masks launch from the identical packed vector.
  if(state>=MASK_CMD&&state<=MASK_B7)sdram_a[12:11]={sdram_dqmh,sdram_dqml};
 end

 assign init_done=(state>=CASE_START);
 assign test_done=(state==DONE);
 assign test_pass=(state==DONE)&&(error_count==0);

 always_ff@(posedge clk)begin
  if(reset)begin
   state<=PWR;timer<=0;refresh_count<=0;case_index<=0;beat<=0;pass_phase<=0;
   tested_words<=0;error_count<=0;first_fail_address<=0;first_fail_expected<=0;
   first_fail_observed<=0;first_fail_state<=0;first_fail_beat<=0;
  end else case(state)
   PWR:if(timer+1>=POWERUP_CYCLES)begin state<=CKE_WAIT;timer<=0;end else timer<=timer+1;
   CKE_WAIT:state<=PRE0;
   PRE0:state<=PRE1;
   PRE1:begin state<=WAIT_RP;timer<=0;end
   WAIT_RP:if(timer+1>=TRP)begin state<=REF0;refresh_count<=0;end else timer<=timer+1;
   REF0:begin state<=WAIT_RF0;timer<=0;end
   WAIT_RF0:if(timer+1>=TRFC)begin
    timer<=0;if(refresh_count==7)begin state<=REF1;refresh_count<=0;end
    else begin refresh_count<=refresh_count+1;state<=REF0;end
   end else timer<=timer+1;
   REF1:begin state<=WAIT_RF1;timer<=0;end
   WAIT_RF1:if(timer+1>=TRFC)begin
    timer<=0;if(refresh_count==7)state<=MRS0;
    else begin refresh_count<=refresh_count+1;state<=REF1;end
   end else timer<=timer+1;
   MRS0:state<=MRS1;
   MRS1:begin state<=WAIT_MRD;timer<=0;end
   WAIT_MRD:if(timer+1>=TMRD)state<=CASE_START;else timer<=timer+1;
   CASE_START:begin
    beat<=0;
    case(pass_phase)
     0:state<=BASE_ACT;
     1:state<=MASK_ACT;
     default:state<=READ_ACT;
    endcase
   end
   BASE_ACT:begin state<=BASE_RCD;timer<=0;end
   BASE_RCD:if(timer+1>=TRCD)begin beat<=0;state<=BASE_CMD;end else timer<=timer+1;
   BASE_CMD:begin beat<=1;state<=BASE_B1;end
   BASE_B1:begin beat<=2;state<=BASE_B2;end BASE_B2:begin beat<=3;state<=BASE_B3;end
   BASE_B3:begin beat<=4;state<=BASE_B4;end BASE_B4:begin beat<=5;state<=BASE_B5;end
   BASE_B5:begin beat<=6;state<=BASE_B6;end BASE_B6:begin beat<=7;state<=BASE_B7;end
   BASE_B7:begin state<=BASE_REC;timer<=0;end
   BASE_REC:if(timer+1>=TWR+TRP)begin beat<=0;state<=NEXT_CASE;end else timer<=timer+1;
   MASK_ACT:begin state<=MASK_RCD;timer<=0;end
   MASK_RCD:if(timer+1>=TRCD)begin beat<=0;state<=MASK_CMD;end else timer<=timer+1;
   MASK_CMD:begin beat<=1;state<=MASK_B1;end
   MASK_B1:begin beat<=2;state<=MASK_B2;end MASK_B2:begin beat<=3;state<=MASK_B3;end
   MASK_B3:begin beat<=4;state<=MASK_B4;end MASK_B4:begin beat<=5;state<=MASK_B5;end
   MASK_B5:begin beat<=6;state<=MASK_B6;end MASK_B6:begin beat<=7;state<=MASK_B7;end
   MASK_B7:begin state<=MASK_REC;timer<=0;end
   MASK_REC:if(timer+1>=TWR+TRP)begin beat<=0;state<=NEXT_CASE;end else timer<=timer+1;
   READ_ACT:begin state<=READ_RCD;timer<=0;end
   READ_RCD:if(timer+1>=TRCD)begin beat<=0;state<=READ_CMD;end else timer<=timer+1;
   READ_CMD:begin state<=READ_WAIT;timer<=0;end
   // Hardware probing established that the packed input register is already
   // accounted for by this CL3 schedule; no additional controller cycle is due.
   READ_WAIT:if(timer+1>=CL)state<=READ_SAMPLE;else timer<=timer+1;
   READ_SAMPLE:begin
    tested_words<=tested_words+1;
    if(sdram_dq_in!==expected_pattern(case_index,beat,test_mode))begin
     if(error_count==0)begin
      first_fail_address<=current_byte_address;
      first_fail_expected<=expected_pattern(case_index,beat,test_mode);
      first_fail_observed<=sdram_dq_in;
      first_fail_state<=READ_SAMPLE;first_fail_beat<=beat;
     end
     if(error_count!=32'hffffffff)error_count<=error_count+1;
    end
    if(beat==7)state<=NEXT_CASE;
    else beat<=beat+1'b1;
   end
   NEXT_CASE:if(case_index!=5'd23)begin case_index<=case_index+1'b1;state<=CASE_START;end
   else begin
    case_index<=0;
    case(pass_phase)
     0:if(test_mode==0)begin pass_phase<=2;timer<=0;state<=PERSIST_WAIT;end
       else begin pass_phase<=1;state<=CASE_START;end
     1:begin pass_phase<=2;timer<=0;state<=PERSIST_WAIT;end
     default:state<=DONE;
    endcase
   end
   PERSIST_WAIT:if(timer+1>=PERSIST_CYCLES)begin timer<=0;state<=CASE_START;end else timer<=timer+1;
   DONE:state<=DONE;
   default:state<=PWR;
  endcase
 end

 initial if(SDRAM_FREQ_HZ==0)$error("SDRAM_FREQ_HZ must be non-zero");
endmodule
