IVERILOG ?= iverilog
VVP ?= vvp

.PHONY: test clean

test: build/tb_framebuffer_pattern_pixel.vvp build/tb_framebuffer_producer_lines.vvp
	$(VVP) $<
	$(VVP) build/tb_framebuffer_producer_lines.vvp

build/tb_framebuffer_pattern_pixel.vvp: rtl/framebuffer_pattern_pixel.sv tb/tb_framebuffer_pattern_pixel.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_framebuffer_pattern_pixel -o $@ $^

build/tb_framebuffer_producer_lines.vvp: rtl/framebuffer_pattern_pixel.sv rtl/framebuffer_producer_lines.sv tb/tb_framebuffer_producer_lines.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_framebuffer_producer_lines -o $@ $^

clean:
	rm -rf build
