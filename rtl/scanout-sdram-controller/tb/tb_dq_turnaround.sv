`timescale 1ns/1ps
module tb_dq_turnaround;
    logic clk=0,reset=1,burst_done,burst_write,proposed_write;
    logic ready0,blocked0,ready1,blocked1,ready2,blocked2;
    always #5 clk=~clk;
    sdram_dq_turnaround #(.DQ_TURNAROUND_CYCLES(0)) gap0(
      .clk,.reset,.burst_done,.burst_write,.proposed_write,.ready(ready0),.blocked(blocked0));
    sdram_dq_turnaround #(.DQ_TURNAROUND_CYCLES(1)) gap1(
      .clk,.reset,.burst_done,.burst_write,.proposed_write,.ready(ready1),.blocked(blocked1));
    sdram_dq_turnaround #(.DQ_TURNAROUND_CYCLES(2)) gap2(
      .clk,.reset,.burst_done,.burst_write,.proposed_write,.ready(ready2),.blocked(blocked2));

    initial begin
      burst_done=0;burst_write=0;proposed_write=0;
      repeat(2)@(negedge clk);reset=0;#1;
      if(!ready0||!ready1||!ready2)$fatal(1,"reset should permit either direction");

      // The final beat was a write. Further writes need no gap; reads do.
      @(negedge clk);burst_write=1;burst_done=1;@(negedge clk);burst_done=0;proposed_write=1;#1;
      if(!ready0||!ready1||!ready2)$fatal(1,"same direction was blocked");
      proposed_write=0;#1;
      if(!ready0||ready1||ready2||!blocked1||!blocked2)$fatal(1,"reversal was not initially blocked");
      @(negedge clk);#1;
      if(!ready1||ready2)$fatal(1,"one-cycle boundary");
      @(negedge clk);#1;
      if(!ready2)$fatal(1,"two-cycle boundary");

      // A read completion resets the gap in the opposite direction.
      burst_write=0;burst_done=1;@(negedge clk);burst_done=0;proposed_write=1;#1;
      if(ready1||ready2)$fatal(1,"read-to-write reversal was not blocked");
      proposed_write=0;#1;if(!ready1||!ready2)$fatal(1,"continued reads were blocked");
      $display("PASS DQ turnaround gaps 0, 1, and 2");$finish;
    end
endmodule
