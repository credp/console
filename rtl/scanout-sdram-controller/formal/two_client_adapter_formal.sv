module two_client_adapter_formal;
 logic clk;logic reset=1;
 (* anyseq *)logic c0_req_valid,c0_req_write,c0_write_valid,c0_read_ready,c0_completion_ready;
 (* anyseq *)logic c1_req_valid,c1_req_write,c1_write_valid,c1_read_ready,c1_completion_ready;
 (* anyseq *)logic[26:0]c0_req_byte_address,c1_req_byte_address;
 (* anyseq *)logic[7:0]c0_req_words,c0_req_tag,c1_req_words,c1_req_tag;
 (* anyseq *)logic[15:0]c0_write_data,c1_write_data;
 (* anyseq *)logic[1:0]c0_write_byte_enable,c1_write_byte_enable;
 (* anyseq *)logic[127:0]arbitrary_response;
 logic c0_req_ready,c0_write_ready,c0_read_valid,c0_completion_valid,c0_completion_error;
 logic[15:0]c0_read_data;logic[7:0]c0_completion_tag,c0_completion_words;
 logic c1_req_ready,c1_write_ready,c1_read_valid,c1_completion_valid,c1_completion_error;
 logic[15:0]c1_read_data;logic[7:0]c1_completion_tag,c1_completion_words;
 logic op_valid,op_ready,op_write,op_chip,op_client;logic[1:0]op_bank;logic[12:0]op_row;
 logic[9:0]op_column;logic[127:0]op_write_data,op_read_data;
 logic[15:0]op_write_byte_enable;logic op_read_data_valid,op_completion_valid,op_completion_ready;
 logic busy,busy_write;logic[1:0]timer;logic[127:0]response_q;
 logic active0,active1;logic[7:0]tag0,tag1,words0,words1;logic seen0,seen1;
 sdram_two_client_adapter #(.LEN_WIDTH(8),.MAX_REQUEST_WORDS(8))dut(.*);
 assign op_ready=!busy;assign op_read_data=response_q;
 assign op_read_data_valid=busy&&!busy_write&&timer==0;
 assign op_completion_valid=busy&&timer==0;
 always_ff@(posedge clk)begin
  reset<=0;
  if(reset)begin busy<=0;busy_write<=0;timer<=0;response_q<=0;
   active0<=0;active1<=0;tag0<=0;tag1<=0;words0<=0;words1<=0;seen0<=0;seen1<=0;end
  else begin
   if(op_valid&&op_ready)begin busy<=1;busy_write<=op_write;timer<=2;response_q<=arbitrary_response;
    if(op_client)seen1<=1;else seen0<=1;end
   else if(busy&&timer!=0)timer<=timer-1'b1;
   else if(op_completion_valid&&op_completion_ready)busy<=0;
   if(c0_req_valid)begin assume(c0_req_words==8);assume(!c0_req_byte_address[0]);end
   if(c1_req_valid)begin assume(c1_req_words==8);assume(!c1_req_byte_address[0]);end
   if(c0_req_valid&&c0_req_ready)begin active0<=1;tag0<=c0_req_tag;words0<=c0_req_words;end
   if(c1_req_valid&&c1_req_ready)begin active1<=1;tag1<=c1_req_tag;words1<=c1_req_words;end
   if(c0_completion_valid)begin assert(active0);assert(c0_completion_tag==tag0);
    assert(c0_completion_words==words0);assert(!c0_completion_error);end
   if(c1_completion_valid)begin assert(active1);assert(c1_completion_tag==tag1);
    assert(c1_completion_words==words1);assert(!c1_completion_error);end
   if(c0_completion_valid&&c0_completion_ready)active0<=0;
   if(c1_completion_valid&&c1_completion_ready)active1<=0;
   cover(seen0&&seen1);cover(c0_completion_valid&&c1_completion_valid);
  end
 end
endmodule
