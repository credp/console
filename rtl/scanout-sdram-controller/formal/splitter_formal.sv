module splitter_formal(input logic clk);
    (* anyseq *) logic req_valid, req_write, op_ready;
    (* anyseq *) logic [26:0] req_address;
    (* anyseq *) logic [15:0] req_words;
    logic reset = 1'b1, req_ready, op_valid, op_write, op_last;
    logic [26:0] op_address; logic [3:0] op_words;
    logic dc,dbs;logic[1:0]db;logic[12:0]dr;logic[9:0]dcol;logic[10:0]contiguous;
    logic past_valid = 1'b0;
    sdram_request_splitter dut(.clk,.reset,.req_valid,.req_ready,.req_write,
      .req_byte_address(req_address),.req_words,.op_valid,.op_ready,
      .op_write,.op_byte_address(op_address),.op_words,.op_last);
    sdram_addr_decode dec(.byte_address(op_address),.chip(dc),.bank(db),.row(dr),.column(dcol),
      .byte_select(dbs),.contiguous_words(contiguous));
    always_ff @(posedge clk) begin
        past_valid <= 1'b1; reset <= 1'b0;
        if (!past_valid) assume(reset);
        if (req_valid) assume(req_words > 0);
        if (!reset && req_valid && req_ready) begin
        end
        if (!reset && op_valid) begin
            assert(op_words >= 1 && op_words <= 8);
            assert(op_words <= contiguous);
            assert(op_words <= 8-dcol[2:0]);
        end
    end
endmodule
