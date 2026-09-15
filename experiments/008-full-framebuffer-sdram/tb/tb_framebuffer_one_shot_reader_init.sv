`timescale 1ns/1ps

// Quartus supplies this primitive in hardware. This behavioural form is
// enough for the command/output-stage ownership regression below.
module altddio_in #(
    parameter intended_device_family = "Cyclone V",
    parameter invert_input_clocks = "OFF",
    parameter lpm_hint = "UNUSED",
    parameter lpm_type = "altddio_in",
    parameter power_up_high = "OFF",
    parameter integer width = 1
) (
    input wire [width-1:0] datain,
    input wire inclock, inclocken, aclr, aset,
    output wire [width-1:0] dataout_h, dataout_l
);
    assign dataout_h = datain;
    assign dataout_l = datain;
endmodule

// Top-level ownership regression: run a real one-shot BL8 writer into the
// shared PHY and SDRAM pin model, transfer command-pin ownership, then require the agg23
// reader to leave its own initialization sequence. This is intentionally
// about reset/ownership, not read data timing.
module tb_framebuffer_one_shot_reader_init;
    logic clk = 0, machine_clk = 0, reset = 1;
    logic writer_init_done, writer_error, write_completion, frame_write_complete;
    logic [12:0] writer_a, reader_a, sdram_a;
    logic [1:0] writer_ba, reader_ba, sdram_ba;
    logic writer_cke, writer_ncs, writer_nras, writer_ncas, writer_nwe, writer_dqml, writer_dqmh;
    logic [12:0] writer_protocol_a;
    logic [1:0] writer_protocol_ba;
    logic writer_protocol_cke, writer_protocol_ncs, writer_protocol_nras, writer_protocol_ncas, writer_protocol_nwe;
    logic writer_protocol_dqml, writer_protocol_dqmh, writer_protocol_dq_oe;
    logic [15:0] writer_protocol_dq_out;
    logic reader_cke, reader_ncs, reader_nras, reader_ncas, reader_nwe, reader_dqml, reader_dqmh;
    logic sdram_cke, sdram_ncs, sdram_nras, sdram_ncas, sdram_nwe, sdram_dqml, sdram_dqmh;
    wire [15:0] sdram_dq;
    wire producer_owns_sdram, reader_reset, reader_owns_sdram, framebuffer_ready;
    wire reader_init_done;
    wire [15:0] sdram_dq_capture, reader_dq_out;
    wire reader_dq_oe;

    always #5 clk = ~clk;
    always #25 machine_clk = ~machine_clk;

    framebuffer_producer_bl8_sdram_path #(
        .FRAMEBUFFER_WIDTH(8), .FRAMEBUFFER_HEIGHT(4), .LINE_ADDR_WIDTH(3),
        .WRITE_CHUNK_WORDS(8), .SDRAM_FREQ_HZ(100_000_000), .SDRAM_POWERUP_US(1),
        .STOP_AFTER_ONE_FRAME(1), .USE_INTERNAL_PHY(0)
    ) producer (
        .machine_clk, .sdram_clk(clk), .reset, .sdram_init_done(writer_init_done),
        .sdram_error(), .write_completion, .frame_write_complete,
        .producer_pixel_x(), .producer_line_y(), .producer_frame_index(),
        .producer_stalled_waiting_for_free_line(), .producer_stalled_waiting_for_writer(),
        .writer_busy(), .writer_error, .SDRAM_A(writer_a), .SDRAM_BA(writer_ba),
        .protocol_a(writer_protocol_a), .protocol_ba(writer_protocol_ba),
        .protocol_cke(writer_protocol_cke), .protocol_ncs(writer_protocol_ncs),
        .protocol_nras(writer_protocol_nras), .protocol_ncas(writer_protocol_ncas),
        .protocol_nwe(writer_protocol_nwe), .protocol_dqml(writer_protocol_dqml),
        .protocol_dqmh(writer_protocol_dqmh), .protocol_dq_out(writer_protocol_dq_out),
        .protocol_dq_oe(writer_protocol_dq_oe),
        .SDRAM_CKE(writer_cke), .SDRAM_nCS(writer_ncs), .SDRAM_nRAS(writer_nras),
        .SDRAM_nCAS(writer_ncas), .SDRAM_nWE(writer_nwe), .SDRAM_DQML(writer_dqml),
        .SDRAM_DQMH(writer_dqmh), .SDRAM_DQ(sdram_dq), .SDRAM_CLK()
    );

    framebuffer_one_shot_handoff handoff (
        .clk, .reset, .frame_write_complete, .reader_init_done, .producer_owns_sdram,
        .reader_reset, .reader_owns_sdram, .framebuffer_ready
    );

    framebuffer_agg23_read_backend #(.SDRAM_FREQ_MHZ(100)) reader (
        .clk, .reset(reset | reader_reset), .req_valid(1'b0), .req_ready(), .req_write(1'b0),
        .req_byte_address('0), .req_words('0), .req_tag('0), .read_valid(), .read_ready(1'b0),
        .read_data(), .completion_valid(), .completion_ready(1'b0), .completion_tag(),
        .completion_words(), .completion_error(), .init_done(reader_init_done),
        .SDRAM_A(reader_a), .SDRAM_BA(reader_ba), .SDRAM_CKE(reader_cke),
        .SDRAM_nCS(reader_ncs), .SDRAM_nRAS(reader_nras), .SDRAM_nCAS(reader_ncas),
        .SDRAM_nWE(reader_nwe), .SDRAM_DQML(reader_dqml), .SDRAM_DQMH(reader_dqmh),
        .sdram_dq_in(sdram_dq_capture), .sdram_dq_out(reader_dq_out), .sdram_dq_oe(reader_dq_oe), .SDRAM_CLK()
    );

    framebuffer_sdram_phy phy (
        .clk, .capture_clk(clk), .producer_owns(producer_owns_sdram), .reader_owns(reader_owns_sdram),
        .producer_a(writer_protocol_a), .producer_ba(writer_protocol_ba), .producer_cke(writer_protocol_cke),
        .producer_ncs(writer_protocol_ncs), .producer_nras(writer_protocol_nras),
        .producer_ncas(writer_protocol_ncas), .producer_nwe(writer_protocol_nwe),
        .producer_dqml(writer_protocol_dqml), .producer_dqmh(writer_protocol_dqmh),
        .producer_dq_out(writer_protocol_dq_out), .producer_dq_oe(writer_protocol_dq_oe),
        .reader_a, .reader_ba, .reader_cke, .reader_ncs, .reader_nras, .reader_ncas, .reader_nwe,
        .reader_dqml, .reader_dqmh, .reader_dq_out, .reader_dq_oe,
        .dq_capture(sdram_dq_capture), .SDRAM_A(sdram_a), .SDRAM_BA(sdram_ba),
        .SDRAM_CKE(sdram_cke), .SDRAM_nCS(sdram_ncs), .SDRAM_nRAS(sdram_nras),
        .SDRAM_nCAS(sdram_ncas), .SDRAM_nWE(sdram_nwe), .SDRAM_DQML(sdram_dqml),
        .SDRAM_DQMH(sdram_dqmh), .SDRAM_DQ(sdram_dq), .SDRAM_CLK()
    );

    sdram_pair_model memory (
        .clk, .cke(sdram_cke), .ncs(sdram_ncs), .nras(sdram_nras), .ncas(sdram_ncas),
        .nwe(sdram_nwe), .a(sdram_a), .ba(sdram_ba), .dqml(sdram_dqml), .dqmh(sdram_dqmh), .dq(sdram_dq)
    );

    initial begin
        repeat (2) @(negedge clk);
        reset = 0;
        wait(frame_write_complete);
        @(posedge clk);
        #1;
        if (!reader_owns_sdram || reader_reset)
            $fatal(1, "reader did not receive ownership after final write");
        wait(reader_init_done);
        @(posedge clk);
        #1;
        if (!framebuffer_ready || writer_error)
            $fatal(1, "handoff did not finish ready=%b writer_error=%b", framebuffer_ready, writer_error);
        $display("PASS framebuffer_one_shot_reader_init: writer handoff and reader initialization");
        $finish;
    end

    initial begin
        repeat (100_000) @(posedge clk);
        $fatal(1, "one-shot reader-init watchdog");
    end
endmodule
