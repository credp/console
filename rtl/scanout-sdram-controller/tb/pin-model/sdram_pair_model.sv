module sdram_pair_model #(
 parameter integer READ_LATENCY_EDGES=3
)(
 input logic clk,input logic cke,input logic ncs,input logic nras,input logic ncas,input logic nwe,
 input logic [12:0] a,input logic [1:0] ba,input logic dqml,input logic dqmh,inout wire [15:0] dq);

 logic [15:0] mem[0:1][0:3][0:31][0:1023];
 logic [12:0] open_row[0:1][0:3];
 logic open_valid[0:1][0:3];
 logic [3:0] burst_length[0:1];
 logic [15:0] dq_out;
 logic dq_oe;
 integer rd_latency,rd_beats,wr_beats;
 logic rd_chip,wr_chip;
 logic [1:0] rd_bank,wr_bank;
 logic [4:0] rd_row,wr_row;
 logic [9:0] rd_col,wr_col;
 logic rd_autoprecharge,wr_autoprecharge;
 integer c,b;

 assign dq=dq_oe?dq_out:16'hzzzz;

 function automatic [3:0] decoded_burst_length(input logic [2:0] code);
  case(code)
   3'b000:decoded_burst_length=1;
   3'b011:decoded_burst_length=8;
   default:decoded_burst_length=1;
  endcase
 endfunction

 // Sequential BL8 wraps within the aligned eight-column group, including
 // masked padding beats following an unaligned partial write.
 function automatic [9:0] next_column(input logic [9:0] col,input logic [3:0] length);
  next_column=(length==8)?{col[9:3],col[2:0]+3'd1}:col;
 endfunction

 initial begin
  dq_oe=0;rd_latency=0;rd_beats=0;wr_beats=0;
  for(c=0;c<2;c=c+1)begin
   burst_length[c]=1;
   for(b=0;b<4;b=b+1)open_valid[c][b]=0;
  end
 end

 always @(posedge clk) if(cke) begin
  dq_oe<=0;

  if(rd_latency>1)rd_latency<=rd_latency-1;
  else if(rd_latency==1)begin
   rd_latency<=0;
   dq_out<=mem[rd_chip][rd_bank][rd_row][rd_col];
   dq_oe<=1;
   rd_col<=next_column(rd_col,burst_length[rd_chip]);
   rd_beats<=rd_beats-1;
   if(rd_beats==1&&rd_autoprecharge)open_valid[rd_chip][rd_bank]<=0;
  end else if(rd_beats>0)begin
   dq_out<=mem[rd_chip][rd_bank][rd_row][rd_col];
   dq_oe<=1;
   rd_col<=next_column(rd_col,burst_length[rd_chip]);
   rd_beats<=rd_beats-1;
   if(rd_beats==1&&rd_autoprecharge)open_valid[rd_chip][rd_bank]<=0;
  end

  if(wr_beats>0)begin
   if(!dqml)mem[wr_chip][wr_bank][wr_row][wr_col][7:0]<=dq[7:0];
   if(!dqmh)mem[wr_chip][wr_bank][wr_row][wr_col][15:8]<=dq[15:8];
   wr_col<=next_column(wr_col,burst_length[wr_chip]);
   wr_beats<=wr_beats-1;
   if(wr_beats==1&&wr_autoprecharge)open_valid[wr_chip][wr_bank]<=0;
  end

  case({nras,ncas,nwe})
   3'b011:begin
    open_valid[ncs][ba]<=1;
    open_row[ncs][ba]<=a;
   end
   3'b101:if(open_valid[ncs][ba])begin
    rd_chip<=ncs;rd_bank<=ba;rd_row<=open_row[ncs][ba][4:0];rd_col<=a[9:0];
    rd_latency<=READ_LATENCY_EDGES;rd_beats<=burst_length[ncs];rd_autoprecharge<=a[10];
   end
   3'b100:if(open_valid[ncs][ba])begin
    if(!dqml)mem[ncs][ba][open_row[ncs][ba][4:0]][a[9:0]][7:0]<=dq[7:0];
    if(!dqmh)mem[ncs][ba][open_row[ncs][ba][4:0]][a[9:0]][15:8]<=dq[15:8];
    wr_chip<=ncs;wr_bank<=ba;wr_row<=open_row[ncs][ba][4:0];wr_col<=next_column(a[9:0],burst_length[ncs]);
    wr_beats<=burst_length[ncs]-1'b1;wr_autoprecharge<=a[10];
    if(burst_length[ncs]==1&&a[10])open_valid[ncs][ba]<=0;
   end
   3'b010:begin
    if(a[10])for(b=0;b<4;b=b+1)open_valid[ncs][b]<=0;
    else open_valid[ncs][ba]<=0;
   end
   3'b000:burst_length[ncs]<=decoded_burst_length(a[2:0]);
   default:;
  endcase
 end
endmodule
