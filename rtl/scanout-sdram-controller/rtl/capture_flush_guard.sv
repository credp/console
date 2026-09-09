module capture_flush_guard #(
 parameter integer TAIL_FLUSH_GUARD_CYCLES=4096
)(input logic capture_active,input logic[31:0]cycles_to_frame_boundary,
 input logic[11:0]capture_fifo_level,input logic[15:0]outstanding_write_words,
 output logic tail_flush,output logic all_writes_committed);
 assign tail_flush=capture_active&&(cycles_to_frame_boundary<=TAIL_FLUSH_GUARD_CYCLES)&&
                   (capture_fifo_level!=0||outstanding_write_words!=0);
 assign all_writes_committed=(capture_fifo_level==0&&outstanding_write_words==0);
 initial if(TAIL_FLUSH_GUARD_CYCLES<1)$error("tail flush guard must be positive");
endmodule
