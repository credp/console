module arbiter_formal(input logic clk);
 (* anyseq *)logic replay_mode,tail_flush,r0,r1,ar,aw,aru,awu,vr,br,ben,accept;
 (* anyseq *)logic[11:0]level;logic reset=1,urgent,valid;logic[2:0]client;logic past_valid=0,past_valid2=0;
 presentation_arbiter dut(.clk,.reset,.replay_mode,.video_fifo_level(level),.tail_flush,
  .refresh0_ready(r0),.refresh1_ready(r1),.audio_read_ready(ar),.audio_write_ready(aw),
  .audio_read_urgent(aru),.audio_write_urgent(awu),.video_ready(vr),.background_ready(br),
  .background_enabled(ben),.grant_accept(accept),.video_urgent(urgent),.grant_valid(valid),.grant_client(client));
 always_ff@(posedge clk)begin
  past_valid<=1;past_valid2<=past_valid;reset<=0;if(!past_valid)assume(reset);assume(level<=2048);
  if(past_valid&&!reset&&$past(!reset)&&$past(valid)&&!$past(accept))begin assert(valid);assert(client==$past(client));end
  if(past_valid&&!reset&&$past(!reset)&&$past(!valid||accept)&&!$past(r0||r1)&&
     ($past(aru&&ar)||$past(awu&&aw)))assert(valid&&(client==2||client==3));
  if(past_valid2&&$past(!reset)&&$past(replay_mode,2)==$past(replay_mode)&&$past(replay_mode)==replay_mode&&replay_mode&&$past(level)<=512)assert(urgent);
  if(past_valid2&&$past(!reset)&&$past(replay_mode,2)==$past(replay_mode)&&$past(replay_mode)==replay_mode&&!replay_mode&&($past(level)>=1536||$past(tail_flush)))assert(urgent);
 end
endmodule
