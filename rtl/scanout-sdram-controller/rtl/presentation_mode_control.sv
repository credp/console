module presentation_mode_control(
 input logic clk,reset,frame_start,new_frame_ready,
 output logic capture_mode,replay_mode);
 always_ff@(posedge clk)begin
  if(reset)begin capture_mode<=0;replay_mode<=0;end
  else if(frame_start)begin capture_mode<=new_frame_ready;replay_mode<=!new_frame_ready;end
 end
endmodule
