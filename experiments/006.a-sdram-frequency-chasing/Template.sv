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

`include "rtl/experiment_config.vh"
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
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_sdram),
	.outclk_2(clk_capture),
	.locked(pll_locked)
);

wire reset = RESET | status[0] | buttons[1] | ~pll_locked;

wire sdram_init_done;
(* keep *) wire [31:0] sdram_pass_count;
(* keep *) wire [31:0] sdram_error_count;
(* keep *) wire [15:0] sdram_first_fail_address;
(* keep *) wire [15:0] sdram_first_fail_expected;
(* keep *) wire [15:0] sdram_first_fail_observed;
(* keep *) wire [4:0] sdram_pattern_number;

wire [12:0] bist_sdram_a;
wire [1:0] bist_sdram_ba;
wire bist_sdram_cke, bist_sdram_ncs, bist_sdram_nras, bist_sdram_ncas, bist_sdram_nwe;
wire bist_sdram_dqml, bist_sdram_dqmh, bist_sdram_dq_oe;
wire [15:0] bist_sdram_dq_out;
reg [12:0] phy_sdram_a;
reg [1:0] phy_sdram_ba;
reg phy_sdram_cke, phy_sdram_ncs, phy_sdram_nras, phy_sdram_ncas, phy_sdram_nwe;
reg phy_sdram_dqml, phy_sdram_dqmh, phy_sdram_dq_oe;
reg [15:0] phy_sdram_dq_out;
reg [15:0] phy_sdram_dq_in;

// Match MiSTer MemTest: launch from packed I/O registers on the controller
// rising edge; its inverted forwarded SDRAM clock samples them half a cycle later.
always @(posedge clk_sdram) begin
	phy_sdram_a <= bist_sdram_a;
	phy_sdram_ba <= bist_sdram_ba;
	phy_sdram_cke <= bist_sdram_cke;
	phy_sdram_ncs <= bist_sdram_ncs;
	phy_sdram_nras <= bist_sdram_nras;
	phy_sdram_ncas <= bist_sdram_ncas;
	phy_sdram_nwe <= bist_sdram_nwe;
	phy_sdram_dqml <= bist_sdram_dqml;
	phy_sdram_dqmh <= bist_sdram_dqmh;
	phy_sdram_dq_oe <= bist_sdram_dq_oe;
	phy_sdram_dq_out <= bist_sdram_dq_out;
end

// This is intentionally adjacent to the top-level pin so FAST_INPUT_REGISTER
// can place the swept capture register in the I/O cell.
always @(posedge clk_capture) phy_sdram_dq_in <= SDRAM_DQ;

assign SDRAM_A=phy_sdram_a;
assign SDRAM_BA=phy_sdram_ba;
assign SDRAM_CKE=phy_sdram_cke;
assign SDRAM_nCS=phy_sdram_ncs;
assign SDRAM_nRAS=phy_sdram_nras;
assign SDRAM_nCAS=phy_sdram_ncas;
assign SDRAM_nWE=phy_sdram_nwe;
assign SDRAM_DQML=phy_sdram_dqml;
assign SDRAM_DQMH=phy_sdram_dqmh;
assign SDRAM_DQ=phy_sdram_dq_oe?phy_sdram_dq_out:16'hzzzz;

// Forward the memory clock through a dedicated DDR output cell.
altddio_out #(.extend_oe_disable("OFF"),.intended_device_family("Cyclone V"),
	.invert_output("OFF"),.lpm_hint("UNUSED"),.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),.power_up_high("OFF"),.width(1)) sdramclk_ddr
(
	.datain_h(1'b0),.datain_l(1'b1),.outclock(clk_sdram),.dataout(SDRAM_CLK),
	.aclr(1'b0),.aset(1'b0),.oe(1'b1),.outclocken(1'b1),.sclr(1'b0),.sset(1'b0)
);

sdram_frequency_bist #(.SDRAM_FREQ_HZ(`SDRAM_FREQ_HZ)) sdram_test
(
	.clk(clk_sdram), .reset(reset), .sdram_dq_in(phy_sdram_dq_in),
	.sdram_a(bist_sdram_a), .sdram_ba(bist_sdram_ba), .sdram_cke(bist_sdram_cke),
	.sdram_ncs(bist_sdram_ncs), .sdram_nras(bist_sdram_nras), .sdram_ncas(bist_sdram_ncas),
	.sdram_nwe(bist_sdram_nwe), .sdram_dqml(bist_sdram_dqml), .sdram_dqmh(bist_sdram_dqmh),
	.sdram_dq_out(bist_sdram_dq_out), .sdram_dq_oe(bist_sdram_dq_oe), .init_done(sdram_init_done),
	.pass_count(sdram_pass_count), .error_count(sdram_error_count),
	.first_fail_address(sdram_first_fail_address),
	.first_fail_expected(sdram_first_fail_expected),
	.first_fail_observed(sdram_first_fail_observed),
	.pattern_number(sdram_pattern_number)
);

wire [1:0] col = status[4:3];

wire HBlank;
wire HSync;
wire VBlank;
wire VSync;
wire ce_pix;
wire hvcnt_atzero;
wire [7:0] video;

// Leave H/V sync always on. This stabilizes the video output while the core
// is in reset. This example releases the reset when H/V counters are at zero.
reg reset_core = 1;
always @(posedge clk_sys) begin
	if(reset) reset_core <= 1;
	else if(hvcnt_atzero) reset_core <= 0;
end

mycore mycore
(
	.clk(clk_sys),
	.reset(reset_core),

	.pal(status[2]),
	.scandouble(forced_scandoubler),

	.ce_pix(ce_pix),
	.hvcnt_atzero(hvcnt_atzero),

	.HBlank(HBlank),
	.HSync(HSync),
	.VBlank(VBlank),
	.VSync(VSync),

	.video(video)
);

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL = ce_pix;

assign VGA_DE = ~(HBlank | VBlank);
assign VGA_HS = HSync;
assign VGA_VS = VSync;
assign VGA_G  = (!col || col == 2) ? video : 8'd0;
assign VGA_R  = (!col || col == 1) ? video : 8'd0;
assign VGA_B  = (!col || col == 3) ? video : 8'd0;

reg  [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1; 
// Match experiment 005's unambiguous convention: off until a complete sweep,
// solid on while clean, and flashing only after a compare error.
assign LED_USER = |sdram_error_count ? act_cnt[20] : |sdram_pass_count;

endmodule
