module sdram_init_refresh #(
 parameter longint unsigned SDRAM_FREQ_HZ=130_000_000, parameter integer CAS_LATENCY=3,
 parameter integer POWERUP_US=200, parameter integer REFRESH_COUNT=8,
 parameter longint unsigned REFRESH_PHASE_CYCLES=0,
 parameter bit INIT_ONLY=0
)(input logic clk,reset,input logic chip0_all_banks_idle,chip1_all_banks_idle,input logic command_accept,
 output logic init_done,cke,dqm_hold,command_valid,command_chip,output logic[2:0]command,
 output logic[12:0]command_address,output logic refresh0_block,refresh1_block,late_refresh0,late_refresh1);
 function automatic longint unsigned ceil_ns(input longint unsigned ns);
   ceil_ns=(ns*SDRAM_FREQ_HZ+64'd999_999_999)/64'd1_000_000_000;
 endfunction
 localparam[2:0] NOP=0,PRE=1,REF=2,MRS=3;
 localparam longint unsigned POWERUP_CYCLES=(SDRAM_FREQ_HZ*POWERUP_US+999_999)/1_000_000;
 localparam longint unsigned TRP=ceil_ns(21),TRFC=ceil_ns(63),TMRD0=ceil_ns(14),TMRD=(TMRD0<2)?2:TMRD0;
 localparam longint unsigned TREFI=(SDRAM_FREQ_HZ*64'd78)/64'd10_000_000;
 localparam longint unsigned PHASE=(REFRESH_PHASE_CYCLES==0)?TREFI/2:REFRESH_PHASE_CYCLES;
 localparam longint unsigned CLOSE_LATENCY=TRP+2;
 localparam longint unsigned REFRESH_SERVICE=CLOSE_LATENCY+TRFC+1;
 // A due chip can be blocked by the other chip's complete refresh transaction.
 // Start early enough for that service plus our own worst-case open-bank close.
 localparam longint unsigned PREP_LATENCY=REFRESH_SERVICE+CLOSE_LATENCY;
 localparam longint unsigned PREP_AGE=(TREFI>PREP_LATENCY)?TREFI-PREP_LATENCY:0;
 localparam[12:0] MODE=(CAS_LATENCY<<4)|3'b011;
 typedef enum logic[4:0]{I_POWER,I_CKE,I_PRE0,I_PRE1,I_TRP,I_REF0,I_RFC0,I_REF1,I_RFC1,I_MRS0,I_MRS1,I_MRD,I_RUN,
  R_PRE0,R_TRP0,R_REF0,R_RFC0,R_PRE1,R_TRP1,R_REF1,R_RFC1}state_t;
 state_t state;longint unsigned timer,age0,age1;integer refs;
 wire due0=init_done&&age0>=PREP_AGE,due1=init_done&&age1>=PREP_AGE;
 assign init_done=(state>=I_RUN);assign cke=(state!=I_POWER);assign dqm_hold=(state==I_POWER||state==I_CKE);
 assign refresh0_block=due0||(state>=R_PRE0&&state<=R_RFC0);
 assign refresh1_block=due1||(state>=R_PRE1&&state<=R_RFC1);
 always_comb begin command_valid=0;command_chip=0;command=NOP;command_address=0;
  case(state)
   I_PRE0,R_PRE0:begin command_valid=1;command=PRE;command_address[10]=1;end
   I_PRE1,R_PRE1:begin command_valid=1;command_chip=1;command=PRE;command_address[10]=1;end
   I_REF0,R_REF0:begin command_valid=1;command=REF;end
   I_REF1,R_REF1:begin command_valid=1;command_chip=1;command=REF;end
   I_MRS0:begin command_valid=1;command=MRS;command_address=MODE;end
   I_MRS1:begin command_valid=1;command_chip=1;command=MRS;command_address=MODE;end
   default:;
  endcase end
 always_ff@(posedge clk)begin
  if(reset)begin state<=I_POWER;timer<=0;refs<=0;age0<=0;age1<=0;late_refresh0<=0;late_refresh1<=0;end
  else begin
   if(init_done&&!INIT_ONLY)begin
    age0<=age0+1;age1<=age1+1;
    if(age0>=TREFI&&!(state==R_REF0&&command_accept))late_refresh0<=1;
    if(age1>=TREFI&&!(state==R_REF1&&command_accept))late_refresh1<=1;
   end
   case(state)
    I_POWER:if(timer+1>=POWERUP_CYCLES)begin state<=I_CKE;timer<=0;end else timer<=timer+1;
    I_CKE:state<=I_PRE0;
    I_PRE0:if(command_accept)state<=I_PRE1;
    I_PRE1:if(command_accept)begin state<=I_TRP;timer<=0;end
    I_TRP:if(timer+1>=TRP)begin state<=I_REF0;refs<=0;end else timer<=timer+1;
    I_REF0:if(command_accept)begin state<=I_RFC0;timer<=0;end
    I_RFC0:if(timer+1>=TRFC)begin if(refs+1>=REFRESH_COUNT)begin state<=I_REF1;refs<=0;end else begin refs<=refs+1;state<=I_REF0;end end else timer<=timer+1;
    I_REF1:if(command_accept)begin state<=I_RFC1;timer<=0;end
    I_RFC1:if(timer+1>=TRFC)begin if(refs+1>=REFRESH_COUNT)state<=I_MRS0;else begin refs<=refs+1;state<=I_REF1;end end else timer<=timer+1;
    I_MRS0:if(command_accept)state<=I_MRS1;
    I_MRS1:if(command_accept)begin state<=I_MRD;timer<=0;end
    I_MRD:if(timer+1>=TMRD)begin state<=I_RUN;age0<=0;age1<=TREFI-PHASE;end else timer<=timer+1;
    I_RUN:if(!INIT_ONLY)begin
     if(due0)begin state<=chip0_all_banks_idle?R_REF0:R_PRE0;timer<=0;end
     else if(due1)begin state<=chip1_all_banks_idle?R_REF1:R_PRE1;timer<=0;end
    end
    R_PRE0:if(command_accept)begin state<=R_TRP0;timer<=0;end
    R_TRP0:if(timer+1>=TRP)state<=R_REF0;else timer<=timer+1;
    R_REF0:if(command_accept)begin state<=R_RFC0;timer<=0;age0<=0;end
    R_RFC0:if(timer+1>=TRFC)state<=I_RUN;else timer<=timer+1;
    R_PRE1:if(command_accept)begin state<=R_TRP1;timer<=0;end
    R_TRP1:if(timer+1>=TRP)state<=R_REF1;else timer<=timer+1;
    R_REF1:if(command_accept)begin state<=R_RFC1;timer<=0;age1<=0;end
    R_RFC1:if(timer+1>=TRFC)state<=I_RUN;else timer<=timer+1;
    default:state<=I_POWER;
   endcase
  end
 end
 initial begin
  if(CAS_LATENCY==2&&SDRAM_FREQ_HZ>100_000_000)$error("CL2 only legal at <=100MHz");
  if(!(CAS_LATENCY==2||CAS_LATENCY==3))$error("CAS latency must be 2 or 3");
  if(PHASE>=TREFI)$error("refresh phase must be below tREFI");
  if(PHASE<REFRESH_SERVICE||TREFI-PHASE<REFRESH_SERVICE)
   $error("refresh phase cannot keep both chips within their refresh deadlines");
  if(SDRAM_FREQ_HZ==130_000_000&&(TRP!=3||TRFC!=9||TMRD!=2||TREFI!=1014))$error("130MHz timing conversion failure");
  if(SDRAM_FREQ_HZ==100_000_000&&(TRP!=3||TRFC!=7||TMRD!=2||TREFI!=780))$error("100MHz timing conversion failure");
  if(SDRAM_FREQ_HZ==120_000_000&&(TRP!=3||TRFC!=8||TMRD!=2||TREFI!=936))$error("120MHz timing conversion failure");
  if(SDRAM_FREQ_HZ==143_000_000&&(TRP!=4||TRFC!=10||TMRD!=3||TREFI!=1115))$error("143MHz timing conversion failure");
 end
endmodule
