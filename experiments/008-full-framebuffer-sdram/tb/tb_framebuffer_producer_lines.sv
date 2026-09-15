`timescale 1ns/1ps

module tb_framebuffer_producer_lines;
    localparam integer TEST_WIDTH = 8;
    localparam integer TEST_HEIGHT = 4;
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
    logic [10:0] producer_x;
    logic [9:0] producer_y;
    logic [7:0] frame_index;
    logic stalled_waiting_for_free_line;

    integer accepted_lines;
    integer released_lines;
    integer x_index;
    logic [15:0] expected;

    always #5 clk = !clk;

    framebuffer_producer_lines #(
        .FRAMEBUFFER_WIDTH(TEST_WIDTH),
        .FRAMEBUFFER_HEIGHT(TEST_HEIGHT),
        .LINE_ADDR_WIDTH(TEST_ADDR_WIDTH)
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
        .producer_x(producer_x),
        .producer_y(producer_y),
        .frame_index(frame_index),
        .stalled_waiting_for_free_line(stalled_waiting_for_free_line)
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

    task automatic accept_and_check_line(
        input logic expected_buffer,
        input logic [9:0] expected_y,
        input logic [7:0] expected_frame
    );
        begin
            wait(line_ready_valid);
            if (line_ready_buffer !== expected_buffer) begin
                $fatal(1, "ready buffer mismatch got=%0d expected=%0d",
                       line_ready_buffer, expected_buffer);
            end
            if (line_ready_y !== expected_y) begin
                $fatal(1, "ready y mismatch got=%0d expected=%0d",
                       line_ready_y, expected_y);
            end

            line_ready_accept = 1'b1;
            @(posedge clk);
            #1;
            line_ready_accept = 1'b0;

            writer_read_buffer = expected_buffer;
            for (x_index = 0; x_index < TEST_WIDTH; x_index = x_index + 1) begin
                writer_read_x = TEST_ADDR_WIDTH'(x_index);
                @(posedge clk);
                #1;
                expected = expected_pixel(11'(x_index), expected_y, expected_frame);
                if (writer_read_pixel !== expected) begin
                    $fatal(1, "line pixel mismatch buffer=%0d x=%0d y=%0d got=%h expected=%h",
                           expected_buffer, x_index, expected_y,
                           writer_read_pixel, expected);
                end
            end

            accepted_lines = accepted_lines + 1;
        end
    endtask

    task automatic release_line(input logic buffer_to_release);
        begin
            @(negedge clk);
            line_release_buffer = buffer_to_release;
            line_release_valid = 1'b1;
            @(posedge clk);
            #1;
            line_release_valid = 1'b0;
            released_lines = released_lines + 1;
        end
    endtask

    initial begin
        line_ready_accept = 1'b0;
        line_release_valid = 1'b0;
        line_release_buffer = 1'b0;
        writer_read_buffer = 1'b0;
        writer_read_x = '0;
        accepted_lines = 0;
        released_lines = 0;

        repeat (3) @(posedge clk);
        reset = 1'b0;

        accept_and_check_line(1'b0, 10'd0, 8'd0);
        accept_and_check_line(1'b1, 10'd1, 8'd0);

        repeat (TEST_WIDTH + 3) @(posedge clk);
        if (!stalled_waiting_for_free_line) begin
            $fatal(1, "producer did not stall when both line buffers were owned by the writer");
        end

        release_line(1'b0);
        accept_and_check_line(1'b0, 10'd2, 8'd0);
        release_line(1'b1);
        accept_and_check_line(1'b1, 10'd3, 8'd0);
        release_line(1'b0);
        accept_and_check_line(1'b0, 10'd0, 8'd1);

        if (accepted_lines != 5 || released_lines != 3) begin
            $fatal(1, "line accounting mismatch accepted=%0d released=%0d",
                   accepted_lines, released_lines);
        end

        $display("PASS framebuffer_producer_lines: two-line ownership and pattern contents");
        $finish;
    end

    initial begin
        repeat (500) @(posedge clk);
        $fatal(1, "producer test watchdog");
    end
endmodule
