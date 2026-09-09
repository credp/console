module sdram_request_splitter #(
    parameter integer LEN_WIDTH = 16,
    parameter integer BURST_WORDS = 8,
    parameter integer MAPPING = 5
) (
    input  logic                 clk,
    input  logic                 reset,
    input  logic                 req_valid,
    output logic                 req_ready,
    input  logic                 req_write,
    input  logic [26:0]          req_byte_address,
    input  logic [LEN_WIDTH-1:0] req_words,
    output logic                 op_valid,
    input  logic                 op_ready,
    output logic                 op_write,
    output logic [26:0]          op_byte_address,
    output logic [3:0]           op_words,
    output logic                 op_last
);
    logic busy;
    logic [26:0] address_q;
    logic [LEN_WIDTH-1:0] remaining_q;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [9:0] decoded_column;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [10:0] contiguous_words;
    logic [3:0] burst_words_left;
    logic [LEN_WIDTH-1:0] selected_words;
    localparam logic [LEN_WIDTH-1:0] BURST_WORDS_W = LEN_WIDTH'(BURST_WORDS);

    assign req_ready = !busy;
    assign op_valid = busy;
    assign op_write = req_write_q;
    assign op_byte_address = address_q;
    /* verilator lint_off PINCONNECTEMPTY */
    sdram_addr_decode #(.MAPPING(MAPPING)) decode(
      .byte_address(address_q),.chip(),.bank(),.row(),
      .column(decoded_column),.byte_select(),.contiguous_words(contiguous_words));
    /* verilator lint_on PINCONNECTEMPTY */
    generate
      if(BURST_WORDS==1)begin:gen_burst1 assign burst_words_left=4'd1;end
      else if(BURST_WORDS==2)begin:gen_burst2 assign burst_words_left=4'd2-{3'b000,decoded_column[0]};end
      else if(BURST_WORDS==4)begin:gen_burst4 assign burst_words_left=4'd4-{2'b00,decoded_column[1:0]};end
      else begin:gen_burst8 assign burst_words_left=4'd8-{1'b0,decoded_column[2:0]};end
    endgenerate
    always_comb begin
        selected_words = remaining_q;
        if (selected_words > BURST_WORDS_W) selected_words = BURST_WORDS_W;
        if (selected_words > {{(LEN_WIDTH-11){1'b0}},contiguous_words})
            selected_words = {{(LEN_WIDTH-11){1'b0}},contiguous_words};
        if (selected_words > {{(LEN_WIDTH-4){1'b0}},burst_words_left})
            selected_words = {{(LEN_WIDTH-4){1'b0}},burst_words_left};
        op_words = selected_words[3:0];
        op_last = (selected_words == remaining_q);
    end

    logic req_write_q;
    always_ff @(posedge clk) begin
        if (reset) begin
            busy <= 1'b0; address_q <= '0; remaining_q <= '0; req_write_q <= 1'b0;
        end else begin
            if (req_valid && req_ready) begin
                busy <= (req_words != 0);
                address_q <= req_byte_address;
                remaining_q <= req_words;
                req_write_q <= req_write;
            end else if (op_valid && op_ready) begin
                address_q <= address_q + {{(27-LEN_WIDTH-1){1'b0}},selected_words,1'b0};
                remaining_q <= remaining_q - selected_words;
                if (op_last) busy <= 1'b0;
            end
        end
    end

    initial begin
        if (!(BURST_WORDS == 1 || BURST_WORDS == 2 || BURST_WORDS == 4 || BURST_WORDS == 8))
            $error("BURST_WORDS must be 1, 2, 4, or 8");
    end
endmodule
