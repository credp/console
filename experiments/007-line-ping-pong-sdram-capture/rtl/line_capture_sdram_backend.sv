`ifdef SDRAM_BACKEND_AGG23_WORD
`include "../../third_party/agg23-sdram-controller/sdram.sv"
`elsif SDRAM_BACKEND_AGG23_BURST
`include "../../third_party/agg23-sdram-controller/sdram_burst.sv"
`endif

module line_capture_sdram_backend #(
    parameter longint unsigned SDRAM_FREQ_HZ = 100_000_000,
    parameter integer SDRAM_FREQ_MHZ = 100,
    parameter integer MAX_REQUEST_WORDS = 1280,
    parameter integer POWERUP_US = 200,
    parameter integer INIT_REFRESH_COUNT = 8,
    parameter integer READ_CAPTURE_CYCLES = 4,
    parameter integer MAX_REFRESH_SERVICE_CYCLES = 64
) (
    input  logic        clk,
    input  logic        clk_capture,
    input  logic        reset,

    input  logic        req_valid,
    output logic        req_ready,
    input  logic        req_write,
    input  logic [26:0] req_byte_address,
    input  logic [15:0] req_words,
    input  logic [7:0]  req_tag,

    input  logic        write_valid,
    output logic        write_ready,
    input  logic [15:0] write_data,
    input  logic [1:0]  write_byte_enable,

    output logic        read_valid,
    input  logic        read_ready,
    output logic [15:0] read_data,

    output logic        completion_valid,
    input  logic        completion_ready,
    output logic [7:0]  completion_tag,
    output logic [15:0] completion_words,
    output logic        completion_error,
    output logic        init_done,

    output logic        diagnostic_error,

    output logic [12:0] SDRAM_A,
    output logic [1:0]  SDRAM_BA,
    output logic        SDRAM_CKE,
    output logic        SDRAM_nCS,
    output logic        SDRAM_nRAS,
    output logic        SDRAM_nCAS,
    output logic        SDRAM_nWE,
    output logic        SDRAM_DQML,
    output logic        SDRAM_DQMH,
    inout  wire  [15:0] SDRAM_DQ,
    output logic        SDRAM_CLK
);
`ifdef SDRAM_BACKEND_AGG23_WORD
    line_capture_agg23_word_backend #(.SDRAM_FREQ_MHZ(SDRAM_FREQ_MHZ)) backend (
        .clk, .reset,
        .req_valid, .req_ready, .req_write, .req_byte_address, .req_words, .req_tag,
        .write_valid, .write_ready, .write_data, .write_byte_enable,
        .read_valid, .read_ready, .read_data,
        .completion_valid, .completion_ready, .completion_tag, .completion_words,
        .completion_error, .init_done, .diagnostic_error,
        .SDRAM_A, .SDRAM_BA, .SDRAM_CKE, .SDRAM_nCS, .SDRAM_nRAS, .SDRAM_nCAS,
        .SDRAM_nWE, .SDRAM_DQML, .SDRAM_DQMH, .SDRAM_DQ, .SDRAM_CLK
    );
`elsif SDRAM_BACKEND_AGG23_BURST
    line_capture_agg23_burst_backend #(.SDRAM_FREQ_MHZ(SDRAM_FREQ_MHZ)) backend (
        .clk, .reset,
        .req_valid, .req_ready, .req_write, .req_byte_address, .req_words, .req_tag,
        .write_valid, .write_ready, .write_data, .write_byte_enable,
        .read_valid, .read_ready, .read_data,
        .completion_valid, .completion_ready, .completion_tag, .completion_words,
        .completion_error, .init_done, .diagnostic_error,
        .SDRAM_A, .SDRAM_BA, .SDRAM_CKE, .SDRAM_nCS, .SDRAM_nRAS, .SDRAM_nCAS,
        .SDRAM_nWE, .SDRAM_DQML, .SDRAM_DQMH, .SDRAM_DQ, .SDRAM_CLK
    );
`else
    line_capture_custom_backend #(
        .SDRAM_FREQ_HZ(SDRAM_FREQ_HZ),
        .MAX_REQUEST_WORDS(MAX_REQUEST_WORDS),
        .POWERUP_US(POWERUP_US),
        .INIT_REFRESH_COUNT(INIT_REFRESH_COUNT),
        .READ_CAPTURE_CYCLES(READ_CAPTURE_CYCLES),
        .MAX_REFRESH_SERVICE_CYCLES(MAX_REFRESH_SERVICE_CYCLES)
    ) backend (
        .clk, .clk_capture, .reset,
        .req_valid, .req_ready, .req_write, .req_byte_address, .req_words, .req_tag,
        .write_valid, .write_ready, .write_data, .write_byte_enable,
        .read_valid, .read_ready, .read_data,
        .completion_valid, .completion_ready, .completion_tag, .completion_words,
        .completion_error, .init_done, .diagnostic_error,
        .SDRAM_A, .SDRAM_BA, .SDRAM_CKE, .SDRAM_nCS, .SDRAM_nRAS, .SDRAM_nCAS,
        .SDRAM_nWE, .SDRAM_DQML, .SDRAM_DQMH, .SDRAM_DQ, .SDRAM_CLK
    );
