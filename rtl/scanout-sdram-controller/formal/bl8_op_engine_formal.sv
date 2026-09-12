module bl8_op_engine_formal(input logic clk);
 logic reset=1;
 always_ff @(posedge clk)reset<=0;
 (* anyseq *) logic op_valid,op_write,write_valid,read_ready;
 (* anyseq *) logic [26:0]op_byte_address;
 (* anyseq *) logic [3:0]op_words;
 (* anyseq *) logic [15:0]write_data,sdram_dq_in;
 (* anyseq *) logic [1:0]write_byte_enable;
 sdram_bl8_op_engine #(.POWERUP_US(0)) dut(
  .clk,.reset,.op_valid,.op_write,.op_byte_address,.op_words,
  .write_valid,.write_data,.write_byte_enable,.read_ready,.sdram_dq_in);
endmodule
