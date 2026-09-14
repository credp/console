module line_ping_pong_capture #(
    parameter integer LINE_WORDS = 1280,
    parameter integer SOURCE_LINE_CYCLES = 4096,
    parameter integer ADDR_WIDTH = 11,
    parameter integer MAX_REQUEST_WORDS = 1280,
    parameter integer DRAIN_WARN_CYCLES = 4095
) (
    input  logic        clk_source,
    input  logic        reset_source,
    input  logic        clk_video,
    input  logic        reset_video,

    input  logic [10:0] video_x,
    input  logic [9:0]  video_y,
    input  logic        video_de,
    output logic [15:0] video_pixel,
    output logic        video_buffer,

    output logic        req_valid,
    input  logic        req_ready,
    output logic        req_write,
    output logic [26:0] req_byte_address,
    output logic [15:0] req_words,
    output logic [7:0]  req_tag,

    output logic        write_valid,
    input  logic        write_ready,
    output logic [15:0] write_data,
    output logic [1:0]  write_byte_enable,

    input  logic        completion_valid,
    output logic        completion_ready,
    input  logic [7:0]  completion_tag,
    input  logic [15:0] completion_words,
    input  logic        completion_error,

    output logic [31:0] source_lines_generated,
    output logic [31:0] sdram_lines_submitted,
    output logic [31:0] sdram_lines_completed,
    output logic        reuse_before_drain_error,
    output logic [15:0] worst_line_drain_cycles,
    output logic [15:0] current_line_drain_cycles
);
    localparam integer CHUNKS_PER_LINE = LINE_WORDS / MAX_REQUEST_WORDS;
    localparam integer CHUNK_WORDS = MAX_REQUEST_WORDS;
    localparam integer CHUNK_INDEX_WIDTH = (CHUNKS_PER_LINE > 1) ? $clog2(CHUNKS_PER_LINE) : 1;

    initial begin
        if (LINE_WORDS != 1280) $fatal(1, "experiment 007 expects 1280-word lines");
        if ((LINE_WORDS % MAX_REQUEST_WORDS) != 0) $fatal(1, "line must split evenly");
        if (CHUNKS_PER_LINE > 128) $fatal(1, "tag format only leaves 7 bits for chunk");
    end

    logic fill_sel;
    logic line_valid_video;
    logic [1:0] pending_drain_video;
    logic [1:0] pending_drain;
    logic [15:0] drain_cycles [0:1];
    logic completed_toggle_video;
    logic completed_toggle_meta;
    logic completed_toggle_source;
    logic completed_toggle_source_prev;
    logic completed_buffer_video;
    logic completed_buffer_meta;
    logic completed_buffer_source;
    logic [9:0] completed_y_video;
    logic [9:0] completed_y_meta;
    logic [9:0] completed_y_source;
    logic [9:0] completed_y [0:1];
    logic [1:0] drain_done_toggle_source;
    logic [1:0] drain_done_toggle_meta;
    logic [1:0] drain_done_toggle_video;
    logic [1:0] drain_done_toggle_video_prev;
    logic cap_error_toggle_source;
    logic cap_error_toggle_meta;
    logic cap_error_toggle_video;
    logic cap_error_toggle_video_prev;
    logic display_sel_q;
    logic newest_display_buffer;

    typedef enum logic [1:0] {CAP_IDLE, CAP_REQ, CAP_WRITE, CAP_WAIT_COMPLETE} cap_state_t;
    cap_state_t cap_state;
    logic capture_sel;
    logic [9:0] cap_line_y;
    logic [CHUNK_INDEX_WIDTH-1:0] cap_chunk;
    wire [6:0] cap_chunk_tag = 7'(cap_chunk);
    logic [ADDR_WIDTH-1:0] cap_word;
    logic [15:0] cap_read_data;
    logic [15:0] cap_drain_cycles;
    logic source_line_accepted;
    wire source_active;
    wire fill_last;
    wire [ADDR_WIDTH-1:0] source_x;
    wire [9:0] source_y;
    wire [15:0] source_pixel;

    line_ping_pong_generated_source #(
        .LINE_WORDS(LINE_WORDS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) source (
        .clk(clk_video),
        .reset(reset_video),
        .video_x(video_x),
        .video_y(video_y),
        .accept_line(source_line_accepted),
        .source_active(source_active),
        .source_line_done(fill_last),
        .source_x(source_x),
        .source_y(source_y),
        .source_pixel(source_pixel)
    );

    wire [ADDR_WIDTH-1:0] video_addr = video_x[ADDR_WIDTH-1:0];
    logic [ADDR_WIDTH-1:0] cap_read_addr;
    wire [15:0] line0_cap_data;
    wire [15:0] line1_cap_data;
    wire [15:0] line0_video_data;
    wire [15:0] line1_video_data;
    //wire display_sel = !fill_sel;
    logic display_sel;
    wire line0_video_we = source_active && fill_sel == 1'b0;
    wire line1_video_we = source_active && fill_sel == 1'b1;
    wire line0_video_read = display_sel == 1'b0;
    wire [ADDR_WIDTH-1:0] line0_video_addr = video_addr;
    wire [ADDR_WIDTH-1:0] line1_video_addr = video_addr;

    line_ping_pong_line_buffer #(.LINE_WORDS(LINE_WORDS), .ADDR_WIDTH(ADDR_WIDTH)) line0_buffer (
        .clk_video(clk_video),
        .video_we(line0_video_we),
        .video_addr(line0_video_addr),
        .video_wdata(source_pixel),
        .video_rdata(line0_video_data),
        .clk_capture(clk_source),
        .capture_addr(cap_read_addr),
        .capture_rdata(line0_cap_data)
    );

    line_ping_pong_line_buffer #(.LINE_WORDS(LINE_WORDS), .ADDR_WIDTH(ADDR_WIDTH)) line1_buffer (
        .clk_video(clk_video),
        .video_we(line1_video_we),
        .video_addr(line1_video_addr),
        .video_wdata(source_pixel),
        .video_rdata(line1_video_data),
        .clk_capture(clk_source),
        .capture_addr(cap_read_addr),
        .capture_rdata(line1_cap_data)
    );

    always_ff @(posedge clk_video) begin
        if (reset_video) begin
            fill_sel <= 1'b0;
            line_valid_video <= 1'b0;
            pending_drain_video <= '0;
            drain_done_toggle_meta <= '0;
            drain_done_toggle_video <= '0;
            drain_done_toggle_video_prev <= '0;
            completed_toggle_video <= 1'b0;
            completed_buffer_video <= 1'b0;
            completed_y_video <= '0;
            source_lines_generated <= '0;
            cap_error_toggle_meta <= 1'b0;
            cap_error_toggle_video <= 1'b0;
            cap_error_toggle_video_prev <= 1'b0;
            reuse_before_drain_error <= 1'b0;
            video_pixel <= 16'h0000;
            video_buffer <= 1'b0;
            display_sel_q <= 1'b0;
            newest_display_buffer <= 1'b0;
            source_line_accepted <= 1'b0;
        end else begin
            source_line_accepted <= 1'b0;
            drain_done_toggle_meta <= drain_done_toggle_source;
            drain_done_toggle_video <= drain_done_toggle_meta;
            cap_error_toggle_meta <= cap_error_toggle_source;
            cap_error_toggle_video <= cap_error_toggle_meta;

            if (drain_done_toggle_video[0] != drain_done_toggle_video_prev[0])
                pending_drain_video[0] <= 1'b0;
            if (drain_done_toggle_video[1] != drain_done_toggle_video_prev[1])
                pending_drain_video[1] <= 1'b0;
            drain_done_toggle_video_prev <= drain_done_toggle_video;

            if (cap_error_toggle_video != cap_error_toggle_video_prev)
                reuse_before_drain_error <= 1'b1;
            cap_error_toggle_video_prev <= cap_error_toggle_video;

            if (source_active && pending_drain_video[fill_sel])
                reuse_before_drain_error <= 1'b1;

            display_sel <= display_sel_q;

            if (fill_last) begin
                if (!pending_drain_video[!fill_sel]) begin
                    source_line_accepted <= 1'b1;
                    source_lines_generated <= source_lines_generated + 1'b1;
                    line_valid_video <= 1'b1;
                    pending_drain_video[fill_sel] <= 1'b1;
                    completed_buffer_video <= fill_sel;
                    completed_y_video <= source_y;
                    completed_toggle_video <= !completed_toggle_video;
                    newest_display_buffer <= fill_sel;
                    fill_sel <= !fill_sel;
                end
            end

            if (video_x == 0) begin
                display_sel_q <= newest_display_buffer;
            end

            if (video_de && video_x < 11'd1280 && video_y < 10'd720 && line_valid_video) begin
                if (line0_video_read) video_pixel <= line0_video_data;
                else video_pixel <= line1_video_data;
            end else begin
                video_pixel <= 16'h0000;
            end
            video_buffer <= display_sel;
        end
    end

    assign req_write = 1'b1;
    assign req_byte_address = ((27'(cap_line_y) * 27'(LINE_WORDS)) +
                               (27'(cap_chunk) * 27'(CHUNK_WORDS))) << 1;
    assign req_words = 16'(CHUNK_WORDS);
    assign req_tag = {capture_sel, cap_chunk_tag};
    assign write_byte_enable = 2'b11;
    assign completion_ready = 1'b1;

    always_comb begin
        req_valid = (cap_state == CAP_REQ);
        write_valid = (cap_state == CAP_WRITE);
        write_data = cap_read_data;
    end

    always_ff @(posedge clk_source) begin
        if (reset_source) begin
            completed_toggle_meta <= 1'b0;
            completed_toggle_source <= 1'b0;
            completed_toggle_source_prev <= 1'b0;
            completed_buffer_meta <= 1'b0;
            completed_buffer_source <= 1'b0;
            completed_y_meta <= '0;
            completed_y_source <= '0;
            pending_drain <= '0;
            drain_cycles[0] <= '0;
            drain_cycles[1] <= '0;
            completed_y[0] <= '0;
            completed_y[1] <= '0;
            cap_state <= CAP_IDLE;
            capture_sel <= 1'b0;
            cap_line_y <= '0;
            cap_chunk <= '0;
            cap_word <= '0;
            cap_read_addr <= '0;
            cap_read_data <= '0;
            cap_drain_cycles <= '0;
            sdram_lines_submitted <= '0;
            sdram_lines_completed <= '0;
            drain_done_toggle_source <= '0;
            cap_error_toggle_source <= 1'b0;
            worst_line_drain_cycles <= '0;
            current_line_drain_cycles <= '0;
        end else begin
            completed_toggle_meta <= completed_toggle_video;
            completed_toggle_source <= completed_toggle_meta;
            completed_buffer_meta <= completed_buffer_video;
            completed_buffer_source <= completed_buffer_meta;
            completed_y_meta <= completed_y_video;
            completed_y_source <= completed_y_meta;

            if (completed_toggle_source != completed_toggle_source_prev) begin
                pending_drain[completed_buffer_source] <= 1'b1;
                drain_cycles[completed_buffer_source] <= '0;
                completed_y[completed_buffer_source] <= completed_y_source;
            end
            completed_toggle_source_prev <= completed_toggle_source;

            if (pending_drain[0] && drain_cycles[0] != 16'hffff) drain_cycles[0] <= drain_cycles[0] + 1'b1;
            if (pending_drain[1] && drain_cycles[1] != 16'hffff) drain_cycles[1] <= drain_cycles[1] + 1'b1;

            case (cap_state)
                CAP_IDLE: begin
                    cap_drain_cycles <= '0;
                    cap_chunk <= '0;
                    cap_word <= '0;
                    if (pending_drain[0]) begin
                        capture_sel <= 1'b0;
                        cap_line_y <= completed_y[0];
                        cap_state <= CAP_REQ;
                        sdram_lines_submitted <= sdram_lines_submitted + 1'b1;
                    end else if (pending_drain[1]) begin
                        capture_sel <= 1'b1;
                        cap_line_y <= completed_y[1];
                        cap_state <= CAP_REQ;
                        sdram_lines_submitted <= sdram_lines_submitted + 1'b1;
                    end
                end
                CAP_REQ: begin
                    cap_drain_cycles <= cap_drain_cycles + 1'b1;
                    if (req_valid && req_ready) begin
                        cap_word <= '0;
                        cap_read_addr <= ADDR_WIDTH'(cap_chunk * CHUNK_WORDS);
                        cap_state <= CAP_WRITE;
                    end
                end
                CAP_WRITE: begin
                    cap_drain_cycles <= cap_drain_cycles + 1'b1;
                    cap_read_data <= capture_sel ? line1_cap_data : line0_cap_data;
                    if (write_valid && write_ready) begin
                        if (cap_word == ADDR_WIDTH'(CHUNK_WORDS - 1)) begin
                            cap_word <= '0;
                            cap_state <= CAP_WAIT_COMPLETE;
                        end else begin
                            cap_word <= cap_word + 1'b1;
                            cap_read_addr <= ADDR_WIDTH'(cap_chunk * CHUNK_WORDS) + cap_word + 1'b1;
                        end
                    end
                end
                CAP_WAIT_COMPLETE: begin
                    cap_drain_cycles <= cap_drain_cycles + 1'b1;
                    if (completion_valid && completion_ready) begin
                        if (completion_error || completion_words != 16'(CHUNK_WORDS) ||
                            completion_tag != {capture_sel, cap_chunk_tag}) begin
                            cap_error_toggle_source <= !cap_error_toggle_source;
                        end
                        if (cap_chunk == CHUNK_INDEX_WIDTH'(CHUNKS_PER_LINE - 1)) begin
                            pending_drain[capture_sel] <= 1'b0;
                            drain_done_toggle_source[capture_sel] <= !drain_done_toggle_source[capture_sel];
                            sdram_lines_completed <= sdram_lines_completed + 1'b1;
                            current_line_drain_cycles <= cap_drain_cycles;
                            if (cap_drain_cycles > worst_line_drain_cycles)
                                worst_line_drain_cycles <= cap_drain_cycles;
                            cap_state <= CAP_IDLE;
                        end else begin
                            cap_chunk <= cap_chunk + 1'b1;
                            cap_state <= CAP_REQ;
                        end
                    end
                end
                default: cap_state <= CAP_IDLE;
            endcase

            if (cap_drain_cycles > 16'(DRAIN_WARN_CYCLES))
                cap_error_toggle_source <= !cap_error_toggle_source;
        end
    end
endmodule

module line_ping_pong_generated_source #(
    parameter integer LINE_WORDS = 1280,
    parameter integer ADDR_WIDTH = 11
) (
    input  logic                  clk,
    input  logic                  reset,
    input  logic [10:0]           video_x,
    input  logic [9:0]            video_y,
    input  logic                  accept_line,
    output logic                  source_active,
    output logic                  source_line_done,
    output logic [ADDR_WIDTH-1:0] source_x,
    output logic [9:0]            source_y,
    output logic [15:0]           source_pixel
);
    logic [15:0] frame_number;

    always_ff @(posedge clk) begin
        if (reset) begin
            source_y <= '0;
            frame_number <= '0;
        end else if (accept_line) begin
            if (source_y == 10'd719) begin
                source_y <= '0;
                frame_number <= frame_number + 1'b1;
            end else begin
                source_y <= source_y + 1'b1;
            end
        end
    end

    always_comb begin
        source_active = (video_x < 11'(LINE_WORDS)) && (video_y < 10'd720);
        source_line_done = (video_x == 11'(LINE_WORDS - 1)) && (video_y < 10'd720);
        source_x = video_x[ADDR_WIDTH-1:0];
        source_pixel = {
//            video_x[10:6] + frame_number[4:0],
//            video_y[8:3] ^ frame_number[5:0],
//            video_x[5:1] ^ video_y[7:3]
            source_x[7:0],
            source_y[7:0],
            frame_number[7:0]
        };
    end
endmodule

module line_ping_pong_line_buffer #(
    parameter integer LINE_WORDS = 1280,
    parameter integer ADDR_WIDTH = 11
) (
    input  logic                  clk_video,
    input  logic                  video_we,
    input  logic [ADDR_WIDTH-1:0] video_addr,
    input  logic [15:0]           video_wdata,
    output logic [15:0]           video_rdata,
    input  logic                  clk_capture,
    input  logic [ADDR_WIDTH-1:0] capture_addr,
    output logic [15:0]           capture_rdata
);
`ifdef VERILATOR
    `define LINE_PING_PONG_BEHAVIORAL_RAM
`endif
`ifdef SIMULATION
    `define LINE_PING_PONG_BEHAVIORAL_RAM
`endif

`ifdef LINE_PING_PONG_BEHAVIORAL_RAM
    (* ramstyle = "M10K" *) logic [15:0] mem [0:LINE_WORDS-1];

    always_ff @(posedge clk_video) begin
        if (video_we) mem[video_addr] <= video_wdata;
        video_rdata <= mem[video_addr];
    end

    always_ff @(posedge clk_capture) begin
        capture_rdata <= mem[capture_addr];
    end
`else
    altsyncram line_ram (
        .clock0(clk_video),
        .address_a(video_addr),
        .data_a(video_wdata),
        .wren_a(video_we),
        .q_a(video_rdata),

        .clock1(clk_capture),
        .address_b(capture_addr),
        .data_b(16'h0000),
        .wren_b(1'b0),
        .q_b(capture_rdata),

        .aclr0(1'b0),
        .aclr1(1'b0),
        .addressstall_a(1'b0),
        .addressstall_b(1'b0),
        .byteena_a(1'b1),
        .byteena_b(1'b1),
        .clocken0(1'b1),
        .clocken1(1'b1),
        .clocken2(1'b1),
        .clocken3(1'b1),
        .eccstatus(),
        .rden_a(1'b1),
        .rden_b(1'b1)
    );
    defparam
        line_ram.numwords_a = LINE_WORDS,
        line_ram.widthad_a = ADDR_WIDTH,
        line_ram.width_a = 16,
        line_ram.numwords_b = LINE_WORDS,
        line_ram.widthad_b = ADDR_WIDTH,
        line_ram.width_b = 16,
        line_ram.address_reg_b = "CLOCK1",
        line_ram.clock_enable_input_a = "BYPASS",
        line_ram.clock_enable_input_b = "BYPASS",
        line_ram.clock_enable_output_a = "BYPASS",
        line_ram.clock_enable_output_b = "BYPASS",
        line_ram.indata_reg_b = "CLOCK1",
        line_ram.intended_device_family = "Cyclone V",
        line_ram.lpm_type = "altsyncram",
        line_ram.operation_mode = "BIDIR_DUAL_PORT",
        line_ram.outdata_aclr_a = "NONE",
        line_ram.outdata_aclr_b = "NONE",
        line_ram.outdata_reg_a = "UNREGISTERED",
        line_ram.outdata_reg_b = "UNREGISTERED",
        line_ram.power_up_uninitialized = "FALSE",
        line_ram.ram_block_type = "M10K",
        line_ram.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
        line_ram.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
        line_ram.width_byteena_a = 1,
        line_ram.width_byteena_b = 1,
        line_ram.wrcontrol_wraddress_reg_b = "CLOCK1";
`endif
`undef LINE_PING_PONG_BEHAVIORAL_RAM
endmodule
