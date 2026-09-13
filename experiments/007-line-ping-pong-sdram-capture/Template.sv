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
/*
assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;
*/

`include "build_id.v" 
localparam CONF_STR = {
	"Template;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[2],TV Mode,NTSC,PAL;",
	"O[4:3],Noise,White,Red,Green,Blue;",
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
wire clk_capture;
wire pll_locked;
wire sdram_pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.locked(pll_locked)
);

sdram_pll sdram_pll_inst
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sdram),
	.outclk_1(clk_capture),
	.locked(sdram_pll_locked)
);

wire reset = RESET | status[0] | buttons[1] | ~pll_locked | ~sdram_pll_locked;

wire [1:0] col = status[4:3];

// Leave H/V sync always on. This stabilizes the video output while the core
// is in reset. 
wire reset_core = reset;

logic [10:0] x;
logic [9:0]  y;
logic        de;
logic        hsync;
logic        vsync;
logic        de_raw;
logic        hsync_raw;
logic        vsync_raw;
//logic        frame_start;

raster_720p raster
(
    .clk(clk_sys),
    .reset(reset_core),

    .x(x),
    .y(y),
    .de(de),
    .hsync(hsync),
    .vsync(vsync),
    .frame_start(),
    .de_raw(de_raw),
    .hsync_raw(hsync_raw),
    .vsync_raw(vsync_raw)
);


assign CLK_VIDEO = clk_sys;
assign CE_PIXEL = 1'b1;

wire [15:0] line_pixel;
wire line_video_buffer;
wire req_valid, req_ready, req_write;
wire [26:0] req_byte_address;
wire [15:0] req_words;
wire [7:0] req_tag;
wire write_valid, write_ready;
wire [15:0] write_data;
wire [1:0] write_byte_enable;
wire read_valid;
wire [15:0] read_data;
wire completion_valid, completion_ready;
wire [7:0] completion_tag;
wire [15:0] completion_words;
wire completion_error;
wire sdram_init_done;
wire [31:0] source_lines_generated;
wire [31:0] sdram_lines_submitted;
wire [31:0] sdram_lines_completed;
wire reuse_before_drain_error;
wire [15:0] worst_line_drain_cycles;
wire [15:0] current_line_drain_cycles;

line_ping_pong_capture line_source
(
	.clk_source(clk_sdram),
	.reset_source(reset | ~sdram_init_done),
	.clk_video(clk_sys),
	.reset_video(reset_core),
	.video_x(x),
	.video_y(y),
	.video_de(de_raw),
	.video_pixel(line_pixel),
	.video_buffer(line_video_buffer),
	.req_valid(req_valid),
	.req_ready(req_ready),
	.req_write(req_write),
	.req_byte_address(req_byte_address),
	.req_words(req_words),
	.req_tag(req_tag),
	.write_valid(write_valid),
	.write_ready(write_ready),
	.write_data(write_data),
	.write_byte_enable(write_byte_enable),
	.completion_valid(completion_valid),
	.completion_ready(completion_ready),
	.completion_tag(completion_tag),
	.completion_words(completion_words),
	.completion_error(completion_error),
	.source_lines_generated(source_lines_generated),
	.sdram_lines_submitted(sdram_lines_submitted),
	.sdram_lines_completed(sdram_lines_completed),
	.reuse_before_drain_error(reuse_before_drain_error),
	.worst_line_drain_cycles(worst_line_drain_cycles),
	.current_line_drain_cycles(current_line_drain_cycles)
);

wire sdram_backend_error;

line_capture_sdram_backend #(.SDRAM_FREQ_HZ(100_000_000), .SDRAM_FREQ_MHZ(100), .MAX_REQUEST_WORDS(1280)) sdram_capture
(
	.clk(clk_sdram), .clk_capture(clk_capture), .reset(reset),
	.req_valid(req_valid), .req_ready(req_ready), .req_write(req_write),
	.req_byte_address(req_byte_address), .req_words(req_words), .req_tag(req_tag),
	.write_valid(write_valid), .write_ready(write_ready), .write_data(write_data),
	.write_byte_enable(write_byte_enable),
	.read_valid(read_valid), .read_ready(1'b1), .read_data(read_data),
	.completion_valid(completion_valid), .completion_ready(completion_ready),
	.completion_tag(completion_tag), .completion_words(completion_words),
	.completion_error(completion_error), .init_done(sdram_init_done),
	.diagnostic_error(sdram_backend_error),
	.SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA), .SDRAM_CKE(SDRAM_CKE),
	.SDRAM_nCS(SDRAM_nCS), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_nWE(SDRAM_nWE), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_DQ(SDRAM_DQ), .SDRAM_CLK(SDRAM_CLK)
);

assign VGA_DE = de_raw;
assign VGA_HS = hsync_raw;
assign VGA_VS = vsync_raw;
assign VGA_R  = (col==0 || col == 1) ? {line_pixel[15:11], line_pixel[15:13]} : 8'd0;
assign VGA_G  = (col==0 || col == 2) ? {line_pixel[10:5],  line_pixel[10:9]} : 8'd0;
assign VGA_B  = (col==0 || col == 3) ? {line_pixel[4:0],   line_pixel[4:2]} : 8'd0;

assign VIDEO_ARX = 13'd16;
assign VIDEO_ARY = 13'd9;

reg  [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1; 
assign LED_USER = (reuse_before_drain_error || sdram_backend_error) ? act_cnt[22] : sdram_init_done;

endmodule
