module refresh_deadline_formal;
    logic clk;
    logic reset=1,enable=0;
    logic refresh_valid,refresh_chip,refresh_completion_ready;
    logic late_refresh0,late_refresh1,refresh_pending;
    logic refresh_completion_valid;
    logic [1:0] service_timer;

    sdram_refresh_deadline #(.SDRAM_FREQ_HZ(2_000_000),.MAX_SERVICE_CYCLES(1),
      .REFRESH_PHASE_CYCLES(7)) dut(.clk,.reset,.enable,.refresh_valid,
      .refresh_ready(1'b1),.refresh_chip,.refresh_completion_valid,
      .refresh_completion_ready,.late_refresh0,.late_refresh1,.refresh_pending);

    // Contract witness: an accepted request completes one clock later.
    assign refresh_completion_valid=(service_timer==1);
    always_ff @(posedge clk) begin
      reset<=0;enable<=1;
      if(reset)service_timer<=0;
      else begin
        if(refresh_valid)service_timer<=1;
        else if(service_timer!=0)service_timer<=service_timer-1'b1;
        assert(!late_refresh0);assert(!late_refresh1);
        cover(!reset&&refresh_completion_valid&&refresh_chip);
        cover(!reset&&refresh_completion_valid&&!refresh_chip);
      end
    end
endmodule
