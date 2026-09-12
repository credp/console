module sdram_open_row_core #(
    parameter longint unsigned SDRAM_FREQ_HZ = 130_000_000,
    parameter integer DQ_TURNAROUND_CYCLES = 1,
    parameter integer READ_CAPTURE_CYCLES = 4
) (
    input  logic         clk,
    input  logic         reset,

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

    input  logic         refresh_valid,
    output logic         refresh_ready,
    input  logic         refresh_chip,
    output logic         refresh_completion_valid,
    input  logic         refresh_completion_ready,

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

    output logic         timing_violation,
    output logic         turnaround_blocked,
    output logic         row_hit,
    output logic         phy_busy
);
    logic command_valid,command_ready,command_chip,command_all_banks;
    logic [2:0] command;
    logic [1:0] command_bank;
    logic [12:0] command_row;
    logic [9:0] command_column;
    logic burst_done;
    logic [127:0] write_data_q;
    logic [15:0] write_enable_q;

    // The scheduler may spend many clocks reaching the column command.  Keep
    // its corresponding write payload private and stable for that whole time.
    always_ff @(posedge clk) begin
        if (reset) begin
            write_data_q <= '0;
            write_enable_q <= '0;
        end else if (op_valid && op_ready) begin
            write_data_q <= op_write_data;
            write_enable_q <= op_write_byte_enable;
        end
    end

    sdram_open_row_scheduler #(
        .SDRAM_FREQ_HZ(SDRAM_FREQ_HZ),
        .DQ_TURNAROUND_CYCLES(DQ_TURNAROUND_CYCLES)
    ) scheduler (
        .clk,.reset,.op_valid,.op_ready,.op_write,.op_chip,.op_bank,.op_row,.op_column,
        .refresh_valid,.refresh_ready,.refresh_chip,
        .refresh_completion_valid,.refresh_completion_ready,
        .command_valid,.command_ready,.command,.command_chip,.command_bank,
        .command_row,.command_column,.command_all_banks,.burst_done,
        .completion_valid,.completion_ready,.timing_violation,.turnaround_blocked,.row_hit
    );

    sdram_bl8_phy_engine #(.READ_CAPTURE_CYCLES(READ_CAPTURE_CYCLES)) phy (
        .clk,.reset,.command_valid,.command_ready,.command,.command_chip,.command_bank,
        .command_row,.command_column,.command_all_banks,
        .write_burst_data(write_data_q),.write_burst_byte_enable(write_enable_q),
        .read_burst_data(op_read_data),.read_burst_valid(op_read_data_valid),.burst_done,
        .sdram_a,.sdram_ba,.sdram_cke,.sdram_ncs,.sdram_nras,.sdram_ncas,.sdram_nwe,
        .sdram_dqml,.sdram_dqmh,.sdram_dq_in,.sdram_dq_out,.sdram_dq_oe,.busy(phy_busy)
    );

`ifdef FORMAL
    always_ff @(posedge clk) if (!reset) begin
        if (op_read_data_valid) assert(completion_valid);
        if (phy_busy) assert(!command_ready);
    end
`endif
endmodule
