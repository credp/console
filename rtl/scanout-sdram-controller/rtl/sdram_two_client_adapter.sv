module sdram_two_client_adapter #(
    parameter integer LEN_WIDTH = 16,
    parameter integer TAG_WIDTH = 8,
    parameter integer MAX_REQUEST_WORDS = 256,
    parameter integer MAPPING = 5
) (
    input logic clk,input logic reset,
    input logic c0_req_valid,output logic c0_req_ready,input logic c0_req_write,
    input logic[26:0]c0_req_byte_address,input logic[LEN_WIDTH-1:0]c0_req_words,
    input logic[TAG_WIDTH-1:0]c0_req_tag,
    input logic c0_write_valid,output logic c0_write_ready,input logic[15:0]c0_write_data,
    input logic[1:0]c0_write_byte_enable,output logic c0_read_valid,input logic c0_read_ready,
    output logic[15:0]c0_read_data,output logic c0_completion_valid,input logic c0_completion_ready,
    output logic[TAG_WIDTH-1:0]c0_completion_tag,
    output logic[LEN_WIDTH-1:0]c0_completion_words,output logic c0_completion_error,

    input logic c1_req_valid,output logic c1_req_ready,input logic c1_req_write,
    input logic[26:0]c1_req_byte_address,input logic[LEN_WIDTH-1:0]c1_req_words,
    input logic[TAG_WIDTH-1:0]c1_req_tag,
    input logic c1_write_valid,output logic c1_write_ready,input logic[15:0]c1_write_data,
    input logic[1:0]c1_write_byte_enable,output logic c1_read_valid,input logic c1_read_ready,
    output logic[15:0]c1_read_data,output logic c1_completion_valid,input logic c1_completion_ready,
    output logic[TAG_WIDTH-1:0]c1_completion_tag,
    output logic[LEN_WIDTH-1:0]c1_completion_words,output logic c1_completion_error,

    output logic op_valid,input logic op_ready,output logic op_write,output logic op_chip,
    output logic[1:0]op_bank,output logic[12:0]op_row,output logic[9:0]op_column,
    output logic[127:0]op_write_data,output logic[15:0]op_write_byte_enable,
    input logic[127:0]op_read_data,input logic op_read_data_valid,
    input logic op_completion_valid,output logic op_completion_ready,
    output logic op_client
);
    logic a0_op_valid,a0_op_ready,a0_op_write,a0_op_chip;
    logic[1:0]a0_op_bank;logic[12:0]a0_op_row;logic[9:0]a0_op_column;
    logic[127:0]a0_op_write_data;logic[15:0]a0_op_write_byte_enable;
    logic a0_op_completion_ready;
    logic a1_op_valid,a1_op_ready,a1_op_write,a1_op_chip;
    logic[1:0]a1_op_bank;logic[12:0]a1_op_row;logic[9:0]a1_op_column;
    logic[127:0]a1_op_write_data;logic[15:0]a1_op_write_byte_enable;
    logic a1_op_completion_ready;
    logic response0_pending,response1_pending;
    logic[127:0]response0_data,response1_data;
    logic round_robin,selected_client,response_owner,response_write;

    wire eligible0=a0_op_valid&&!response0_pending;
    wire eligible1=a1_op_valid&&!response1_pending;
    always_comb begin
        if(eligible0&&eligible1)selected_client=round_robin;
        else selected_client=eligible1;
        op_valid=eligible0||eligible1;
        op_write=selected_client?a1_op_write:a0_op_write;
        op_chip=selected_client?a1_op_chip:a0_op_chip;
        op_bank=selected_client?a1_op_bank:a0_op_bank;
        op_row=selected_client?a1_op_row:a0_op_row;
        op_column=selected_client?a1_op_column:a0_op_column;
        op_write_data=selected_client?a1_op_write_data:a0_op_write_data;
        op_write_byte_enable=selected_client?a1_op_write_byte_enable:a0_op_write_byte_enable;
        op_client=selected_client;
        a0_op_ready=op_ready&&op_valid&&!selected_client;
        a1_op_ready=op_ready&&op_valid&&selected_client;
    end

    // Runtime responses are accepted immediately into the selected client's
    // reserved slot. A stalled client therefore cannot stretch the physical
    // operation or prevent the other client from issuing its next operation.
    assign op_completion_ready=(response_write||op_read_data_valid)&&
                               (response_owner?!response1_pending:!response0_pending);
    always_ff@(posedge clk)begin
        if(reset)begin
            round_robin<=1'b0;response_owner<=1'b0;response_write<=1'b0;
            response0_pending<=1'b0;response1_pending<=1'b0;
            response0_data<='0;response1_data<='0;
        end else begin
            if(response0_pending&&a0_op_completion_ready)response0_pending<=1'b0;
            if(response1_pending&&a1_op_completion_ready)response1_pending<=1'b0;
            if(op_valid&&op_ready)begin
                response_owner<=selected_client;
                response_write<=op_write;
                round_robin<=~selected_client;
            end
            if(op_completion_valid&&op_completion_ready)begin
                if(response_owner)begin response1_pending<=1'b1;response1_data<=op_read_data;end
                else begin response0_pending<=1'b1;response0_data<=op_read_data;end
            end
        end
    end

    sdram_single_client_adapter #(.LEN_WIDTH(LEN_WIDTH),.TAG_WIDTH(TAG_WIDTH),
      .MAX_REQUEST_WORDS(MAX_REQUEST_WORDS),.MAPPING(MAPPING)) client0(
      .clk,.reset,.req_valid(c0_req_valid),.req_ready(c0_req_ready),.req_write(c0_req_write),
      .req_byte_address(c0_req_byte_address),.req_words(c0_req_words),.req_tag(c0_req_tag),
      .write_valid(c0_write_valid),.write_ready(c0_write_ready),.write_data(c0_write_data),
      .write_byte_enable(c0_write_byte_enable),.read_valid(c0_read_valid),.read_ready(c0_read_ready),
      .read_data(c0_read_data),.completion_valid(c0_completion_valid),
      .completion_ready(c0_completion_ready),.completion_tag(c0_completion_tag),
      .completion_words(c0_completion_words),.completion_error(c0_completion_error),
      .op_valid(a0_op_valid),.op_ready(a0_op_ready),.op_write(a0_op_write),.op_chip(a0_op_chip),
      .op_bank(a0_op_bank),.op_row(a0_op_row),.op_column(a0_op_column),
      .op_write_data(a0_op_write_data),.op_write_byte_enable(a0_op_write_byte_enable),
      .op_read_data(response0_data),.op_read_data_valid(response0_pending),
      .op_completion_valid(response0_pending),.op_completion_ready(a0_op_completion_ready));
    sdram_single_client_adapter #(.LEN_WIDTH(LEN_WIDTH),.TAG_WIDTH(TAG_WIDTH),
      .MAX_REQUEST_WORDS(MAX_REQUEST_WORDS),.MAPPING(MAPPING)) client1(
      .clk,.reset,.req_valid(c1_req_valid),.req_ready(c1_req_ready),.req_write(c1_req_write),
      .req_byte_address(c1_req_byte_address),.req_words(c1_req_words),.req_tag(c1_req_tag),
      .write_valid(c1_write_valid),.write_ready(c1_write_ready),.write_data(c1_write_data),
      .write_byte_enable(c1_write_byte_enable),.read_valid(c1_read_valid),.read_ready(c1_read_ready),
      .read_data(c1_read_data),.completion_valid(c1_completion_valid),
      .completion_ready(c1_completion_ready),.completion_tag(c1_completion_tag),
      .completion_words(c1_completion_words),.completion_error(c1_completion_error),
      .op_valid(a1_op_valid),.op_ready(a1_op_ready),.op_write(a1_op_write),.op_chip(a1_op_chip),
      .op_bank(a1_op_bank),.op_row(a1_op_row),.op_column(a1_op_column),
      .op_write_data(a1_op_write_data),.op_write_byte_enable(a1_op_write_byte_enable),
      .op_read_data(response1_data),.op_read_data_valid(response1_pending),
      .op_completion_valid(response1_pending),.op_completion_ready(a1_op_completion_ready));

`ifdef FORMAL
    always_ff@(posedge clk)if(!reset)begin
        assert(!(a0_op_ready&&a1_op_ready));
        if(response0_pending)assert(!a0_op_ready);
        if(response1_pending)assert(!a1_op_ready);
        if(op_valid&&op_ready&&eligible0&&eligible1)
            assert(selected_client==round_robin);
    end
`endif
endmodule
