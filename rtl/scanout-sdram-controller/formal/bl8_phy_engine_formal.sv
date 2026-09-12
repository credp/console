module bl8_phy_engine_formal;
    logic clk;
    (* anyseq *) logic reset,command_valid,command_chip,command_all_banks;
    (* anyseq *) logic[2:0]command;
    (* anyseq *) logic[1:0]command_bank;
    (* anyseq *) logic[12:0]command_row;
    (* anyseq *) logic[9:0]command_column;
    (* anyseq *) logic[127:0]write_burst_data;
    (* anyseq *) logic[15:0]write_burst_byte_enable,sdram_dq_in;
    logic command_ready,read_burst_valid,burst_done,busy;
    logic[127:0]read_burst_data;
    logic[12:0]sdram_a;logic[1:0]sdram_ba;
    logic sdram_cke,sdram_ncs,sdram_nras,sdram_ncas,sdram_nwe;
    logic sdram_dqml,sdram_dqmh;logic[15:0]sdram_dq_out;logic sdram_dq_oe;
    logic past_valid=0;
    integer accepted_age;
    logic outstanding;

    sdram_bl8_phy_engine #(.READ_CAPTURE_CYCLES(4)) dut(.*);

    always_ff @(posedge clk) begin
        past_valid <= 1;
        if (!past_valid) assume(reset);
        else assume(!reset);

        if (reset) begin
            outstanding <= 0;
            accepted_age <= 0;
        end else begin
            if (command_valid && command_ready &&
                (command == 3'd3 || command == 3'd4)) begin
                outstanding <= 1;
                accepted_age <= 0;
            end else if (outstanding) accepted_age <= accepted_age + 1;
            if (burst_done) outstanding <= 0;

            assert(accepted_age <= 12);
            if (outstanding) assert(!command_ready);
            if (read_burst_valid) assert(!busy);
        end
        cover(past_valid && !reset && read_burst_valid);
        cover(past_valid && !reset && burst_done && sdram_dq_oe);
    end
endmodule
