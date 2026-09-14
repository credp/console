`timescale 1ns/1ps

module tb_framebuffer_write_read_path;
    localparam integer TEST_WIDTH = 8;
    localparam integer TEST_HEIGHT = 4;
    localparam integer TEST_ADDR_WIDTH = 3;
    localparam integer TEST_CHUNK_WORDS = 4;

    logic clk = 1'b0;
    logic reset = 1'b1;

    logic producer_req_valid;
    logic producer_req_ready;
    logic producer_req_write;
    logic [26:0] producer_req_byte_address;
    logic [15:0] producer_req_words;
    logic [7:0] producer_req_tag;
    logic producer_write_valid;
    logic producer_write_ready;
    logic [15:0] producer_write_data;
    logic [1:0] producer_write_byte_enable;
    logic producer_completion_valid;
    logic producer_completion_ready;
    logic [7:0] producer_completion_tag;
    logic [15:0] producer_completion_words;
    logic producer_completion_error;
    logic producer_stalled;
    logic producer_waiting_for_writer;
    logic writer_busy;
    logic writer_error;

    logic start_line_valid;
    logic start_line_ready;
    logic [9:0] start_line_y;
    logic output_line_advance;
    logic output_line_valid;
    logic [9:0] output_line_y;
    logic [TEST_ADDR_WIDTH-1:0] scanout_x;
    logic [15:0] scanout_pixel;
    logic scanout_pixel_valid;
    logic consumer_req_valid;
    logic consumer_req_ready;
    logic consumer_req_write;
    logic [26:0] consumer_req_byte_address;
    logic [15:0] consumer_req_words;
    logic [7:0] consumer_req_tag;
    logic consumer_read_valid;
    logic consumer_read_ready;
    logic [15:0] consumer_read_data;
    logic consumer_completion_valid;
    logic consumer_completion_ready;
    logic [7:0] consumer_completion_tag;
    logic [15:0] consumer_completion_words;
    logic consumer_completion_error;
    logic reader_busy;
    logic reader_error;
    logic consumer_waiting_for_output_release;
    logic consumer_overwrite_error;

    logic [31:0] producer_stall_cycles;
    logic [31:0] producer_idle_cycles;
    logic [31:0] consumer_stall_cycles;
    logic [31:0] consumer_idle_cycles;
    logic [15:0] framebuffer_memory [0:TEST_WIDTH * TEST_HEIGHT-1];
    logic [15:0] expected;
    integer line_index;
    integer chunk_index;
    integer word_index;
    integer memory_index;
    integer physical_line;
    integer write_frame;

    always #5 clk = !clk;

    framebuffer_producer_write_path #(
        .FRAMEBUFFER_WIDTH(TEST_WIDTH),
        .FRAMEBUFFER_HEIGHT(TEST_HEIGHT),
        .LINE_ADDR_WIDTH(TEST_ADDR_WIDTH),
        .WRITE_CHUNK_WORDS(TEST_CHUNK_WORDS)
    ) producer (
        .clk(clk), .reset(reset),
        .req_valid(producer_req_valid), .req_ready(producer_req_ready),
        .req_write(producer_req_write), .req_byte_address(producer_req_byte_address),
        .req_words(producer_req_words), .req_tag(producer_req_tag),
        .write_valid(producer_write_valid), .write_ready(producer_write_ready),
        .write_data(producer_write_data), .write_byte_enable(producer_write_byte_enable),
        .completion_valid(producer_completion_valid), .completion_ready(producer_completion_ready),
        .completion_tag(producer_completion_tag), .completion_words(producer_completion_words),
        .completion_error(producer_completion_error),
        .producer_pixel_x(), .producer_line_y(), .producer_frame_index(),
        .producer_stalled_waiting_for_free_line(producer_stalled),
        .producer_stalled_waiting_for_writer(producer_waiting_for_writer),
        .writer_busy(writer_busy), .writer_error(writer_error)
    );

    framebuffer_consumer_read_path #(
        .FRAMEBUFFER_WIDTH(TEST_WIDTH),
        .LINE_ADDR_WIDTH(TEST_ADDR_WIDTH),
        .READ_CHUNK_WORDS(TEST_CHUNK_WORDS)
    ) consumer (
        .clk(clk), .reset(reset),
        .start_line_valid(start_line_valid), .start_line_ready(start_line_ready),
        .start_line_y(start_line_y), .output_line_advance(output_line_advance),
        .output_line_valid(output_line_valid), .output_buffer(), .output_line_y(output_line_y),
        .scanout_x(scanout_x), .scanout_pixel(scanout_pixel),
        .scanout_pixel_valid(scanout_pixel_valid),
        .req_valid(consumer_req_valid), .req_ready(consumer_req_ready),
        .req_write(consumer_req_write), .req_byte_address(consumer_req_byte_address),
        .req_words(consumer_req_words), .req_tag(consumer_req_tag),
        .read_valid(consumer_read_valid), .read_ready(consumer_read_ready),
        .read_data(consumer_read_data), .completion_valid(consumer_completion_valid),
        .completion_ready(consumer_completion_ready), .completion_tag(consumer_completion_tag),
        .completion_words(consumer_completion_words), .completion_error(consumer_completion_error),
        .reader_busy(reader_busy), .reader_error(reader_error),
        .consumer_waiting_for_output_release(consumer_waiting_for_output_release),
        .consumer_overwrite_error(consumer_overwrite_error)
    );

    framebuffer_transfer_statistics statistics (
        .clk(clk), .reset(reset), .count_enable(1'b1),
        .producer_stall(producer_stalled || producer_waiting_for_writer), .producer_idle(!writer_busy),
        .consumer_stall(consumer_waiting_for_output_release), .consumer_idle(!reader_busy),
        .producer_stall_cycles(producer_stall_cycles),
        .producer_idle_cycles(producer_idle_cycles),
        .consumer_stall_cycles(consumer_stall_cycles),
        .consumer_idle_cycles(consumer_idle_cycles)
    );

    function automatic logic [15:0] expected_pixel(
        input logic [10:0] sample_x,
        input logic [9:0] sample_y,
        input logic [7:0] sample_frame
    );
        logic [4:0] red;
        logic [5:0] green;
        logic [4:0] blue;
        begin
            if ((sample_x == 11'd0) || (sample_x == 11'(TEST_WIDTH - 1)) ||
                (sample_y == 10'd0) || (sample_y == 10'(TEST_HEIGHT - 1))) begin
                expected_pixel = 16'hffff;
            end else begin
                red = sample_x[7:3] + sample_frame[4:0];
                green = sample_y[7:2] + {1'b0, sample_frame[4:0]};
                blue = (sample_x[6:2] ^ sample_y[6:2]) + sample_frame[4:0];
                expected_pixel = {red, green, blue};
            end
        end
    endfunction

    task automatic write_request(input integer expected_line, input integer expected_chunk);
        logic [26:0] expected_address;
        begin
            expected_address = 27'((expected_line * TEST_WIDTH +
                                    expected_chunk * TEST_CHUNK_WORDS) * 2);
            wait(producer_req_valid);
            if (!producer_req_write || producer_req_byte_address != expected_address ||
                producer_req_words != TEST_CHUNK_WORDS) $fatal(1, "bad producer request");
            @(negedge clk); producer_req_ready = 1'b1;
            @(posedge clk); #1; producer_req_ready = 1'b0;
        end
    endtask

    task automatic write_words(
        input integer expected_line,
        input integer expected_chunk,
        input logic [7:0] expected_frame
    );
        begin
            for (word_index = 0; word_index < TEST_CHUNK_WORDS; word_index = word_index + 1) begin
                wait(producer_write_valid);
                expected = expected_pixel(11'(expected_chunk * TEST_CHUNK_WORDS + word_index),
                                          10'(expected_line), expected_frame);
                if (producer_write_data !== expected || producer_write_byte_enable != 2'b11)
                    $fatal(1, "bad producer word line=%0d word=%0d", expected_line, word_index);
                framebuffer_memory[expected_line * TEST_WIDTH + expected_chunk * TEST_CHUNK_WORDS + word_index] = producer_write_data;
                @(negedge clk); producer_write_ready = 1'b1;
                @(posedge clk); #1; producer_write_ready = 1'b0;
            end
        end
    endtask

    task automatic complete_write(input logic expected_buffer, input integer expected_chunk);
        begin
            wait(producer_completion_ready);
            @(negedge clk);
            producer_completion_tag = {expected_buffer, 7'(expected_chunk)};
            producer_completion_words = TEST_CHUNK_WORDS;
            producer_completion_valid = 1'b1;
            @(posedge clk); #1; producer_completion_valid = 1'b0;
        end
    endtask

    task automatic start_read(input integer line_y);
        begin
            wait(start_line_ready);
            @(negedge clk); start_line_y = line_y; start_line_valid = 1'b1;
            @(posedge clk); #1; start_line_valid = 1'b0;
        end
    endtask

    task automatic read_request(input integer expected_line, input integer expected_chunk);
        logic [26:0] expected_address;
        begin
            expected_address = 27'((expected_line * TEST_WIDTH +
                                    expected_chunk * TEST_CHUNK_WORDS) * 2);
            wait(consumer_req_valid);
            if (consumer_req_write || consumer_req_byte_address != expected_address ||
                consumer_req_words != TEST_CHUNK_WORDS) $fatal(1, "bad consumer request");
            @(negedge clk); consumer_req_ready = 1'b1;
            @(posedge clk); #1; consumer_req_ready = 1'b0;
        end
    endtask

    task automatic read_words(input integer expected_line, input integer expected_chunk);
        begin
            for (word_index = 0; word_index < TEST_CHUNK_WORDS; word_index = word_index + 1) begin
                @(negedge clk);
                consumer_read_data = framebuffer_memory[expected_line * TEST_WIDTH +
                                                        expected_chunk * TEST_CHUNK_WORDS + word_index];
                consumer_read_valid = 1'b1;
                wait(consumer_read_ready);
                @(posedge clk); #1; consumer_read_valid = 1'b0;
            end
        end
    endtask

    task automatic complete_read(input integer expected_chunk);
        begin
            wait(consumer_completion_ready);
            @(negedge clk);
            consumer_completion_tag = {1'b0, 7'(expected_chunk)};
            consumer_completion_words = TEST_CHUNK_WORDS;
            consumer_completion_valid = 1'b1;
            @(posedge clk); #1; consumer_completion_valid = 1'b0;
        end
    endtask

    task automatic check_scanout_line(
        input integer expected_line,
        input logic [7:0] expected_frame
    );
        begin
            if (!output_line_valid || !scanout_pixel_valid || output_line_y != expected_line)
                $fatal(1, "wrong output line got valid=%b y=%0d", output_line_valid, output_line_y);
            for (word_index = 0; word_index < TEST_WIDTH; word_index = word_index + 1) begin
                @(negedge clk); scanout_x = word_index;
                @(posedge clk); #1;
                expected = expected_pixel(11'(word_index), 10'(expected_line), expected_frame);
                if (scanout_pixel !== expected)
                    $fatal(1, "scanout mismatch x=%0d y=%0d got=%h expected=%h",
                           word_index, expected_line, scanout_pixel, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("build/framebuffer_write_read_path.vcd");
        $dumpvars(0, tb_framebuffer_write_read_path);
    end

    initial begin
        producer_req_ready = 1'b0; producer_write_ready = 1'b0;
        producer_completion_valid = 1'b0; producer_completion_tag = '0;
        producer_completion_words = '0; producer_completion_error = 1'b0;
        start_line_valid = 1'b0; start_line_y = '0; output_line_advance = 1'b0;
        scanout_x = '0; consumer_req_ready = 1'b0; consumer_read_valid = 1'b0;
        consumer_read_data = '0; consumer_completion_valid = 1'b0;
        consumer_completion_tag = '0; consumer_completion_words = '0;
        consumer_completion_error = 1'b0;
        for (memory_index = 0; memory_index < TEST_WIDTH * TEST_HEIGHT; memory_index = memory_index + 1)
            framebuffer_memory[memory_index] = 16'hxxxx;

        repeat (3) @(posedge clk);
        reset = 1'b0;

        // Hold the first request long enough for the producer to exhaust both lines.
        wait(producer_req_valid);
        repeat (48) @(posedge clk);
        // This covers a complete frame plus four lines of the next frame.
        for (line_index = 0; line_index < TEST_HEIGHT + 4; line_index = line_index + 1) begin
            physical_line = line_index % TEST_HEIGHT;
            write_frame = line_index / TEST_HEIGHT;
            for (chunk_index = 0; chunk_index < TEST_WIDTH / TEST_CHUNK_WORDS; chunk_index = chunk_index + 1) begin
                write_request(physical_line, chunk_index);
                write_words(physical_line, chunk_index, 8'(write_frame));
                complete_write(line_index[0], chunk_index);
            end
        end

        for (line_index = 0; line_index < TEST_HEIGHT; line_index = line_index + 1) begin
            start_read(line_index);
            for (chunk_index = 0; chunk_index < TEST_WIDTH / TEST_CHUNK_WORDS; chunk_index = chunk_index + 1) begin
                read_request(line_index, chunk_index);
                read_words(line_index, chunk_index);
                complete_read(chunk_index);
            end
            wait(!reader_busy);
            if (line_index == 0) begin
                check_scanout_line(line_index, 8'd1);
            end else begin
                if (!consumer_waiting_for_output_release) $fatal(1, "consumer did not wait for scanout");
                repeat (5) @(posedge clk);
                @(negedge clk); output_line_advance = 1'b1;
                @(posedge clk); #1; output_line_advance = 1'b0;
                repeat (2) @(posedge clk);
                check_scanout_line(line_index, 8'd1);
            end
        end

        if (writer_error || reader_error || consumer_overwrite_error)
            $fatal(1, "unexpected transfer error writer=%b reader=%b consumer_overwrite=%b",
                   writer_error, reader_error, consumer_overwrite_error);
        if (producer_stall_cycles == 0 || producer_idle_cycles == 0 ||
            consumer_stall_cycles == 0 || consumer_idle_cycles == 0)
            $fatal(1, "statistics did not observe all states producer_stall=%0d producer_idle=%0d consumer_stall=%0d consumer_idle=%0d",
                   producer_stall_cycles, producer_idle_cycles,
                   consumer_stall_cycles, consumer_idle_cycles);

        $display("PASS framebuffer_write_read_path: shared memory pixel path and transfer statistics");
        $finish;
    end

    initial begin
        repeat (10000) @(posedge clk);
        $fatal(1, "write/read path watchdog");
    end
endmodule
