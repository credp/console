module sdram_bl8_phy_engine #(
    // Number of full clocks after a READ command before the first registered
    // sdram_dq_in word is captured.  The board PHY/capture phase determines
    // this value; CL=3 plus the existing input handoff gives four clocks.
    parameter integer READ_CAPTURE_CYCLES = 4
) (
    input  logic         clk,
    input  logic         reset,

    input  logic         command_valid,
    output logic         command_ready,
    input  logic [2:0]   command,
    input  logic         command_chip,
    input  logic [1:0]   command_bank,
    input  logic [12:0]  command_row,
    input  logic [9:0]   command_column,
    input  logic         command_all_banks,

    // A complete physical burst is supplied with a WRITE command.  Buffering
    // belongs above this boundary, so an accepted SDRAM burst never waits for
    // a producer once its non-pausable pin transaction has begun.
    input  logic [127:0] write_burst_data,
    input  logic [15:0]  write_burst_byte_enable,
    output logic [127:0] read_burst_data,
    output logic         read_burst_valid,

    // Pulses on the clock edge containing physical beat seven.
    output logic         burst_done,

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
    output logic         busy
);
    localparam logic [2:0] CMD_NOP   = 3'd0;
    localparam logic [2:0] CMD_ACT   = 3'd1;
    localparam logic [2:0] CMD_PRE   = 3'd2;
    localparam logic [2:0] CMD_READ  = 3'd3;
    localparam logic [2:0] CMD_WRITE = 3'd4;
    localparam logic [2:0] CMD_REF   = 3'd5;
    localparam integer WAIT_BITS = (READ_CAPTURE_CYCLES > 1) ?
                                   $clog2(READ_CAPTURE_CYCLES + 1) : 1;

    typedef enum logic [1:0] {IDLE, WRITE_BEATS, READ_WAIT, READ_BEATS} state_t;
    state_t state;
    logic [2:0] beat;
    logic [WAIT_BITS-1:0] wait_count;
    logic chip_q;
    logic [1:0] bank_q;
    logic [127:0] write_data_q;
    logic [15:0] write_enable_q;
    logic command_fire;

    assign command_ready = (state == IDLE);
    assign command_fire = command_valid && command_ready;
    assign busy = (state != IDLE);

    always_comb begin
        sdram_a = '0;
        sdram_ba = (state == IDLE) ? command_bank : bank_q;
        sdram_cke = 1'b1;
        sdram_ncs = (state == IDLE) ? command_chip : chip_q;
        sdram_nras = 1'b1;
        sdram_ncas = 1'b1;
        sdram_nwe = 1'b1;
        sdram_dqml = 1'b0;
        sdram_dqmh = 1'b0;
        sdram_dq_out = '0;
        sdram_dq_oe = 1'b0;
        burst_done = 1'b0;

        if (state == IDLE && command_valid) begin
            case (command)
                CMD_ACT: begin
                    sdram_nras = 1'b0;
                    sdram_a = command_row;
                end
                CMD_PRE: begin
                    sdram_nras = 1'b0;
                    sdram_nwe = 1'b0;
                    sdram_a[10] = command_all_banks;
                end
                CMD_READ: begin
                    sdram_ncas = 1'b0;
                    sdram_a[9:0] = command_column;
                end
                CMD_WRITE: begin
                    sdram_ncas = 1'b0;
                    sdram_nwe = 1'b0;
                    sdram_a[9:0] = command_column;
                    sdram_dq_out = write_burst_data[15:0];
                    sdram_dqml = !write_burst_byte_enable[0];
                    sdram_dqmh = !write_burst_byte_enable[1];
                    // Keep DQM in the address output registers as required by
                    // the qualified MiSTer pin placement used by experiment 6.
                    sdram_a[12:11] = {sdram_dqmh, sdram_dqml};
                    sdram_dq_oe = 1'b1;
                end
                CMD_REF: begin
                    sdram_nras = 1'b0;
                    sdram_ncas = 1'b0;
                end
                default: ;
            endcase
        end else if (state == WRITE_BEATS) begin
            sdram_dq_out = write_data_q[beat*16 +: 16];
            sdram_dqml = !write_enable_q[beat*2];
            sdram_dqmh = !write_enable_q[beat*2+1];
            sdram_a[12:11] = {sdram_dqmh, sdram_dqml};
            sdram_dq_oe = 1'b1;
            burst_done = (beat == 3'd7);
        end else if (state == READ_BEATS) begin
            burst_done = (beat == 3'd7);
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            beat <= '0;
            wait_count <= '0;
            chip_q <= 1'b0;
            bank_q <= '0;
            write_data_q <= '0;
            write_enable_q <= '0;
            read_burst_data <= '0;
            read_burst_valid <= 1'b0;
        end else begin
            read_burst_valid <= 1'b0;
            case (state)
                IDLE: if (command_fire && command == CMD_WRITE) begin
                    chip_q <= command_chip;
                    bank_q <= command_bank;
                    write_data_q <= write_burst_data;
                    write_enable_q <= write_burst_byte_enable;
                    beat <= 3'd1;
                    state <= WRITE_BEATS;
                end else if (command_fire && command == CMD_READ) begin
                    chip_q <= command_chip;
                    bank_q <= command_bank;
                    beat <= '0;
                    wait_count <= '0;
                    state <= (READ_CAPTURE_CYCLES == 0) ? READ_BEATS : READ_WAIT;
                end
                WRITE_BEATS: if (beat == 3'd7) begin
                    beat <= '0;
                    state <= IDLE;
                end else beat <= beat + 1'b1;
                READ_WAIT: if (wait_count == READ_CAPTURE_CYCLES-1) begin
                    beat <= '0;
                    state <= READ_BEATS;
                end else wait_count <= wait_count + 1'b1;
                READ_BEATS: begin
                    read_burst_data[beat*16 +: 16] <= sdram_dq_in;
                    if (beat == 3'd7) begin
                        read_burst_valid <= 1'b1;
                        beat <= '0;
                        state <= IDLE;
                    end else beat <= beat + 1'b1;
                end
                default: state <= IDLE;
            endcase
        end
    end

`ifdef FORMAL
    logic f_past_valid = 1'b0;
    integer f_age;
    always_ff @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (reset || state == IDLE) f_age <= 0;
        else f_age <= f_age + 1;
        if (!reset) begin
            assert(beat <= 7);
            assert(f_age <= READ_CAPTURE_CYCLES + 8);
            if (state == WRITE_BEATS) assert(sdram_dq_oe);
            if (state == READ_WAIT || state == READ_BEATS) assert(!sdram_dq_oe);
            if (burst_done) assert((state == WRITE_BEATS || state == READ_BEATS) && beat == 7);
        end
    end
`endif
endmodule
