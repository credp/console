`timescale 1ns/1ps

// Temporary first-picture ownership policy. This block is intentionally small
// and separate from the eventual round-robin arbiter: its only job is to make
// the producer-to-reader cut visible, safe, and easy to remove later.
module framebuffer_one_shot_handoff (
    input  logic clk,
    input  logic reset,
    // Pulses only after the producer's last line has fully committed.
    input  logic frame_write_complete,
    input  logic reader_init_done,
    output logic producer_owns_sdram,
    output logic reader_reset,
    output logic reader_owns_sdram,
    output logic framebuffer_ready
);
    typedef enum logic [1:0] {
        HANDOFF_PRODUCER,
        HANDOFF_READER_INIT,
        HANDOFF_READER
    } handoff_state_t;
    handoff_state_t state;

    assign producer_owns_sdram = (state == HANDOFF_PRODUCER);
    // Keep the reader reset until the writer's final transaction has ended.
    assign reader_reset = (state == HANDOFF_PRODUCER);
    // The reader needs the physical pins for its own SDRAM initialization.
    // Ownership therefore begins as soon as the final writer transaction has
    // finished, while framebuffer_ready remains low until that init completes.
    assign reader_owns_sdram = (state != HANDOFF_PRODUCER);
    assign framebuffer_ready = (state == HANDOFF_READER);

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= HANDOFF_PRODUCER;
        end else begin
            case (state)
                HANDOFF_PRODUCER: begin
                    if (frame_write_complete)
                        state <= HANDOFF_READER_INIT;
                end
                HANDOFF_READER_INIT: begin
                    if (reader_init_done)
                        state <= HANDOFF_READER;
                end
                HANDOFF_READER: begin
                    // This temporary mode intentionally never returns pins to
                    // the producer. The final experiment replaces this state
                    // machine with transaction-boundary round robin.
                end
                default: state <= HANDOFF_PRODUCER;
            endcase
        end
    end
endmodule
