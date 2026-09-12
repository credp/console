// Top-level composition for two architecture clients sharing one initialized
// SDRAM runtime. Arbitration and response isolation live in
// sdram_two_client_adapter; initialization and pin ownership live in
// sdram_initialized_runtime.
module sdram_two_client_controller #(
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
    input logic clk,
    input logic reset,

    input logic c0_req_valid,
    output logic c0_req_ready,
    input logic c0_req_write,
    input logic [26:0] c0_req_byte_address,
    input logic [LEN_WIDTH-1:0] c0_req_words,
    input logic [TAG_WIDTH-1:0] c0_req_tag,
    input logic c0_write_valid,
    output logic c0_write_ready,
    input logic [15:0] c0_write_data,
    input logic [1:0] c0_write_byte_enable,
    output logic c0_read_valid,
    input logic c0_read_ready,
    output logic [15:0] c0_read_data,
    output logic c0_completion_valid,
    input logic c0_completion_ready,
    output logic [TAG_WIDTH-1:0] c0_completion_tag,
    output logic [LEN_WIDTH-1:0] c0_completion_words,
    output logic c0_completion_error,

    input logic c1_req_valid,
    output logic c1_req_ready,
    input logic c1_req_write,
    input logic [26:0] c1_req_byte_address,
    input logic [LEN_WIDTH-1:0] c1_req_words,
    input logic [TAG_WIDTH-1:0] c1_req_tag,
    input logic c1_write_valid,
    output logic c1_write_ready,
    input logic [15:0] c1_write_data,
    input logic [1:0] c1_write_byte_enable,
    output logic c1_read_valid,
    input logic c1_read_ready,
    output logic [15:0] c1_read_data,
    output logic c1_completion_valid,
    input logic c1_completion_ready,
    output logic [TAG_WIDTH-1:0] c1_completion_tag,
    output logic [LEN_WIDTH-1:0] c1_completion_words,
    output logic c1_completion_error,

    output logic init_done,
    output logic granted_client,
    output logic [12:0] sdram_a,
    output logic [1:0] sdram_ba,
    output logic sdram_cke,
    output logic sdram_ncs,
    output logic sdram_nras,
    output logic sdram_ncas,
    output logic sdram_nwe,
    output logic sdram_dqml,
    output logic sdram_dqmh,
    input logic [15:0] sdram_dq_in,
    output logic [15:0] sdram_dq_out,
    output logic sdram_dq_oe,
    output logic late_refresh0,
    output logic late_refresh1,
    output logic refresh_pending,
    output logic timing_violation,
    output logic turnaround_blocked,
    output logic row_hit,
    output logic phy_busy
);
    logic frontend_reset;
    logic adapter_c0_req_ready;
    logic adapter_c1_req_ready;

    logic op_valid;
    logic op_ready;
    logic op_write;
    logic op_chip;
    logic [1:0] op_bank;
    logic [12:0] op_row;
    logic [9:0] op_column;
    logic [127:0] op_write_data;
    logic [15:0] op_write_byte_enable;
    logic [127:0] op_read_data;
    logic op_read_data_valid;
    logic op_completion_valid;
    logic op_completion_ready;

    // Both front ends become visible on the same edge as the runtime. A
    // request held valid during initialization is accepted afterwards.
    assign frontend_reset = reset || !init_done;
    assign c0_req_ready = init_done && adapter_c0_req_ready;
    assign c1_req_ready = init_done && adapter_c1_req_ready;

    sdram_two_client_adapter #(
        .LEN_WIDTH(LEN_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .MAX_REQUEST_WORDS(MAX_REQUEST_WORDS),
        .MAPPING(MAPPING)
    ) clients (
        .clk,
        .reset(frontend_reset),
        .c0_req_valid(c0_req_valid && init_done),
        .c0_req_ready(adapter_c0_req_ready),
        .c0_req_write,
        .c0_req_byte_address,
        .c0_req_words,
        .c0_req_tag,
        .c0_write_valid,
        .c0_write_ready,
        .c0_write_data,
        .c0_write_byte_enable,
        .c0_read_valid,
        .c0_read_ready,
        .c0_read_data,
        .c0_completion_valid,
        .c0_completion_ready,
        .c0_completion_tag,
        .c0_completion_words,
        .c0_completion_error,
        .c1_req_valid(c1_req_valid && init_done),
        .c1_req_ready(adapter_c1_req_ready),
        .c1_req_write,
        .c1_req_byte_address,
        .c1_req_words,
        .c1_req_tag,
        .c1_write_valid,
        .c1_write_ready,
        .c1_write_data,
        .c1_write_byte_enable,
        .c1_read_valid,
        .c1_read_ready,
        .c1_read_data,
        .c1_completion_valid,
        .c1_completion_ready,
        .c1_completion_tag,
        .c1_completion_words,
        .c1_completion_error,
        .op_valid,
        .op_ready,
        .op_write,
        .op_chip,
        .op_bank,
        .op_row,
        .op_column,
        .op_write_data,
        .op_write_byte_enable,
        .op_read_data,
        .op_read_data_valid,
        .op_completion_valid,
        .op_completion_ready,
        .op_client(granted_client)
    );

    sdram_initialized_runtime #(
        .SDRAM_FREQ_HZ(SDRAM_FREQ_HZ),
        .CAS_LATENCY(CAS_LATENCY),
        .POWERUP_US(POWERUP_US),
        .INIT_REFRESH_COUNT(INIT_REFRESH_COUNT),
        .DQ_TURNAROUND_CYCLES(DQ_TURNAROUND_CYCLES),
        .READ_CAPTURE_CYCLES(READ_CAPTURE_CYCLES),
        .MAX_REFRESH_SERVICE_CYCLES(MAX_REFRESH_SERVICE_CYCLES),
        .REFRESH_PHASE_CYCLES(REFRESH_PHASE_CYCLES)
    ) memory_runtime (
        .clk,
        .reset,
        .init_done,
        .op_valid,
        .op_ready,
        .op_write,
        .op_chip,
        .op_bank,
        .op_row,
        .op_column,
        .op_write_data,
        .op_write_byte_enable,
        .op_read_data,
        .op_read_data_valid,
        .completion_valid(op_completion_valid),
        .completion_ready(op_completion_ready),
        .sdram_a,
        .sdram_ba,
        .sdram_cke,
        .sdram_ncs,
        .sdram_nras,
        .sdram_ncas,
        .sdram_nwe,
        .sdram_dqml,
        .sdram_dqmh,
        .sdram_dq_in,
        .sdram_dq_out,
        .sdram_dq_oe,
        .late_refresh0,
        .late_refresh1,
        .refresh_pending,
        .timing_violation,
        .turnaround_blocked,
        .row_hit,
        .phy_busy
    );

`ifdef FORMAL
    always_ff @(posedge clk) begin
        if (!reset && !init_done) begin
            assert(!c0_req_ready);
            assert(!c1_req_ready);
            assert(!op_valid);
        end
    end
`endif
endmodule
