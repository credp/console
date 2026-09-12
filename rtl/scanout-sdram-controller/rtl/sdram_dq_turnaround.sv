module sdram_dq_turnaround #(
    parameter integer DQ_TURNAROUND_CYCLES = 1
) (
    input  logic clk,
    input  logic reset,
    input  logic burst_done,
    input  logic burst_write,
    input  logic proposed_write,
    output logic ready,
    output logic blocked
);
    localparam integer GAP_BITS = (DQ_TURNAROUND_CYCLES < 1) ? 1 :
                                  $clog2(DQ_TURNAROUND_CYCLES + 1);
    logic direction_seen,last_write;
    logic [GAP_BITS-1:0] gap_cycles;

    assign blocked = direction_seen && (proposed_write != last_write) &&
                     (gap_cycles < DQ_TURNAROUND_CYCLES);
    assign ready = !blocked;

    always_ff @(posedge clk) begin
        if (reset) begin
            direction_seen <= 1'b0;
            last_write <= 1'b0;
            gap_cycles <= '0;
        end else if (burst_done) begin
            direction_seen <= 1'b1;
            last_write <= burst_write;
            gap_cycles <= '0;
        end else if (direction_seen && gap_cycles < DQ_TURNAROUND_CYCLES) begin
            gap_cycles <= gap_cycles + 1'b1;
        end
    end

    initial begin
        if (DQ_TURNAROUND_CYCLES < 0)
            $error("DQ_TURNAROUND_CYCLES must not be negative");
    end
endmodule
