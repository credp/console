`timescale 1ns/1ps

// One non-white, interior read after SDRAM ownership changes from writer to
// reader. The returned word is deliberately exposed as a separate diagnostic
// signal so it can be shown directly on HDMI without any line-buffer logic.
// The one-shot producer writes frame zero, for which pixel (1023, 256) is the
// coarse-grid RGB565 value 16'h6204.
module framebuffer_sdram_readback_probe #(
    parameter logic [26:0] PROBE_BYTE_ADDRESS = 27'd657406,
    parameter logic [15:0] EXPECTED_WORD = 16'h6204
) (
    input  logic        clk,
    input  logic        reset,
    output logic        req_valid,
    input  logic        req_ready,
    output logic        req_write,
    output logic [26:0] req_byte_address,
    output logic [15:0] req_words,
    output logic [7:0]  req_tag,
    input  logic        read_valid,
    output logic        read_ready,
    input  logic [15:0] read_data,
    input  logic        completion_valid,
    output logic        completion_ready,
    input  logic [7:0]  completion_tag,
    input  logic [15:0] completion_words,
    input  logic        completion_error,
    output logic        done,
    output logic        passed,
    output logic        failed,
    output logic [7:0]  status,
    output logic [15:0] sample_word
);
    localparam logic [7:0] PROBE_TAG = 8'hf0;
    typedef enum logic [1:0] { REQUEST, RECEIVE, COMPLETE, FINISHED } state_t;
    state_t state;
    logic mismatch;

    assign req_valid = (state == REQUEST);
    assign req_write = 1'b0;
    assign req_byte_address = PROBE_BYTE_ADDRESS;
    assign req_words = 16'd1;
    assign req_tag = PROBE_TAG;
    assign read_ready = (state == RECEIVE);
    assign completion_ready = (state == COMPLETE);
    assign done = (state == FINISHED);
    // 10: request waiting, 11: waiting for read data, 12: waiting for the
    // controller completion. These states make a stalled read visible on HDMI.
    assign status = passed ? 8'h01 : failed ? 8'hee :
                    (state == REQUEST) ? 8'h10 :
                    (state == RECEIVE) ? 8'h11 : 8'h12;

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= REQUEST;
            mismatch <= 1'b0;
            passed <= 1'b0;
            failed <= 1'b0;
            sample_word <= '0;
        end else begin
            case (state)
                REQUEST: if (req_ready) state <= RECEIVE;
                RECEIVE: if (read_valid) begin
                    sample_word <= read_data;
                    mismatch <= (read_data != EXPECTED_WORD);
                    state <= COMPLETE;
                end
                COMPLETE: if (completion_valid) begin
                    if (mismatch || completion_error ||
                        completion_tag != PROBE_TAG || completion_words != 16'd1)
                        failed <= 1'b1;
                    else
                        passed <= 1'b1;
                    state <= FINISHED;
                end
                FINISHED: begin
                    // Hold the observation until the experiment resets.
                end
                default: state <= REQUEST;
            endcase
        end
    end
endmodule
