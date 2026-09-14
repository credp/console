`timescale 1ns/1ps

module tb_framebuffer_line_write_sequencer;
    localparam integer TEST_WIDTH = 8;
    localparam integer TEST_CHUNK_WORDS = 4;
    localparam integer TEST_ADDR_WIDTH = 3;

    logic clk = 1'b0;
    logic reset = 1'b1;

    logic line_ready_valid;
    logic line_ready_accept;
    logic line_ready_buffer;
    logic [9:0] line_ready_y;
    logic line_release_valid;
    logic line_release_buffer;
    logic writer_read_buffer;
    logic [TEST_ADDR_WIDTH-1:0] writer_read_x;
    logic [15:0] writer_read_pixel;
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
    logic busy;
    logic error;

    logic [15:0] line0_pixels [0:TEST_WIDTH-1];
    logic [15:0] line1_pixels [0:TEST_WIDTH-1];
    integer index;
    integer chunk;
    integer word_count;
    integer stalled_once;

    always #5 clk = !clk;

    framebuffer_line_write_sequencer #(
        .FRAMEBUFFER_WIDTH(TEST_WIDTH),
        .LINE_ADDR_WIDTH(TEST_ADDR_WIDTH),
        .WRITE_CHUNK_WORDS(TEST_CHUNK_WORDS)
    ) dut (
        .clk(clk),
        .reset(reset),
        .line_ready_valid(line_ready_valid),
        .line_ready_accept(line_ready_accept),
        .line_ready_buffer(line_ready_buffer),
        .line_ready_y(line_ready_y),
        .line_release_valid(line_release_valid),
        .line_release_buffer(line_release_buffer),
        .writer_read_buffer(writer_read_buffer),
        .writer_read_x(writer_read_x),
        .writer_read_pixel(writer_read_pixel),
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
        .busy(busy),
        .error(error)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            writer_read_pixel <= 16'h0000;
        end else if (writer_read_buffer) begin
            writer_read_pixel <= line1_pixels[writer_read_x];
        end else begin
            writer_read_pixel <= line0_pixels[writer_read_x];
        end
    end

    task automatic accept_request(
        input integer expected_chunk,
        input logic [26:0] expected_address,
        input logic [7:0] expected_tag
    );
        begin
            wait(req_valid);
            if (!req_write || req_words != TEST_CHUNK_WORDS ||
                req_byte_address != expected_address || req_tag != expected_tag) begin
                $fatal(1, "bad request chunk=%0d write=%b addr=%0d words=%0d tag=%h",
                       expected_chunk, req_write, req_byte_address, req_words, req_tag);
            end
            @(negedge clk);
            req_ready = 1'b1;
            @(posedge clk);
            #1;
            req_ready = 1'b0;
        end
    endtask

    task automatic accept_chunk_words(input integer expected_chunk);
        begin
            word_count = 0;
            stalled_once = 0;
            while (word_count < TEST_CHUNK_WORDS) begin
                wait(write_valid);
                @(negedge clk);
                if (word_count == 1 && !stalled_once) begin
                    write_ready = 1'b0;
                    stalled_once = 1;
                end else begin
                    write_ready = 1'b1;
                end
                if (write_valid && write_ready) begin
                    if (write_byte_enable != 2'b11) begin
                        $fatal(1, "bad byte enable %b", write_byte_enable);
                    end
                    if (write_data != line1_pixels[expected_chunk * TEST_CHUNK_WORDS + word_count]) begin
                        $fatal(1, "bad data chunk=%0d word=%0d got=%h expected=%h",
                               expected_chunk, word_count, write_data,
                               line1_pixels[expected_chunk * TEST_CHUNK_WORDS + word_count]);
                    end
                    word_count = word_count + 1;
                end
                @(posedge clk);
                #1;
            end
            @(negedge clk);
            write_ready = 1'b0;
        end
    endtask

    task automatic complete_chunk(input logic [7:0] expected_tag);
        begin
            wait(completion_ready);
            @(negedge clk);
            completion_tag = expected_tag;
            completion_words = TEST_CHUNK_WORDS;
            completion_error = 1'b0;
            completion_valid = 1'b1;
            @(posedge clk);
            #1;
            completion_valid = 1'b0;
        end
    endtask

    initial begin
        line_ready_valid = 1'b0;
        line_ready_buffer = 1'b1;
        line_ready_y = 10'd3;
        req_ready = 1'b0;
        write_ready = 1'b0;
        completion_valid = 1'b0;
        completion_tag = '0;
        completion_words = '0;
        completion_error = 1'b0;

        for (index = 0; index < TEST_WIDTH; index = index + 1) begin
            line0_pixels[index] = 16'h1000 + index;
            line1_pixels[index] = 16'h8000 + index;
        end

        repeat (3) @(posedge clk);
        reset = 1'b0;

        @(negedge clk);
        line_ready_valid = 1'b1;
        wait(line_ready_accept);
        @(posedge clk);
        #1;
        line_ready_valid = 1'b0;

        for (chunk = 0; chunk < 2; chunk = chunk + 1) begin
            accept_request(chunk,
                           27'((3 * TEST_WIDTH + chunk * TEST_CHUNK_WORDS) * 2),
                           {1'b1, 7'(chunk)});
            accept_chunk_words(chunk);
            complete_chunk({1'b1, 7'(chunk)});
        end

        wait(line_release_valid);
        if (line_release_buffer != 1'b1) begin
            $fatal(1, "released wrong buffer %0d", line_release_buffer);
        end
        @(posedge clk);
        #1;
        if (busy || error) begin
            $fatal(1, "sequencer finished with busy=%b error=%b", busy, error);
        end

        $display("PASS framebuffer_line_write_sequencer: chunked line writes and release");
        $finish;
    end

    initial begin
        repeat (800) @(posedge clk);
        $fatal(1, "line write sequencer watchdog");
    end
endmodule
