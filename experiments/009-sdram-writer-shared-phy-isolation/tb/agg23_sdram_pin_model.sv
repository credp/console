`timescale 1ns/1ps

// Compact SDRAM pin model for the writer/agg23 integration tests. It retains
// BL8 writes and returns agg23's continuous 1024-word reads. This models the
// command/address/DQ behavior used here, not every SDRAM datasheet rule.
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
    integer read_latency, read_beats, write_beats, configured_burst_words;
    logic [1:0] read_bank;
    logic [4:0] read_row;
    logic [9:0] read_column;
    logic [1:0] write_bank;
    logic [4:0] write_row;
    logic [9:0] write_column;
    integer bank_index;

    function automatic logic [9:0] next_write_column(input logic [9:0] column);
        // The producer programs BL8 sequential mode. Column addresses wrap
        // inside the aligned group of eight, as they do in the physical SDRAM.
        next_write_column = {column[9:3], column[2:0] + 3'd1};
    endfunction

    assign dq = dq_oe ? dq_out : 16'hzzzz;

    initial begin
        dq_oe = 1'b0;
        read_latency = 0;
        read_beats = 0;
        write_beats = 0;
        configured_burst_words = 1;
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

        if (write_beats > 0) begin
            if (!dqml)
                mem[write_bank][write_row][write_column][7:0] <= dq[7:0];
            if (!dqmh)
                mem[write_bank][write_row][write_column][15:8] <= dq[15:8];
            write_column <= next_write_column(write_column);
            write_beats <= write_beats - 1;
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
                read_beats <= configured_burst_words;
            end
            3'b100: if (open_valid[ba]) begin
                // The first write word accompanies the WRITE command. The
                // remaining seven BL8 words follow on consecutive edges.
                if (!dqml)
                    mem[ba][open_row[ba][4:0]][a[9:0]][7:0] <= dq[7:0];
                if (!dqmh)
                    mem[ba][open_row[ba][4:0]][a[9:0]][15:8] <= dq[15:8];
                write_bank <= ba;
                write_row <= open_row[ba][4:0];
                write_column <= next_write_column(a[9:0]);
                write_beats <= configured_burst_words - 1;
            end
            3'b010: if (a[10]) begin
                for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1)
                    open_valid[bank_index] <= 1'b0;
            end else begin
                open_valid[ba] <= 1'b0;
            end
            3'b000: begin
                case (a[2:0])
                    3'b011: configured_burst_words <= 8;
                    3'b111: configured_burst_words <= 1024;
                    default: configured_burst_words <= 1;
                endcase
            end
            default: ;
        endcase
    end
endmodule
