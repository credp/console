module presentation_fifos (
    input logic clk, input logic reset,
    input logic vc_wvalid, output logic vc_wready, input logic [17:0] vc_wdata,
    output logic vc_rvalid, input logic vc_rready, output logic [17:0] vc_rdata,
    output logic [11:0] vc_level, output logic vc_overflow,
    input logic vr_wvalid, output logic vr_wready, input logic [15:0] vr_wdata,
    output logic vr_rvalid, input logic vr_rready, output logic [15:0] vr_rdata,
    output logic [11:0] vr_level, output logic vr_underflow,
    input logic ar_wvalid, output logic ar_wready, input logic [15:0] ar_wdata,
    output logic ar_rvalid, input logic ar_rready, output logic [15:0] ar_rdata,
    output logic [9:0] ar_level, output logic ar_underflow,
    input logic aw_wvalid, output logic aw_wready, input logic [17:0] aw_wdata,
    output logic aw_rvalid, input logic aw_rready, output logic [17:0] aw_rdata,
    output logic [8:0] aw_level, output logic aw_overflow
);
    logic unused0,unused1,unused2,unused3, af0,af1,af2,af3;
    // Capture/write staging includes the two DQM bits beside each word.
    sdram_bram_fifo #(.WIDTH(18),.DEPTH(2048),.ALMOST_FULL_LEVEL(1536)) vc (
      .clk,.reset,.write_valid(vc_wvalid),.write_ready(vc_wready),.write_data(vc_wdata),
      .read_valid(vc_rvalid),.read_ready(vc_rready),.read_data(vc_rdata),.level(vc_level),
      .almost_full(af0),.overflow(vc_overflow),.underflow(unused0));
    sdram_bram_fifo #(.WIDTH(16),.DEPTH(2048),.ALMOST_FULL_LEVEL(1536)) vr (
      .clk,.reset,.write_valid(vr_wvalid),.write_ready(vr_wready),.write_data(vr_wdata),
      .read_valid(vr_rvalid),.read_ready(vr_rready),.read_data(vr_rdata),.level(vr_level),
      .almost_full(af1),.overflow(unused1),.underflow(vr_underflow));
    sdram_bram_fifo #(.WIDTH(16),.DEPTH(512),.ALMOST_FULL_LEVEL(504)) ar (
      .clk,.reset,.write_valid(ar_wvalid),.write_ready(ar_wready),.write_data(ar_wdata),
      .read_valid(ar_rvalid),.read_ready(ar_rready),.read_data(ar_rdata),.level(ar_level),
      .almost_full(af2),.overflow(unused2),.underflow(ar_underflow));
    sdram_bram_fifo #(.WIDTH(18),.DEPTH(256),.ALMOST_FULL_LEVEL(248)) aw (
      .clk,.reset,.write_valid(aw_wvalid),.write_ready(aw_wready),.write_data(aw_wdata),
      .read_valid(aw_rvalid),.read_ready(aw_rready),.read_data(aw_rdata),.level(aw_level),
      .almost_full(af3),.overflow(aw_overflow),.underflow(unused3));
endmodule
