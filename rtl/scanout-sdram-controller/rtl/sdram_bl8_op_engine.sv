module sdram_bl8_op_engine #(
 parameter longint unsigned SDRAM_FREQ_HZ=20_000_000,
 parameter integer POWERUP_US=200
)(
 input logic clk,reset,
 input logic op_valid,op_write,input logic[26:0]op_byte_address,input logic[3:0]op_words,
 output logic op_ready,
 input logic write_valid,input logic[15:0]write_data,input logic[1:0]write_byte_enable,
 output logic write_ready,
 output logic read_valid,input logic read_ready,output logic[15:0]read_data,
 output logic completion_valid,
 output logic[12:0]sdram_a,output logic[1:0]sdram_ba,
 output logic sdram_cke,sdram_ncs,sdram_nras,sdram_ncas,sdram_nwe,
 output logic sdram_dqml,sdram_dqmh,
 input logic[15:0]sdram_dq_in,output logic[15:0]sdram_dq_out,output logic sdram_dq_oe,
 output logic init_done
);
 function automatic longint unsigned ceil_ns(input longint unsigned ns);
  ceil_ns=(ns*SDRAM_FREQ_HZ+64'd999_999_999)/64'd1_000_000_000;
 endfunction
 localparam longint unsigned POWERUP_CYCLES=(SDRAM_FREQ_HZ*POWERUP_US+999_999)/1_000_000;
 localparam longint unsigned TRCD=ceil_ns(21),TRP=ceil_ns(21),TWR=ceil_ns(14),TRFC=ceil_ns(63);
 localparam longint unsigned TMRD_RAW=ceil_ns(14),TMRD=(TMRD_RAW<2)?2:TMRD_RAW;
 localparam longint unsigned CL=3;
 localparam logic[12:0]MODE=13'b000_0_00_011_0_011;
 typedef enum logic[4:0]{PWR,CKE_WAIT,PRE0,PRE1,WAIT_RP,REF0,WAIT_RF0,REF1,WAIT_RF1,
  MRS0,MRS1,WAIT_MRD,IDLE,COLLECT,ACT,WAIT_RCD,WRITE_BURST,WRITE_REC,
  READ_CMD,READ_WAIT,READ_BURST,READ_DRAIN,DONE}state_t;
 state_t state;
 // Keep the startup delay out of the per-command timer's carry/comparison path.
 localparam integer POWERUP_BITS=(POWERUP_CYCLES>1)?$clog2(POWERUP_CYCLES):1;
 localparam longint unsigned WAIT_MAX0=(TRFC>TWR+TRP)?TRFC:TWR+TRP;
 localparam longint unsigned WAIT_MAX1=(WAIT_MAX0>TRCD)?WAIT_MAX0:TRCD;
 localparam longint unsigned WAIT_MAX2=(WAIT_MAX1>TMRD)?WAIT_MAX1:TMRD;
 localparam longint unsigned WAIT_MAX=(WAIT_MAX2>CL+1)?WAIT_MAX2:CL+1;
 localparam integer TIMER_BITS=(WAIT_MAX>1)?$clog2(WAIT_MAX):1;
 logic [POWERUP_BITS-1:0] powerup_timer;
 logic [TIMER_BITS-1:0] timer;
 logic [2:0] refresh_count;
 logic write_q,chip_q;
 logic[1:0]bank_q;
 logic[12:0]row_q;
 logic[9:0]column_q;
 logic[3:0]words_q;
 logic[3:0]beat;
 logic[15:0]write_buffer[0:7];
 logic[1:0]enable_buffer[0:7];
 // One operation owns the whole buffer. Capture never depends on read_ready;
 // completion is withheld until every useful word has been delivered.
 logic[15:0]read_buffer[0:7];
 // Unconditional fabric register: keep the phase-shifted I/O-to-core path
 // free of RAM input muxing, comparison, and counter enables.
 (* preserve *) logic[15:0]dq_handoff;
 always_ff @(posedge clk)dq_handoff<=sdram_dq_in;
 wire decoded_chip,decoded_byte_select;
 wire[1:0]decoded_bank;
 wire[12:0]decoded_row;
 wire[9:0]decoded_column;
 wire[10:0]decoded_contiguous;
 sdram_addr_decode #(.MAPPING(5)) decode(
  .byte_address(op_byte_address),.chip(decoded_chip),.bank(decoded_bank),.row(decoded_row),
  .column(decoded_column),.byte_select(decoded_byte_select),.contiguous_words(decoded_contiguous));

 assign init_done=(state>=IDLE);
 assign op_ready=(state==IDLE)&&init_done&&!decoded_byte_select&&
                 (op_words>=1)&&(op_words<=8-{1'b0,decoded_column[2:0]})&&
                 ({7'b0,op_words}<=decoded_contiguous);
 assign write_ready=(state==COLLECT);
 assign read_valid=(state==READ_DRAIN);
 assign read_data=read_buffer[beat[2:0]];
 assign completion_valid=(state==DONE);

 always_comb begin
  sdram_a=0;sdram_ba=bank_q;sdram_cke=(state!=PWR);sdram_ncs=chip_q;
  sdram_nras=1;sdram_ncas=1;sdram_nwe=1;sdram_dqml=0;sdram_dqmh=0;
  sdram_dq_out=write_buffer[beat[2:0]];sdram_dq_oe=0;
  case(state)
   PRE0:begin sdram_ncs=0;sdram_nras=0;sdram_nwe=0;sdram_a[10]=1;end
   PRE1:begin sdram_ncs=1;sdram_nras=0;sdram_nwe=0;sdram_a[10]=1;end
   REF0:begin sdram_ncs=0;sdram_nras=0;sdram_ncas=0;end
   REF1:begin sdram_ncs=1;sdram_nras=0;sdram_ncas=0;end
   MRS0:begin sdram_ncs=0;sdram_nras=0;sdram_ncas=0;sdram_nwe=0;sdram_a=MODE;sdram_ba=0;end
   MRS1:begin sdram_ncs=1;sdram_nras=0;sdram_ncas=0;sdram_nwe=0;sdram_a=MODE;sdram_ba=0;end
   ACT:begin sdram_nras=0;sdram_a=row_q;end
   WRITE_BURST:begin
    sdram_dq_oe=1;
    if(beat<words_q)begin sdram_dqml=!enable_buffer[beat[2:0]][0];sdram_dqmh=!enable_buffer[beat[2:0]][1];end
    else begin sdram_dqml=1;sdram_dqmh=1;end
    sdram_a[12:11]={sdram_dqmh,sdram_dqml};
    if(beat==0)begin sdram_ncas=0;sdram_nwe=0;sdram_a[10]=1;sdram_a[9:0]=column_q;end
   end
   READ_CMD:begin sdram_ncas=0;sdram_a={2'b0,1'b1,column_q};end
   default:;
  endcase
 end

 always_ff@(posedge clk)begin
  if(reset)begin state<=PWR;powerup_timer<=0;timer<=0;refresh_count<=0;beat<=0;write_q<=0;chip_q<=0;
   bank_q<=0;row_q<=0;column_q<=0;words_q<=0;end
  else case(state)
   PWR:if(POWERUP_CYCLES==0||powerup_timer==POWERUP_CYCLES-1)state<=CKE_WAIT;
       else powerup_timer<=powerup_timer+1'b1;
   CKE_WAIT:state<=PRE0;PRE0:state<=PRE1;PRE1:begin state<=WAIT_RP;timer<=0;end
   WAIT_RP:if(timer==TRP-1)begin state<=REF0;refresh_count<=0;end else timer<=timer+1'b1;
   REF0:begin state<=WAIT_RF0;timer<=0;end
   WAIT_RF0:if(timer==TRFC-1)begin timer<=0;if(refresh_count==7)begin state<=REF1;refresh_count<=0;end else begin refresh_count<=refresh_count+1'b1;state<=REF0;end end else timer<=timer+1'b1;
   REF1:begin state<=WAIT_RF1;timer<=0;end
   WAIT_RF1:if(timer==TRFC-1)begin timer<=0;if(refresh_count==7)state<=MRS0;else begin refresh_count<=refresh_count+1'b1;state<=REF1;end end else timer<=timer+1'b1;
   MRS0:state<=MRS1;MRS1:begin state<=WAIT_MRD;timer<=0;end
   WAIT_MRD:if(timer==TMRD-1)state<=IDLE;else timer<=timer+1'b1;
   IDLE:if(op_valid&&op_ready)begin
    write_q<=op_write;chip_q<=decoded_chip;bank_q<=decoded_bank;row_q<=decoded_row;
    column_q<=decoded_column;words_q<=op_words;beat<=0;
    state<=op_write?COLLECT:ACT;
   end
   COLLECT:if(write_valid&&write_ready)begin
    write_buffer[beat[2:0]]<=write_data;enable_buffer[beat[2:0]]<=write_byte_enable;
    if(beat==words_q-1'b1)begin beat<=0;state<=ACT;end else beat<=beat+1'b1;
   end
   ACT:begin state<=WAIT_RCD;timer<=0;end
   WAIT_RCD:if(timer==TRCD-1)begin beat<=0;state<=write_q?WRITE_BURST:READ_CMD;end else timer<=timer+1'b1;
   WRITE_BURST:if(beat==7)begin state<=WRITE_REC;timer<=0;end else beat<=beat+1'b1;
   WRITE_REC:if(timer==TWR+TRP-1)state<=DONE;else timer<=timer+1'b1;
   READ_CMD:begin state<=READ_WAIT;timer<=0;end
   // One extra cycle compensates for dq_handoff, preserving physical beat 0.
   READ_WAIT:if(timer==CL)begin beat<=0;state<=READ_BURST;end else timer<=timer+1'b1;
   READ_BURST:begin
    read_buffer[beat[2:0]]<=dq_handoff;
    if(beat==7)begin beat<=0;state<=READ_DRAIN;end else beat<=beat+1'b1;
   end
   READ_DRAIN:if(read_valid&&read_ready)begin
    if(beat==words_q-1'b1)state<=DONE;else beat<=beat+1'b1;
   end
   DONE:state<=IDLE;
   default:state<=PWR;
  endcase
 end
`ifdef FORMAL
 // Prove conservation and stall behavior independently of SDRAM contents.
 // One arbitrary watched beat represents any of the eight burst positions.
 (* anyconst *) logic [2:0] f_watch;
 logic [15:0] f_expected;
 logic f_seen;
 logic [3:0] f_captured,f_delivered,f_written;
 logic f_past_valid=0;
 always_ff @(posedge clk)begin
  f_past_valid<=1;
  if(reset)begin f_seen<=0;f_captured<=0;f_delivered<=0;f_written<=0;end
  else begin
   if(op_valid&&op_ready)begin f_seen<=0;f_captured<=0;f_delivered<=0;f_written<=0;end
   if(write_valid&&write_ready)f_written<=f_written+1'b1;
   if(state==READ_BURST)begin
    f_captured<=f_captured+1'b1;
    if(beat[2:0]==f_watch)begin f_expected<=dq_handoff;f_seen<=1;end
   end
   if(read_valid&&read_ready)f_delivered<=f_delivered+1'b1;
   assert(beat<=7);
   if(state>=COLLECT)begin assert(words_q>=1);assert(words_q<=8);end
   if(state==COLLECT)assert(beat<words_q);
   if(state==COLLECT||state==WRITE_BURST||state==WRITE_REC)assert(write_q);
   if(state==READ_CMD||state==READ_WAIT||state==READ_BURST||state==READ_DRAIN)assert(!write_q);
   if(state==COLLECT)assert(f_written==beat);
   if(state==WRITE_BURST||state==WRITE_REC)assert(f_written==words_q);
   if(state==READ_BURST)assert(f_captured==beat);
   if(state==READ_BURST||state==READ_DRAIN)begin
    assert(f_seen==(f_captured>{1'b0,f_watch}));
    if(f_seen)assert(read_buffer[f_watch]==f_expected);
   end
   if(read_valid)begin
    assert(f_captured==8);
    assert(f_delivered==beat);
    assert(beat<words_q);
    if(beat[2:0]==f_watch)begin assert(f_seen);assert(read_data==f_expected);end
   end
   if(completion_valid)begin
    assert(init_done);
    if(write_q)assert(f_written==words_q);
    else begin assert(f_captured==8);assert(f_delivered==words_q);end
   end
  end
  if(f_past_valid&&!reset&&!$past(reset))begin
   if($past(read_valid&&!read_ready))begin
    assert(read_valid);assert(read_data==$past(read_data));assert(!completion_valid);
   end
  end
  cover(!reset&&completion_valid&&!write_q&&words_q==8);
 end
`endif
endmodule
