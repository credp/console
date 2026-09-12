module sdram_single_client_adapter #(
    parameter integer LEN_WIDTH = 16,
    parameter integer TAG_WIDTH = 8,
    parameter integer MAX_REQUEST_WORDS = 256,
    parameter integer MAPPING = 5
) (
    input  logic                 clk,
    input  logic                 reset,

    input  logic                 req_valid,
    output logic                 req_ready,
    input  logic                 req_write,
    input  logic [26:0]          req_byte_address,
    input  logic [LEN_WIDTH-1:0] req_words,
    input  logic [TAG_WIDTH-1:0] req_tag,

    input  logic                 write_valid,
    output logic                 write_ready,
    input  logic [15:0]          write_data,
    input  logic [1:0]           write_byte_enable,

    output logic                 read_valid,
    input  logic                 read_ready,
    output logic [15:0]          read_data,

    output logic                 completion_valid,
    input  logic                 completion_ready,
    output logic [TAG_WIDTH-1:0] completion_tag,
    output logic [LEN_WIDTH-1:0] completion_words,
    output logic                 completion_error,

    // Atomic physical-operation interface to sdram_runtime_core.
    output logic                 op_valid,
    input  logic                 op_ready,
    output logic                 op_write,
    output logic                 op_chip,
    output logic [1:0]           op_bank,
    output logic [12:0]          op_row,
    output logic [9:0]           op_column,
    output logic [127:0]         op_write_data,
    output logic [15:0]          op_write_byte_enable,
    input  logic [127:0]         op_read_data,
    input  logic                 op_read_data_valid,
    input  logic                 op_completion_valid,
    output logic                 op_completion_ready
);
    localparam integer COUNT_BITS = (MAX_REQUEST_WORDS > 1) ?
                                    $clog2(MAX_REQUEST_WORDS + 1) : 1;
    typedef enum logic [2:0] {IDLE,LOAD_WRITE,ISSUE,WAIT_WRITE,
                              WAIT_READ,COMPLETE} state_t;
    state_t state;

    logic [15:0] packet_data [0:7];
    logic [1:0] packet_enable [0:7];
    logic [2:0] packet_index;
    logic [LEN_WIDTH-1:0] request_words_q;
    logic error_q;
    logic [TAG_WIDTH-1:0] tag_q;
    logic [3:0] current_words;
    logic current_last;
    logic [2:0] read_beat;
    logic valid_request;

    logic split_req_valid,split_req_ready,split_op_valid,split_op_ready;
    logic split_op_write,split_op_last;
    logic [26:0] split_op_address;
    logic [3:0] split_op_words;
    /* verilator lint_off UNUSEDSIGNAL */
    logic decoded_byte_select;
    logic [10:0] decoded_contiguous;
    /* verilator lint_on UNUSEDSIGNAL */
    integer payload_index;

    assign valid_request = (req_words != 0) &&
                           (req_words <= LEN_WIDTH'(MAX_REQUEST_WORDS)) &&
                           !req_byte_address[0];
    assign req_ready = (state == IDLE) && split_req_ready;
    assign split_req_valid = req_valid && req_ready && valid_request;
    assign write_ready = (state == LOAD_WRITE) && split_op_valid &&
                         ({1'b0, packet_index} < split_op_words);
    assign completion_valid = (state == COMPLETE);
    assign completion_tag = tag_q;
    // "completed words" means words committed by a successful request.  A
    // rejected request has not touched SDRAM, so it reports zero.
    assign completion_words = error_q ? '0 : request_words_q;
    assign completion_error = error_q;

    assign op_valid = (state == ISSUE) && split_op_valid;
    assign split_op_ready = op_valid && op_ready;
    assign op_write = split_op_write;

    sdram_request_splitter #(.LEN_WIDTH(LEN_WIDTH),.BURST_WORDS(8),.MAPPING(MAPPING)) splitter (
        .clk,.reset,.req_valid(split_req_valid),.req_ready(split_req_ready),
        .req_write,.req_byte_address,.req_words,
        .op_valid(split_op_valid),.op_ready(split_op_ready),.op_write(split_op_write),
        .op_byte_address(split_op_address),.op_words(split_op_words),.op_last(split_op_last)
    );

    sdram_addr_decode #(.MAPPING(MAPPING)) decode (
        .byte_address(split_op_address),.chip(op_chip),.bank(op_bank),.row(op_row),
        .column(op_column),.byte_select(decoded_byte_select),
        .contiguous_words(decoded_contiguous)
    );

    always_comb begin
        op_write_data = '0;
        op_write_byte_enable = '0;
        for (payload_index = 0; payload_index < 8; payload_index = payload_index + 1) begin
            if (payload_index < current_words) begin
                op_write_data[payload_index*16 +: 16] =
                    packet_data[payload_index];
                op_write_byte_enable[payload_index*2 +: 2] =
                    packet_enable[payload_index];
            end
        end
    end

    assign read_valid = (state == WAIT_READ) && op_read_data_valid;
    assign read_data = op_read_data[read_beat*16 +: 16];
    always_comb begin
        op_completion_ready = 1'b0;
        if (state == WAIT_WRITE)
            op_completion_ready = 1'b1;
        else if (state == WAIT_READ && op_read_data_valid &&
                 read_valid && read_ready && read_beat + 1'b1 == current_words)
            op_completion_ready = 1'b1;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            packet_index <= '0;
            request_words_q <= '0;
            tag_q <= '0;
            error_q <= 1'b0;
            current_words <= '0;
            current_last <= 1'b0;
            read_beat <= '0;
        end else begin
            case (state)
                IDLE: if (req_valid && req_ready) begin
                    request_words_q <= req_words;
                    tag_q <= req_tag;
                    error_q <= !valid_request;
                    packet_index <= '0;
                    if (!valid_request) state <= COMPLETE;
                    else if (req_write) state <= LOAD_WRITE;
                    else state <= ISSUE;
                end
                LOAD_WRITE: begin
                    if (split_op_valid && packet_index == '0) begin
                        packet_enable[0] <= '0;
                        packet_enable[1] <= '0;
                        packet_enable[2] <= '0;
                        packet_enable[3] <= '0;
                        packet_enable[4] <= '0;
                        packet_enable[5] <= '0;
                        packet_enable[6] <= '0;
                        packet_enable[7] <= '0;
                    end
                    if (write_valid && write_ready) begin
                        packet_data[packet_index] <= write_data;
                        packet_enable[packet_index] <= write_byte_enable;
                        if ({1'b0, packet_index} + 4'd1 == split_op_words) begin
                            current_words <= split_op_words;
                            current_last <= split_op_last;
                            packet_index <= '0;
                            state <= ISSUE;
                        end else packet_index <= packet_index + 1'b1;
                    end
                end
                ISSUE: if (op_valid && op_ready) begin
                    if (split_op_write) begin
                        state <= WAIT_WRITE;
                    end else begin
                        current_words <= split_op_words;
                        current_last <= split_op_last;
                        read_beat <= '0;
                        state <= WAIT_READ;
                    end
                end
                WAIT_WRITE: if (op_completion_valid && op_completion_ready)
                    state <= current_last ? COMPLETE : LOAD_WRITE;
                WAIT_READ: if (read_valid && read_ready) begin
                    if (read_beat + 1'b1 == current_words) begin
                        read_beat <= '0;
                        state <= current_last ? COMPLETE : ISSUE;
                    end else read_beat <= read_beat + 1'b1;
                end
                COMPLETE: if (completion_valid && completion_ready)
                    state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end

`ifdef FORMAL
    logic f_past_valid = 1'b0;
    always_ff @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (!reset) begin
            assert(packet_index < 8);
            if (state == ISSUE) begin
                assert(split_op_words >= 1 && split_op_words <= 8);
                assert(!decoded_byte_select);
            end
            if (read_valid) assert(read_beat < current_words);
            if (f_past_valid && !$past(reset) && $past(read_valid && !read_ready)) begin
                assert(read_valid);
                assert(read_data == $past(read_data));
            end
            if (f_past_valid && !$past(reset) &&
                $past(completion_valid && !completion_ready)) begin
                assert(completion_valid);
                assert(completion_tag == $past(completion_tag));
                assert(completion_words == $past(completion_words));
                assert(completion_error == $past(completion_error));
            end
        end
    end
`endif

    initial begin
        if (MAX_REQUEST_WORDS < 8) $error("MAX_REQUEST_WORDS must be at least 8");
        if ((1 << COUNT_BITS) <= MAX_REQUEST_WORDS)
            $error("request counter must represent MAX_REQUEST_WORDS");
    end
endmodule
