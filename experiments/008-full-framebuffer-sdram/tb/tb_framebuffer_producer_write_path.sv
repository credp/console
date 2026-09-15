`timescale 1ns/1ps

module tb_framebuffer_producer_write_path;
    localparam integer TEST_WIDTH = 8;
    localparam integer TEST_HEIGHT = 4;
    localparam integer TEST_ADDR_WIDTH = 3;
    localparam integer TEST_CHUNK_WORDS = 4;

    logic clk = 1'b0;
    logic reset = 1'b1;

    logic req_valid;
    logic req_ready;
    logic req_write;
    logic [26:0] req_byte_address;
    logic [15:0] req_words;
    logic [7:0] req_tag;
    logic write_valid;
    logic write_ready;
    logic [15:0] write_data;
    logic [1:0] write_byte_enable;
    logic completion_valid;
    logic completion_ready;
    logic [7:0] completion_tag;
    logic [15:0] completion_words;
    logic completion_error;
    logic [10:0] producer_pixel_x;
    logic [9:0] producer_line_y;
    logic [7:0] producer_frame_index;
    logic producer_stalled_waiting_for_free_line;
    logic writer_busy;
    logic writer_error;

    integer line_index;
    integer chunk_index;
    integer word_index;
    integer stall_once;
    integer memory_index;
    integer current_write_word_address;
    logic expected_buffer;
    logic [15:0] expected;
    logic [15:0] framebuffer_memory [0:TEST_WIDTH*TEST_HEIGHT-1];

    always #5 clk = !clk;

    framebuffer_producer_write_path #(
        .FRAMEBUFFER_WIDTH(TEST_WIDTH),
        .FRAMEBUFFER_HEIGHT(TEST_HEIGHT),
        .LINE_ADDR_WIDTH(TEST_ADDR_WIDTH),
        .WRITE_CHUNK_WORDS(TEST_CHUNK_WORDS)
    ) dut (
        .clk(clk),
        .reset(reset),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_write(req_write),
        .req_byte_address(req_byte_address),
        .req_words(req_words),
        .req_tag(req_tag),
        .write_valid(write_valid),
        .write_ready(write_ready),
        .write_data(write_data),
        .write_byte_enable(write_byte_enable),
        .completion_valid(completion_valid),
        .completion_ready(completion_ready),
        .completion_tag(completion_tag),
        .completion_words(completion_words),
        .completion_error(completion_error),
        .producer_pixel_x(producer_pixel_x),
        .producer_line_y(producer_line_y),
        .producer_frame_index(producer_frame_index),
        .producer_stalled_waiting_for_free_line(producer_stalled_waiting_for_free_line),
        .writer_busy(writer_busy),
        .writer_error(writer_error)
    );

    function automatic logic [15:0] expected_pixel(
        input logic [10:0] sample_x,
        input logic [9:0]  sample_y,
        input logic [7:0]  sample_frame
    );
        logic [4:0] red;
        logic [5:0] green;
        logic [4:0] blue;
        begin
            if ((sample_x == 11'd0) ||
                (sample_x == 11'(TEST_WIDTH - 1)) ||
                (sample_y == 10'd0) ||
                (sample_y == 10'(TEST_HEIGHT - 1))) begin
                expected_pixel = 16'hffff;
            end else begin
                red = {sample_x[10:8], 2'b00} + sample_frame[4:0];
                green = {sample_y[9:7], 3'b000} + {sample_frame[4:0], 1'b0};
                blue = {(sample_x[10:8] ^ sample_y[9:7]), 2'b00} + sample_frame[4:0];
                expected_pixel = {red, green, blue};
            end
        end
    endfunction

    task automatic accept_request(
        input integer expected_line,
        input integer expected_chunk,
        input logic expected_request_buffer
    );
        logic [26:0] expected_address;
        logic [7:0] expected_tag;
        begin
            expected_address = 27'((expected_line * TEST_WIDTH +
                                    expected_chunk * TEST_CHUNK_WORDS) * 2);
            expected_tag = {expected_request_buffer, 7'(expected_chunk)};

            wait(req_valid);
            if (!req_write || req_words != TEST_CHUNK_WORDS ||
                req_byte_address != expected_address || req_tag != expected_tag) begin
                $fatal(1, "bad request line=%0d chunk=%0d write=%b addr=%0d words=%0d tag=%h expected_addr=%0d expected_tag=%h",
                       expected_line, expected_chunk, req_write, req_byte_address,
                       req_words, req_tag, expected_address, expected_tag);
            end
            current_write_word_address = req_byte_address[26:1];
            @(negedge clk);
            req_ready = 1'b1;
            @(posedge clk);
            #1;
            req_ready = 1'b0;
        end
    endtask

    task automatic accept_chunk_words(
        input integer expected_line,
        input integer expected_chunk,
        input logic [7:0] expected_frame
    );
        begin
            word_index = 0;
            stall_once = 0;
            while (word_index < TEST_CHUNK_WORDS) begin
                wait(write_valid);
                @(negedge clk);
                if (word_index == 2 && !stall_once) begin
                    write_ready = 1'b0;
                    stall_once = 1;
                end else begin
                    write_ready = 1'b1;
                end

                if (write_valid && write_ready) begin
                    expected = expected_pixel(
                        11'(expected_chunk * TEST_CHUNK_WORDS + word_index),
                        10'(expected_line),
                        expected_frame
                    );
                    if (write_byte_enable != 2'b11 || write_data !== expected) begin
                        $fatal(1, "bad write line=%0d chunk=%0d word=%0d data=%h expected=%h byte_enable=%b",
                               expected_line, expected_chunk, word_index,
                               write_data, expected, write_byte_enable);
                    end
                    framebuffer_memory[current_write_word_address + word_index] = write_data;
                    word_index = word_index + 1;
                end
                @(posedge clk);
                #1;
            end
            @(negedge clk);
            write_ready = 1'b0;
        end
    endtask

    task automatic complete_chunk(input logic expected_request_buffer, input integer expected_chunk);
        begin
            wait(completion_ready);
            @(negedge clk);
            completion_tag = {expected_request_buffer, 7'(expected_chunk)};
            completion_words = TEST_CHUNK_WORDS;
            completion_error = 1'b0;
            completion_valid = 1'b1;
            @(posedge clk);
            #1;
            completion_valid = 1'b0;
        end
    endtask

    initial begin
        req_ready = 1'b0;
        write_ready = 1'b0;
        completion_valid = 1'b0;
        completion_tag = '0;
        completion_words = '0;
        completion_error = 1'b0;
        current_write_word_address = 0;

        for (memory_index = 0; memory_index < TEST_WIDTH * TEST_HEIGHT; memory_index = memory_index + 1) begin
            framebuffer_memory[memory_index] = 16'hxxxx;
        end

        repeat (3) @(posedge clk);
        reset = 1'b0;

        for (line_index = 0; line_index < TEST_HEIGHT + 1; line_index = line_index + 1) begin
            expected_buffer = line_index[0];
            for (chunk_index = 0; chunk_index < TEST_WIDTH / TEST_CHUNK_WORDS; chunk_index = chunk_index + 1) begin
                accept_request(line_index % TEST_HEIGHT, chunk_index, expected_buffer);
                accept_chunk_words(line_index % TEST_HEIGHT, chunk_index,
                                   8'(line_index / TEST_HEIGHT));
                complete_chunk(expected_buffer, chunk_index);
            end
        end

        repeat (4) @(posedge clk);
        if (writer_error || producer_stalled_waiting_for_free_line) begin
            $fatal(1, "unexpected final status writer_error=%b producer_stalled=%b",
                   writer_error, producer_stalled_waiting_for_free_line);
        end

        for (line_index = 0; line_index < TEST_HEIGHT; line_index = line_index + 1) begin
            for (word_index = 0; word_index < TEST_WIDTH; word_index = word_index + 1) begin
                expected = expected_pixel(11'(word_index), 10'(line_index),
                                          (line_index == 0) ? 8'd1 : 8'd0);
                if (framebuffer_memory[line_index * TEST_WIDTH + word_index] !== expected) begin
                    $fatal(1, "stored framebuffer mismatch x=%0d y=%0d got=%h expected=%h",
                           word_index, line_index,
                           framebuffer_memory[line_index * TEST_WIDTH + word_index],
                           expected);
                end
            end
        end

        $display("PASS framebuffer_producer_write_path: producer writes a linear framebuffer image");
        $finish;
    end

    initial begin
        repeat (2500) @(posedge clk);
        $fatal(1, "producer write path watchdog");
    end
endmodule
