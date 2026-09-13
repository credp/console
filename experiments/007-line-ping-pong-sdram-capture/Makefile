IVERILOG ?= iverilog
VVP ?= vvp

SDRAM_RTL := \
	../../rtl/scanout-sdram-controller/rtl/sdram_init_refresh.sv \
	../../rtl/scanout-sdram-controller/rtl/sdram_addr_decode.sv \
	../../rtl/scanout-sdram-controller/rtl/sdram_request_splitter.sv \
	../../rtl/scanout-sdram-controller/rtl/sdram_single_client_adapter.sv \
	../../rtl/scanout-sdram-controller/rtl/sdram_bank_timing.sv \
	../../rtl/scanout-sdram-controller/rtl/sdram_dq_turnaround.sv \
	../../rtl/scanout-sdram-controller/rtl/sdram_open_row_scheduler.sv \
	../../rtl/scanout-sdram-controller/rtl/sdram_bl8_phy_engine.sv \
	../../rtl/scanout-sdram-controller/rtl/sdram_open_row_core.sv \
	../../rtl/scanout-sdram-controller/rtl/sdram_refresh_deadline.sv \
	../../rtl/scanout-sdram-controller/rtl/sdram_runtime_core.sv \
	../../rtl/scanout-sdram-controller/rtl/sdram_initialized_runtime.sv \
	../../rtl/scanout-sdram-controller/rtl/sdram_single_client_controller.sv

.PHONY: test clean

test: build/tb_line_ping_pong_capture.vvp
	$(VVP) $<

build/tb_line_ping_pong_capture.vvp: rtl/line_ping_pong_capture.sv $(SDRAM_RTL) ../../rtl/scanout-sdram-controller/tb/pin-model/sdram_pair_model.sv tb/tb_line_ping_pong_capture.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_line_ping_pong_capture -o $@ $^

clean:
	rm -rf build
