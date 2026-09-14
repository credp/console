IVERILOG ?= iverilog
VVP ?= vvp

.PHONY: test clean

test: build/tb_framebuffer_pattern_pixel.vvp build/tb_framebuffer_machine_line_source.vvp build/tb_framebuffer_producer_lines.vvp build/tb_framebuffer_line_write_sequencer.vvp build/tb_framebuffer_producer_write_path.vvp
	$(VVP) $<
	$(VVP) build/tb_framebuffer_machine_line_source.vvp
	$(VVP) build/tb_framebuffer_producer_lines.vvp
	$(VVP) build/tb_framebuffer_line_write_sequencer.vvp
	$(VVP) build/tb_framebuffer_producer_write_path.vvp

build/tb_framebuffer_pattern_pixel.vvp: rtl/framebuffer_pattern_pixel.sv tb/tb_framebuffer_pattern_pixel.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_framebuffer_pattern_pixel -o $@ $^

build/tb_framebuffer_machine_line_source.vvp: rtl/framebuffer_pattern_pixel.sv rtl/framebuffer_machine_line_source.sv tb/tb_framebuffer_machine_line_source.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_framebuffer_machine_line_source -o $@ $^

build/tb_framebuffer_producer_lines.vvp: rtl/framebuffer_pattern_pixel.sv rtl/framebuffer_machine_line_source.sv rtl/framebuffer_producer_lines.sv tb/tb_framebuffer_producer_lines.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_framebuffer_producer_lines -o $@ $^

build/tb_framebuffer_line_write_sequencer.vvp: rtl/framebuffer_line_write_sequencer.sv tb/tb_framebuffer_line_write_sequencer.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_framebuffer_line_write_sequencer -o $@ $^

build/tb_framebuffer_producer_write_path.vvp: rtl/framebuffer_pattern_pixel.sv rtl/framebuffer_machine_line_source.sv rtl/framebuffer_producer_lines.sv rtl/framebuffer_line_write_sequencer.sv rtl/framebuffer_producer_write_path.sv tb/tb_framebuffer_producer_write_path.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_framebuffer_producer_write_path -o $@ $^

clean:
	rm -rf build
