module sdram_splitter_bist(
 input logic clk,reset,
 output logic done,pass,
 output logic[7:0]checked_ops,
 output logic[3:0]first_fail_request,
 output logic[1:0]first_fail_op
);
 logic req_valid,req_ready,op_valid,op_ready,op_write,op_last;
 logic[26:0]req_byte_address,op_byte_address;
 logic[15:0]req_words;
 logic[3:0]op_words;
 logic[2:0]request_index;
 logic[1:0]operation_index;
 logic request_accepted;

 sdram_request_splitter #(.MAPPING(5),.BURST_WORDS(8)) splitter(
  .clk,.reset,.req_valid,.req_ready,.req_write(request_index[0]),
  .req_byte_address,.req_words,.op_valid,.op_ready,
  .op_write,.op_byte_address,.op_words,.op_last);

 function automatic[26:0]request_address(input[2:0]n);
  case(n)
   0:request_address=27'd14;     // BL8 wrap
   1:request_address=27'd1016;   // chip stripe
   2:request_address=27'd2040;   // bank stripe
   3:request_address=27'd8184;   // physical half-row
   default:request_address=27'd16376; // physical row
  endcase
 endfunction
 function automatic[15:0]request_length(input[2:0]n);
  request_length=(n==0)?16'd10:16'd12;
 endfunction
 function automatic[1:0]expected_count(input[2:0]n);
  expected_count=(n==0)?2'd3:2'd2;
 endfunction
 function automatic[26:0]expected_address(input[2:0]n,input[1:0]o);
  case(n)
   0:case(o) 0:expected_address=14;1:expected_address=16;default:expected_address=32;endcase
   1:expected_address=(o==0)?27'd1016:27'd1024;
   2:expected_address=(o==0)?27'd2040:27'd2048;
   3:expected_address=(o==0)?27'd8184:27'd8192;
   default:expected_address=(o==0)?27'd16376:27'd16384;
  endcase
 endfunction
 function automatic[3:0]expected_words(input[2:0]n,input[1:0]o);
  if(n==0)case(o)0:expected_words=1;1:expected_words=8;default:expected_words=1;endcase
  else expected_words=(o==0)?4:8;
 endfunction

 assign req_valid=!done&&!request_accepted;
 assign req_byte_address=request_address(request_index);
 assign req_words=request_length(request_index);
 assign op_ready=request_accepted;

 always_ff@(posedge clk)begin
  if(reset)begin
   done<=0;pass<=1;checked_ops<=0;request_index<=0;operation_index<=0;
   request_accepted<=0;first_fail_request<=0;first_fail_op<=0;
  end else begin
   if(req_valid&&req_ready)request_accepted<=1;
   if(op_valid&&op_ready)begin
    checked_ops<=checked_ops+1'b1;
    if(op_byte_address!=expected_address(request_index,operation_index)||
       op_words!=expected_words(request_index,operation_index)||
       op_write!=request_index[0]||
       op_last!=(operation_index+1'b1==expected_count(request_index)))begin
     if(pass)begin first_fail_request<=request_index;first_fail_op<=operation_index;end
     pass<=0;
    end
    if(op_last)begin
     request_accepted<=0;operation_index<=0;
     if(request_index==4)done<=1;
     else request_index<=request_index+1'b1;
    end else operation_index<=operation_index+1'b1;
   end
  end
 end
endmodule