`endif
endmodule

module line_capture_custom_backend #(
    parameter longint unsigned SDRAM_FREQ_HZ = 100_000_000,
    parameter integer MAX_REQUEST_WORDS = 1280,
    parameter integer POWERUP_US = 200,
    parameter integer INIT_REFRESH_COUNT = 8,
    parameter integer READ_CAPTURE_CYCLES = 4,
    parameter integer MAX_REFRESH_SERVICE_CYCLES = 64
) (
    input  logic        clk,
    input  logic        clk_capture,
    input  logic        reset,

    input  logic        req_valid,
    output logic        req_ready,
    input  logic        req_write,
    input  logic [26:0] req_byte_address,
    input  logic [15:0] req_words,
    input  logic [7:0]  req_tag,

    input  logic        write_valid,
    output logic        write_ready,
    input  logic [15:0] write_data,
    input  logic [1:0]  write_byte_enable,

    output logic        read_valid,
    input  logic        read_ready,
    output logic [15:0] read_data,

    output logic        completion_valid,
    input  logic        completion_ready,
    output logic [7:0]  completion_tag,
    output logic [15:0] completion_words,
    output logic        completion_error,
    output logic        init_done,
    output logic        diagnostic_error,

    output logic [12:0] SDRAM_A,
    output logic [1:0]  SDRAM_BA,
    output logic        SDRAM_CKE,
    output logic        SDRAM_nCS,
    output logic        SDRAM_nRAS,
    output logic        SDRAM_nCAS,
    output logic        SDRAM_nWE,
    output logic        SDRAM_DQML,
    output logic        SDRAM_DQMH,
    inout  wire  [15:0] SDRAM_DQ,
    output logic        SDRAM_CLK
);
    wire [12:0] core_sdram_a;
    wire [1:0] core_sdram_ba;
    wire core_sdram_cke, core_sdram_ncs, core_sdram_nras, core_sdram_ncas, core_sdram_nwe;
    wire core_sdram_dqml, core_sdram_dqmh, core_sdram_dq_oe;
    wire [15:0] core_sdram_dq_out;
    logic [12:0] phy_sdram_a;
    logic [1:0] phy_sdram_ba;
    logic phy_sdram_cke, phy_sdram_ncs, phy_sdram_nras, phy_sdram_ncas, phy_sdram_nwe;
    logic phy_sdram_dqml, phy_sdram_dqmh, phy_sdram_dq_oe;
    logic [15:0] phy_sdram_dq_out;
    logic [15:0] phy_sdram_dq_in;
    logic late_refresh0, late_refresh1, timing_violation;
    logic refresh_pending, turnaround_blocked, row_hit, phy_busy;

    always_ff @(posedge clk) begin
        phy_sdram_a <= core_sdram_a;
        phy_sdram_ba <= core_sdram_ba;
        phy_sdram_cke <= core_sdram_cke;
        phy_sdram_ncs <= core_sdram_ncs;
        phy_sdram_nras <= core_sdram_nras;
        phy_sdram_ncas <= core_sdram_ncas;
        phy_sdram_nwe <= core_sdram_nwe;
        phy_sdram_dqml <= core_sdram_dqml;
        phy_sdram_dqmh <= core_sdram_dqmh;
        phy_sdram_dq_oe <= core_sdram_dq_oe;
        phy_sdram_dq_out <= core_sdram_dq_out;
    end

    always_ff @(posedge clk_capture) phy_sdram_dq_in <= SDRAM_DQ;

    assign SDRAM_A = phy_sdram_a;
    assign SDRAM_BA = phy_sdram_ba;
    assign SDRAM_CKE = phy_sdram_cke;
    assign SDRAM_nCS = phy_sdram_ncs;
    assign SDRAM_nRAS = phy_sdram_nras;
    assign SDRAM_nCAS = phy_sdram_ncas;
    assign SDRAM_nWE = phy_sdram_nwe;
    assign SDRAM_DQML = phy_sdram_dqml;
    assign SDRAM_DQMH = phy_sdram_dqmh;
    assign SDRAM_DQ = phy_sdram_dq_oe ? phy_sdram_dq_out : 16'hzzzz;
    assign diagnostic_error = late_refresh0 || late_refresh1 || timing_violation;

    altddio_out #(.extend_oe_disable("OFF"),.intended_device_family("Cyclone V"),
        .invert_output("OFF"),.lpm_hint("UNUSED"),.lpm_type("altddio_out"),
        .oe_reg("UNREGISTERED"),.power_up_high("OFF"),.width(1)) sdramclk_ddr
    (
        .datain_h(1'b0),.datain_l(1'b1),.outclock(clk),.dataout(SDRAM_CLK),
        .oe(1'b1),.outclocken(1'b1)
    );

    sdram_single_client_controller #(
        .SDRAM_FREQ_HZ(SDRAM_FREQ_HZ),
        .POWERUP_US(POWERUP_US),
        .INIT_REFRESH_COUNT(INIT_REFRESH_COUNT),
        .READ_CAPTURE_CYCLES(READ_CAPTURE_CYCLES),
        .MAX_REFRESH_SERVICE_CYCLES(MAX_REFRESH_SERVICE_CYCLES),
        .MAX_REQUEST_WORDS(MAX_REQUEST_WORDS)
    ) controller (
        .clk, .reset,
        .req_valid, .req_ready, .req_write, .req_byte_address, .req_words, .req_tag,
        .write_valid, .write_ready, .write_data, .write_byte_enable,
        .read_valid, .read_ready, .read_data,
        .completion_valid, .completion_ready, .completion_tag, .completion_words,
        .completion_error, .init_done,
        .sdram_a(core_sdram_a), .sdram_ba(core_sdram_ba), .sdram_cke(core_sdram_cke),
        .sdram_ncs(core_sdram_ncs), .sdram_nras(core_sdram_nras),
        .sdram_ncas(core_sdram_ncas), .sdram_nwe(core_sdram_nwe),
        .sdram_dqml(core_sdram_dqml), .sdram_dqmh(core_sdram_dqmh),
        .sdram_dq_in(phy_sdram_dq_in), .sdram_dq_out(core_sdram_dq_out),
        .sdram_dq_oe(core_sdram_dq_oe),
        .late_refresh0, .late_refresh1, .refresh_pending,
        .timing_violation, .turnaround_blocked, .row_hit, .phy_busy
    );
endmodule

module line_capture_agg23_adapter #(
    parameter integer BURST_BACKEND = 0
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        init_done,

    input  logic        req_valid,
    output logic        req_ready,
    input  logic        req_write,
    input  logic [26:0] req_byte_address,
    input  logic [15:0] req_words,
    input  logic [7:0]  req_tag,

    input  logic        write_valid,
    output logic        write_ready,
    input  logic [15:0] write_data,
    input  logic [1:0]  write_byte_enable,

    output logic        read_valid,
    input  logic        read_ready,
    output logic [15:0] read_data,

    output logic        completion_valid,
    input  logic        completion_ready,
    output logic [7:0]  completion_tag,
    output logic [15:0] completion_words,
    output logic        completion_error,

    output logic [24:0] p0_addr,
    output logic [15:0] p0_data,
    output logic [1:0]  p0_byte_en,
    input  logic [15:0] p0_q,
    output logic        p0_wr_req,
    output logic        p0_rd_req,
    output logic        p0_end_burst_req,
    input  logic        p0_available,
    input  logic        p0_ready,
    input  logic        p0_data_available
);
    typedef enum logic [2:0] {
        IDLE,
        LOAD_WRITE,
        WAIT_AVAILABLE,
        PULSE_NATIVE,
        WAIT_NATIVE,
        COMPLETE
    } state_t;

    state_t state;
    logic [26:0] address_q;
    logic [15:0] words_q;
    logic [15:0] word_index_q;
    logic [7:0] tag_q;
    logic [15:0] write_data_q;
    logic [1:0] byte_enable_q;
    logic error_q;
    logic [27:0] native_byte_address;

    assign native_byte_address = {1'b0, address_q} + {11'b0, word_index_q, 1'b0};
    assign p0_addr = native_byte_address[25:1];
    assign p0_data = write_data_q;
    assign p0_byte_en = byte_enable_q;
    assign p0_wr_req = state == PULSE_NATIVE && !error_q;
    assign p0_rd_req = 1'b0;
    assign p0_end_burst_req = 1'b1;

    assign req_ready = init_done && state == IDLE;
    assign write_ready = state == LOAD_WRITE;
    assign read_valid = 1'b0;
    assign read_data = p0_q;
    assign completion_valid = state == COMPLETE;
    assign completion_tag = tag_q;
    assign completion_words = words_q;
    assign completion_error = error_q;

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            address_q <= '0;
            words_q <= '0;
            word_index_q <= '0;
            tag_q <= '0;
            write_data_q <= '0;
            byte_enable_q <= 2'b11;
            error_q <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (req_valid && req_ready) begin
                        address_q <= req_byte_address;
                        words_q <= req_words;
                        tag_q <= req_tag;
                        word_index_q <= '0;
                        byte_enable_q <= 2'b11;
                        error_q <= !req_write || req_words == 16'd0 || req_byte_address[0];
                        if (!req_write || req_words == 16'd0 || req_byte_address[0])
                            state <= COMPLETE;
                        else
                            state <= LOAD_WRITE;
                    end
                end
                LOAD_WRITE: begin
                    if (write_valid) begin
                        write_data_q <= write_data;
                        byte_enable_q <= write_byte_enable;
                        state <= WAIT_AVAILABLE;
                    end
                end
                WAIT_AVAILABLE: begin
                    if (p0_available)
                        state <= PULSE_NATIVE;
                end
                PULSE_NATIVE: begin
                    state <= WAIT_NATIVE;
                end
                WAIT_NATIVE: begin
                    if (p0_ready) begin
                        if (word_index_q + 1'b1 == words_q) begin
                            state <= COMPLETE;
                        end else begin
                            word_index_q <= word_index_q + 1'b1;
                            state <= LOAD_WRITE;
                        end
                    end
                end
                COMPLETE: begin
                    if (completion_ready)
                        state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

`ifdef SDRAM_BACKEND_AGG23_WORD
module line_capture_agg23_word_backend #(
    parameter integer SDRAM_FREQ_MHZ = 100
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        req_valid,
    output logic        req_ready,
    input  logic        req_write,
    input  logic [26:0] req_byte_address,
    input  logic [15:0] req_words,
    input  logic [7:0]  req_tag,
    input  logic        write_valid,
    output logic        write_ready,
    input  logic [15:0] write_data,
    input  logic [1:0]  write_byte_enable,
    output logic        read_valid,
    input  logic        read_ready,
    output logic [15:0] read_data,
    output logic        completion_valid,
    input  logic        completion_ready,
    output logic [7:0]  completion_tag,
    output logic [15:0] completion_words,
    output logic        completion_error,
    output logic        init_done,
    output logic        diagnostic_error,
    output logic [12:0] SDRAM_A,
    output logic [1:0]  SDRAM_BA,
    output logic        SDRAM_CKE,
    output logic        SDRAM_nCS,
    output logic        SDRAM_nRAS,
    output logic        SDRAM_nCAS,
    output logic        SDRAM_nWE,
    output logic        SDRAM_DQML,
    output logic        SDRAM_DQMH,
    inout  wire  [15:0] SDRAM_DQ,
    output logic        SDRAM_CLK
);
    wire [1:0] sdram_dqm;
    logic [24:0] p0_addr;
    logic [15:0] p0_data;
    logic [1:0] p0_byte_en;
    logic [15:0] p0_q;
    logic p0_wr_req, p0_rd_req, p0_available, p0_ready;

    assign {SDRAM_DQMH, SDRAM_DQML} = sdram_dqm;
    assign diagnostic_error = 1'b0;

    line_capture_agg23_adapter adapter (
        .clk, .reset, .init_done,
        .req_valid, .req_ready, .req_write, .req_byte_address, .req_words, .req_tag,
        .write_valid, .write_ready, .write_data, .write_byte_enable,
        .read_valid, .read_ready, .read_data,
        .completion_valid, .completion_ready, .completion_tag, .completion_words,
        .completion_error,
        .p0_addr, .p0_data, .p0_byte_en, .p0_q, .p0_wr_req, .p0_rd_req,
        .p0_end_burst_req(), .p0_available, .p0_ready, .p0_data_available(1'b0)
    );

    sdram #(
        .CLOCK_SPEED_MHZ(SDRAM_FREQ_MHZ),
        .BURST_LENGTH(1),
        .CAS_LATENCY(3),
        .P0_BURST_LENGTH(1)
    ) backend (
        .clk, .reset, .init_complete(init_done),
        .p0_addr, .p0_data, .p0_byte_en, .p0_q, .p0_wr_req, .p0_rd_req,
        .p0_available, .p0_ready,
        .SDRAM_DQ, .SDRAM_A, .SDRAM_DQM(sdram_dqm), .SDRAM_BA,
        .SDRAM_nCS, .SDRAM_nWE, .SDRAM_nRAS, .SDRAM_nCAS, .SDRAM_CKE,
        .SDRAM_CLK
    );
