module sdram_open_row_scheduler #(
    parameter longint unsigned SDRAM_FREQ_HZ = 130_000_000
) (
    input  logic        clk,
    input  logic        reset,

    input  logic        op_valid,
    output logic        op_ready,
    input  logic        op_write,
    input  logic        op_chip,
    input  logic [1:0]  op_bank,
    input  logic [12:0] op_row,
    input  logic [9:0]  op_column,

    output logic        command_valid,
    input  logic        command_ready,
    output logic [2:0]  command,
    output logic        command_chip,
    output logic [1:0]  command_bank,
    output logic [12:0] command_row,
    output logic [9:0]  command_column,
    output logic        command_all_banks,

    // Assert on the edge containing the final physical DQ beat.
    input  logic        burst_done,
    output logic        completion_valid,
    input  logic        completion_ready,

    output logic        timing_violation,
    output logic        row_hit
);
    localparam logic [2:0] CMD_NOP   = 3'd0;
    localparam logic [2:0] CMD_ACT   = 3'd1;
    localparam logic [2:0] CMD_PRE   = 3'd2;
    localparam logic [2:0] CMD_READ  = 3'd3;
    localparam logic [2:0] CMD_WRITE = 3'd4;

    typedef enum logic [1:0] {IDLE, RESOLVE, WAIT_BURST, COMPLETE} state_t;
    state_t state;
    logic write_q,chip_q;
    logic [1:0] bank_q;
    logic [12:0] row_q;
    logic [9:0] column_q;
    logic target_open,can_activate,can_precharge,can_read,can_write;
    logic tracker_command_legal;
    logic command_fire;
    logic tracked_burst_done;
    logic unused_idle0,unused_idle1,unused_refresh;

    assign op_ready = (state == IDLE);
    assign completion_valid = (state == COMPLETE);
    assign command_fire = command_valid && command_ready;
    assign tracked_burst_done = burst_done && (state == WAIT_BURST);

    always_comb begin
        command_valid = 1'b0;
        command = CMD_NOP;
        command_chip = chip_q;
        command_bank = bank_q;
        command_row = row_q;
        command_column = column_q;
        command_all_banks = 1'b0;
        if (state == RESOLVE) begin
            if (row_hit) begin
                command = write_q ? CMD_WRITE : CMD_READ;
                command_valid = write_q ? can_write : can_read;
            end else if (target_open) begin
                command = CMD_PRE;
                command_valid = can_precharge;
            end else begin
                command = CMD_ACT;
                command_valid = can_activate;
            end
        end
    end

    sdram_bank_timing #(.SDRAM_FREQ_HZ(SDRAM_FREQ_HZ)) timing (
        .clk,.reset,
        .command_fire,.command,.command_chip,.command_bank,.command_row,.command_all_banks,
        .command_legal(tracker_command_legal),.timing_violation,
        .burst_done(tracked_burst_done),.burst_write(write_q),
        .burst_chip(chip_q),.burst_bank(bank_q),
        .target_chip(chip_q),.target_bank(bank_q),.target_row(row_q),
        .target_open,.target_row_hit(row_hit),.can_activate,.can_precharge,.can_read,.can_write,
        .chip0_all_banks_idle(unused_idle0),.chip1_all_banks_idle(unused_idle1),
        .can_refresh_target(unused_refresh));

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            write_q <= 1'b0;
            chip_q <= 1'b0;
            bank_q <= '0;
            row_q <= '0;
            column_q <= '0;
        end else begin
            case (state)
                IDLE: if (op_valid && op_ready) begin
                    write_q <= op_write;
                    chip_q <= op_chip;
                    bank_q <= op_bank;
                    row_q <= op_row;
                    column_q <= op_column;
                    state <= RESOLVE;
                end
                RESOLVE: if (command_fire &&
                            (command == CMD_READ || command == CMD_WRITE))
                    state <= WAIT_BURST;
                WAIT_BURST: if (burst_done) state <= COMPLETE;
                COMPLETE: if (completion_ready) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end

`ifdef FORMAL
    logic f_past_valid = 1'b0;
    always_ff @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (!reset) begin
            if (command_fire) assert(tracker_command_legal);
            if (state == WAIT_BURST) assert(!command_valid);
            if (completion_valid) assert(state == COMPLETE);
            if (f_past_valid && !$past(reset) && $past(command_valid && !command_ready)) begin
                assert(command_valid);
                assert(command == $past(command));
                assert(command_chip == $past(command_chip));
                assert(command_bank == $past(command_bank));
                assert(command_row == $past(command_row));
                assert(command_column == $past(command_column));
            end
        end
    end
`endif
endmodule
