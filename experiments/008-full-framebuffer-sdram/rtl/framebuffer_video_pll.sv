module framebuffer_video_pll(input wire refclk,input wire rst,output wire outclk,output wire locked);
  altera_pll #(.reference_clock_frequency("50.0 MHz"),.operation_mode("direct"),.number_of_clocks(1),.output_clock_frequency0("74.250000 MHz"),.phase_shift0("0 ps"),.duty_cycle0(50),.pll_type("General"),.pll_subtype("General")) pll(.rst(rst),.outclk(outclk),.locked(locked),.fboutclk(),.fbclk(1'b0),.refclk(refclk));
endmodule
