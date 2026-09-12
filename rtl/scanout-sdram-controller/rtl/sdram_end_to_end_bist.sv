module sdram_end_to_end_bist #(
 parameter longint unsigned SDRAM_FREQ_HZ=20_000_000,
 parameter integer PERSIST_US=1000
)(
 input logic clk,reset,input logic[1:0]test_mode,input logic engine_init_done,
 output logic op_valid,input logic op_ready,output logic op_write,
 output logic[26:0]op_byte_address,output logic[3:0]op_words,output logic op_last,
 output logic write_valid,input logic write_ready,output logic[15:0]write_data,
 output logic[1:0]write_byte_enable,
 input logic read_valid,output logic read_ready,input logic[15:0]read_data,
 input logic completion_valid,
 output logic done,pass,output logic[31:0]checked_words,error_count,
 output logic[26:0]first_fail_address,output logic[15:0]first_fail_expected,first_fail_observed
);
 localparam longint unsigned DWELL_RAW=(SDRAM_FREQ_HZ*PERSIST_US+999_999)/1_000_000;
 localparam longint unsigned DWELL_CYCLES=(DWELL_RAW<1)?1:DWELL_RAW;
 localparam integer DWELL_BITS=(DWELL_CYCLES>1)?$clog2(DWELL_CYCLES):1;
 localparam integer TOTAL_WORDS=58;
 typedef enum logic[1:0]{RUN,DWELL,FINISHED}state_t;
 state_t state;
 logic[1:0]phase;
 logic[2:0]request_index;
 logic request_submitted,operation_active,active_last;
 logic[26:0]active_address;
 logic[3:0]active_words,word_index;
 logic[3:0]logical_word_index;
 logic[DWELL_BITS-1:0]dwell_timer;
 logic protocol_error;
 logic sample_valid,compare_valid,compare_bad;
 logic[26:0]sample_address,compare_address;
 logic[15:0]sample_expected,sample_observed,compare_expected,compare_observed;
 logic split_req_valid,split_req_ready,split_op_valid,split_op_ready;
 logic split_op_write,split_op_last;
 logic[26:0]split_op_address;
 logic[3:0]split_op_words;

 function automatic[26:0]request_address(input[2:0]n);
  case(n)
   0:request_address=27'd14;
   1:request_address=27'd1016;
   2:request_address=27'd2040;
   3:request_address=27'd8184;
   default:request_address=27'd16376;
  endcase
 endfunction
 function automatic[15:0]request_length(input[2:0]n);
  request_length=(n==0)?16'd10:16'd12;
 endfunction
 function automatic[15:0]base_pattern(input[26:0]a);
  base_pattern=16'h35a7^a[15:0]^{a[7:0],a[26:19]};
 endfunction
 function automatic[15:0]overlay_pattern(input[26:0]a);
  overlay_pattern=16'hca18^{a[23:8]}^{a[14:0],1'b0};
 endfunction
 function automatic[1:0]byte_enable(input[26:0]a,input[1:0]mode);
  case(mode)
   0:byte_enable=2'b11;
   1:byte_enable=a[1]?2'b10:2'b01;
   2:byte_enable=2'b01;
   default:byte_enable=2'b10;
  endcase
 endfunction
 function automatic[15:0]expected_pattern(input[26:0]a,input[1:0]mode);
  reg[15:0]base,over;reg[1:0]be;
  begin
   base=base_pattern(a);over=overlay_pattern(a);be=byte_enable(a,mode);
   expected_pattern=(mode==0)?base:{be[1]?over[15:8]:base[15:8],be[0]?over[7:0]:base[7:0]};
  end
 endfunction

 assign split_req_valid=(state==RUN)&&engine_init_done&&!request_submitted;
 sdram_request_splitter #(.MAPPING(5),.BURST_WORDS(8)) splitter(
  .clk,.reset,.req_valid(split_req_valid),.req_ready(split_req_ready),
  .req_write(phase!=2),.req_byte_address(request_address(request_index)),
  .req_words(request_length(request_index)),.op_valid(split_op_valid),.op_ready(split_op_ready),
  .op_write(split_op_write),.op_byte_address(split_op_address),.op_words(split_op_words),.op_last(split_op_last));
 assign op_valid=split_op_valid&&!operation_active;
 assign split_op_ready=op_ready&&!operation_active;
 assign op_write=split_op_write;
 assign op_byte_address=split_op_address;
 assign op_words=split_op_words;
 assign op_last=split_op_last;
 // Independent logical cursor: a consistently wrong splitter must fail too.
 wire[26:0]logical_address=request_address(request_index)+{22'b0,logical_word_index,1'b0};
 assign write_valid=operation_active&&(phase!=2)&&(word_index<active_words);
 assign write_data=(phase==0)?base_pattern(logical_address):overlay_pattern(logical_address);
 assign write_byte_enable=(phase==0)?2'b11:byte_enable(logical_address,test_mode);
 assign read_ready=1;
 assign done=(state==FINISHED)&&!sample_valid&&!compare_valid;
 assign pass=done&&(error_count==0)&&!protocol_error&&(checked_words==TOTAL_WORDS);

 always_ff@(posedge clk)begin
  if(reset)begin state<=RUN;phase<=0;request_index<=0;request_submitted<=0;
   operation_active<=0;active_last<=0;active_address<=0;active_words<=0;word_index<=0;
   logical_word_index<=0;protocol_error<=0;sample_valid<=0;compare_valid<=0;compare_bad<=0;
   sample_address<=0;sample_expected<=0;sample_observed<=0;
   compare_address<=0;compare_expected<=0;compare_observed<=0;
   dwell_timer<=0;checked_words<=0;error_count<=0;first_fail_address<=0;
   first_fail_expected<=0;first_fail_observed<=0;
  end else begin
   // Separate accepting data, comparing it, and updating diagnostics.
   sample_valid<=read_valid&&read_ready&&operation_active;
   compare_valid<=sample_valid;
   if(sample_valid)begin
    compare_bad<=(sample_observed!==sample_expected);
    compare_address<=sample_address;compare_expected<=sample_expected;compare_observed<=sample_observed;
   end
   if(compare_valid)begin
    checked_words<=checked_words+1'b1;
    if(compare_bad)begin
     if(error_count==0)begin
      first_fail_address<=compare_address;first_fail_expected<=compare_expected;first_fail_observed<=compare_observed;
     end
     if(error_count!=32'hffffffff)error_count<=error_count+1'b1;
    end
   end
   if(split_req_valid&&split_req_ready)request_submitted<=1;
   if(op_valid&&op_ready)begin
    operation_active<=1;active_last<=split_op_last;active_address<=split_op_address;
    active_words<=split_op_words;word_index<=0;
    if(split_op_address!=logical_address||split_op_write!=(phase!=2)||
       split_op_words==0||{12'b0,logical_word_index}+{12'b0,split_op_words}>request_length(request_index)||
       split_op_last!=({12'b0,logical_word_index}+{12'b0,split_op_words}==request_length(request_index)))
     protocol_error<=1;
   end
   if(write_valid&&write_ready)begin word_index<=word_index+1'b1;logical_word_index<=logical_word_index+1'b1;end
   if(read_valid&&read_ready&&(!operation_active||phase!=2||word_index>=active_words))protocol_error<=1;
   if(read_valid&&read_ready&&operation_active)begin
    sample_address<=logical_address;sample_expected<=expected_pattern(logical_address,test_mode);sample_observed<=read_data;
    word_index<=word_index+1'b1;
    logical_word_index<=logical_word_index+1'b1;
   end
   if(completion_valid&&!operation_active)protocol_error<=1;
   if(completion_valid&&operation_active)begin
    if(word_index!=active_words)protocol_error<=1;
    operation_active<=0;word_index<=0;
    if(active_last)begin
     if({12'b0,logical_word_index}!=request_length(request_index))protocol_error<=1;
     logical_word_index<=0;
     request_submitted<=0;
     if(request_index!=4)request_index<=request_index+1'b1;
     else begin
      request_index<=0;
      if(phase==0&&test_mode!=0)phase<=1;
      else if(phase<2)begin phase<=2;state<=DWELL;dwell_timer<=0;end
      else state<=FINISHED;
     end
    end
   end
   if(state==DWELL)begin
    if(dwell_timer==DWELL_CYCLES-1)begin state<=RUN;request_submitted<=0;end
    else dwell_timer<=dwell_timer+1'b1;
   end
  end
 end
endmodule
