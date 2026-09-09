`timescale 1ns/1ps
module tb_foundation;
    logic clk=0, reset=1; always #5 clk=~clk;
    logic [26:0] a; logic chip,bs; logic [1:0] bank; logic [12:0] row; logic [9:0] col;
    sdram_addr_decode dut_addr(.byte_address(a),.chip(chip),.bank(bank),.row(row),.column(col),.byte_select(bs));
    logic rv,rr,rw,ov,ordy,ow,olast; logic [26:0] ra,oa; logic [15:0] words; logic [3:0] owds;
    sdram_request_splitter dut_split(.clk,.reset,.req_valid(rv),.req_ready(rr),.req_write(rw),
      .req_byte_address(ra),.req_words(words),.op_valid(ov),.op_ready(ordy),.op_write(ow),
      .op_byte_address(oa),.op_words(owds),.op_last(olast));
    integer seen;
    initial begin
        a=0; rv=0; rw=0; ra=0; words=0; ordy=0; repeat(2) @(posedge clk); reset=0;
        #1; if ({row,col,bank,chip,bs} !== 0) $fatal(1,"zero decode");
        a=27'h400; #1; if(chip!==1 || bank!==0 || col!==0) $fatal(1,"1KiB stripe");
        a=27'h800; #1; if(chip!==0 || bank!==1 || col!==0) $fatal(1,"bank stripe");
        a=27'h2000; #1; if(col[9]!==1 || chip!==0 || bank!==0) $fatal(1,"half row");
        @(negedge clk); ra=27'd2032; words=16'd12; rv=1;
        @(negedge clk); rv=0; #1;
        if(!ov || owds!=8 || oa!=2032 || olast) $fatal(1,"first split");
        ordy=1;
        @(negedge clk); #1;
        if(!ov || owds!=4 || oa!=2048 || !olast) $fatal(1,"second split");
        $display("PASS foundation"); $finish;
    end
endmodule
