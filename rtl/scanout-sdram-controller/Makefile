IVERILOG ?= iverilog
VVP ?= vvp
VERILATOR ?= verilator
CAD_SUITE ?= /home/chris/Projects/oss-cad-suite
RTL := $(wildcard rtl/*.sv)

.PHONY: test lint formal trace-current trace-agg23-stock trace-agg23-request-layer clean
test: build/tb_foundation.vvp build/tb_bank_timing.vvp build/tb_dq_turnaround.vvp build/tb_refresh_deadline.vvp build/tb_open_row_scheduler.vvp build/tb_bl8_phy_engine.vvp build/tb_open_row_core.vvp build/tb_runtime_core.vvp build/tb_single_client_adapter.vvp build/tb_two_client_adapter.vvp build/tb_single_client_controller.vvp build/tb_two_client_controller.vvp build/tb_pin_bist.vvp build/tb_pin_bl8_bist.vvp build/tb_pin_end_to_end.vvp
	$(VVP) build/tb_foundation.vvp
	$(VVP) build/tb_bank_timing.vvp
	$(VVP) build/tb_dq_turnaround.vvp
	$(VVP) build/tb_refresh_deadline.vvp
	$(VVP) build/tb_open_row_scheduler.vvp
	$(VVP) build/tb_bl8_phy_engine.vvp
	$(VVP) build/tb_open_row_core.vvp
	$(VVP) build/tb_runtime_core.vvp
	$(VVP) build/tb_single_client_adapter.vvp
	$(VVP) build/tb_two_client_adapter.vvp
	$(VVP) build/tb_single_client_controller.vvp
	$(VVP) build/tb_two_client_controller.vvp
	$(VVP) build/tb_pin_bist.vvp
	$(VVP) build/tb_pin_bl8_bist.vvp
	$(VVP) build/tb_pin_end_to_end.vvp

build/tb_foundation.vvp: $(RTL) tb/tb_foundation.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_foundation -o $@ $(RTL) tb/tb_foundation.sv

build/tb_bank_timing.vvp: rtl/sdram_bank_timing.sv tb/tb_bank_timing.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_bank_timing -o $@ $^

build/tb_open_row_scheduler.vvp: rtl/sdram_bank_timing.sv rtl/sdram_dq_turnaround.sv rtl/sdram_open_row_scheduler.sv tb/tb_open_row_scheduler.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_open_row_scheduler -o $@ $^

build/tb_dq_turnaround.vvp: rtl/sdram_dq_turnaround.sv tb/tb_dq_turnaround.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_dq_turnaround -o $@ $^

build/tb_refresh_deadline.vvp: rtl/sdram_refresh_deadline.sv tb/tb_refresh_deadline.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_refresh_deadline -o $@ $^

build/tb_bl8_phy_engine.vvp: rtl/sdram_bl8_phy_engine.sv tb/pin-model/sdram_pair_model.sv tb/tb_bl8_phy_engine.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_bl8_phy_engine -o $@ $^

build/tb_open_row_core.vvp: rtl/sdram_bank_timing.sv rtl/sdram_dq_turnaround.sv rtl/sdram_open_row_scheduler.sv rtl/sdram_bl8_phy_engine.sv rtl/sdram_open_row_core.sv tb/pin-model/sdram_pair_model.sv tb/tb_open_row_core.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_open_row_core -o $@ $^

build/tb_runtime_core.vvp: rtl/sdram_bank_timing.sv rtl/sdram_dq_turnaround.sv rtl/sdram_open_row_scheduler.sv rtl/sdram_bl8_phy_engine.sv rtl/sdram_open_row_core.sv rtl/sdram_refresh_deadline.sv rtl/sdram_runtime_core.sv tb/pin-model/sdram_pair_model.sv tb/tb_runtime_core.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_runtime_core -o $@ $^

build/tb_single_client_adapter.vvp: rtl/sdram_addr_decode.sv rtl/sdram_request_splitter.sv rtl/sdram_single_client_adapter.sv rtl/sdram_bank_timing.sv rtl/sdram_dq_turnaround.sv rtl/sdram_open_row_scheduler.sv rtl/sdram_bl8_phy_engine.sv rtl/sdram_open_row_core.sv rtl/sdram_refresh_deadline.sv rtl/sdram_runtime_core.sv tb/pin-model/sdram_pair_model.sv tb/tb_single_client_adapter.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_single_client_adapter -o $@ $^

build/tb_single_client_controller.vvp: rtl/sdram_init_refresh.sv rtl/sdram_addr_decode.sv rtl/sdram_request_splitter.sv rtl/sdram_single_client_adapter.sv rtl/sdram_bank_timing.sv rtl/sdram_dq_turnaround.sv rtl/sdram_open_row_scheduler.sv rtl/sdram_bl8_phy_engine.sv rtl/sdram_open_row_core.sv rtl/sdram_refresh_deadline.sv rtl/sdram_runtime_core.sv rtl/sdram_initialized_runtime.sv rtl/sdram_single_client_controller.sv tb/pin-model/sdram_pair_model.sv tb/tb_single_client_controller.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_single_client_controller -o $@ $^

build/tb_two_client_adapter.vvp: rtl/sdram_addr_decode.sv rtl/sdram_request_splitter.sv rtl/sdram_single_client_adapter.sv rtl/sdram_two_client_adapter.sv rtl/sdram_bank_timing.sv rtl/sdram_dq_turnaround.sv rtl/sdram_open_row_scheduler.sv rtl/sdram_bl8_phy_engine.sv rtl/sdram_open_row_core.sv rtl/sdram_refresh_deadline.sv rtl/sdram_runtime_core.sv tb/pin-model/sdram_pair_model.sv tb/tb_two_client_adapter.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_two_client_adapter -o $@ $^

build/tb_two_client_controller.vvp: rtl/sdram_init_refresh.sv rtl/sdram_addr_decode.sv rtl/sdram_request_splitter.sv rtl/sdram_single_client_adapter.sv rtl/sdram_two_client_adapter.sv rtl/sdram_bank_timing.sv rtl/sdram_dq_turnaround.sv rtl/sdram_open_row_scheduler.sv rtl/sdram_bl8_phy_engine.sv rtl/sdram_open_row_core.sv rtl/sdram_refresh_deadline.sv rtl/sdram_runtime_core.sv rtl/sdram_initialized_runtime.sv rtl/sdram_two_client_controller.sv tb/pin-model/sdram_pair_model.sv tb/tb_two_client_controller.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_two_client_controller -o $@ $^

build/tb_pin_bist.vvp: rtl/sdram_rw_bist.sv tb/pin-model/sdram_pair_model.sv tb/tb_pin_bist.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_pin_bist -o $@ $^

build/tb_pin_bl8_bist.vvp: rtl/sdram_addr_decode.sv rtl/sdram_bl8_bist.sv tb/pin-model/sdram_pair_model.sv tb/tb_pin_bl8_bist.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_pin_bl8_bist -o $@ $^

build/tb_pin_end_to_end.vvp: rtl/sdram_addr_decode.sv rtl/sdram_request_splitter.sv rtl/sdram_bl8_op_engine.sv rtl/sdram_end_to_end_bist.sv tb/pin-model/sdram_pair_model.sv tb/tb_pin_end_to_end.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_pin_end_to_end -o $@ $^

build/tb_trace_current_controller.vvp: rtl/sdram_init_refresh.sv rtl/sdram_addr_decode.sv rtl/sdram_request_splitter.sv rtl/sdram_single_client_adapter.sv rtl/sdram_two_client_adapter.sv rtl/sdram_bank_timing.sv rtl/sdram_dq_turnaround.sv rtl/sdram_open_row_scheduler.sv rtl/sdram_bl8_phy_engine.sv rtl/sdram_open_row_core.sv rtl/sdram_refresh_deadline.sv rtl/sdram_runtime_core.sv rtl/sdram_initialized_runtime.sv rtl/sdram_two_client_controller.sv tb/pin-model/sdram_pair_model.sv tb/backend-bench/tb_trace_current_controller.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_trace_current_controller -o $@ $^

trace-current: build/tb_trace_current_controller.vvp
	$(VVP) build/tb_trace_current_controller.vvp +trace_mem=$${TRACE_MEM:?set TRACE_MEM to a trace .mem fixture} +trace_count=$${TRACE_COUNT:?set TRACE_COUNT to fixture row count}

build/obj_agg23_stock/tb_trace_agg23_stock: ../../third_party/agg23-sdram-controller/sdram.sv tb/pin-model/sdram_pair_model.sv tb/backend-bench/altddio_out_sim.sv tb/backend-bench/tb_trace_agg23_stock.sv
	mkdir -p build
	$(VERILATOR) --binary -Wno-fatal --timing --top-module tb_trace_agg23_stock --Mdir build/obj_agg23_stock -o tb_trace_agg23_stock $^

trace-agg23-stock: build/obj_agg23_stock/tb_trace_agg23_stock
	build/obj_agg23_stock/tb_trace_agg23_stock +trace_mem=$${TRACE_MEM:?set TRACE_MEM to a trace .mem fixture} +trace_count=$${TRACE_COUNT:?set TRACE_COUNT to fixture row count}

build/obj_agg23_request_layer/tb_trace_agg23_request_layer: ../../third_party/agg23-sdram-controller/sdram.sv tb/pin-model/sdram_pair_model.sv tb/backend-bench/altddio_out_sim.sv tb/backend-bench/agg23_request_layer_wrapper.sv tb/backend-bench/tb_trace_agg23_request_layer.sv
	mkdir -p build
	$(VERILATOR) --binary -Wno-fatal --timing --top-module tb_trace_agg23_request_layer --Mdir build/obj_agg23_request_layer -o tb_trace_agg23_request_layer $^

trace-agg23-request-layer: build/obj_agg23_request_layer/tb_trace_agg23_request_layer
	build/obj_agg23_request_layer/tb_trace_agg23_request_layer +trace_mem=$${TRACE_MEM:?set TRACE_MEM to a trace .mem fixture} +trace_count=$${TRACE_COUNT:?set TRACE_COUNT to fixture row count}

lint:
	verilator --lint-only -Wall -Wno-fatal --top-module sdram_request_splitter $(RTL)

formal:
	PATH=$(CAD_SUITE)/bin:$$PATH $(CAD_SUITE)/bin/sby -f formal/open_row_scheduler.sby
	PATH=$(CAD_SUITE)/bin:$$PATH $(CAD_SUITE)/bin/sby -f formal/bl8_phy_engine.sby
	PATH=$(CAD_SUITE)/bin:$$PATH $(CAD_SUITE)/bin/sby -f formal/refresh_deadline.sby
	PATH=$(CAD_SUITE)/bin:$$PATH $(CAD_SUITE)/bin/sby -f formal/single_client_adapter.sby
	PATH=$(CAD_SUITE)/bin:$$PATH $(CAD_SUITE)/bin/sby -f formal/two_client_adapter.sby
	PATH=$(CAD_SUITE)/bin:$$PATH $(CAD_SUITE)/bin/sby -f formal/bl8_op_engine.sby
	PATH=$(CAD_SUITE)/bin:$$PATH $(CAD_SUITE)/bin/sby -f formal/splitter.sby
	PATH=$(CAD_SUITE)/bin:$$PATH $(CAD_SUITE)/bin/sby -f formal/arbiter.sby
	PATH=$(CAD_SUITE)/bin:$$PATH $(CAD_SUITE)/bin/sby -f formal/fifo.sby
	PATH=$(CAD_SUITE)/bin:$$PATH $(CAD_SUITE)/bin/sby -f formal/frame_publish.sby
	PATH=$(CAD_SUITE)/bin:$$PATH $(CAD_SUITE)/bin/sby -f formal/refresh.sby

clean:
	rm -rf build formal/splitter formal/arbiter formal/fifo formal/frame_publish formal/refresh \
	formal/bl8_op_engine formal/bl8_op_engine_prove formal/bl8_op_engine_cover \
		formal/bl8_phy_engine formal/bl8_phy_engine_prove formal/bl8_phy_engine_cover \
		formal/refresh_deadline formal/refresh_deadline_prove formal/refresh_deadline_cover \
		formal/runtime_core formal/runtime_core_prove formal/runtime_core_cover \
		formal/single_client_adapter formal/single_client_adapter_prove formal/single_client_adapter_cover \
		formal/two_client_adapter formal/two_client_adapter_prove formal/two_client_adapter_cover \
		formal/open_row_scheduler formal/open_row_scheduler_prove formal/open_row_scheduler_cover
