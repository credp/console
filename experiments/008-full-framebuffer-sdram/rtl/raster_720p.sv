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
    output logic        frame_start,
    output logic        de_raw,
    output logic        hsync_raw,
    output logic        vsync_raw
);

logic [10:0] h_count;
logic [9:0]  v_count;

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

assign de_raw    = (h_count < 1280) && (v_count < 720);
assign hsync_raw = (h_count >= 1390) && (h_count < 1430);
assign vsync_raw = (v_count >= 725)  && (v_count < 730);

// The framebuffer and pattern generators consume the live coordinates below.
// Keep the timing outputs combinational from those same counters: registering
// them here delays DE/sync by one pixel while x/y have already advanced.
assign de    = de_raw;
assign hsync = hsync_raw;
assign vsync = vsync_raw;

assign x = h_count;
assign y = v_count;

assign frame_start = (h_count == 0) && (v_count == 0);


endmodule
