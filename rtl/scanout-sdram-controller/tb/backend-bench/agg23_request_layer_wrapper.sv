`timescale 1ns/1ps

module agg23_request_layer_wrapper #(
    parameter integer LEN_WIDTH = 16,
    parameter integer TAG_WIDTH = 32
) (
    input logic clk,
    input logic reset,

    input logic c0_req_valid,
    output logic c0_req_ready,
    input logic c0_req_write,
    input logic [26:0] c0_req_byte_address,
    input logic [LEN_WIDTH-1:0] c0_req_words,
    input logic [TAG_WIDTH-1:0] c0_req_tag,
    input logic c0_write_valid,
    output logic c0_write_ready,
    input logic [15:0] c0_write_data,
    input logic [1:0] c0_write_byte_enable,
    output logic c0_read_valid,
    input logic c0_read_ready,
    output logic [15:0] c0_read_data,
    output logic c0_completion_valid,
    input logic c0_completion_ready,
    output logic [TAG_WIDTH-1:0] c0_completion_tag,
    output logic [LEN_WIDTH-1:0] c0_completion_words,
    output logic c0_completion_error,

    input logic c1_req_valid,
    output logic c1_req_ready,
    input logic c1_req_write,
    input logic [26:0] c1_req_byte_address,
    input logic [LEN_WIDTH-1:0] c1_req_words,
    input logic [TAG_WIDTH-1:0] c1_req_tag,
    input logic c1_write_valid,
    output logic c1_write_ready,
    input logic [15:0] c1_write_data,
    input logic [1:0] c1_write_byte_enable,
    output logic c1_read_valid,
    input logic c1_read_ready,
    output logic [15:0] c1_read_data,
    output logic c1_completion_valid,
    input logic c1_completion_ready,
    output logic [TAG_WIDTH-1:0] c1_completion_tag,
    output logic [LEN_WIDTH-1:0] c1_completion_words,
    output logic c1_completion_error,

    output logic init_done,

    inout wire [15:0] SDRAM_DQ,
    output logic [12:0] SDRAM_A,
    output logic [1:0] SDRAM_DQM,
    output logic [1:0] SDRAM_BA,
    output logic SDRAM_nCS,
    output logic SDRAM_nWE,
    output logic SDRAM_nRAS,
    output logic SDRAM_nCAS,
    output logic SDRAM_CKE,
    output logic SDRAM_CLK
);
    typedef enum logic [2:0] {
        IDLE,
        LOAD_WRITE,
        WAIT_AVAILABLE,
        PULSE_NATIVE,
        WAIT_NATIVE,
        EMIT_READ,
        COMPLETE
    } state_t;

    state_t state;
    logic owner;
    logic round_robin;
    logic req_write_q;
    logic [26:0] address_q;
    logic [LEN_WIDTH-1:0] words_q;
    logic [LEN_WIDTH-1:0] word_index_q;
    logic [TAG_WIDTH-1:0] tag_q;
    logic [15:0] write_data_q;
    logic [1:0] byte_enable_q;
    logic error_q;

    logic [24:0] p0_addr;
    logic [15:0] p0_data;
    logic [1:0] p0_byte_en;
    logic [15:0] p0_q;
    logic p0_wr_req;
    logic p0_rd_req;
    logic p0_available;
    logic p0_ready;
    logic [27:0] native_byte_address;

    logic select_client;
    logic accept0;
    logic accept1;
    logic valid_request;

    assign valid_request = (select_client ? c1_req_words : c0_req_words) != '0 &&
                           !(select_client ? c1_req_byte_address[0] : c0_req_byte_address[0]);

    always_comb begin
        if (c0_req_valid && c1_req_valid)
            select_client = round_robin;
        else
            select_client = c1_req_valid;
    end

    assign c0_req_ready = init_done && state == IDLE && c0_req_valid && (!c1_req_valid || !select_client);
    assign c1_req_ready = init_done && state == IDLE && c1_req_valid && select_client;
    assign accept0 = c0_req_valid && c0_req_ready;
    assign accept1 = c1_req_valid && c1_req_ready;

    assign c0_write_ready = state == LOAD_WRITE && !owner;
    assign c1_write_ready = state == LOAD_WRITE && owner;
    assign c0_read_valid = state == EMIT_READ && !owner;
    assign c1_read_valid = state == EMIT_READ && owner;
    assign c0_read_data = p0_q;
    assign c1_read_data = p0_q;

    assign c0_completion_valid = state == COMPLETE && !owner;
    assign c1_completion_valid = state == COMPLETE && owner;
    assign c0_completion_tag = tag_q;
    assign c1_completion_tag = tag_q;
    assign c0_completion_words = words_q;
    assign c1_completion_words = words_q;
    assign c0_completion_error = error_q;
    assign c1_completion_error = error_q;

    assign native_byte_address = {1'b0, address_q} + {11'b0, word_index_q, 1'b0};
    assign p0_addr = native_byte_address[25:1];
    assign p0_data = write_data_q;
    assign p0_byte_en = byte_enable_q;
    assign p0_wr_req = state == PULSE_NATIVE && req_write_q;
    assign p0_rd_req = state == PULSE_NATIVE && !req_write_q;

    sdram #(
        .CLOCK_SPEED_MHZ(100),
        .BURST_LENGTH(1),
        .CAS_LATENCY(3),
        .P0_BURST_LENGTH(1)
    ) backend (
        .clk,
        .reset,
        .init_complete(init_done),
        .p0_addr,
        .p0_data,
        .p0_byte_en,
        .p0_q,
        .p0_wr_req,
        .p0_rd_req,
        .p0_available,
        .p0_ready,
        .SDRAM_DQ,
        .SDRAM_A,
        .SDRAM_DQM,
        .SDRAM_BA,
        .SDRAM_nCS,
        .SDRAM_nWE,
        .SDRAM_nRAS,
        .SDRAM_nCAS,
        .SDRAM_CKE,
        .SDRAM_CLK
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            owner <= 1'b0;
            round_robin <= 1'b0;
            req_write_q <= 1'b0;
            address_q <= '0;
            words_q <= '0;
            word_index_q <= '0;
            tag_q <= '0;
            write_data_q <= '0;
            byte_enable_q <= 2'b11;
            error_q <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (accept0 || accept1) begin
                        owner <= accept1;
                        round_robin <= accept0;
                        req_write_q <= accept1 ? c1_req_write : c0_req_write;
                        address_q <= accept1 ? c1_req_byte_address : c0_req_byte_address;
                        words_q <= accept1 ? c1_req_words : c0_req_words;
                        tag_q <= accept1 ? c1_req_tag : c0_req_tag;
                        byte_enable_q <= 2'b11;
                        word_index_q <= '0;
                        error_q <= !valid_request;
                        if (!valid_request)
                            state <= COMPLETE;
                        else if (accept1 ? c1_req_write : c0_req_write)
                            state <= LOAD_WRITE;
                        else
                            state <= WAIT_AVAILABLE;
                    end
                end
                LOAD_WRITE: begin
                    if ((!owner && c0_write_valid) || (owner && c1_write_valid)) begin
                        write_data_q <= owner ? c1_write_data : c0_write_data;
                        byte_enable_q <= owner ? c1_write_byte_enable : c0_write_byte_enable;
                        state <= WAIT_AVAILABLE;
                    end
                end
                WAIT_AVAILABLE: begin
                    if (p0_available)
                        state <= PULSE_NATIVE;
                end
                PULSE_NATIVE: begin
                    state <= WAIT_NATIVE;
                end
                WAIT_NATIVE: begin
                    if (p0_ready) begin
                        if (req_write_q) begin
                            if (word_index_q + 1'b1 == words_q)
                                state <= COMPLETE;
                            else begin
                                word_index_q <= word_index_q + 1'b1;
                                state <= LOAD_WRITE;
                            end
                        end else begin
                            state <= EMIT_READ;
                        end
                    end
                end
                EMIT_READ: begin
                    if ((!owner && c0_read_ready) || (owner && c1_read_ready)) begin
                        if (word_index_q + 1'b1 == words_q)
                            state <= COMPLETE;
                        else begin
                            word_index_q <= word_index_q + 1'b1;
                            state <= WAIT_AVAILABLE;
                        end
                    end
                end
                COMPLETE: begin
                    if ((!owner && c0_completion_ready) || (owner && c1_completion_ready))
                        state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
