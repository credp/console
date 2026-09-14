`timescale 1ns/1ps

// Compact SDRAM pin model for agg23's full-page read mode. It models the
// command/address/DQ behavior used by this experiment, not datasheet timing.
module agg23_sdram_pin_model (
    input logic clk, input logic cke, input logic ncs, input logic nras,
    input logic ncas, input logic nwe, input logic [12:0] a,
    input logic [1:0] ba, input logic dqml, input logic dqmh,
    inout wire [15:0] dq
);
    logic [15:0] mem [0:3][0:31][0:1023];
    logic [12:0] open_row [0:3];
    logic open_valid [0:3];
    logic [15:0] dq_out;
    logic dq_oe;
    integer read_latency, read_beats;
    logic [1:0] read_bank;
    logic [4:0] read_row;
    logic [9:0] read_column;
    integer bank_index;

    assign dq = dq_oe ? dq_out : 16'hzzzz;

    initial begin
        dq_oe = 1'b0;
        read_latency = 0;
        read_beats = 0;
        for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1)
            open_valid[bank_index] = 1'b0;
    end

    always_ff @(posedge clk) if (cke) begin
        dq_oe <= 1'b0;
        if (read_latency > 1) begin
            read_latency <= read_latency - 1;
        end else if (read_latency == 1 || read_beats > 0) begin
            if (read_latency == 1)
                read_latency <= 0;
            dq_out <= mem[read_bank][read_row][read_column];
            dq_oe <= 1'b1;
            read_column <= read_column + 1'b1;
            read_beats <= read_beats - 1;
        end

        case ({nras, ncas, nwe})
            3'b011: begin
                open_valid[ba] <= 1'b1;
                open_row[ba] <= a;
            end
            3'b101: if (open_valid[ba]) begin
                read_bank <= ba;
                read_row <= open_row[ba][4:0];
                read_column <= a[9:0];
                read_latency <= 3;
                read_beats <= 1024;
            end
            3'b010: if (a[10]) begin
                for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1)
                    open_valid[bank_index] <= 1'b0;
            end else begin
                open_valid[ba] <= 1'b0;
            end
            default: ;
        endcase
    end
endmodule
