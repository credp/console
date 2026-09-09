module fifo_formal(input logic clk);
 (* anyseq *)logic wvalid,rready;(* anyseq *)logic[7:0]wdata;
 logic reset=1,wready,rvalid,af,overflow,underflow;logic[7:0]rdata;logic[2:0]level;logic past_valid=0;
 logic[7:0]expected[0:3];logic[2:0]count;logic[1:0]wp,rp;
 sdram_bram_fifo #(.WIDTH(8),.DEPTH(4),.ALMOST_FULL_LEVEL(3))dut(.clk,.reset,.write_valid(wvalid),
  .write_ready(wready),.write_data(wdata),.read_valid(rvalid),.read_ready(rready),.read_data(rdata),
  .level,.almost_full(af),.overflow,.underflow);
 wire push=wvalid&&wready,pop=rvalid&&rready;
 always_ff@(posedge clk)begin
  past_valid<=1;reset<=0;if(!past_valid)assume(reset);
  if(reset)begin count<=0;wp<=0;rp<=0;end else begin
   assert(level==count);assert(level<=4);if(rvalid)assert(rdata==expected[rp]);
   if(push)begin expected[wp]<=wdata;wp<=wp+1'b1;end if(pop)rp<=rp+1'b1;
   case({push,pop})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:count<=count;endcase
  end
 end
endmodule
