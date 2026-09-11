module sdram_frequency_bist #(
 parameter longint unsigned SDRAM_FREQ_HZ = 100_000_000,
 parameter integer ADDRESS_BITS = 16,
 parameter integer POWERUP_US = 200
)(
 input  logic clk,
 input  logic reset,
 input  logic [15:0] sdram_dq_in,
 output logic [12:0] sdram_a,
 output logic [1:0]  sdram_ba,
 output logic sdram_cke,
 output logic sdram_ncs,
 output logic sdram_nras,
 output logic sdram_ncas,
 output logic sdram_nwe,
 output logic sdram_dqml,
 output logic sdram_dqmh,
 output logic [15:0] sdram_dq_out,
 output logic sdram_dq_oe,
 output logic init_done,
 output logic [31:0] pass_count,
 output logic [31:0] error_count,
 output logic [15:0] first_fail_address,
 output logic [15:0] first_fail_expected,
 output logic [15:0] first_fail_observed,
 output logic [4:0] pattern_number
);
 function automatic longint unsigned ceil_ns(input longint unsigned ns);
  ceil_ns = (ns*SDRAM_FREQ_HZ+64'd999_999_999)/64'd1_000_000_000;
 endfunction
 localparam longint unsigned POWERUP_CYCLES=(SDRAM_FREQ_HZ*POWERUP_US+999_999)/1_000_000;
 localparam longint unsigned TRCD=ceil_ns(21),TRP=ceil_ns(21),TWR=ceil_ns(14);
 localparam longint unsigned TRFC=ceil_ns(63),TMRD0=ceil_ns(14),TMRD=(TMRD0<2)?2:TMRD0;
 localparam longint unsigned CL=3;
 localparam [12:0] MODE_REGISTER=13'h030; // sequential BL1, CL3
 localparam logic [4:0] LAST_PATTERN=5'd23;

 typedef enum logic[4:0] {PWR,CKE_WAIT,PRE0,PRE1,WAIT_RP,REF0,WAIT_RF0,
  REF1,WAIT_RF1,MRS0,MRS1,WAIT_MRD,WRITE_START,ACT_W,WAIT_RCD_W,
  WRITE_CMD,WAIT_WRITE,WRITE_NEXT,READ_START,ACT_R,WAIT_RCD_R,READ_CMD,
  WAIT_READ,CHECK,READ_NEXT,TEST_REF0,TEST_RFC0,TEST_REF1,TEST_RFC1,
  TEST_RESUME} state_t;
 state_t state;
 longint unsigned timer;
 integer refresh_count;
 logic [ADDRESS_BITS-1:0] index;
 logic refresh_resume_read;
 wire last_address=&index;

 function automatic [15:0] lfsr_mix(input [15:0] value);
  integer n;
  reg [15:0] x;
  begin
   x=value^16'h1d3f;
   for(n=0;n<16;n=n+1) x={x[14:0],x[15]^x[13]^x[12]^x[10]};
   lfsr_mix=x;
  end
 endfunction
 function automatic [15:0] pattern(input [4:0] number,input [15:0] address);
  begin
   case(number)
    0: pattern=16'h0000;
    1: pattern=16'hffff;
    2: pattern=16'haaaa;
    3: pattern=16'h5555;
    4: pattern=address;
    5: pattern=~address;
    6: pattern=lfsr_mix(address);
    7: pattern=~lfsr_mix(address);
    default: pattern=16'h0001<<(number-8); // walking one, patterns 8..23
   endcase
  end
 endfunction

 // Deliberately make consecutive logical addresses exercise columns first,
 // then rows, banks, and finally the board's complementary chip select.
 wire target_chip=index[ADDRESS_BITS-1];
 wire [1:0] target_bank=index[ADDRESS_BITS-2 -: 2];
 wire [12:0] target_row={10'b0,index[12:10]};
 wire [9:0] target_column=index[9:0];

 always_comb begin
  sdram_a=0;sdram_ba=target_bank;sdram_cke=(state!=PWR);sdram_ncs=target_chip;
  sdram_nras=1;sdram_ncas=1;sdram_nwe=1;
  sdram_dqml=(state==PWR||state==CKE_WAIT);sdram_dqmh=sdram_dqml;
  sdram_dq_oe=0;sdram_dq_out=pattern(pattern_number,index);
  case(state)
   PRE0:begin sdram_ncs=0;sdram_nras=0;sdram_nwe=0;sdram_a[10]=1;end
   PRE1:begin sdram_ncs=1;sdram_nras=0;sdram_nwe=0;sdram_a[10]=1;end
   REF0,TEST_REF0:begin sdram_ncs=0;sdram_nras=0;sdram_ncas=0;end
   REF1,TEST_REF1:begin sdram_ncs=1;sdram_nras=0;sdram_ncas=0;end
   MRS0:begin sdram_ncs=0;sdram_nras=0;sdram_ncas=0;sdram_nwe=0;sdram_a=MODE_REGISTER;sdram_ba=0;end
   MRS1:begin sdram_ncs=1;sdram_nras=0;sdram_ncas=0;sdram_nwe=0;sdram_a=MODE_REGISTER;sdram_ba=0;end
   ACT_W,ACT_R:begin sdram_nras=0;sdram_a=target_row;end
   WRITE_CMD:begin sdram_ncas=0;sdram_nwe=0;sdram_a={2'b0,1'b1,target_column};sdram_dq_oe=1;end
   READ_CMD:begin sdram_ncas=0;sdram_a={2'b0,1'b1,target_column};end
   default:;
  endcase
 end
 assign init_done=(state>=WRITE_START);

 always_ff @(posedge clk) begin
  if(reset) begin
   state<=PWR;timer<=0;refresh_count<=0;index<=0;pattern_number<=0;
   refresh_resume_read<=0;pass_count<=0;error_count<=0;
   first_fail_address<=0;first_fail_expected<=0;first_fail_observed<=0;
  end else case(state)
   PWR:if(timer+1>=POWERUP_CYCLES)begin state<=CKE_WAIT;timer<=0;end else timer<=timer+1;
   CKE_WAIT:state<=PRE0;
   PRE0:state<=PRE1;
   PRE1:begin state<=WAIT_RP;timer<=0;end
   WAIT_RP:if(timer+1>=TRP)begin state<=REF0;refresh_count<=0;end else timer<=timer+1;
   REF0:begin state<=WAIT_RF0;timer<=0;end
   WAIT_RF0:if(timer+1>=TRFC)begin if(refresh_count==7)begin state<=REF1;refresh_count<=0;end else begin refresh_count<=refresh_count+1;state<=REF0;end end else timer<=timer+1;
   REF1:begin state<=WAIT_RF1;timer<=0;end
   WAIT_RF1:if(timer+1>=TRFC)begin if(refresh_count==7)state<=MRS0;else begin refresh_count<=refresh_count+1;state<=REF1;end end else timer<=timer+1;
   MRS0:state<=MRS1;
   MRS1:begin state<=WAIT_MRD;timer<=0;end
   WAIT_MRD:if(timer+1>=TMRD)state<=WRITE_START;else timer<=timer+1;
   WRITE_START:begin index<=0;state<=ACT_W;end
   ACT_W:begin state<=WAIT_RCD_W;timer<=0;end
   WAIT_RCD_W:if(timer+1>=TRCD)state<=WRITE_CMD;else timer<=timer+1;
   WRITE_CMD:begin state<=WAIT_WRITE;timer<=0;end
   WAIT_WRITE:if(timer+1>=TWR+TRP)state<=WRITE_NEXT;else timer<=timer+1;
   WRITE_NEXT:if(last_address)state<=READ_START;else begin index<=index+1'b1;
     if(index[5:0]==6'h3f)begin refresh_resume_read<=0;state<=TEST_REF0;end else state<=ACT_W;end
   READ_START:begin index<=0;state<=ACT_R;end
   ACT_R:begin state<=WAIT_RCD_R;timer<=0;end
   WAIT_RCD_R:if(timer+1>=TRCD)state<=READ_CMD;else timer<=timer+1;
   READ_CMD:begin state<=WAIT_READ;timer<=0;end
   // The packed input register captures on the controller edge after the CL3
   // external return edge; allow one further controller cycle for that sample
   // to cross into this state machine through nonblocking register semantics.
   WAIT_READ:if(timer+1>=CL+1)state<=CHECK;else timer<=timer+1;
   CHECK:begin
    if(sdram_dq_in!==pattern(pattern_number,index))begin
     if(error_count==0)begin first_fail_address<=index;first_fail_expected<=pattern(pattern_number,index);first_fail_observed<=sdram_dq_in;end
     if(error_count!=32'hffffffff)error_count<=error_count+1'b1;
    end
    state<=READ_NEXT;
   end
   READ_NEXT:if(last_address)begin
     if(pattern_number==LAST_PATTERN)begin pattern_number<=0;if(pass_count!=32'hffffffff)pass_count<=pass_count+1'b1;end
     else pattern_number<=pattern_number+1'b1;
     state<=WRITE_START;
    end else begin index<=index+1'b1;
     if(index[5:0]==6'h3f)begin refresh_resume_read<=1;state<=TEST_REF0;end else state<=ACT_R;end
   TEST_REF0:begin state<=TEST_RFC0;timer<=0;end
   TEST_RFC0:if(timer+1>=TRFC)state<=TEST_REF1;else timer<=timer+1;
   TEST_REF1:begin state<=TEST_RFC1;timer<=0;end
   TEST_RFC1:if(timer+1>=TRFC)state<=TEST_RESUME;else timer<=timer+1;
   TEST_RESUME:state<=refresh_resume_read?ACT_R:ACT_W;
   default:state<=PWR;
  endcase
 end

 initial begin
  if(ADDRESS_BITS!=16)$error("006.a address mapping requires ADDRESS_BITS=16");
  if(SDRAM_FREQ_HZ!=20_000_000&&SDRAM_FREQ_HZ!=100_000_000&&
     SDRAM_FREQ_HZ!=120_000_000&&SDRAM_FREQ_HZ!=130_000_000&&
     SDRAM_FREQ_HZ!=142_857_000&&SDRAM_FREQ_HZ!=150_000_000&&
     SDRAM_FREQ_HZ!=153_000_000&&
     SDRAM_FREQ_HZ!=143_000_000)$error("unsupported 006.a SDRAM frequency");
 end
endmodule
