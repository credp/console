module sdram_pair_model(
 input logic clk,input logic cke,input logic ncs,input logic nras,input logic ncas,input logic nwe,
 input logic [12:0] a,input logic [1:0] ba,input logic dqml,input logic dqmh,inout wire [15:0] dq);
 logic [15:0] mem[0:1][0:3][0:31][0:1];
 logic [12:0] open_row[0:1][0:3]; logic open_valid[0:1][0:3];
 logic [15:0] dq_out; logic dq_oe; integer rd_count; logic rd_chip; logic [1:0] rd_bank; logic [4:0] rd_col;
 integer c,b;
 assign dq=dq_oe?dq_out:16'hzzzz;
 initial begin dq_oe=0;rd_count=0;for(c=0;c<2;c=c+1)for(b=0;b<4;b=b+1)open_valid[c][b]=0;end
 always @(posedge clk) if(cke) begin
   if(dq_oe) dq_oe<=0;
   if(rd_count>0) begin rd_count<=rd_count-1; if(rd_count==1) begin
      dq_out<=mem[rd_chip][rd_bank][open_row[rd_chip][rd_bank][4:0]][rd_col[0]];dq_oe<=1;end end
   case({nras,ncas,nwe})
     3'b011: begin open_valid[ncs][ba]<=1;open_row[ncs][ba]<=a;end // ACT
     3'b101: if(open_valid[ncs][ba]) begin rd_chip<=ncs;rd_bank<=ba;rd_col<=a[4:0];rd_count<=3;
       if(a[10]) open_valid[ncs][ba]<=0;end
     3'b100: if(open_valid[ncs][ba]) begin
       if(!dqml) mem[ncs][ba][open_row[ncs][ba][4:0]][a[0]][7:0]<=dq[7:0];
       if(!dqmh) mem[ncs][ba][open_row[ncs][ba][4:0]][a[0]][15:8]<=dq[15:8];
       if(a[10]) open_valid[ncs][ba]<=0;end
     3'b010: begin if(a[10]) for(b=0;b<4;b=b+1)open_valid[ncs][b]<=0;else open_valid[ncs][ba]<=0;end
     default: ;
   endcase
 end
endmodule
