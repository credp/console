`ifdef SDRAM_BACKEND_AGG23_WORD
`include "../../third_party/agg23-sdram-controller/sdram.sv"
`else
`ifdef SDRAM_BACKEND_AGG23_BURST
`include "../../third_party/agg23-sdram-controller/sdram_burst.sv"
`endif
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
`else
`ifdef SDRAM_BACKEND_AGG23_BURST
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
`ifdef SDRAM_BACKEND_AGG23_BL8_WRITE
    line_capture_bl8_write_backend #(
        .SDRAM_FREQ_HZ(SDRAM_FREQ_HZ),
        .POWERUP_US(POWERUP_US)
    ) backend (
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
`endif
`endif
endmodule

module line_capture_bl8_write_backend #(
    parameter longint unsigned SDRAM_FREQ_HZ = 100_000_000,
    parameter integer POWERUP_US = 200
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
    localparam logic [3:0] CMD_NOP = 4'b0111;
    localparam logic [3:0] CMD_ACTIVE = 4'b0011;
    localparam logic [3:0] CMD_WRITE = 4'b0100;
    localparam logic [3:0] CMD_PRECHARGE = 4'b0010;
    localparam logic [3:0] CMD_REFRESH = 4'b0001;
    localparam logic [3:0] CMD_LOAD_MODE = 4'b0000;
    localparam logic [12:0] MODE_BL8_WRITE_BURST = {3'b000, 1'b0, 2'b00, 3'b011, 1'b0, 3'b011};

    function automatic longint unsigned ceil_ns(input longint unsigned ns);
        ceil_ns = (ns * SDRAM_FREQ_HZ + 64'd999_999_999) / 64'd1_000_000_000;
    endfunction

    localparam longint unsigned CYCLES_PER_US = SDRAM_FREQ_HZ / 64'd1_000_000;
    localparam longint unsigned POWERUP_CYCLES = CYCLES_PER_US * POWERUP_US;
    localparam integer TRCD_CYCLES = integer'(ceil_ns(21));
    localparam integer TWRP_CYCLES = integer'(ceil_ns(35));
    localparam integer TRP_CYCLES = integer'(ceil_ns(21));
    localparam integer TRFC_CYCLES = integer'(ceil_ns(80));

    typedef enum logic [4:0] {
        INIT_WAIT,
        INIT_PRECHARGE,
        INIT_WAIT_PRECHARGE,
        INIT_REFRESH1,
        INIT_WAIT_REFRESH1,
        INIT_REFRESH2,
        INIT_WAIT_REFRESH2,
        INIT_MODE,
        INIT_WAIT_MODE,
        IDLE,
        COLLECT,
        PRECHARGE_OPEN,
        WAIT_PRECHARGE_OPEN,
        ACTIVATE,
        WAIT_RCD,
        PREP_WRITE,
        WRITE_CMD,
        WRITE_DATA,
        WAIT_WRITE_TO_PRECHARGE,
        COMPLETE
    } state_t;

    state_t state;
    logic [3:0] command;
    logic [31:0] wait_count;
    logic [26:0] address_q;
    logic [15:0] words_q;
    logic [15:0] word_index_q;
    logic [15:0] burst_word_start_q;
    logic [7:0] tag_q;
    logic [15:0] burst_data [0:7];
    logic [1:0] burst_byte_enable [0:7];
    logic [2:0] fill_count_q;
    logic [2:0] beat_q;
    logic [24:0] burst_word_addr;
    logic [24:0] next_word_addr;
    logic row_open_q;
    logic [1:0] open_bank_q;
    logic [12:0] open_row_q;
    logic precharge_then_complete_q;
    logic precharge_then_activate_q;
    logic [15:0] dq_out_q;
    logic [1:0] dqm_q;
    logic dq_oe_q;
    logic error_q;

    assign {SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} = command;
    assign SDRAM_DQ = dq_oe_q ? dq_out_q : 16'hzzzz;
    assign {SDRAM_DQMH, SDRAM_DQML} = dqm_q;
    assign burst_word_addr = address_q[25:1] + {9'b0, burst_word_start_q};
    assign next_word_addr = address_q[25:1] + {9'b0, word_index_q};

    assign init_done = state >= IDLE;
    assign req_ready = state == IDLE;
    assign write_ready = state == COLLECT;
    assign read_valid = 1'b0;
    assign read_data = 16'h0000;
    assign completion_valid = state == COMPLETE;
    assign completion_tag = tag_q;
    assign completion_words = words_q;
    assign completion_error = error_q;
    assign diagnostic_error = 1'b0;

    altddio_out #(.extend_oe_disable("OFF"),.intended_device_family("Cyclone V"),
        .invert_output("OFF"),.lpm_hint("UNUSED"),.lpm_type("altddio_out"),
        .oe_reg("UNREGISTERED"),.power_up_high("OFF"),.width(1)) sdramclk_ddr
    (
        .datain_h(1'b0),.datain_l(1'b1),.outclock(clk),.dataout(SDRAM_CLK),
        .oe(1'b1),.outclocken(1'b1)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= INIT_WAIT;
            command <= CMD_NOP;
            wait_count <= POWERUP_CYCLES[31:0];
            SDRAM_CKE <= 1'b0;
            SDRAM_A <= '0;
            SDRAM_BA <= '0;
            address_q <= '0;
            words_q <= '0;
            word_index_q <= '0;
            burst_word_start_q <= '0;
            tag_q <= '0;
            fill_count_q <= '0;
            beat_q <= '0;
            row_open_q <= 1'b0;
            open_bank_q <= '0;
            open_row_q <= '0;
            precharge_then_complete_q <= 1'b0;
            precharge_then_activate_q <= 1'b0;
            dq_out_q <= '0;
            dqm_q <= 2'b11;
            dq_oe_q <= 1'b0;
            error_q <= 1'b0;
        end else begin
            command <= CMD_NOP;
            dq_oe_q <= 1'b0;

            case (state)
                INIT_WAIT: begin
                    SDRAM_CKE <= 1'b1;
                    if (wait_count == 0)
                        state <= INIT_PRECHARGE;
                    else
                        wait_count <= wait_count - 1'b1;
                end
                INIT_PRECHARGE: begin
                    command <= CMD_PRECHARGE;
                    SDRAM_A[10] <= 1'b1;
                    wait_count <= TRP_CYCLES[31:0];
                    state <= INIT_WAIT_PRECHARGE;
                end
                INIT_WAIT_PRECHARGE: begin
                    if (wait_count == 0)
                        state <= INIT_REFRESH1;
                    else
                        wait_count <= wait_count - 1'b1;
                end
                INIT_REFRESH1: begin
                    command <= CMD_REFRESH;
                    wait_count <= TRFC_CYCLES[31:0];
                    state <= INIT_WAIT_REFRESH1;
                end
                INIT_WAIT_REFRESH1: begin
                    if (wait_count == 0)
                        state <= INIT_REFRESH2;
                    else
                        wait_count <= wait_count - 1'b1;
                end
                INIT_REFRESH2: begin
                    command <= CMD_REFRESH;
                    wait_count <= TRFC_CYCLES[31:0];
                    state <= INIT_WAIT_REFRESH2;
                end
                INIT_WAIT_REFRESH2: begin
                    if (wait_count == 0)
                        state <= INIT_MODE;
                    else
                        wait_count <= wait_count - 1'b1;
                end
                INIT_MODE: begin
                    command <= CMD_LOAD_MODE;
                    SDRAM_BA <= 2'b00;
                    SDRAM_A <= MODE_BL8_WRITE_BURST;
                    wait_count <= 32'd2;
                    state <= INIT_WAIT_MODE;
                end
                INIT_WAIT_MODE: begin
                    if (wait_count == 0)
                        state <= IDLE;
                    else
                        wait_count <= wait_count - 1'b1;
                end
                IDLE: begin
                    if (req_valid && req_ready) begin
                        address_q <= req_byte_address;
                        words_q <= req_words;
                        tag_q <= req_tag;
                        word_index_q <= '0;
                        fill_count_q <= '0;
                        row_open_q <= 1'b0;
                        precharge_then_complete_q <= 1'b0;
                        precharge_then_activate_q <= 1'b0;
                        error_q <= !req_write || req_words == 16'd0 || req_byte_address[0] ||
                                   req_words[2:0] != 3'b000;
                        if (!req_write || req_words == 16'd0 || req_byte_address[0] ||
                            req_words[2:0] != 3'b000)
                            state <= COMPLETE;
                        else
                            state <= COLLECT;
                    end
                end
                COLLECT: begin
                    if (write_valid && write_ready) begin
                        burst_data[fill_count_q] <= write_data;
                        burst_byte_enable[fill_count_q] <= write_byte_enable;
                        if (fill_count_q == 3'd0)
                            burst_word_start_q <= word_index_q;
                        word_index_q <= word_index_q + 1'b1;
                        if (fill_count_q == 3'd7) begin
                            fill_count_q <= '0;
                            if (row_open_q &&
                                open_bank_q == burst_word_addr[24:23] &&
                                open_row_q == burst_word_addr[22:10])
                                state <= PREP_WRITE;
                            else if (row_open_q) begin
                                precharge_then_complete_q <= 1'b0;
                                precharge_then_activate_q <= 1'b1;
                                state <= PRECHARGE_OPEN;
                            end else begin
                                state <= ACTIVATE;
                            end
                        end else begin
                            fill_count_q <= fill_count_q + 1'b1;
                        end
                    end
                end
                PRECHARGE_OPEN: begin
                    command <= CMD_PRECHARGE;
                    SDRAM_BA <= open_bank_q;
                    SDRAM_A[10] <= 1'b0;
                    row_open_q <= 1'b0;
                    wait_count <= TRP_CYCLES[31:0];
                    state <= WAIT_PRECHARGE_OPEN;
                end
                WAIT_PRECHARGE_OPEN: begin
                    if (wait_count == 0) begin
                        if (precharge_then_complete_q)
                            state <= COMPLETE;
                        else if (precharge_then_activate_q)
                            state <= ACTIVATE;
                        else
                            state <= COLLECT;
                    end else begin
                        wait_count <= wait_count - 1'b1;
                    end
                end
                ACTIVATE: begin
                    command <= CMD_ACTIVE;
                    SDRAM_BA <= burst_word_addr[24:23];
                    SDRAM_A <= burst_word_addr[22:10];
                    row_open_q <= 1'b1;
                    open_bank_q <= burst_word_addr[24:23];
                    open_row_q <= burst_word_addr[22:10];
                    wait_count <= TRCD_CYCLES[31:0];
                    state <= WAIT_RCD;
                end
                WAIT_RCD: begin
                    if (wait_count == 0) begin
                        state <= PREP_WRITE;
                    end else begin
                        wait_count <= wait_count - 1'b1;
                    end
                end
                PREP_WRITE: begin
                    beat_q <= 3'd0;
                    dq_out_q <= burst_data[0];
                    dqm_q <= ~burst_byte_enable[0];
                    dq_oe_q <= 1'b1;
                    state <= WRITE_CMD;
                end
                WRITE_CMD: begin
                    command <= CMD_WRITE;
                    SDRAM_A <= {2'b00, 1'b0, burst_word_addr[9:0]};
                    SDRAM_BA <= burst_word_addr[24:23];
                    dq_oe_q <= 1'b1;
                    dq_out_q <= burst_data[1];
                    dqm_q <= ~burst_byte_enable[1];
                    beat_q <= 3'd1;
                    state <= WRITE_DATA;
                end
                WRITE_DATA: begin
                    dq_oe_q <= 1'b1;
                    if (beat_q == 3'd7) begin
                        dq_oe_q <= 1'b0;
                        if (word_index_q == words_q) begin
                            wait_count <= TWRP_CYCLES[31:0];
                            state <= WAIT_WRITE_TO_PRECHARGE;
                        end else if (next_word_addr[24:10] != burst_word_addr[24:10]) begin
                            wait_count <= TWRP_CYCLES[31:0];
                            state <= WAIT_WRITE_TO_PRECHARGE;
                        end else begin
                            state <= COLLECT;
                        end
                    end else begin
                        beat_q <= beat_q + 1'b1;
                        dq_out_q <= burst_data[beat_q + 1'b1];
                        dqm_q <= ~burst_byte_enable[beat_q + 1'b1];
                    end
                end
                WAIT_WRITE_TO_PRECHARGE: begin
                    if (wait_count == 0) begin
                        if (word_index_q == words_q) begin
                            if (row_open_q) begin
                                precharge_then_complete_q <= 1'b1;
                                precharge_then_activate_q <= 1'b0;
                                state <= PRECHARGE_OPEN;
                            end else begin
                                state <= COMPLETE;
                            end
                        end else begin
                            precharge_then_complete_q <= 1'b0;
                            precharge_then_activate_q <= 1'b0;
                            state <= PRECHARGE_OPEN;
                        end
                    end else begin
                        wait_count <= wait_count - 1'b1;
                    end
                end
                COMPLETE: begin
                    if (completion_ready)
                        state <= IDLE;
                end
                default: state <= INIT_WAIT;
            endcase

        end
    end
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
    logic phy_sdram_dqml, phy_sdram_dqmh;
    (* useioff = 1 *) logic [15:0] phy_sdram_dq_oe;
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
        phy_sdram_dq_oe <= {16{core_sdram_dq_oe}};
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
    genvar dq_bit;
    generate
        for (dq_bit = 0; dq_bit < 16; dq_bit = dq_bit + 1) begin : dq_out
            assign SDRAM_DQ[dq_bit] = phy_sdram_dq_oe[dq_bit] ? phy_sdram_dq_out[dq_bit] : 1'bz;
        end
    endgenerate
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
