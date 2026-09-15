`timescale 1ns/1ps

// Temporary single physical SDRAM-pin owner. Client selection remains the
// one-shot policy for now, but no client is connected directly to board pins.
module framebuffer_sdram_phy (
    input logic clk, input logic capture_clk, input logic producer_owns, input logic reader_owns,
    input logic [12:0] producer_a, input logic [1:0] producer_ba,
    input logic producer_cke, producer_ncs, producer_nras, producer_ncas, producer_nwe,
    input logic producer_dqml, producer_dqmh, input logic [15:0] producer_dq_out, input logic producer_dq_oe,
    input logic [12:0] reader_a, input logic [1:0] reader_ba,
    input logic reader_cke, reader_ncs, reader_nras, reader_ncas, reader_nwe,
    input logic reader_dqml, reader_dqmh, input logic [15:0] reader_dq_out, input logic reader_dq_oe,
    (* useioff = 1 *) output logic [15:0] dq_capture,
    (* useioff = 1 *) output logic [12:0] SDRAM_A,
    (* useioff = 1 *) output logic [1:0] SDRAM_BA,
    (* useioff = 1 *) output logic SDRAM_CKE, SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE,
    (* useioff = 1 *) output logic SDRAM_DQML, SDRAM_DQMH, inout wire [15:0] SDRAM_DQ,
    output logic SDRAM_CLK
);
    logic [12:0] selected_a;
    logic [1:0] selected_ba;
    logic selected_cke, selected_ncs, selected_nras, selected_ncas, selected_nwe;
    logic selected_dqml, selected_dqmh, selected_dq_oe;
    logic [15:0] selected_dq_out;
    (* useioff = 1 *) logic [15:0] dq_out_q;
    (* useioff = 1 *) logic dq_oe_q;

    // Explicitly instantiate the Cyclone V input-DDIO primitive. Quartus 17
    // did not honour inferred I/O-register placement here; this primitive is
    // the unambiguous physical capture boundary for the reader data stream.
    // dataout_h is the rising-edge sample characterized in experiment 006.a.
    // dataout_l is the falling-edge sample: using it silently moves capture by
    // half a cycle and breaks both the proven phase point and beat alignment.
    altddio_in #(
        .intended_device_family("Cyclone V"),
        .invert_input_clocks("OFF"),
        .lpm_hint("UNUSED"),
        .lpm_type("altddio_in"),
        .power_up_high("OFF"),
        .width(16)
    ) dq_input_ddr (
        .datain(SDRAM_DQ), .inclock(capture_clk), .inclocken(1'b1),
        .aclr(1'b0), .aset(1'b0), .dataout_h(dq_capture), .dataout_l()
    );

    // Client arbitration ends here. Every board-facing output is captured by
    // the register bank below, after this mux, so no client owns a pin.
    always_comb begin
        selected_a='0; selected_ba='0; selected_cke=0; selected_ncs=1; selected_nras=1;
        selected_ncas=1; selected_nwe=1; selected_dqml=1; selected_dqmh=1;
        selected_dq_out='0; selected_dq_oe=0;
        if (producer_owns) begin
            selected_a=producer_a; selected_ba=producer_ba; selected_cke=producer_cke; selected_ncs=producer_ncs;
            selected_nras=producer_nras; selected_ncas=producer_ncas; selected_nwe=producer_nwe;
            selected_dqml=producer_dqml; selected_dqmh=producer_dqmh;
            selected_dq_out=producer_dq_out; selected_dq_oe=producer_dq_oe;
        end else if (reader_owns) begin
            selected_a=reader_a; selected_ba=reader_ba; selected_cke=reader_cke; selected_ncs=reader_ncs;
            selected_nras=reader_nras; selected_ncas=reader_ncas; selected_nwe=reader_nwe;
            selected_dqml=reader_dqml; selected_dqmh=reader_dqmh;
            selected_dq_out=reader_dq_out; selected_dq_oe=reader_dq_oe;
        end
    end
    always_ff @(posedge clk) begin
        SDRAM_A <= selected_a;
        SDRAM_BA <= selected_ba;
        SDRAM_CKE <= selected_cke;
        SDRAM_nCS <= selected_ncs;
        SDRAM_nRAS <= selected_nras;
        SDRAM_nCAS <= selected_ncas;
        SDRAM_nWE <= selected_nwe;
        SDRAM_DQML <= selected_dqml;
        SDRAM_DQMH <= selected_dqmh;
        dq_out_q <= selected_dq_out;
        dq_oe_q <= selected_dq_oe;
    end
    assign SDRAM_DQ = dq_oe_q ? dq_out_q : 16'hzzzz;
    framebuffer_sdram_clock_forward clock_forward (.clk, .SDRAM_CLK);
endmodule
