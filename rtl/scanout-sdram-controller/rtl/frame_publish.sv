module frame_publish (
    input logic clk, input logic reset,
    input logic frame_start,
    input logic capture_enable,
    // Pulses only when a word has completed on SDRAM DQ, never on FIFO acceptance.
    input logic capture_word_commit,
    input logic capture_error,
    input logic capture_drained,
    input logic replay_frame_start,
    input logic [31:0] expected_words,
    output logic capture_buffer,
    output logic published_buffer,
    output logic published_valid,
    output logic replay_buffer,
    output logic replay_valid,
    output logic [31:0] publish_version,
    output logic publish_pulse,
    output logic capture_active,
    output logic capture_failed,
    output logic [31:0] completed_words,
    output logic [31:0] failed_capture_count
);
    logic failed_q;
    assign capture_failed = failed_q;
    wire publish_success = frame_start && capture_active && !failed_q && !capture_error &&
                           capture_drained &&
                           (completed_words + (capture_word_commit ? 1 : 0) == expected_words);
    always_ff @(posedge clk) begin
        if (reset) begin
            capture_buffer <= 1'b0; published_buffer <= 1'b0; published_valid <= 1'b0;
            replay_buffer <= 0; replay_valid <= 0; publish_version <= 0; publish_pulse <= 0;
            capture_active <= 1'b0; completed_words <= 0; failed_capture_count <= 0; failed_q <= 0;
        end else begin
            publish_pulse <= 1'b0;
            if (replay_frame_start) begin
                replay_buffer <= publish_success ? capture_buffer : published_buffer;
                replay_valid <= publish_success || published_valid;
            end
            if (capture_word_commit && capture_active) completed_words <= completed_words + 1'b1;
            if (capture_error && capture_active) failed_q <= 1'b1;
            if (frame_start) begin
                if (capture_active) begin
                    if (publish_success) begin
                        published_buffer <= capture_buffer;
                        published_valid <= 1'b1;
                        capture_buffer <= published_valid ? published_buffer : ~capture_buffer;
                        publish_version <= publish_version + 1'b1;
                        publish_pulse <= 1'b1;
                    end else failed_capture_count <= failed_capture_count + 1'b1;
                end
                capture_active <= capture_enable;
                if (!capture_active) capture_buffer <= published_valid ? ~published_buffer : capture_buffer;
                completed_words <= 0;
                failed_q <= 0;
            end
        end
    end
endmodule
