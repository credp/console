module frame_publish_formal(input logic clk);
 (* anyseq *)logic frame_start,capture_enable,commit,error,replay_start,drained;
 logic reset=1,cap,pub,pvalid,replay,replay_valid,active,pulse,capture_failed;logic[31:0]version,words,fails;logic past_valid=0;
 frame_publish dut(.clk,.reset,.frame_start,.capture_enable,.capture_word_commit(commit),.capture_error(error),.capture_drained(drained),
  .replay_frame_start(replay_start),.expected_words(32'd4),.capture_buffer(cap),.published_buffer(pub),
  .published_valid(pvalid),.replay_buffer(replay),.replay_valid,.publish_version(version),.publish_pulse(pulse),
  .capture_active(active),.capture_failed,.completed_words(words),.failed_capture_count(fails));
 always_ff@(posedge clk)begin
  past_valid<=1;reset<=0;if(!past_valid)assume(reset);
  if(!reset&&pvalid&&active)assert(cap!=pub);
  if(past_valid&&!reset&&$past(!reset)&&pub!=$past(pub))begin assert(pulse);assert(version==$past(version)+1);end
  if(past_valid&&!reset&&$past(!reset)&&$past(active)&&$past(frame_start)&&($past(error)||!$past(drained)||$past(words)+($past(commit)?1:0)!=4))assert(pub==$past(pub));
  if(past_valid&&!reset&&$past(!reset)&&!$past(replay_start))assert(replay==$past(replay));
  if(past_valid&&!reset&&$past(!reset)&&$past(replay_start)&&$past(active)&&$past(frame_start)&&
     !$past(capture_failed)&&!$past(error)&&$past(drained)&&$past(words)+($past(commit)?1:0)==4)begin
    assert(replay==$past(cap));assert(replay_valid);
  end
 end
endmodule
