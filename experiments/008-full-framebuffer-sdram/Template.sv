//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 0;
assign AUDIO_L = 0;
assign AUDIO_R = 0;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v" 
localparam CONF_STR = {
	"Template;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[2],TV Mode,NTSC,PAL;",
	"O[3],Video source,Framebuffer,Raster test;",
	"-;",
	"P1,Test Page 1;",
	"P1-;",
	"P1-, -= Options in page 1 =-;",
	"P1-;",
	"P1O[5],Option 1-1,Off,On;",
	"d0P1F1,BIN;",
	"H0P1O[10],Option 1-2,Off,On;",
	"-;",
	"P2,Test Page 2;",
	"P2-;",
	"P2-, -= Options in page 2 =-;",
	"P2-;",
	"P2S0,DSK;",
	"P2O[7:6],Option 2,1,2,3,4;",
	"-;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"v,0;", // [optional] config version 0-99. 
	        // If CONF_STR options are changed in incompatible way, then change version number too,
			  // so all options will get default values on first start.
	"V,v",`BUILD_DATE 
};

wire forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({status[5]}),
	
	.ps2_key(ps2_key)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;
wire clk_sdram;
wire clk_sdram_capture;
wire clk_video;
wire sdram_pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys), .outclk_1(clk_video)
);

// Experiment 006.a characterized this command-clock point with an inverted
// forwarded SDRAM clock. Scanout uses the second output of the existing core
// PLL, leaving this PLL dedicated to SDRAM command and capture timing.
framebuffer_sdram_pll sdram_pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk(clk_sdram), .capture_clk(clk_sdram_capture),
	.locked(sdram_pll_locked)
);

wire reset = RESET | status[0] | buttons[1] | ~sdram_pll_locked;

wire sdram_init_done;
wire sdram_error;
wire write_completion;
wire [10:0] producer_pixel_x;
wire [9:0] producer_line_y;
wire [7:0] producer_frame_index;
wire producer_stalled_waiting_for_free_line;
wire producer_stalled_waiting_for_writer;
wire writer_busy;
wire writer_error;
wire frame_write_complete;
wire [12:0] producer_sdram_a;
wire [1:0] producer_sdram_ba;
wire producer_sdram_cke, producer_sdram_ncs, producer_sdram_nras, producer_sdram_ncas, producer_sdram_nwe;
wire producer_sdram_dqml, producer_sdram_dqmh, producer_sdram_clk, producer_sdram_dq_oe;
wire [15:0] producer_sdram_dq, producer_sdram_dq_out;

framebuffer_producer_bl8_sdram_path #(
	.SDRAM_FREQ_HZ(142_857_000),
	.STOP_AFTER_ONE_FRAME(1)
) framebuffer_producer (
	.machine_clk(clk_sys),
	.sdram_clk(clk_sdram),
	.reset(reset),
	.sdram_init_done(sdram_init_done),
	.sdram_error(sdram_error),
	.write_completion(write_completion),
	.frame_write_complete(frame_write_complete),
	.producer_pixel_x(producer_pixel_x),
	.producer_line_y(producer_line_y),
	.producer_frame_index(producer_frame_index),
	.producer_stalled_waiting_for_free_line(producer_stalled_waiting_for_free_line),
	.producer_stalled_waiting_for_writer(producer_stalled_waiting_for_writer),
	.writer_busy(writer_busy),
	.writer_error(writer_error),
	.SDRAM_A(producer_sdram_a), .SDRAM_BA(producer_sdram_ba),
	.SDRAM_CKE(producer_sdram_cke), .SDRAM_nCS(producer_sdram_ncs),
	.SDRAM_nRAS(producer_sdram_nras), .SDRAM_nCAS(producer_sdram_ncas),
	.SDRAM_nWE(producer_sdram_nwe), .SDRAM_DQML(producer_sdram_dqml),
	.SDRAM_DQMH(producer_sdram_dqmh), .SDRAM_DQ(producer_sdram_dq),
	.SDRAM_CLK(producer_sdram_clk), .sdram_dq_out(producer_sdram_dq_out),
	.sdram_dq_oe(producer_sdram_dq_oe)
);

// The temporary handoff controls the physical-pin mux, so it must run in the
// SDRAM clock domain with the producer completion and reader-init signals it
// observes. The final arbiter will replace this policy, but keeps this clock
// ownership rule.
reg sdram_reset_sync_meta, sdram_reset_sync;
always @(posedge clk_sdram) begin
	if (reset)
		sdram_reset_sync_meta <= 1'b1;
	else
		sdram_reset_sync_meta <= 1'b0;
	// Only the first stage observes the asynchronous framework reset. The
	// second stage must remain a normal, timed synchronizer register.
	sdram_reset_sync <= sdram_reset_sync_meta;
end

wire producer_owns_sdram, reader_reset, reader_owns_sdram, framebuffer_ready_sdram;
wire sdram_clk_mux_unused;
framebuffer_one_shot_handoff handoff (
	.clk(clk_sdram), .reset(sdram_reset_sync), .frame_write_complete,
	.reader_init_done, .producer_owns_sdram,
	.reader_reset, .reader_owns_sdram, .framebuffer_ready(framebuffer_ready_sdram)
);

wire reader_reset_sdram = sdram_reset_sync | reader_reset;

wire reader_init_done;
wire [12:0] reader_sdram_a;
wire [1:0] reader_sdram_ba;
wire reader_sdram_cke, reader_sdram_ncs, reader_sdram_nras, reader_sdram_ncas, reader_sdram_nwe;
wire reader_sdram_dqml, reader_sdram_dqmh, reader_sdram_clk, reader_sdram_dq_oe;
wire [15:0] reader_sdram_dq_out;
wire [15:0] sdram_dq_capture;
wire reader_req_valid, reader_req_ready, reader_req_write, reader_read_valid, reader_read_ready;
wire [26:0] reader_req_byte_address;
wire [15:0] reader_req_words, reader_read_data, reader_completion_words;
wire [7:0] reader_req_tag, reader_completion_tag;
wire reader_completion_valid, reader_completion_ready, reader_completion_error;
reg [15:0] debug_writer_count, debug_reader_count, debug_error_count;
always @(posedge clk_sdram) begin
	if (sdram_reset_sync) begin debug_writer_count<=0; debug_reader_count<=0; debug_error_count<=0; end
	else begin
		if (write_completion && &debug_writer_count==0) debug_writer_count <= debug_writer_count + 1'd1;
		if (reader_completion_valid && reader_completion_ready && &debug_reader_count==0) debug_reader_count <= debug_reader_count + 1'd1;
		if (reader_completion_valid && reader_completion_ready && reader_completion_error && &debug_error_count==0) debug_error_count <= debug_error_count + 1'd1;
	end
end

// Scanout and the user LED are the only consumers outside clk_sdram of the
// one-shot completion flag. Keep that crossing away from SDRAM pin control.
reg framebuffer_ready_sync_meta, framebuffer_ready;
always @(posedge clk_video) begin
	if (reset) begin
		framebuffer_ready_sync_meta <= 1'b0;
		framebuffer_ready <= 1'b0;
	end else begin
		framebuffer_ready_sync_meta <= framebuffer_ready_sdram;
		framebuffer_ready <= framebuffer_ready_sync_meta;
	end
end

framebuffer_agg23_read_backend #(.SDRAM_FREQ_MHZ(143), .PHY_DQ_CAPTURE_STAGES(1)) framebuffer_reader (
	.clk(clk_sdram), .reset(reader_reset_sdram),
	.req_valid(reader_req_valid), .req_ready(reader_req_ready), .req_write(reader_req_write),
	.req_byte_address(reader_req_byte_address), .req_words(reader_req_words), .req_tag(reader_req_tag),
	.read_valid(reader_read_valid), .read_ready(reader_read_ready), .read_data(reader_read_data),
	.completion_valid(reader_completion_valid), .completion_ready(reader_completion_ready),
	.completion_tag(reader_completion_tag), .completion_words(reader_completion_words),
	.completion_error(reader_completion_error), .init_done(reader_init_done),
	.SDRAM_A(reader_sdram_a), .SDRAM_BA(reader_sdram_ba), .SDRAM_CKE(reader_sdram_cke),
	.SDRAM_nCS(reader_sdram_ncs), .SDRAM_nRAS(reader_sdram_nras), .SDRAM_nCAS(reader_sdram_ncas),
	.SDRAM_nWE(reader_sdram_nwe), .SDRAM_DQML(reader_sdram_dqml), .SDRAM_DQMH(reader_sdram_dqmh),
	.sdram_dq_in(sdram_dq_capture), .sdram_dq_out(reader_sdram_dq_out), .sdram_dq_oe(reader_sdram_dq_oe),
	.SDRAM_CLK(reader_sdram_clk)
);

wire [10:0] raster_x;
wire [9:0] raster_y;
wire raster_de, raster_hsync, raster_vsync, raster_frame_start;
raster_720p raster (
	.clk(clk_video), .reset(reset), .x(raster_x), .y(raster_y), .de(raster_de),
	.hsync(raster_hsync), .vsync(raster_vsync), .frame_start(raster_frame_start),
	.de_raw(), .hsync_raw(), .vsync_raw()
);

wire [15:0] scanout_pixel;
wire scanout_pixel_valid, scanout_underflow, consumer_primed;
wire [9:0] scanout_line_y;
wire [15:0] scanout_skipped_lines;
reg [15:0] debug_underflow_count;
always @(posedge clk_video) begin
	if (reset)
		debug_underflow_count <= 0;
	else if (scanout_underflow && &debug_underflow_count == 0)
		debug_underflow_count <= debug_underflow_count + 1'd1;
end

// The overlay is sampled once per displayed frame. Synchronize the SDRAM
// counters first so the frame-boundary snapshot never reads another domain
// directly.
reg [15:0] debug_writer_meta, debug_writer_sample;
reg [15:0] debug_reader_meta, debug_reader_sample;
reg [15:0] debug_error_meta, debug_error_sample;
reg [15:0] debug_writer_sync, debug_reader_sync, debug_error_sync;
always @(posedge clk_video) begin
	if (reset) begin
		debug_writer_meta <= 0; debug_writer_sample <= 0;
		debug_reader_meta <= 0; debug_reader_sample <= 0;
		debug_error_meta <= 0; debug_error_sample <= 0;
		debug_writer_sync <= 0; debug_reader_sync <= 0; debug_error_sync <= 0;
	end else begin
		debug_writer_meta <= debug_writer_count;
		debug_writer_sample <= debug_writer_meta;
		debug_reader_meta <= debug_reader_count;
		debug_reader_sample <= debug_reader_meta;
		debug_error_meta <= debug_error_count;
		debug_error_sample <= debug_error_meta;
		if (raster_frame_start) begin
			debug_writer_sync <= debug_writer_sample;
			debug_reader_sync <= debug_reader_sample;
			debug_error_sync <= debug_error_sample;
		end
	end
end

wire debug_override; wire [15:0] debug_pixel;
framebuffer_debug_overlay debug_overlay(.x(raster_x),.y(raster_y),.active(raster_de),.writer_count(debug_writer_sync),.reader_count(debug_reader_sync),.error_count(debug_error_sync),.underflow_count(debug_underflow_count),.override(debug_override),.pixel(debug_pixel));
// This switch isolates the core-to-HDMI raster path from SDRAM. The direct
// source intentionally reuses the framebuffer's test pattern so a white edge
// and the drifting interior have the same expected appearance in both modes.
wire video_raster_test = status[3];
reg [7:0] raster_test_frame_index;
always @(posedge clk_video) begin
	if (reset)
		raster_test_frame_index <= '0;
	else if (raster_frame_start)
		raster_test_frame_index <= raster_test_frame_index + 1'b1;
end
wire [15:0] raster_test_pixel;
framebuffer_pattern_pixel raster_test_pattern (
	.x(raster_x), .y(raster_y), .frame_index(raster_test_frame_index),
	.pixel(raster_test_pixel)
);
wire reader_busy, reader_error, consumer_waiting_for_output_release, consumer_overwrite_error;
wire [9:0] next_framebuffer_line_y;
wire scheduler_waiting_for_scanout, scheduler_timing_error;
reg consumer_primed_sync_1, consumer_primed_sync_2, scanout_started;
always @(posedge clk_video) begin
	if (reset || !framebuffer_ready) begin
		consumer_primed_sync_1 <= 0; consumer_primed_sync_2 <= 0; scanout_started <= 0;
	end else begin
		consumer_primed_sync_1 <= consumer_primed;
		consumer_primed_sync_2 <= consumer_primed_sync_1;
		if (raster_frame_start && consumer_primed_sync_2) scanout_started <= 1;
	end
end
wire scanout_start = raster_frame_start && consumer_primed_sync_2 && !scanout_started;

framebuffer_consumer_read_path_dual_clock consumer (
	.fill_clk(clk_sdram), .fill_reset(reader_reset_sdram | !reader_init_done),
	.scanout_clk(clk_video), .scanout_reset(reset | !framebuffer_ready),
	.scanout_start, .scanout_line_advance(raster_de && raster_x == 0 && raster_y != 0 && scanout_started),
	.scanout_x(raster_x), .scanout_pixel, .scanout_pixel_valid, .scanout_line_y,
	.scanout_underflow, .scanout_skipped_lines, .consumer_primed,
	.req_valid(reader_req_valid), .req_ready(reader_req_ready), .req_write(reader_req_write),
	.req_byte_address(reader_req_byte_address), .req_words(reader_req_words), .req_tag(reader_req_tag),
	.read_valid(reader_read_valid), .read_ready(reader_read_ready), .read_data(reader_read_data),
	.completion_valid(reader_completion_valid), .completion_ready(reader_completion_ready),
	.completion_tag(reader_completion_tag), .completion_words(reader_completion_words),
	.completion_error(reader_completion_error), .reader_busy, .reader_error,
	.consumer_waiting_for_output_release, .consumer_overwrite_error,
	.next_framebuffer_line_y, .scheduler_waiting_for_scanout, .scheduler_timing_error
);

framebuffer_sdram_phy sdram_phy (
	.clk(clk_sdram), .capture_clk(clk_sdram_capture), .producer_owns(producer_owns_sdram), .reader_owns(reader_owns_sdram),
	.producer_a(producer_sdram_a), .producer_ba(producer_sdram_ba), .producer_cke(producer_sdram_cke),
	.producer_ncs(producer_sdram_ncs), .producer_nras(producer_sdram_nras), .producer_ncas(producer_sdram_ncas),
	.producer_nwe(producer_sdram_nwe), .producer_dqml(producer_sdram_dqml), .producer_dqmh(producer_sdram_dqmh),
	.producer_dq_out(producer_sdram_dq_out), .producer_dq_oe(producer_sdram_dq_oe),
	.reader_a(reader_sdram_a), .reader_ba(reader_sdram_ba), .reader_cke(reader_sdram_cke),
	.reader_ncs(reader_sdram_ncs), .reader_nras(reader_sdram_nras), .reader_ncas(reader_sdram_ncas),
	.reader_nwe(reader_sdram_nwe), .reader_dqml(reader_sdram_dqml), .reader_dqmh(reader_sdram_dqmh),
	.reader_dq_out(reader_sdram_dq_out), .reader_dq_oe(reader_sdram_dq_oe),
	.SDRAM_A, .SDRAM_BA, .SDRAM_CKE, .SDRAM_nCS, .SDRAM_nRAS, .SDRAM_nCAS, .SDRAM_nWE,
	.dq_capture(sdram_dq_capture), .SDRAM_DQML, .SDRAM_DQMH, .SDRAM_DQ, .SDRAM_CLK
);

assign CLK_VIDEO = clk_video;
assign CE_PIXEL = 1'b1;
assign VGA_DE = raster_de && (video_raster_test || debug_override ||
	(scanout_pixel_valid && (scanout_line_y == raster_y)));
assign VGA_HS = raster_hsync;
assign VGA_VS = raster_vsync;
wire [15:0] video_pixel = video_raster_test ? raster_test_pixel :
	debug_override ? debug_pixel : scanout_pixel;
assign VGA_R = VGA_DE ? {video_pixel[15:11],video_pixel[15:13]} : 0;
assign VGA_G = VGA_DE ? {video_pixel[10:5],video_pixel[10:9]} : 0;
assign VGA_B = VGA_DE ? {video_pixel[4:0],video_pixel[4:2]} : 0;

reg  [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1;
// Bring-up visibility: initialization is solid, framebuffer-ready is a slow
// blink, and an SDRAM/reader/line-ownership error flashes rapidly.
assign LED_USER = (sdram_error || writer_error || reader_error || consumer_overwrite_error) ? act_cnt[24] :
                  framebuffer_ready ? act_cnt[26] : sdram_init_done;

endmodule
