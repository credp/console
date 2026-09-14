`timescale 1ns/1ps

module framebuffer_bl8_write_backend #(
    parameter longint unsigned SDRAM_FREQ_HZ = 100_000_000,
    parameter integer POWERUP_US = 200,
    parameter longint unsigned REFRESH_INTERVAL_CYCLES = (SDRAM_FREQ_HZ * 70) / 10_000_000
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
        COMPLETE,
        RUNTIME_REFRESH,
        WAIT_RUNTIME_REFRESH
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
    logic [31:0] refresh_count;
    logic refresh_due;
    logic precharge_then_refresh_q;
    logic refresh_resume_activate_q;
    logic refresh_resume_collect_q;
    (* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *) logic reset_sync_meta = 1'b1;
    (* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *) logic reset_sync = 1'b1;

    assign {SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} = command;
    assign SDRAM_DQ = dq_oe_q ? dq_out_q : 16'hzzzz;
    assign {SDRAM_DQMH, SDRAM_DQML} = dqm_q;
    assign burst_word_addr = address_q[25:1] + {9'b0, burst_word_start_q};
    assign next_word_addr = address_q[25:1] + {9'b0, word_index_q};

    assign init_done = state >= IDLE;
    assign req_ready = (state == IDLE) && !refresh_due;
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

    initial begin
        if (REFRESH_INTERVAL_CYCLES <= TRFC_CYCLES)
            $error("refresh interval must exceed tRFC");
    end

    always_ff @(posedge clk) begin
        reset_sync_meta <= reset;
        reset_sync <= reset_sync_meta;

        if (reset_sync) begin
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
            refresh_count <= REFRESH_INTERVAL_CYCLES[31:0];
            refresh_due <= 1'b0;
            precharge_then_refresh_q <= 1'b0;
            refresh_resume_activate_q <= 1'b0;
            refresh_resume_collect_q <= 1'b0;
        end else begin
            command <= CMD_NOP;
            dq_oe_q <= 1'b0;

            if ((state >= IDLE) && !refresh_due) begin
                if (refresh_count == 0)
                    refresh_due <= 1'b1;
                else
                    refresh_count <= refresh_count - 1'b1;
            end

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
                    if (refresh_due) begin
                        refresh_resume_activate_q <= 1'b0;
                        refresh_resume_collect_q <= 1'b0;
                        state <= RUNTIME_REFRESH;
                    end else if (req_valid && req_ready) begin
                        address_q <= req_byte_address;
                        words_q <= req_words;
                        tag_q <= req_tag;
                        word_index_q <= '0;
                        fill_count_q <= '0;
                        row_open_q <= 1'b0;
                        precharge_then_complete_q <= 1'b0;
                        precharge_then_activate_q <= 1'b0;
                        precharge_then_refresh_q <= 1'b0;
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
                                precharge_then_refresh_q <= 1'b0;
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
                        else if (precharge_then_refresh_q) begin
                            refresh_resume_activate_q <= precharge_then_activate_q;
                            refresh_resume_collect_q <= !precharge_then_activate_q;
                            state <= RUNTIME_REFRESH;
                        end
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
                    // The SDRAM samples its first write word on the clock
                    // after the WRITE command. Keep beat zero present here;
                    // WRITE_DATA advances to beat one for the following edge.
                    dq_out_q <= burst_data[0];
                    dqm_q <= ~burst_byte_enable[0];
                    beat_q <= 3'd0;
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
                        end else if (refresh_due) begin
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
                            precharge_then_refresh_q <= refresh_due;
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

                RUNTIME_REFRESH: begin
                    command <= CMD_REFRESH;
                    wait_count <= TRFC_CYCLES[31:0];
                    state <= WAIT_RUNTIME_REFRESH;
                end

                WAIT_RUNTIME_REFRESH: begin
                    if (wait_count == 0) begin
                        refresh_count <= REFRESH_INTERVAL_CYCLES[31:0];
                        refresh_due <= 1'b0;
                        precharge_then_refresh_q <= 1'b0;
                        if (refresh_resume_activate_q) begin
                            refresh_resume_activate_q <= 1'b0;
                            state <= ACTIVATE;
                        end else if (refresh_resume_collect_q) begin
                            refresh_resume_collect_q <= 1'b0;
                            state <= COLLECT;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        wait_count <= wait_count - 1'b1;
                    end
                end
                default: state <= INIT_WAIT;
            endcase

        end
    end
endmodule
