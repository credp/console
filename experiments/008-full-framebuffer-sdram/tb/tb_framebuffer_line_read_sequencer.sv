`timescale 1ns/1ps

module tb_framebuffer_line_read_sequencer;
    localparam integer TEST_WIDTH = 8;
    localparam integer TEST_CHUNK_WORDS = 4;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start_line_valid;
    logic start_line_ready;
    logic [9:0] start_line_y;
    logic fill_valid;
    logic fill_ready;
    logic [15:0] fill_pixel;
    logic [9:0] fill_line_y;
    logic req_valid;
    logic req_ready;
    logic req_write;
    logic [26:0] req_byte_address;
    logic [15:0] req_words;
    logic [7:0] req_tag;
    logic read_valid;
    logic read_ready;
    logic [15:0] read_data;
    logic completion_valid;
    logic completion_ready;
    logic [7:0] completion_tag;
    logic [15:0] completion_words;
    logic completion_error;
    logic busy;
    logic line_done;
    logic error;

    integer chunk_index;
    integer word_index;
    integer stall_once;
    logic [15:0] expected_word;

    always #5 clk = !clk;

    framebuffer_line_read_sequencer #(
        .FRAMEBUFFER_WIDTH(TEST_WIDTH),
        .READ_CHUNK_WORDS(TEST_CHUNK_WORDS)
    ) dut (
        .clk(clk),
        .reset(reset),
        .start_line_valid(start_line_valid),
        .start_line_ready(start_line_ready),
        .start_line_y(start_line_y),
        .fill_valid(fill_valid),
        .fill_ready(fill_ready),
        .fill_pixel(fill_pixel),
        .fill_line_y(fill_line_y),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_write(req_write),
        .req_byte_address(req_byte_address),
        .req_words(req_words),
        .req_tag(req_tag),
        .read_valid(read_valid),
        .read_ready(read_ready),
        .read_data(read_data),
        .completion_valid(completion_valid),
        .completion_ready(completion_ready),
        .completion_tag(completion_tag),
        .completion_words(completion_words),
        .completion_error(completion_error),
        .busy(busy),
        .line_done(line_done),
        .error(error)
    );

    task automatic start_line(input logic [9:0] line_y);
        begin
            wait(start_line_ready);
            @(negedge clk);
            start_line_y = line_y;
            start_line_valid = 1'b1;
            @(posedge clk);
            #1;
            start_line_valid = 1'b0;
        end
    endtask

    task automatic accept_request(input integer expected_chunk);
        logic [26:0] expected_address;
        logic [7:0] expected_tag;
        begin
            expected_address = 27'((3 * TEST_WIDTH + expected_chunk * TEST_CHUNK_WORDS) * 2);
            expected_tag = {1'b0, 7'(expected_chunk)};
            wait(req_valid);
            if (req_write || req_words != TEST_CHUNK_WORDS ||
                req_byte_address != expected_address || req_tag != expected_tag) begin
                $fatal(1, "bad read request chunk=%0d write=%b addr=%0d words=%0d tag=%h",
                       expected_chunk, req_write, req_byte_address, req_words, req_tag);
            end
            @(negedge clk);
            req_ready = 1'b1;
            @(posedge clk);
            #1;
            req_ready = 1'b0;
        end
    endtask

    task automatic send_chunk_words(input integer expected_chunk);
        begin
            word_index = 0;
            stall_once = 0;
            while (word_index < TEST_CHUNK_WORDS) begin
                @(negedge clk);
                expected_word = 16'h7000 + 16'(expected_chunk * TEST_CHUNK_WORDS + word_index);
                read_data = expected_word;
                read_valid = 1'b1;
                if (word_index == 1 && !stall_once) begin
                    fill_ready = 1'b0;
                    stall_once = 1;
                end else begin
                    fill_ready = 1'b1;
                end

                #1;
                if (read_valid && read_ready) begin
                    if (!fill_valid || fill_pixel !== expected_word || fill_line_y != 10'd3) begin
                        $fatal(1, "bad fill stream word=%0d fill_valid=%b pixel=%h expected=%h y=%0d",
                               word_index, fill_valid, fill_pixel, expected_word, fill_line_y);
                    end
                    word_index = word_index + 1;
                end
                @(posedge clk);
                #1;
                if (read_valid && read_ready) read_valid = 1'b0;
            end
            @(negedge clk);
            read_valid = 1'b0;
            fill_ready = 1'b0;
        end
    endtask

    task automatic complete_chunk(input integer expected_chunk);
        begin
            wait(completion_ready);
            @(negedge clk);
            completion_tag = {1'b0, 7'(expected_chunk)};
            completion_words = TEST_CHUNK_WORDS;
            completion_error = 1'b0;
            completion_valid = 1'b1;
            @(posedge clk);
            #1;
            completion_valid = 1'b0;
        end
    endtask

    initial begin
        start_line_valid = 1'b0;
        start_line_y = 10'd0;
        req_ready = 1'b0;
        read_valid = 1'b0;
        read_data = 16'h0000;
        fill_ready = 1'b0;
        completion_valid = 1'b0;
        completion_tag = '0;
        completion_words = '0;
        completion_error = 1'b0;

        repeat (3) @(posedge clk);
        reset = 1'b0;

        start_line(10'd3);
        for (chunk_index = 0; chunk_index < TEST_WIDTH / TEST_CHUNK_WORDS; chunk_index = chunk_index + 1) begin
            accept_request(chunk_index);
            send_chunk_words(chunk_index);
            complete_chunk(chunk_index);
        end

        wait(line_done);
        @(posedge clk);
        #1;
        if (busy || error) begin
            $fatal(1, "reader finished with busy=%b error=%b", busy, error);
        end

        $display("PASS framebuffer_line_read_sequencer: chunked reads to fill stream");
        $finish;
    end

    initial begin
        repeat (1000) @(posedge clk);
        $fatal(1, "line read sequencer watchdog");
    end
endmodule
