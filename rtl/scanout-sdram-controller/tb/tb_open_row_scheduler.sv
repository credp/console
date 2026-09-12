`timescale 1ns/1ps
module tb_open_row_scheduler;
    localparam logic [2:0] ACT=3'd1,PRE=3'd2,READ=3'd3,WRITE=3'd4;
    logic clk=0,reset=1,op_valid,op_ready,op_write,op_chip;
    logic[1:0]op_bank;logic[12:0]op_row;logic[9:0]op_column;
    logic command_valid,command_ready=1,command_chip,command_all_banks;
    logic[2:0]command;logic[1:0]command_bank;logic[12:0]command_row;logic[9:0]command_column;
    logic burst_done,completion_valid,completion_ready=1,timing_violation,row_hit;
    integer cycle=0,act_count=0,pre_count=0,read_count=0,write_count=0;
    integer last_command_cycle=-1,last_write_end_cycle=-1,last_pre_cycle=-1;
    always #5 clk=~clk;
    always @(posedge clk) begin
      cycle<=cycle+1;
      if(command_valid&&command_ready)begin
        last_command_cycle<=cycle;
        case(command)
          ACT:act_count<=act_count+1;PRE:begin pre_count<=pre_count+1;last_pre_cycle<=cycle;end
          READ:read_count<=read_count+1;WRITE:write_count<=write_count+1;
        endcase
      end
      if(burst_done&&op_write)last_write_end_cycle<=cycle;
    end
    sdram_open_row_scheduler #(.SDRAM_FREQ_HZ(130_000_000)) dut(.*);

    task submit(input logic write,input logic chip,input logic[1:0]bank,
                input logic[12:0]row,input logic[9:0]column);
      begin
        @(negedge clk);op_write=write;op_chip=chip;op_bank=bank;op_row=row;op_column=column;op_valid=1;
        if(!op_ready)$fatal(1,"submitted while scheduler busy");
        @(posedge clk);@(negedge clk);op_valid=0;
      end
    endtask
    task complete_burst;
      begin repeat(8)@(negedge clk);burst_done=1;@(negedge clk);burst_done=0;
        wait(completion_valid);@(negedge clk);
      end
    endtask

    initial begin
      op_valid=0;op_write=0;op_chip=0;op_bank=0;op_row=0;op_column=0;burst_done=0;
      repeat(2)@(negedge clk);reset=0;

      submit(0,0,0,13'h010,10'h008);wait(command_valid&&command==READ);complete_burst();
      if(act_count!=1||pre_count!=0||read_count!=1)$fatal(1,"closed-bank sequence");

      // Same row is a hit: no PRE or ACT is required.
      submit(1,0,0,13'h010,10'h010);wait(command_valid&&command==WRITE);complete_burst();
      if(act_count!=1||pre_count!=0||write_count!=1)$fatal(1,"row-hit sequence");

      // A new row waits for write recovery, then PRE -> ACT -> READ.
      submit(0,0,0,13'h011,10'h018);wait(command_valid&&command==PRE);
      if(cycle-last_write_end_cycle<2)$fatal(1,"PRE violated tWR");
      wait(command_valid&&command==READ);complete_burst();
      if(act_count!=2||pre_count!=1||read_count!=2)$fatal(1,"row-conflict sequence");

      // Backpressure must hold a proposed command and its complete address stable.
      submit(0,1,2,13'h222,10'h155);command_ready=0;wait(command_valid);
      begin logic[2:0]held_command;logic[12:0]held_row;logic[9:0]held_column;
        held_command=command;held_row=command_row;held_column=command_column;
        repeat(3)begin @(negedge clk);if(!command_valid||command!=held_command||command_row!=held_row||command_column!=held_column)
          $fatal(1,"stalled command changed");end
      end
      command_ready=1;wait(command_valid&&command==READ);complete_burst();
      if(timing_violation)$fatal(1,"scheduler emitted an illegal command");
      $display("PASS open-row scheduler: closed, hit, conflict, tWR, and command stall");$finish;
    end
endmodule
