`timescale 1ns/1ps

// Four fixed 16-bit hexadecimal counters in the top-left diagnostic strip.
// Fields are writer, reader, errors, and scanout underflows respectively.
module framebuffer_debug_overlay(
    input logic [10:0] x, input logic [9:0] y, input logic active,
    input logic [15:0] writer_count, reader_count, error_count, underflow_count,
    output logic override, output logic [15:0] pixel
);
    logic [15:0] value; logic [3:0] nibble; logic [6:0] segments;
    logic [1:0] field; logic digit; logic [2:0] dx; logic [3:0] dy;
    always_comb begin
        override=0; pixel='0; field=x[5:4]; digit=x[3]; dx=x[2:0]; dy=y[3:0];
        case(field) 0:value=writer_count; 1:value=reader_count; 2:value=error_count; default:value=underflow_count; endcase
        nibble=value >> ((1-digit)*4);
        case(nibble)
          0:segments=7'b1111110;1:segments=7'b0110000;2:segments=7'b1101101;3:segments=7'b1111001;
          4:segments=7'b0110011;5:segments=7'b1011011;6:segments=7'b1011111;7:segments=7'b1110000;
          8:segments=7'b1111111;9:segments=7'b1111011;10:segments=7'b1110111;11:segments=7'b0011111;
          12:segments=7'b1001110;13:segments=7'b0111101;14:segments=7'b1001111;default:segments=7'b1000111; endcase
        if(active && y<10 && x<64 && ((dy==0&&segments[6])||(dy==9&&segments[3])||(dx==0&&dy<5&&segments[5])||(dx==0&&dy>4&&segments[4])||(dx==5&&dy<5&&segments[1])||(dx==5&&dy>4&&segments[2])||(dy==4&&segments[0]))) begin
          override=1; pixel=(field==2)?16'hf800:(field==3)?16'hffe0:16'hffff;
        end
    end
endmodule
