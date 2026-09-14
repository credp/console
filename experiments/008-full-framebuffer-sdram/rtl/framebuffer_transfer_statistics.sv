`timescale 1ns/1ps

// Owns observable cycle counters for the framebuffer transfer paths.
// The counters are deliberately separate from the blocks that cause the events.
module framebuffer_transfer_statistics (
    input  logic        clk,
    input  logic        reset,
    input  logic        count_enable,

    input  logic        producer_stall,
    input  logic        producer_idle,
    input  logic        consumer_stall,
    input  logic        consumer_idle,

    output logic [31:0] producer_stall_cycles,
    output logic [31:0] producer_idle_cycles,
    output logic [31:0] consumer_stall_cycles,
    output logic [31:0] consumer_idle_cycles
);
    always_ff @(posedge clk) begin
        if (reset) begin
            producer_stall_cycles <= '0;
            producer_idle_cycles <= '0;
            consumer_stall_cycles <= '0;
            consumer_idle_cycles <= '0;
        end else if (count_enable) begin
            if (producer_stall && !(&producer_stall_cycles))
                producer_stall_cycles <= producer_stall_cycles + 1'b1;
            if (producer_idle && !(&producer_idle_cycles))
                producer_idle_cycles <= producer_idle_cycles + 1'b1;
            if (consumer_stall && !(&consumer_stall_cycles))
                consumer_stall_cycles <= consumer_stall_cycles + 1'b1;
            if (consumer_idle && !(&consumer_idle_cycles))
                consumer_idle_cycles <= consumer_idle_cycles + 1'b1;
        end
    end
endmodule
