/*
# pixel clock:  74.25 MHz
#
#horizontal:
#  active      1280
#  front porch  110
#  sync          40
#  back porch   220
#  total       1650
#
#vertical:
#  active       720
#  front porch    5
#  sync            5
#  back porch     20
#  total          750
#
#HSync: positive
#VSync: positive
*/

module raster_720p (
    input  logic        clk,
    input  logic        reset,

    output logic [10:0] x,
    output logic [9:0]  y,
    output logic        de,
    output logic        hsync,
    output logic        vsync,
    output logic        frame_start
);

logic [10:0] h_count;
logic [9:0]  v_count;
logic [7:0]  video;

always_ff @(posedge clk) begin
    if (reset) begin
        h_count <= 0;
        v_count <= 0;
    end
    else if (h_count == 1649) begin
        h_count <= 0;
        if (v_count == 749)
            v_count <= 0;
        else
            v_count <= v_count + 1;
    end
    else begin
        h_count <= h_count + 1;
    end
end

assign de = (h_count < 1280) && (v_count < 720);
assign hsync = (h_count >= 1390) && (h_count < 1430);
assign vsync = (v_count >= 725)  && (v_count < 730);
assign HBlank = (h_count >= 1280);
assign VBlank = (v_count >= 720);

assign x = h_count;
assign y = v_count;

assign frame_start = (h_count == 0) && (v_count == 0);

wire border =
    (x == 0) || (x == 1279) ||
    (y == 0) || (y == 719);

wire grid =
    (x[5:0] == 0) ||
    (y[5:0] == 0);

wire marker =
    (x >= 100 && x < 200 &&
     y >= 100 && y < 200);


assign video =
	border ? 8'hFF :
	marker ? 8'hA0 :
	grid   ? 8'h50 :
             8'h20 ;


endmodule
