`timescale 1ns/1ps

// Two complete SDRAM pages decouple agg23's continuous, unpausable read stream
// from the paced framebuffer consumer protocol.  A page is 1024 RGB565 words.
module framebuffer_agg23_burst_cache #(
    // Number of cycles by which the cache's accepted response trails the MIT
    // controller's predicted response. This includes command-launch delay as
    // well as DQ capture registers. The direct cache unit test has no delay.
    parameter logic [9:0] P0_DATA_PIPELINE_STAGES = 10'd0
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        init_done,
    input  logic        req_valid,
    output logic        req_ready,
    input  logic        req_write,
    input  logic [26:0] req_byte_address,
    input  logic [15:0] req_words,
    input  logic [7:0]  req_tag,
    output logic        read_valid,
    input  logic        read_ready,
    output logic [15:0] read_data,
    output logic        completion_valid,
    input  logic        completion_ready,
    output logic [7:0]  completion_tag,
    output logic [15:0] completion_words,
    output logic        completion_error,
    output logic [24:0] p0_addr,
    output logic        p0_rd_req,
    output logic        p0_end_burst_req,
    input  logic [15:0] p0_q,
    input  logic        p0_available,
    input  logic        p0_ready,
    input  logic        p0_data_available
);
    typedef enum logic [3:0] { IDLE, FETCH_WAIT, FETCH_PULSE, FETCH,
                               FETCH_DONE, SERVE_PRIME, SERVE_WAIT, SERVE,
                               COMPLETE } state_t;
    state_t state;
    // One physical 2048-word cache RAM rather than two independently inferred
    // page RAMs. Fetch and serve are globally exclusive, so this is a genuine
    // single-port memory and Quartus need not create read/write bypass logic.
    // no_rw_check is safe here: the FSM above makes capture and serve
    // mutually exclusive, so a read/write collision cannot occur. It prevents
    // Quartus 17 from adding a large defensive bypass network to this RAM.
    (* ramstyle = "M10K, no_rw_check" *) logic [15:0] page_memory [0:2047];
    logic page0_valid, page1_valid, fetch_buffer, serve_buffer;
    logic [14:0] page0_number, page1_number, request_page_q;
    logic [14:0] incoming_page;
    logic [9:0] incoming_offset, request_offset_q, serve_index, fetch_index;
    logic [15:0] words_q;
    logic [7:0] tag_q;
    logic error_q, read_valid_q, native_fetch_done;
    logic [15:0] page_read_data;
    logic request_fits_page, cache_hit0, cache_hit1;
    localparam logic [9:0] P0_END_FETCH_INDEX =
        10'd1023 - P0_DATA_PIPELINE_STAGES;

    assign incoming_page = req_byte_address[25:11];
    assign incoming_offset = req_byte_address[10:1];
    assign request_fits_page = (req_words != 16'd0) &&
                               ({1'b0, incoming_offset} + req_words <= 17'd1024);
    assign cache_hit0 = page0_valid && page0_number == incoming_page;
    assign cache_hit1 = page1_valid && page1_number == incoming_page;
    assign req_ready = init_done && state == IDLE;
    assign p0_addr = {request_page_q, 10'b0};
    assign p0_rd_req = state == FETCH_PULSE;
    // Ask the controller to stop early enough for its final output cycles to
    // drain through every response-latency stage. The cache still stores all
    // 1024 words before declaring the fetched page valid.
    assign p0_end_burst_req = state == FETCH && p0_data_available &&
                              fetch_index == P0_END_FETCH_INDEX;
    assign read_valid = read_valid_q;
    assign completion_valid = state == COMPLETE;
    assign completion_tag = tag_q;
    assign completion_words = words_q;
    assign completion_error = error_q;

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            page0_valid <= 1'b0;
            page1_valid <= 1'b0;
            fetch_buffer <= 1'b0;
            serve_buffer <= 1'b0;
            page0_number <= '0;
            page1_number <= '0;
            request_page_q <= '0;
            request_offset_q <= '0;
            serve_index <= '0;
            fetch_index <= '0;
            words_q <= '0;
            tag_q <= '0;
            error_q <= 1'b0;
            read_valid_q <= 1'b0;
            native_fetch_done <= 1'b0;
            read_data <= '0;
            page_read_data <= '0;
        end else begin
            // p0_ready is a one-cycle pulse from the native controller. With a
            // registered PHY, it can arrive while the last SDRAM words are still
            // moving through the DQ/valid pipeline. Remember it until those words
            // have reached page_memory and FETCH_DONE can consume it.
            if (state == FETCH && p0_ready)
                native_fetch_done <= 1'b1;

            if (state == FETCH && p0_data_available) begin
                page_memory[{fetch_buffer, fetch_index}] <= p0_q;
                fetch_index <= fetch_index + 1'b1;
            end else if (state == SERVE_PRIME || state == SERVE_WAIT ||
                         state == SERVE) begin
                // A page is either captured or served, never both. This
                // synchronous, mutually exclusive port use avoids Quartus's
                // read-during-write M10K bypass logic.
                page_read_data <= page_memory[{serve_buffer, serve_index}];
            end

            case (state)
                IDLE: if (req_valid && req_ready) begin
                    request_page_q <= incoming_page;
                    request_offset_q <= incoming_offset;
                    words_q <= req_words;
                    tag_q <= req_tag;
                    error_q <= req_write || req_byte_address[0] || !request_fits_page;
                    if (req_write || req_byte_address[0] || !request_fits_page) begin
                        state <= COMPLETE;
                    end else if (cache_hit0 || cache_hit1) begin
                        serve_buffer <= cache_hit1;
                        serve_index <= incoming_offset;
                        state <= SERVE_PRIME;
                    end else begin
                        // Prefer an empty page. Otherwise replace page zero;
                        // a later prefetch step will make eviction policy explicit.
                        fetch_buffer <= page0_valid && !page1_valid;
                        fetch_index <= '0;
                        native_fetch_done <= 1'b0;
                        state <= FETCH_WAIT;
                    end
                end
                FETCH_WAIT: if (p0_available) state <= FETCH_PULSE;
                FETCH_PULSE: state <= FETCH;
                FETCH: if (p0_data_available && fetch_index == 10'h3ff)
                    state <= FETCH_DONE;
                FETCH_DONE: if (p0_ready || native_fetch_done) begin
                    native_fetch_done <= 1'b0;
                    if (fetch_buffer) begin
                        page1_valid <= 1'b1;
                        page1_number <= request_page_q;
                    end else begin
                        page0_valid <= 1'b1;
                        page0_number <= request_page_q;
                    end
                    serve_buffer <= fetch_buffer;
                    serve_index <= request_offset_q;
                    state <= SERVE_PRIME;
                end
                SERVE_PRIME: begin
                    state <= SERVE_WAIT;
                end
                SERVE_WAIT: begin
                    read_data <= page_read_data;
                    read_valid_q <= 1'b1;
                    state <= SERVE;
                end
                SERVE: if (read_valid_q && read_ready) begin
                    if (serve_index + 1'b1 == request_offset_q + words_q) begin
                        read_valid_q <= 1'b0;
                        state <= COMPLETE;
                    end else begin
                        serve_index <= serve_index + 1'b1;
                        read_valid_q <= 1'b0;
                        state <= SERVE_PRIME;
                    end
                end
                COMPLETE: if (completion_ready) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
