IVERILOG ?= iverilog
VVP ?= vvp
VERILATOR ?= verilator

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

COMMON_TB_RTL := \
	rtl/line_ping_pong_capture.sv \
	rtl/line_capture_sdram_backend.sv \
	$(SDRAM_RTL) \
	../../rtl/scanout-sdram-controller/tb/backend-bench/altddio_out_sim.sv \
	../../rtl/scanout-sdram-controller/tb/pin-model/sdram_pair_model.sv \
	tb/tb_line_ping_pong_capture.sv

.PHONY: test test-custom test-agg23-word test-agg23-burst clean

test: test-custom test-agg23-word test-agg23-burst

test-custom: build/tb_line_ping_pong_capture_custom.vvp
	$(VVP) $<

test-agg23-word: build/tb_line_ping_pong_capture_agg23_word.vvp
	build/obj_agg23_word/tb_line_ping_pong_capture_agg23_word

test-agg23-burst: build/tb_line_ping_pong_capture_agg23_burst.vvp
	build/obj_agg23_burst/tb_line_ping_pong_capture_agg23_burst

build/tb_line_ping_pong_capture_custom.vvp: $(COMMON_TB_RTL)
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -DSIMULATION -s tb_line_ping_pong_capture -o $@ $^

build/tb_line_ping_pong_capture_agg23_word.vvp: $(COMMON_TB_RTL) ../../third_party/agg23-sdram-controller/sdram.sv
	mkdir -p build
	$(VERILATOR) --binary -Wno-fatal --timing -DSIMULATION -DSDRAM_BACKEND_AGG23_WORD \
		--top-module tb_line_ping_pong_capture --Mdir build/obj_agg23_word \
		-o tb_line_ping_pong_capture_agg23_word $(COMMON_TB_RTL)
	touch $@

build/tb_line_ping_pong_capture_agg23_burst.vvp: $(COMMON_TB_RTL) ../../third_party/agg23-sdram-controller/sdram_burst.sv
	mkdir -p build
	$(VERILATOR) --binary -Wno-fatal --timing -DSIMULATION -DSDRAM_BACKEND_AGG23_BURST \
		--top-module tb_line_ping_pong_capture --Mdir build/obj_agg23_burst \
		-o tb_line_ping_pong_capture_agg23_burst $(COMMON_TB_RTL)
	touch $@

clean:
	rm -rf build
