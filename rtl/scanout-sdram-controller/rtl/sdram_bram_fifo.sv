module sdram_bram_fifo #(
    parameter integer WIDTH = 16,
    parameter integer DEPTH = 2048,
    parameter integer ALMOST_FULL_LEVEL = DEPTH-8
) (
    input logic clk, input logic reset,
    input logic write_valid, output logic write_ready,
    input logic [WIDTH-1:0] write_data,
    output logic read_valid, input logic read_ready,
    output logic [WIDTH-1:0] read_data,
    output logic [$clog2(DEPTH+1)-1:0] level,
    output logic almost_full, output logic overflow, output logic underflow
);
    localparam integer AW = $clog2(DEPTH);
    // Quartus infers M10K/M20K storage rather than registers for this array.
    (* ramstyle = "M10K, no_rw_check" *) logic [WIDTH-1:0] memory [0:DEPTH-1];
    logic [AW-1:0] write_pointer, read_pointer;
    wire push = write_valid && write_ready;
    wire pop = read_valid && read_ready;
    assign write_ready = (level != DEPTH);
    assign read_valid = (level != 0);
    assign almost_full = (level >= ALMOST_FULL_LEVEL);
    // Registered synchronous read: head is fetched whenever the consumer advances.
    always_ff @(posedge clk) begin
        if (push) memory[write_pointer] <= write_data;
        if (push && pop && level == 1) read_data <= write_data;
        else if (pop && level > 1) read_data <= memory[read_pointer + 1'b1];
        else if (push && level == 0) read_data <= write_data;
        if (reset) begin
            write_pointer <= 0; read_pointer <= 0; level <= 0; read_data <= 0;
            overflow <= 0; underflow <= 0;
        end else begin
            if (push) write_pointer <= write_pointer + 1'b1;
            if (pop) read_pointer <= read_pointer + 1'b1;
            case ({push,pop})
                2'b10: level <= level + 1'b1;
                2'b01: level <= level - 1'b1;
                default: level <= level;
            endcase
            if (write_valid && !write_ready) overflow <= 1'b1;
            if (read_ready && !read_valid) underflow <= 1'b1;
        end
    end
    initial begin
        if (DEPTH < 2 || (DEPTH & (DEPTH-1)) != 0) $error("FIFO DEPTH must be a power of two");
        if (ALMOST_FULL_LEVEL < 1 || ALMOST_FULL_LEVEL > DEPTH) $error("bad almost-full level");
    end
endmodule