endmodule
`endif

`ifdef SDRAM_BACKEND_AGG23_BURST
module line_capture_agg23_burst_backend #(
    parameter integer SDRAM_FREQ_MHZ = 100
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        req_valid,
    output logic        req_ready,
    input  logic        req_write,
    input  logic [26:0] req_byte_address,
    input  logic [15:0] req_words,
    input  logic [7:0]  req_tag,
    input  logic        write_valid,
    output logic        write_ready,
    input  logic [15:0] write_data,
    input  logic [1:0]  write_byte_enable,
    output logic        read_valid,
    input  logic        read_ready,
    output logic [15:0] read_data,
    output logic        completion_valid,
    input  logic        completion_ready,
    output logic [7:0]  completion_tag,
    output logic [15:0] completion_words,
    output logic        completion_error,
    output logic        init_done,
    output logic        diagnostic_error,
    output logic [12:0] SDRAM_A,
    output logic [1:0]  SDRAM_BA,
    output logic        SDRAM_CKE,
    output logic        SDRAM_nCS,
    output logic        SDRAM_nRAS,
    output logic        SDRAM_nCAS,
    output logic        SDRAM_nWE,
    output logic        SDRAM_DQML,
    output logic        SDRAM_DQMH,
    inout  wire  [15:0] SDRAM_DQ,
    output logic        SDRAM_CLK
);
    wire [1:0] sdram_dqm;
    logic [24:0] p0_addr;
    logic [15:0] p0_data;
    logic [1:0] p0_byte_en;
    logic [15:0] p0_q;
    logic p0_wr_req, p0_rd_req, p0_end_burst_req, p0_available, p0_ready, p0_data_available;

    assign {SDRAM_DQMH, SDRAM_DQML} = sdram_dqm;
    assign diagnostic_error = 1'b0;

    line_capture_agg23_adapter #(.BURST_BACKEND(1)) adapter (
        .clk, .reset, .init_done,
        .req_valid, .req_ready, .req_write, .req_byte_address, .req_words, .req_tag,
        .write_valid, .write_ready, .write_data, .write_byte_enable,
        .read_valid, .read_ready, .read_data,
        .completion_valid, .completion_ready, .completion_tag, .completion_words,
        .completion_error,
        .p0_addr, .p0_data, .p0_byte_en, .p0_q, .p0_wr_req, .p0_rd_req,
        .p0_end_burst_req, .p0_available, .p0_ready, .p0_data_available
    );

    sdram_burst #(
        .CLOCK_SPEED_MHZ(SDRAM_FREQ_MHZ),
        .CAS_LATENCY(3),
        .WRITE_BURST(0)
    ) backend (
        .clk, .reset, .init_complete(init_done),
        .p0_addr, .p0_data, .p0_byte_en, .p0_q, .p0_wr_req, .p0_rd_req,
        .p0_end_burst_req, .p0_available, .p0_ready, .p0_data_available,
        .SDRAM_DQ, .SDRAM_A, .SDRAM_DQM(sdram_dqm), .SDRAM_BA,
        .SDRAM_nCS, .SDRAM_nWE, .SDRAM_nRAS, .SDRAM_nCAS, .SDRAM_CKE,
        .SDRAM_CLK
    );
endmodule
`endif
