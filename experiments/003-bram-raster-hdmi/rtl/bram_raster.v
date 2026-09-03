module bram_raster (
    input  wire        clk,
    input  wire [10:0] x,
    input  wire [9:0]  y,

    output wire [7:0]  r,
    output wire [7:0]  g,
    output wire [7:0]  b
);

    reg [15:0] mem [0:65535];
    reg [15:0] pixel;

    wire [7:0] bx = x[7:0];
    wire [7:0] by = y[7:0];
    wire [15:0] addr = {by, bx};

    initial begin
        $readmemh("bram.hex", mem);
    end

    always @(posedge clk) begin
        pixel <= mem[addr];
    end

    assign r = {pixel[15:11], pixel[15:13]};
    assign g = {pixel[10:6],  pixel[10:8]};
    assign b = {pixel[5:1],   pixel[5:3]};

endmodule
