`timescale 1ns/1ps
module tb_refresh_deadline;
    logic clk=0,reset=1,enable=0,refresh_valid,refresh_ready=1,refresh_chip;
    logic refresh_completion_valid=0,refresh_completion_ready;
    logic late_refresh0,late_refresh1,refresh_pending;
    integer service_timer=-1,count0=0,count1=0,cycle=0,last0=0,last1=0;
    logic service_chip;
    always #5 clk=~clk;

    sdram_refresh_deadline #(.SDRAM_FREQ_HZ(10_000_000),.MAX_SERVICE_CYCLES(8)) dut(.*);

    // A scheduler model with a deliberately variable-looking fixed service
    // time. Completion is later than request acceptance, which distinguishes
    // the two events being tested.
    always @(posedge clk) begin
      cycle<=cycle+1;refresh_completion_valid<=0;
      if(refresh_valid&&refresh_ready)begin service_timer<=6;service_chip<=refresh_chip;end
      else if(service_timer>0)service_timer<=service_timer-1;
      else if(service_timer==0)begin
        refresh_completion_valid<=1;service_timer<=-1;
        if(service_chip)begin
          if(count1>0&&cycle-last1>78)$fatal(1,"chip 1 refresh interval %0d",cycle-last1);
          last1<=cycle;count1<=count1+1;
        end else begin
          if(count0>0&&cycle-last0>78)$fatal(1,"chip 0 refresh interval %0d",cycle-last0);
          last0<=cycle;count0<=count0+1;
        end
      end
    end

    initial begin
      repeat(2)@(negedge clk);reset=0;enable=1;
      wait(count0>=3&&count1>=3);@(negedge clk);
      if(late_refresh0||late_refresh1)$fatal(1,"refresh deadline reported late");
      $display("PASS refresh deadline: persistent staggered requests and completion accounting");$finish;
    end
    initial begin repeat(400)@(posedge clk);$fatal(1,"refresh deadline watchdog");end
endmodule
