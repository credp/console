IVERILOG ?= iverilog
VVP ?= vvp
CAD_SUITE ?= /home/chris/Projects/oss-cad-suite
RTL := $(wildcard rtl/*.sv)

.PHONY: test lint formal clean
test: build/tb_foundation.vvp build/tb_pin_bist.vvp build/tb_pin_bl8_bist.vvp
	$(VVP) build/tb_foundation.vvp
	$(VVP) build/tb_pin_bist.vvp
	$(VVP) build/tb_pin_bl8_bist.vvp

build/tb_foundation.vvp: $(RTL) tb/tb_foundation.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_foundation -o $@ $(RTL) tb/tb_foundation.sv

build/tb_pin_bist.vvp: rtl/sdram_rw_bist.sv tb/pin-model/sdram_pair_model.sv tb/tb_pin_bist.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_pin_bist -o $@ $^

build/tb_pin_bl8_bist.vvp: rtl/sdram_addr_decode.sv rtl/sdram_bl8_bist.sv tb/pin-model/sdram_pair_model.sv tb/tb_pin_bl8_bist.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_pin_bl8_bist -o $@ $^

lint:
	verilator --lint-only -Wall -Wno-fatal --top-module sdram_request_splitter $(RTL)

formal:
	PATH=$(CAD_SUITE)/bin:$$PATH $(CAD_SUITE)/bin/sby -f formal/splitter.sby
	PATH=$(CAD_SUITE)/bin:$$PATH $(CAD_SUITE)/bin/sby -f formal/arbiter.sby
	PATH=$(CAD_SUITE)/bin:$$PATH $(CAD_SUITE)/bin/sby -f formal/fifo.sby
	PATH=$(CAD_SUITE)/bin:$$PATH $(CAD_SUITE)/bin/sby -f formal/frame_publish.sby
	PATH=$(CAD_SUITE)/bin:$$PATH $(CAD_SUITE)/bin/sby -f formal/refresh.sby

clean:
	rm -rf build formal/splitter formal/arbiter formal/fifo formal/frame_publish formal/refresh
