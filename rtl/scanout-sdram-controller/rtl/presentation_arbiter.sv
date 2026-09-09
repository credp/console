module presentation_arbiter #(
 parameter integer FIFO_CAPACITY=2048,LOW_WATERMARK=512,HIGH_WATERMARK=1536
)(input logic clk,reset,replay_mode,input logic[11:0]video_fifo_level,input logic tail_flush,
 input logic refresh0_ready,refresh1_ready,
 input logic audio_read_ready,audio_write_ready,audio_read_urgent,audio_write_urgent,
 input logic video_ready,background_ready,background_enabled,input logic grant_accept,
 output logic video_urgent,grant_valid,output logic[2:0]grant_client);
 localparam[2:0] R0=0,R1=1,AR=2,AW=3,VIDEO=4,BG=5;
 logic audio_rr,mode_q;logic[2:0]candidate;logic candidate_valid;

 always_comb begin
  candidate_valid=1;candidate=R0;
  if(refresh0_ready)candidate=R0;
  else if(refresh1_ready)candidate=R1;
  else if(audio_read_urgent&&audio_read_ready&&audio_write_urgent&&audio_write_ready)candidate=audio_rr?AW:AR;
  else if(audio_read_urgent&&audio_read_ready)candidate=AR;
  else if(audio_write_urgent&&audio_write_ready)candidate=AW;
  else if(video_urgent&&video_ready)candidate=VIDEO;
  else if(audio_read_ready&&audio_write_ready)candidate=audio_rr?AW:AR;
  else if(audio_read_ready)candidate=AR;
  else if(audio_write_ready)candidate=AW;
  else if(background_enabled&&background_ready)candidate=BG;
  else if(video_ready)candidate=VIDEO;
  else candidate_valid=0;
 end

 always_ff@(posedge clk)begin
  if(reset)begin video_urgent<=0;mode_q<=replay_mode;audio_rr<=0;grant_valid<=0;grant_client<=0;end
  else begin
   mode_q<=replay_mode;
   if(replay_mode!=mode_q)video_urgent<=replay_mode?(video_fifo_level<=LOW_WATERMARK):(video_fifo_level>=HIGH_WATERMARK||tail_flush);
   else if(replay_mode)begin if(video_fifo_level<=LOW_WATERMARK)video_urgent<=1;else if(video_fifo_level>=HIGH_WATERMARK)video_urgent<=0;end
   else begin if(video_fifo_level>=HIGH_WATERMARK||tail_flush)video_urgent<=1;else if(video_fifo_level<=LOW_WATERMARK&&!tail_flush)video_urgent<=0;end
   if(!grant_valid||grant_accept)begin grant_valid<=candidate_valid;grant_client<=candidate;
    if(candidate_valid&&(candidate==AR||candidate==AW))audio_rr<=~audio_rr;
   end
  end
 end
 initial begin
  if(!(0<=LOW_WATERMARK&&LOW_WATERMARK<HIGH_WATERMARK&&HIGH_WATERMARK<=FIFO_CAPACITY))$error("illegal FIFO watermarks");
 end
endmodule
