module single_client_adapter_formal;
    logic clk;
    logic reset=1;
    (* anyseq *) logic req_valid,req_write,write_valid,read_ready,completion_ready;
    (* anyseq *) logic[26:0]req_byte_address;
    (* anyseq *) logic[7:0]req_words,req_tag;
    (* anyseq *) logic[15:0]write_data;
    (* anyseq *) logic[1:0]write_byte_enable;
    (* anyseq *) logic[127:0]response_data;
    logic req_ready,write_ready,read_valid,completion_valid,completion_error;
    logic[15:0]read_data;logic[7:0]completion_tag,completion_words;
    logic op_valid,op_ready,op_write,op_chip;logic[1:0]op_bank;logic[12:0]op_row;
    logic[9:0]op_column;logic[127:0]op_write_data,op_read_data;
    logic[15:0]op_write_byte_enable;logic op_read_data_valid,op_completion_valid,op_completion_ready;
    logic downstream_busy,downstream_write;
    logic[2:0]response_timer;
    logic[127:0]response_data_q;
    logic client_active,expected_write;
    logic[7:0]expected_tag,expected_words;

    sdram_single_client_adapter #(.LEN_WIDTH(8),.MAX_REQUEST_WORDS(16)) dut(.*);

    assign op_ready=!downstream_busy;
    assign op_read_data=response_data_q;
    assign op_read_data_valid=downstream_busy&&!downstream_write&&response_timer==0;
    assign op_completion_valid=downstream_busy&&response_timer==0;

    // A bounded atomic-operation peer whose response remains stable until the
    // adapter consumes it.
    always_ff @(posedge clk) begin
      reset<=0;
      if(reset)begin
        downstream_busy<=0;downstream_write<=0;response_timer<=0;response_data_q<=0;
        client_active<=0;expected_write<=0;expected_tag<=0;expected_words<=0;
      end
      else begin
        if(op_valid&&op_ready)begin
          downstream_busy<=1;downstream_write<=op_write;response_timer<=2;
          response_data_q<=response_data;
        end else if(downstream_busy&&response_timer!=0)
          response_timer<=response_timer-1'b1;
        else if(op_completion_valid&&op_completion_ready)
          downstream_busy<=0;

        if(req_valid&&req_ready)begin
          client_active<=1;expected_write<=req_write;expected_tag<=req_tag;expected_words<=req_words;
        end
        if(completion_valid&&completion_ready)client_active<=0;

        if(req_valid)begin assume(req_words<=16);assume(req_words!=0);assume(!req_byte_address[0]);end
        if(read_valid)begin assert(client_active);assert(!expected_write);end
        if(completion_valid)begin
          assert(client_active);assert(!req_ready);assert(completion_tag==expected_tag);
          assert(!completion_error);assert(completion_words==expected_words);
        end
        cover(completion_valid&&!completion_error&&completion_tag==expected_tag);
        cover(read_valid&&read_ready);
      end
    end
endmodule
