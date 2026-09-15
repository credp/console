// One-shot physical SDRAM round-trip verification for experiment 009.
// Video is a constant status colour from the known-good 720p raster; no SDRAM
// data enters the video path, so scanout cannot disguise a read/write failure.
`timescale 1ns/1ps

module emu (
    `include "sys/emu_ports.vh"
);
    assign ADC_BUS = 'Z;
    assign USER_OUT = '1;
    assign {UART_RTS, UART_TXD, UART_DTR} = 0;
    assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
    assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;
    assign VGA_SL = 0;
    assign VGA_F1 = 0;
    assign VGA_SCALER = 0;
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

    `include "build_id.v"
    localparam CONF_STR = {
        "SDRAM write/read verify;;",
        "-;",
        "T[0],Reset;",
        "R[0],Reset and close OSD;",
        "v,0;",
        "V,v", `BUILD_DATE
    };

    wire clk_sys, clk_video, clk_sdram, clk_sdram_capture;
    wire [1:0] buttons;
    wire [127:0] status;
    wire sdram_pll_locked;

    hps_io #(.CONF_STR(CONF_STR)) hps_io (
        .clk_sys(clk_sys), .HPS_BUS(HPS_BUS), .EXT_BUS(), .gamma_bus(),
        .forced_scandoubler(), .buttons(buttons), .status(status),
        .status_menumask(), .ps2_key()
    );

    pll pll (
        .refclk(CLK_50M), .rst(1'b0), .outclk_0(clk_sys), .outclk_1(clk_video)
    );
    framebuffer_sdram_pll sdram_pll (
        .refclk(CLK_50M), .rst(1'b0), .outclk(clk_sdram),
        .capture_clk(clk_sdram_capture), .locked(sdram_pll_locked)
    );

    logic [20:0] startup_reset_counter = '0;
    always_ff @(posedge clk_sys) begin
        if (!(&startup_reset_counter))
            startup_reset_counter <= startup_reset_counter + 1'b1;
    end
    wire reset = RESET | status[0] | buttons[1] | !(&startup_reset_counter) | !sdram_pll_locked;

    wire sdram_init_done, sdram_error, write_completion, frame_write_complete;
    wire [10:0] producer_pixel_x;
    wire [9:0] producer_line_y;
    wire [7:0] producer_frame_index;
    wire producer_stalled_waiting_for_free_line, producer_stalled_waiting_for_writer;
    wire writer_busy, writer_error;
    wire [2:0] writer_error_reason;
    wire [12:0] producer_a;
    wire [1:0] producer_ba;
    wire producer_cke, producer_ncs, producer_nras, producer_ncas, producer_nwe;
    wire producer_dqml, producer_dqmh, producer_dq_oe;
    wire [15:0] producer_dq_out;

    framebuffer_producer_bl8_sdram_path #(
        .SDRAM_FREQ_HZ(142_857_000), .STOP_AFTER_ONE_FRAME(1), .USE_INTERNAL_PHY(0)
    ) producer (
        .machine_clk(clk_sys), .sdram_clk(clk_sdram), .reset,
        .sdram_init_done, .sdram_error, .write_completion, .frame_write_complete,
        .producer_pixel_x, .producer_line_y, .producer_frame_index,
        .producer_stalled_waiting_for_free_line, .producer_stalled_waiting_for_writer,
        .writer_busy, .writer_error, .writer_error_reason,
        .protocol_a(producer_a), .protocol_ba(producer_ba), .protocol_cke(producer_cke),
        .protocol_ncs(producer_ncs), .protocol_nras(producer_nras),
        .protocol_ncas(producer_ncas), .protocol_nwe(producer_nwe),
        .protocol_dqml(producer_dqml), .protocol_dqmh(producer_dqmh),
        .protocol_dq_out(producer_dq_out), .protocol_dq_oe(producer_dq_oe),
        .SDRAM_A(), .SDRAM_BA(), .SDRAM_CKE(), .SDRAM_nCS(), .SDRAM_nRAS(),
        .SDRAM_nCAS(), .SDRAM_nWE(), .SDRAM_DQML(), .SDRAM_DQMH(), .SDRAM_DQ(),
        .SDRAM_CLK(), .sdram_dq_out(), .sdram_dq_oe()
    );

    // Reset enters this clock domain through one explicit two-register path.
    // The ownership FSM and reader therefore leave reset on SDRAM clock edges.
    logic sdram_reset_meta = 1'b1;
    logic sdram_reset_sync = 1'b1;
    always_ff @(posedge clk_sdram) begin
        if (reset)
            sdram_reset_meta <= 1'b1;
        else
            sdram_reset_meta <= 1'b0;
        sdram_reset_sync <= sdram_reset_meta;
    end

    wire producer_owns_sdram, reader_reset, reader_owns_sdram;
    wire framebuffer_ready;
    wire reader_init_done;
    framebuffer_one_shot_handoff handoff (
        .clk(clk_sdram), .reset(sdram_reset_sync), .frame_write_complete,
        .reader_init_done, .producer_owns_sdram, .reader_reset,
        .reader_owns_sdram, .framebuffer_ready
    );

    wire reader_reset_sdram = sdram_reset_sync | reader_reset;
    wire [12:0] reader_a;
    wire [1:0] reader_ba;
    wire reader_cke, reader_ncs, reader_nras, reader_ncas, reader_nwe;
    wire reader_dqml, reader_dqmh, reader_dq_oe;
    wire [15:0] reader_dq_out, sdram_dq_capture;
    wire reader_req_valid, reader_req_ready, reader_req_write;
    wire [26:0] reader_req_byte_address;
    wire [15:0] reader_req_words;
    wire [7:0] reader_req_tag;
    wire reader_read_valid, reader_read_ready;
    wire [15:0] reader_read_data;
    wire reader_completion_valid, reader_completion_ready;
    wire [7:0] reader_completion_tag;
    wire [15:0] reader_completion_words;
    wire reader_completion_error;

    // The shared PHY adds one registered command-launch stage and one DQ input
    // capture stage. Tell the wrapper about both so data and valid remain paired.
    framebuffer_agg23_read_backend #(
        .SDRAM_FREQ_MHZ(143),
        .PHY_DQ_CAPTURE_STAGES(1),
        .PHY_COMMAND_LAUNCH_STAGES(1)
    ) reader (
        .clk(clk_sdram), .capture_clk(clk_sdram_capture),
        .reset(reader_reset_sdram),
        .req_valid(reader_req_valid), .req_ready(reader_req_ready),
        .req_write(reader_req_write), .req_byte_address(reader_req_byte_address),
        .req_words(reader_req_words), .req_tag(reader_req_tag),
        .read_valid(reader_read_valid), .read_ready(reader_read_ready),
        .read_data(reader_read_data), .completion_valid(reader_completion_valid),
        .completion_ready(reader_completion_ready),
        .completion_tag(reader_completion_tag),
        .completion_words(reader_completion_words),
        .completion_error(reader_completion_error), .init_done(reader_init_done),
        .SDRAM_A(reader_a), .SDRAM_BA(reader_ba), .SDRAM_CKE(reader_cke),
        .SDRAM_nCS(reader_ncs), .SDRAM_nRAS(reader_nras),
        .SDRAM_nCAS(reader_ncas), .SDRAM_nWE(reader_nwe),
        .SDRAM_DQML(reader_dqml), .SDRAM_DQMH(reader_dqmh),
        .sdram_dq_in(sdram_dq_capture), .sdram_dq_out(reader_dq_out),
        .sdram_dq_oe(reader_dq_oe), .SDRAM_CLK()
    );

    wire verify_done, verify_passed, verify_failed;
    wire [31:0] verify_mismatch_count;
    framebuffer_sdram_frame_verifier verifier (
        .clk(clk_sdram), .reset(reader_reset_sdram | !reader_init_done),
        .req_valid(reader_req_valid), .req_ready(reader_req_ready),
        .req_write(reader_req_write),
        .req_byte_address(reader_req_byte_address), .req_words(reader_req_words),
        .req_tag(reader_req_tag), .read_valid(reader_read_valid),
        .read_ready(reader_read_ready), .read_data(reader_read_data),
        .completion_valid(reader_completion_valid),
        .completion_ready(reader_completion_ready),
        .completion_tag(reader_completion_tag),
        .completion_words(reader_completion_words),
        .completion_error(reader_completion_error), .done(verify_done),
        .passed(verify_passed), .failed(verify_failed),
        .mismatch_count(verify_mismatch_count)
    );

    framebuffer_sdram_phy phy (
        .clk(clk_sdram), .capture_clk(clk_sdram_capture),
        .producer_owns(producer_owns_sdram), .reader_owns(reader_owns_sdram),
        .producer_a, .producer_ba, .producer_cke, .producer_ncs, .producer_nras,
        .producer_ncas, .producer_nwe, .producer_dqml, .producer_dqmh,
        .producer_dq_out, .producer_dq_oe,
        .reader_a, .reader_ba, .reader_cke, .reader_ncs, .reader_nras,
        .reader_ncas, .reader_nwe, .reader_dqml, .reader_dqmh,
        .reader_dq_out, .reader_dq_oe, .dq_capture(sdram_dq_capture),
        .SDRAM_A, .SDRAM_BA, .SDRAM_CKE, .SDRAM_nCS, .SDRAM_nRAS,
        .SDRAM_nCAS, .SDRAM_nWE, .SDRAM_DQML, .SDRAM_DQMH, .SDRAM_DQ, .SDRAM_CLK
    );

    wire [10:0] raster_x;
    wire [9:0] raster_y;
    wire raster_de, raster_hsync, raster_vsync;
    raster_720p raster (
        .clk(clk_video), .reset, .x(raster_x), .y(raster_y), .de(raster_de),
        .hsync(raster_hsync), .vsync(raster_vsync), .frame_start(),
        .de_raw(), .hsync_raw(), .vsync_raw()
    );

    // Cross only sticky phase/result bits into the video domain. SDRAM data and
    // counters do not feed this raster, which keeps the diagnostic unambiguous.
    logic [4:0] verify_state_meta, verify_state_sync;
    always_ff @(posedge clk_video) begin
        if (reset) begin
            verify_state_meta <= '0;
            verify_state_sync <= '0;
        end else begin
            verify_state_meta <= {writer_error, verify_failed, verify_passed,
                                  reader_init_done, frame_write_complete};
            verify_state_sync <= verify_state_meta;
        end
    end

    wire status_writer_failed = verify_state_sync[4];
    wire status_verify_failed = verify_state_sync[3];
    wire status_verify_passed = verify_state_sync[2];
    wire status_reader_ready = verify_state_sync[1];
    wire status_write_done = verify_state_sync[0];
    wire [15:0] video_pixel = (raster_y <= producer_line_y) ? 16'hffff :
                              (status_writer_failed || status_verify_failed) ? 16'hf800 :
                              status_verify_passed ? 16'h07e0 :
                              !status_write_done ? 16'h001f :
                              !status_reader_ready ? 16'h07ff : 16'hffe0;

    assign CLK_VIDEO = clk_video;
    assign CE_PIXEL = 1'b1;
    assign VGA_DE = raster_de;
    assign VGA_HS = raster_hsync;
    assign VGA_VS = raster_vsync;
    assign VGA_R = raster_de ? {video_pixel[15:11], video_pixel[15:13]} : '0;
    assign VGA_G = raster_de ? {video_pixel[10:5], video_pixel[10:9]} : '0;
    assign VGA_B = raster_de ? {video_pixel[4:0], video_pixel[4:2]} : '0;

    logic [26:0] led_counter;
    always_ff @(posedge clk_sys) led_counter <= led_counter + 1'b1;
    assign LED_USER = (status_writer_failed || status_verify_failed) ? led_counter[24] :
                      status_verify_passed ? 1'b1 : led_counter[25];
endmodule
