module sdram_single_client_controller #(
    parameter longint unsigned SDRAM_FREQ_HZ = 130_000_000,
    parameter integer CAS_LATENCY = 3,
    parameter integer POWERUP_US = 200,
    parameter integer INIT_REFRESH_COUNT = 8,
    parameter integer DQ_TURNAROUND_CYCLES = 1,
    parameter integer READ_CAPTURE_CYCLES = 4,
    parameter integer MAX_REFRESH_SERVICE_CYCLES = 64,
    parameter longint unsigned REFRESH_PHASE_CYCLES = 0,
    parameter integer LEN_WIDTH = 16,
    parameter integer TAG_WIDTH = 8,
    parameter integer MAX_REQUEST_WORDS = 256,
    parameter integer MAPPING = 5
) (
    input  logic                 clk,
    input  logic                 reset,
    input  logic                 req_valid,
    output logic                 req_ready,
    input  logic                 req_write,
    input  logic [26:0]          req_byte_address,
    input  logic [LEN_WIDTH-1:0] req_words,
    input  logic [TAG_WIDTH-1:0] req_tag,
    input  logic                 write_valid,
    output logic                 write_ready,
    input  logic [15:0]          write_data,
    input  logic [1:0]           write_byte_enable,
    output logic                 read_valid,
    input  logic                 read_ready,
    output logic [15:0]          read_data,
    output logic                 completion_valid,
    input  logic                 completion_ready,
    output logic [TAG_WIDTH-1:0] completion_tag,
    output logic [LEN_WIDTH-1:0] completion_words,
    output logic                 completion_error,
    output logic                 init_done,
    output logic [12:0]          sdram_a,
    output logic [1:0]           sdram_ba,
    output logic                 sdram_cke,
    output logic                 sdram_ncs,
    output logic                 sdram_nras,
    output logic                 sdram_ncas,
    output logic                 sdram_nwe,
    output logic                 sdram_dqml,
    output logic                 sdram_dqmh,
    input  logic [15:0]          sdram_dq_in,
    output logic [15:0]          sdram_dq_out,
    output logic                 sdram_dq_oe,
    output logic                 late_refresh0,
    output logic                 late_refresh1,
    output logic                 refresh_pending,
    output logic                 timing_violation,
    output logic                 turnaround_blocked,
    output logic                 row_hit,
    output logic                 phy_busy
);
    localparam logic [2:0] INIT_PRE = 3'd1;
    localparam logic [2:0] INIT_REF = 3'd2;
    localparam logic [2:0] INIT_MRS = 3'd3;

    logic init_cke,init_dqm_hold,init_command_valid,init_command_chip;
    logic [2:0] init_command;
    logic [12:0] init_command_address;
    logic unused_init_refresh0,unused_init_refresh1;
    logic unused_init_late0,unused_init_late1;
    logic adapter_reset,adapter_req_ready;
    logic op_valid,op_ready,op_write,op_chip;
    logic [1:0] op_bank;
    logic [12:0] op_row;
    logic [9:0] op_column;
    logic [127:0] op_write_data,op_read_data;
    logic [15:0] op_write_byte_enable;
    logic op_read_data_valid,op_completion_valid,op_completion_ready;
    logic [12:0] runtime_a;
    logic [1:0] runtime_ba;
    logic runtime_cke,runtime_ncs,runtime_nras,runtime_ncas,runtime_nwe;
    logic runtime_dqml,runtime_dqmh;
    logic [15:0] runtime_dq_out;
    logic runtime_dq_oe;

    assign adapter_reset = reset || !init_done;
    assign req_ready = init_done && adapter_req_ready;

    sdram_init_refresh #(
        .SDRAM_FREQ_HZ(SDRAM_FREQ_HZ),.CAS_LATENCY(CAS_LATENCY),
        .POWERUP_US(POWERUP_US),.REFRESH_COUNT(INIT_REFRESH_COUNT),
        .REFRESH_PHASE_CYCLES(REFRESH_PHASE_CYCLES),.INIT_ONLY(1'b1)
    ) initialization (
        .clk,.reset,.chip0_all_banks_idle(1'b1),.chip1_all_banks_idle(1'b1),
        .command_accept(init_command_valid),.init_done,.cke(init_cke),
        .dqm_hold(init_dqm_hold),.command_valid(init_command_valid),
        .command_chip(init_command_chip),.command(init_command),
        .command_address(init_command_address),
        .refresh0_block(unused_init_refresh0),.refresh1_block(unused_init_refresh1),
        .late_refresh0(unused_init_late0),.late_refresh1(unused_init_late1)
    );

    sdram_single_client_adapter #(
        .LEN_WIDTH(LEN_WIDTH),.TAG_WIDTH(TAG_WIDTH),
        .MAX_REQUEST_WORDS(MAX_REQUEST_WORDS),.MAPPING(MAPPING)
    ) adapter (
        .clk,.reset(adapter_reset),.req_valid(req_valid && init_done),
        .req_ready(adapter_req_ready),.req_write,.req_byte_address,.req_words,.req_tag,
        .write_valid,.write_ready,.write_data,.write_byte_enable,
        .read_valid,.read_ready,.read_data,
        .completion_valid,.completion_ready,.completion_tag,.completion_words,.completion_error,
        .op_valid,.op_ready,.op_write,.op_chip,.op_bank,.op_row,.op_column,
        .op_write_data,.op_write_byte_enable,.op_read_data,.op_read_data_valid,
        .op_completion_valid,.op_completion_ready
    );

    sdram_runtime_core #(
        .SDRAM_FREQ_HZ(SDRAM_FREQ_HZ),.DQ_TURNAROUND_CYCLES(DQ_TURNAROUND_CYCLES),
        .READ_CAPTURE_CYCLES(READ_CAPTURE_CYCLES),
        .MAX_REFRESH_SERVICE_CYCLES(MAX_REFRESH_SERVICE_CYCLES),
        .REFRESH_PHASE_CYCLES(REFRESH_PHASE_CYCLES)
    ) runtime (
        .clk,.reset(adapter_reset),.runtime_enable(init_done),
        .op_valid,.op_ready,.op_write,.op_chip,.op_bank,.op_row,.op_column,
        .op_write_data,.op_write_byte_enable,.op_read_data,.op_read_data_valid,
        .completion_valid(op_completion_valid),.completion_ready(op_completion_ready),
        .sdram_a(runtime_a),.sdram_ba(runtime_ba),.sdram_cke(runtime_cke),
        .sdram_ncs(runtime_ncs),.sdram_nras(runtime_nras),.sdram_ncas(runtime_ncas),
        .sdram_nwe(runtime_nwe),.sdram_dqml(runtime_dqml),.sdram_dqmh(runtime_dqmh),
        .sdram_dq_in,.sdram_dq_out(runtime_dq_out),.sdram_dq_oe(runtime_dq_oe),
        .late_refresh0,.late_refresh1,.refresh_pending,.timing_violation,
        .turnaround_blocked,.row_hit,.phy_busy
    );

    always_comb begin
        sdram_a = runtime_a;
        sdram_ba = runtime_ba;
        sdram_cke = runtime_cke;
        sdram_ncs = runtime_ncs;
        sdram_nras = runtime_nras;
        sdram_ncas = runtime_ncas;
        sdram_nwe = runtime_nwe;
        sdram_dqml = runtime_dqml;
        sdram_dqmh = runtime_dqmh;
        sdram_dq_out = runtime_dq_out;
        sdram_dq_oe = runtime_dq_oe;
        if (!init_done) begin
            sdram_a = init_command_address;
            sdram_ba = '0;
            sdram_cke = init_cke;
            sdram_ncs = init_command_chip;
            sdram_nras = 1'b1;
            sdram_ncas = 1'b1;
            sdram_nwe = 1'b1;
            sdram_dqml = init_dqm_hold;
            sdram_dqmh = init_dqm_hold;
            sdram_dq_out = '0;
            sdram_dq_oe = 1'b0;
            if (init_command_valid) begin
                case (init_command)
                    INIT_PRE: begin sdram_nras = 1'b0; sdram_nwe = 1'b0; end
                    INIT_REF: begin sdram_nras = 1'b0; sdram_ncas = 1'b0; end
                    INIT_MRS: begin
                        sdram_nras = 1'b0; sdram_ncas = 1'b0; sdram_nwe = 1'b0;
                    end
                    default: ;
                endcase
            end
        end
    end

`ifdef FORMAL
    always_ff @(posedge clk) if (!reset && !init_done) begin
        assert(!req_ready);
        assert(!op_valid);
        assert(!sdram_dq_oe);
    end
`endif
endmodule
