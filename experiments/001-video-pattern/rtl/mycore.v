
module mycore
(
	input         clk,
	input         reset,
	
	input         pal,
	input         scandouble,

	output reg    ce_pix,
	output        hvcnt_atzero,

	output reg    HBlank,
	output reg    HSync,
	output reg    VBlank,
	output reg    VSync,

	output  [7:0] video
);

reg   [9:0] hc = 0;
reg   [9:0] vc = 0;
reg   [9:0] vvc = 0;
reg  [63:0] rnd_reg;

wire  [5:0] rnd_c = {rnd_reg[0],rnd_reg[1],rnd_reg[2],rnd_reg[2],rnd_reg[2],rnd_reg[2]};
wire [63:0] rnd;

lfsr random(rnd);

// In case the H/V counters need to be cleared after a reset, feed a signal to release
// the reset at the right time.
assign hvcnt_atzero = ce_pix && !hc && !vc;

always @(posedge clk) begin
	// In normal mode advance one pixel every two clk cycles.
	// In scandouble mode advance one pixel every clk cycle.
	if(scandouble) ce_pix <= 1; 
		else ce_pix <= ~ce_pix;

	if(ce_pix) begin // THIS DOESN'T SEE THE INVERTED ce_pix
		if(hc == 637) begin // 0-637 is 638 pixels per line
			hc <= 0;
			if(vc >= (pal ? (scandouble ? 623 : 311) : (scandouble ? 523 : 261))) begin
				vc <= 0;
				vvc <= vvc + 9'd6;
			end else begin
				vc <= vc + 1'd1;
			end
		end else begin
			hc <= hc + 1'd1;
		end

		rnd_reg <= rnd;
	end

	if(reset) vvc <= 0;
end

// manage the frame timing signals
always @(posedge clk) begin
	if (hc == 529) HBlank <= 1; //assert HBlank at horizontal pixel count 529
		else if (hc == 0) HBlank <= 0; //otherwise, if we're at the start, clear it

	if (hc == 544) begin // start the pulse for HSync at horizontal pixel count 544
		HSync <= 1;

		// vsyncs - different for pal or ntsc or scan doubled
		if(pal) begin 
			if(vc == (scandouble ? 609 : 304)) VSync <= 1;
				else if (vc == (scandouble ? 617 : 308)) VSync <= 0;

			if(vc == (scandouble ? 601 : 300)) VBlank <= 1;
				else if (vc == 0) VBlank <= 0;
		end
		else begin
			if(vc == (scandouble ? 490 : 245)) VSync <= 1;
				else if (vc == (scandouble ? 496 : 248)) VSync <= 0;

			if(vc == (scandouble ? 480 : 240)) VBlank <= 1;
				else if (vc == 0) VBlank <= 0;
		end
	end
	
	if (hc == 590) HSync <= 0; // end the horizontal sync pulse at 590
end

reg [7:0] frame = 0;

always @(posedge clk) begin
	if(ce_pix && hc == 0 && vc == 0) // when we at the start of a frame, increment the frame counter
		frame <= frame + 1'd1;
end

wire [9:0] display_y = vc >> scandouble;

// 32x32-ish checkerboard, drifting horizontally over time.
wire checker = hc[5] ^ display_y[5] ^ frame[4];

// Add some fixed vertical bars so the picture is unmistakable.
wire bar_a = (hc >= 64  && hc < 96);
wire bar_b = (hc >= 160 && hc < 192);
wire bar_c = (hc >= 256 && hc < 288);

// this is the rule to get pixel colour
assign video =
	bar_a ? 8'hFF :
	bar_b ? 8'hA0 :
	bar_c ? 8'h50 :
	checker ? 8'hD0 : 8'h20;

endmodule
