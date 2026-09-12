module sdram_bank_timing #(
    parameter longint unsigned SDRAM_FREQ_HZ = 130_000_000
) (
    input  logic        clk,
    input  logic        reset,

    // A command which was actually placed on the SDRAM command bus.
    input  logic        command_fire,
    input  logic [2:0]  command,
    input  logic        command_chip,
    input  logic [1:0]  command_bank,
    input  logic [12:0] command_row,
    input  logic        command_all_banks,
    output logic        command_legal,
    output logic        timing_violation,

    // End of the eight physical DQ beats belonging to a column command.
    input  logic        burst_done,
    input  logic        burst_write,
    input  logic        burst_chip,
    input  logic [1:0]  burst_bank,

    // Combinational eligibility for a proposed target.
    input  logic        target_chip,
    input  logic [1:0]  target_bank,
    input  logic [12:0] target_row,
    output logic        target_open,
    output logic        target_row_hit,
    output logic        can_activate,
    output logic        can_precharge,
    output logic        can_read,
    output logic        can_write,
    output logic        chip0_all_banks_idle,
    output logic        chip1_all_banks_idle,
    output logic        can_refresh_target
);
    localparam logic [2:0] CMD_ACT   = 3'd1;
    localparam logic [2:0] CMD_PRE   = 3'd2;
    localparam logic [2:0] CMD_READ  = 3'd3;
    localparam logic [2:0] CMD_WRITE = 3'd4;
    localparam logic [2:0] CMD_REF   = 3'd5;

    function automatic longint unsigned ceil_ns(input longint unsigned ns);
        ceil_ns = (ns * SDRAM_FREQ_HZ + 64'd999_999_999) / 64'd1_000_000_000;
    endfunction

    localparam longint unsigned TRCD = ceil_ns(21);
    localparam longint unsigned TRP  = ceil_ns(21);
    localparam longint unsigned TRAS = ceil_ns(42);
    localparam longint unsigned TRC  = ceil_ns(63);
    localparam longint unsigned TRRD = ceil_ns(14);
    localparam longint unsigned TWR  = ceil_ns(14);
    localparam longint unsigned TRFC = ceil_ns(63);
    localparam longint unsigned MAX_DELAY0 = (TRC > TRFC) ? TRC : TRFC;
    localparam longint unsigned MAX_DELAY1 = (TRAS > MAX_DELAY0) ? TRAS : MAX_DELAY0;
    localparam integer AGE_BITS = (MAX_DELAY1 < 1) ? 1 : $clog2(MAX_DELAY1 + 1);
    localparam logic [AGE_BITS-1:0] AGE_MAX = {AGE_BITS{1'b1}};

    logic bank_open [0:1][0:3];
    logic [12:0] open_row [0:1][0:3];
    logic read_inflight [0:1][0:3];
    logic write_inflight [0:1][0:3];
    logic [AGE_BITS-1:0] since_activate [0:1][0:3];
    logic [AGE_BITS-1:0] since_precharge [0:1][0:3];
    logic [AGE_BITS-1:0] since_write_end [0:1][0:3];
    logic [AGE_BITS-1:0] since_chip_activate [0:1];
    logic [AGE_BITS-1:0] since_refresh [0:1];
    logic command_bank_open;
    logic command_row_hit;
    logic command_can_activate;
    logic command_can_precharge;
    logic command_can_column;
    logic command_can_refresh;
    logic precharge_all_legal;
    logic burst_legal;

    integer chip_index;
    integer bank_index;
    integer precharge_index;
    always_comb begin
        target_open = bank_open[target_chip][target_bank];
        target_row_hit = target_open && (open_row[target_chip][target_bank] == target_row);
        chip0_all_banks_idle = !bank_open[0][0] && !bank_open[0][1] &&
                               !bank_open[0][2] && !bank_open[0][3];
        chip1_all_banks_idle = !bank_open[1][0] && !bank_open[1][1] &&
                               !bank_open[1][2] && !bank_open[1][3];

        can_activate = !target_open &&
                       (since_precharge[target_chip][target_bank] >= TRP) &&
                       (since_activate[target_chip][target_bank] >= TRC) &&
                       (since_chip_activate[target_chip] >= TRRD) &&
                       (since_refresh[target_chip] >= TRFC);
        can_precharge = target_open &&
                        !read_inflight[target_chip][target_bank] &&
                        !write_inflight[target_chip][target_bank] &&
                        (since_activate[target_chip][target_bank] >= TRAS) &&
                        (since_write_end[target_chip][target_bank] >= TWR);
        can_read = target_row_hit &&
                   !read_inflight[target_chip][target_bank] &&
                   !write_inflight[target_chip][target_bank] &&
                   (since_activate[target_chip][target_bank] >= TRCD) &&
                   (since_refresh[target_chip] >= TRFC);
        can_write = can_read;
        can_refresh_target = (target_chip ? chip1_all_banks_idle : chip0_all_banks_idle) &&
                             (since_precharge[target_chip][0] >= TRP) &&
                             (since_precharge[target_chip][1] >= TRP) &&
                             (since_precharge[target_chip][2] >= TRP) &&
                             (since_precharge[target_chip][3] >= TRP) &&
                             (since_refresh[target_chip] >= TRFC);

        command_bank_open = bank_open[command_chip][command_bank];
        command_row_hit = command_bank_open &&
                          (open_row[command_chip][command_bank] == command_row);
        command_can_activate = !command_bank_open &&
                               (since_precharge[command_chip][command_bank] >= TRP) &&
                               (since_activate[command_chip][command_bank] >= TRC) &&
                               (since_chip_activate[command_chip] >= TRRD) &&
                               (since_refresh[command_chip] >= TRFC);
        command_can_precharge = command_bank_open &&
                                !read_inflight[command_chip][command_bank] &&
                                !write_inflight[command_chip][command_bank] &&
                                (since_activate[command_chip][command_bank] >= TRAS) &&
                                (since_write_end[command_chip][command_bank] >= TWR);
        command_can_column = command_row_hit &&
                             !read_inflight[command_chip][command_bank] &&
                             !write_inflight[command_chip][command_bank] &&
                             (since_activate[command_chip][command_bank] >= TRCD) &&
                             (since_refresh[command_chip] >= TRFC);
        precharge_all_legal = 1'b1;
        for (precharge_index = 0; precharge_index < 4; precharge_index = precharge_index + 1) begin
            if (bank_open[command_chip][precharge_index] &&
                (read_inflight[command_chip][precharge_index] ||
                 write_inflight[command_chip][precharge_index] ||
                 since_activate[command_chip][precharge_index] < TRAS ||
                 since_write_end[command_chip][precharge_index] < TWR))
                precharge_all_legal = 1'b0;
        end
        command_can_refresh = (command_chip ? chip1_all_banks_idle : chip0_all_banks_idle) &&
                              (since_precharge[command_chip][0] >= TRP) &&
                              (since_precharge[command_chip][1] >= TRP) &&
                              (since_precharge[command_chip][2] >= TRP) &&
                              (since_precharge[command_chip][3] >= TRP) &&
                              (since_refresh[command_chip] >= TRFC);
        case (command)
            CMD_ACT: command_legal = command_can_activate;
            CMD_PRE: command_legal = command_all_banks ? precharge_all_legal : command_can_precharge;
            CMD_READ, CMD_WRITE: command_legal = command_can_column;
            CMD_REF: command_legal = command_can_refresh;
            default: command_legal = 1'b1;
        endcase
        burst_legal = burst_write ? write_inflight[burst_chip][burst_bank] :
                                    read_inflight[burst_chip][burst_bank];
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            for (chip_index = 0; chip_index < 2; chip_index = chip_index + 1) begin
                since_chip_activate[chip_index] <= AGE_MAX;
                since_refresh[chip_index] <= AGE_MAX;
                for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1) begin
                    bank_open[chip_index][bank_index] <= 1'b0;
                    open_row[chip_index][bank_index] <= '0;
                    read_inflight[chip_index][bank_index] <= 1'b0;
                    write_inflight[chip_index][bank_index] <= 1'b0;
                    since_activate[chip_index][bank_index] <= AGE_MAX;
                    since_precharge[chip_index][bank_index] <= AGE_MAX;
                    since_write_end[chip_index][bank_index] <= AGE_MAX;
                end
            end
            timing_violation <= 1'b0;
        end else begin
            for (chip_index = 0; chip_index < 2; chip_index = chip_index + 1) begin
                if (since_chip_activate[chip_index] != AGE_MAX)
                    since_chip_activate[chip_index] <= since_chip_activate[chip_index] + 1'b1;
                if (since_refresh[chip_index] != AGE_MAX)
                    since_refresh[chip_index] <= since_refresh[chip_index] + 1'b1;
                for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1) begin
                    if (since_activate[chip_index][bank_index] != AGE_MAX)
                        since_activate[chip_index][bank_index] <= since_activate[chip_index][bank_index] + 1'b1;
                    if (since_precharge[chip_index][bank_index] != AGE_MAX)
                        since_precharge[chip_index][bank_index] <= since_precharge[chip_index][bank_index] + 1'b1;
                    if (since_write_end[chip_index][bank_index] != AGE_MAX)
                        since_write_end[chip_index][bank_index] <= since_write_end[chip_index][bank_index] + 1'b1;
                end
            end

            if ((command_fire && !command_legal) || (burst_done && !burst_legal))
                timing_violation <= 1'b1;

            if (burst_done && burst_legal) begin
                read_inflight[burst_chip][burst_bank] <= 1'b0;
                write_inflight[burst_chip][burst_bank] <= 1'b0;
                if (burst_write)
                    since_write_end[burst_chip][burst_bank] <= '0;
            end

            if (command_fire && command_legal) begin
                case (command)
                    CMD_ACT: begin
                        bank_open[command_chip][command_bank] <= 1'b1;
                        open_row[command_chip][command_bank] <= command_row;
                        since_activate[command_chip][command_bank] <= '0;
                        since_chip_activate[command_chip] <= '0;
                    end
                    CMD_PRE: begin
                        if (command_all_banks) begin
                            for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1) begin
                                bank_open[command_chip][bank_index] <= 1'b0;
                                since_precharge[command_chip][bank_index] <= '0;
                            end
                        end else begin
                            bank_open[command_chip][command_bank] <= 1'b0;
                            since_precharge[command_chip][command_bank] <= '0;
                        end
                    end
                    CMD_READ: read_inflight[command_chip][command_bank] <= 1'b1;
                    CMD_WRITE: write_inflight[command_chip][command_bank] <= 1'b1;
                    CMD_REF: since_refresh[command_chip] <= '0;
                    default: ;
                endcase
            end
        end
    end

    initial begin
        if (TRCD < 1 || TRP < 1 || TRAS < 1 || TRC < 1 || TRRD < 1 || TWR < 1 || TRFC < 1)
            $error("SDRAM clock is too slow for cycle-age representation");
        if (SDRAM_FREQ_HZ == 130_000_000 &&
            (TRCD != 3 || TRP != 3 || TRAS != 6 || TRC != 9 || TRRD != 2 || TWR != 2 || TRFC != 9))
            $error("130 MHz timing conversion failure");
    end
endmodule
