module sdram_runtime_core #(
    parameter longint unsigned SDRAM_FREQ_HZ = 130_000_000,
    parameter integer DQ_TURNAROUND_CYCLES = 1,
    parameter integer READ_CAPTURE_CYCLES = 4,
    parameter integer MAX_REFRESH_SERVICE_CYCLES = 64,
    parameter longint unsigned REFRESH_PHASE_CYCLES = 0
) (
    input  logic         clk,
    input  logic         reset,
    // Assert once the separate initialization sequencer has completed.
    input  logic         runtime_enable,

    input  logic         op_valid,
    output logic         op_ready,
    input  logic         op_write,
    input  logic         op_chip,
    input  logic [1:0]   op_bank,
    input  logic [12:0]  op_row,
    input  logic [9:0]   op_column,
    input  logic [127:0] op_write_data,
    input  logic [15:0]  op_write_byte_enable,
    output logic [127:0] op_read_data,
    output logic         op_read_data_valid,
    output logic         completion_valid,
    input  logic         completion_ready,

    output logic [12:0]  sdram_a,
    output logic [1:0]   sdram_ba,
    output logic         sdram_cke,
    output logic         sdram_ncs,
    output logic         sdram_nras,
    output logic         sdram_ncas,
    output logic         sdram_nwe,
    output logic         sdram_dqml,
    output logic         sdram_dqmh,
    input  logic [15:0]  sdram_dq_in,
    output logic [15:0]  sdram_dq_out,
    output logic         sdram_dq_oe,

    output logic         late_refresh0,
    output logic         late_refresh1,
    output logic         refresh_pending,
    output logic         timing_violation,
    output logic         turnaround_blocked,
    output logic         row_hit,
    output logic         phy_busy
);
    logic refresh_valid,refresh_ready,refresh_chip;
    logic refresh_completion_valid,refresh_completion_ready;
    logic core_op_valid,core_op_ready,core_completion_valid;
    logic core_read_data_valid;
    logic response_pending,operation_write_q;

    // The SDRAM side must never inherit unbounded client response stalls.  A
    // one-entry holding register acknowledges the scheduler immediately and
    // prevents another client operation until the old response is consumed;
    // refresh remains free to run while that response is being held.
    assign core_op_valid = op_valid && !response_pending;
    assign op_ready = core_op_ready && !response_pending;
    assign completion_valid = response_pending;
    assign op_read_data_valid = response_pending && !operation_write_q;

    always_ff @(posedge clk) begin
        if (reset) begin
            response_pending <= 1'b0;
            operation_write_q <= 1'b0;
        end else begin
            if (completion_valid && completion_ready)
                response_pending <= 1'b0;
            if (op_valid && op_ready)
                operation_write_q <= op_write;
            if (core_completion_valid)
                response_pending <= 1'b1;
        end
    end

    sdram_refresh_deadline #(
        .SDRAM_FREQ_HZ(SDRAM_FREQ_HZ),
        .MAX_SERVICE_CYCLES(MAX_REFRESH_SERVICE_CYCLES),
        .REFRESH_PHASE_CYCLES(REFRESH_PHASE_CYCLES)
    ) refresh_deadline (
        .clk,.reset,.enable(runtime_enable),.refresh_valid,.refresh_ready,.refresh_chip,
        .refresh_completion_valid,.refresh_completion_ready,
        .late_refresh0,.late_refresh1,.refresh_pending
    );

    sdram_open_row_core #(
        .SDRAM_FREQ_HZ(SDRAM_FREQ_HZ),
        .DQ_TURNAROUND_CYCLES(DQ_TURNAROUND_CYCLES),
        .READ_CAPTURE_CYCLES(READ_CAPTURE_CYCLES)
    ) core (
        .clk,.reset,.op_valid(core_op_valid),.op_ready(core_op_ready),
        .op_write,.op_chip,.op_bank,.op_row,.op_column,
        .op_write_data,.op_write_byte_enable,.op_read_data,
        .op_read_data_valid(core_read_data_valid),
        .completion_valid(core_completion_valid),.completion_ready(1'b1),
        .refresh_valid,.refresh_ready,.refresh_chip,
        .refresh_completion_valid,.refresh_completion_ready,
        .sdram_a,.sdram_ba,.sdram_cke,.sdram_ncs,.sdram_nras,.sdram_ncas,.sdram_nwe,
        .sdram_dqml,.sdram_dqmh,.sdram_dq_in,.sdram_dq_out,.sdram_dq_oe,
        .timing_violation,.turnaround_blocked,.row_hit,.phy_busy
    );

`ifdef FORMAL
    always_ff @(posedge clk) if (!reset && runtime_enable) begin
        assert(!late_refresh0);
        assert(!late_refresh1);
        if (completion_valid && !completion_ready) begin
            assert(!op_ready);
            if (!operation_write_q) assert(op_read_data_valid);
        end
    end
`endif
endmodule
