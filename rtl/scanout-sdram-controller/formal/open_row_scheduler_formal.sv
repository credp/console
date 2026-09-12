module open_row_scheduler_formal;
    logic clk;
    (* anyseq *) logic reset,op_valid,op_write,op_chip,command_ready,burst_done,completion_ready;
    (* anyseq *) logic refresh_valid,refresh_chip,refresh_completion_ready;
    (* anyseq *) logic[1:0]op_bank;
    (* anyseq *) logic[12:0]op_row;
    (* anyseq *) logic[9:0]op_column;
    logic op_ready,command_valid,command_chip,command_all_banks,completion_valid;
    logic[2:0]command;logic[1:0]command_bank;logic[12:0]command_row;logic[9:0]command_column;
    logic timing_violation,row_hit;
    logic refresh_ready,refresh_completion_valid;
    logic past_valid=0;

    sdram_open_row_scheduler #(.SDRAM_FREQ_HZ(130_000_000)) dut(.*);

    always_ff @(posedge clk) begin
        past_valid<=1;
        if(!past_valid)assume(reset);
        else assume(!reset);
        if(past_valid&&!reset&&$past(op_valid&&!op_ready))begin
            assume(op_valid);
            assume(op_write==$past(op_write));assume(op_chip==$past(op_chip));
            assume(op_bank==$past(op_bank));assume(op_row==$past(op_row));
            assume(op_column==$past(op_column));
        end
        if(past_valid&&!reset&&$past(refresh_valid&&!refresh_ready))begin
            assume(refresh_valid);assume(refresh_chip==$past(refresh_chip));
        end
        if(!reset)begin
            if(completion_valid)assert(!op_ready);
        end
        cover(past_valid&&!reset&&completion_valid);
        cover(past_valid&&!reset&&refresh_completion_valid);
    end
endmodule
