`timescale 1ns/1ps

module tb_framebuffer_line_chunk_address;
    logic [9:0] framebuffer_line_y;
    logic [6:0] chunk_index;
    logic [26:0] byte_address;

    framebuffer_line_chunk_address #(
        .FRAMEBUFFER_WIDTH(1280),
        .WRITE_CHUNK_WORDS(320)
    ) dut (
        .framebuffer_line_y(framebuffer_line_y),
        .chunk_index(chunk_index),
        .byte_address(byte_address)
    );

    task automatic check_address(
        input logic [9:0] sample_y,
        input logic [6:0] sample_chunk,
        input logic [26:0] expected_address
    );
        begin
            framebuffer_line_y = sample_y;
            chunk_index = sample_chunk;
            #1;
            if (byte_address !== expected_address) begin
                $fatal(1, "address mismatch y=%0d chunk=%0d got=%0d expected=%0d",
                       sample_y, sample_chunk, byte_address, expected_address);
            end
        end
    endtask

    initial begin
        check_address(10'd0,   7'd0, 27'd0);
        check_address(10'd0,   7'd1, 27'd640);
        check_address(10'd1,   7'd0, 27'd2560);
        check_address(10'd719, 7'd3, 27'((719 * 1280 + 3 * 320) * 2));

        $display("PASS framebuffer_line_chunk_address: line/chunk to linear byte address");
        $finish;
    end
endmodule
