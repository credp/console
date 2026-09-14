IVERILOG ?= iverilog
VVP ?= vvp

.PHONY: test test-producer-bl8 test-producer-bl8-refresh test-producer-bl8-capacity test-producer-bl8-chunks waveform clean

test: build/tb_framebuffer_pattern_pixel.vvp build/tb_framebuffer_machine_line_source.vvp build/tb_framebuffer_line_chunk_address.vvp build/tb_framebuffer_producer_lines.vvp build/tb_framebuffer_line_write_sequencer.vvp build/tb_framebuffer_producer_write_path.vvp build/tb_framebuffer_consumer_lines.vvp build/tb_framebuffer_line_read_sequencer.vvp build/tb_framebuffer_consumer_line_scheduler.vvp build/tb_framebuffer_scanout_timing_adapter.vvp build/tb_framebuffer_write_read_path.vvp
	$(VVP) $<
	$(VVP) build/tb_framebuffer_machine_line_source.vvp
	$(VVP) build/tb_framebuffer_line_chunk_address.vvp
	$(VVP) build/tb_framebuffer_producer_lines.vvp
	$(VVP) build/tb_framebuffer_line_write_sequencer.vvp
	$(VVP) build/tb_framebuffer_producer_write_path.vvp
	$(VVP) build/tb_framebuffer_consumer_lines.vvp
	$(VVP) build/tb_framebuffer_line_read_sequencer.vvp
	$(VVP) build/tb_framebuffer_consumer_line_scheduler.vvp
	$(VVP) build/tb_framebuffer_scanout_timing_adapter.vvp
	$(VVP) build/tb_framebuffer_write_read_path.vvp

waveform: build/tb_framebuffer_write_read_path.vvp
	$(VVP) build/tb_framebuffer_write_read_path.vvp

test-producer-bl8: build/tb_framebuffer_producer_bl8_write_backend.vvp
	$(VVP) build/tb_framebuffer_producer_bl8_write_backend.vvp

test-producer-bl8-refresh: build/tb_framebuffer_producer_bl8_refresh.vvp
	$(VVP) build/tb_framebuffer_producer_bl8_refresh.vvp

test-producer-bl8-capacity: build/tb_framebuffer_producer_bl8_capacity.vvp
	$(VVP) build/tb_framebuffer_producer_bl8_capacity.vvp

test-producer-bl8-chunks: build/tb_framebuffer_producer_bl8_chunks.vvp
	$(VVP) build/tb_framebuffer_producer_bl8_chunks.vvp

build/tb_framebuffer_pattern_pixel.vvp: rtl/framebuffer_pattern_pixel.sv tb/tb_framebuffer_pattern_pixel.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_framebuffer_pattern_pixel -o $@ $^

build/tb_framebuffer_machine_line_source.vvp: rtl/framebuffer_pattern_pixel.sv rtl/framebuffer_machine_line_source.sv tb/tb_framebuffer_machine_line_source.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_framebuffer_machine_line_source -o $@ $^

build/tb_framebuffer_line_chunk_address.vvp: rtl/framebuffer_line_chunk_address.sv tb/tb_framebuffer_line_chunk_address.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_framebuffer_line_chunk_address -o $@ $^

build/tb_framebuffer_producer_lines.vvp: rtl/framebuffer_pattern_pixel.sv rtl/framebuffer_machine_line_source.sv rtl/framebuffer_producer_lines.sv tb/tb_framebuffer_producer_lines.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_framebuffer_producer_lines -o $@ $^

build/tb_framebuffer_line_write_sequencer.vvp: rtl/framebuffer_line_chunk_address.sv rtl/framebuffer_line_write_sequencer.sv tb/tb_framebuffer_line_write_sequencer.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_framebuffer_line_write_sequencer -o $@ $^

build/tb_framebuffer_producer_write_path.vvp: rtl/framebuffer_pattern_pixel.sv rtl/framebuffer_machine_line_source.sv rtl/framebuffer_line_chunk_address.sv rtl/framebuffer_producer_lines.sv rtl/framebuffer_line_write_sequencer.sv rtl/framebuffer_producer_write_path.sv tb/tb_framebuffer_producer_write_path.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_framebuffer_producer_write_path -o $@ $^

build/tb_framebuffer_consumer_lines.vvp: rtl/framebuffer_consumer_lines.sv tb/tb_framebuffer_consumer_lines.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_framebuffer_consumer_lines -o $@ $^

build/tb_framebuffer_line_read_sequencer.vvp: rtl/framebuffer_line_chunk_address.sv rtl/framebuffer_line_read_sequencer.sv tb/tb_framebuffer_line_read_sequencer.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_framebuffer_line_read_sequencer -o $@ $^

build/tb_framebuffer_consumer_line_scheduler.vvp: rtl/framebuffer_consumer_line_scheduler.sv tb/tb_framebuffer_consumer_line_scheduler.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_framebuffer_consumer_line_scheduler -o $@ $^

build/tb_framebuffer_scanout_timing_adapter.vvp: rtl/framebuffer_scanout_timing_adapter.sv tb/tb_framebuffer_scanout_timing_adapter.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_framebuffer_scanout_timing_adapter -o $@ $^

build/tb_framebuffer_write_read_path.vvp: rtl/framebuffer_pattern_pixel.sv rtl/framebuffer_machine_line_source.sv rtl/framebuffer_line_chunk_address.sv rtl/framebuffer_producer_lines.sv rtl/framebuffer_line_write_sequencer.sv rtl/framebuffer_producer_write_path.sv rtl/framebuffer_consumer_lines.sv rtl/framebuffer_line_read_sequencer.sv rtl/framebuffer_consumer_line_scheduler.sv rtl/framebuffer_consumer_read_path.sv rtl/framebuffer_transfer_statistics.sv tb/tb_framebuffer_write_read_path.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_framebuffer_write_read_path -o $@ $^

build/tb_framebuffer_producer_bl8_write_backend.vvp: rtl/framebuffer_pattern_pixel.sv rtl/framebuffer_machine_line_source.sv rtl/framebuffer_line_chunk_address.sv rtl/framebuffer_producer_lines.sv rtl/framebuffer_line_write_sequencer.sv rtl/framebuffer_producer_write_path.sv rtl/framebuffer_bl8_write_backend.sv tb/tb_framebuffer_producer_bl8_write_backend.sv ../../rtl/scanout-sdram-controller/tb/backend-bench/altddio_out_sim.sv ../../rtl/scanout-sdram-controller/tb/pin-model/sdram_pair_model.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -DSIMULATION -s tb_framebuffer_producer_bl8_write_backend -o $@ $^

build/tb_framebuffer_producer_bl8_refresh.vvp: rtl/framebuffer_pattern_pixel.sv rtl/framebuffer_machine_line_source.sv rtl/framebuffer_line_chunk_address.sv rtl/framebuffer_producer_lines.sv rtl/framebuffer_line_write_sequencer.sv rtl/framebuffer_producer_write_path.sv rtl/framebuffer_bl8_write_backend.sv tb/tb_framebuffer_producer_bl8_write_backend.sv ../../rtl/scanout-sdram-controller/tb/backend-bench/altddio_out_sim.sv ../../rtl/scanout-sdram-controller/tb/pin-model/sdram_pair_model.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -DSIMULATION -Ptb_framebuffer_producer_bl8_write_backend.REFRESH_INTERVAL_CYCLES=16 -Ptb_framebuffer_producer_bl8_write_backend.REQUIRE_RUNTIME_REFRESH=1 -s tb_framebuffer_producer_bl8_write_backend -o $@ $^

build/tb_framebuffer_producer_bl8_capacity.vvp: rtl/framebuffer_pattern_pixel.sv rtl/framebuffer_machine_line_source.sv rtl/framebuffer_line_chunk_address.sv rtl/framebuffer_producer_lines.sv rtl/framebuffer_line_write_sequencer.sv rtl/framebuffer_producer_write_path.sv rtl/framebuffer_bl8_write_backend.sv tb/tb_framebuffer_producer_bl8_write_backend.sv ../../rtl/scanout-sdram-controller/tb/backend-bench/altddio_out_sim.sv ../../rtl/scanout-sdram-controller/tb/pin-model/sdram_pair_model.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -DSIMULATION -Ptb_framebuffer_producer_bl8_write_backend.TEST_WIDTH=1280 -Ptb_framebuffer_producer_bl8_write_backend.TEST_HEIGHT=4 -Ptb_framebuffer_producer_bl8_write_backend.TEST_ADDR_WIDTH=11 -Ptb_framebuffer_producer_bl8_write_backend.TEST_CHUNK_WORDS=1280 -Ptb_framebuffer_producer_bl8_write_backend.REQUIRE_PRODUCER_STALL=1 -s tb_framebuffer_producer_bl8_write_backend -o $@ $^

build/tb_framebuffer_producer_bl8_chunks.vvp: rtl/framebuffer_pattern_pixel.sv rtl/framebuffer_machine_line_source.sv rtl/framebuffer_line_chunk_address.sv rtl/framebuffer_producer_lines.sv rtl/framebuffer_line_write_sequencer.sv rtl/framebuffer_producer_write_path.sv rtl/framebuffer_bl8_write_backend.sv tb/tb_framebuffer_producer_bl8_write_backend.sv ../../rtl/scanout-sdram-controller/tb/backend-bench/altddio_out_sim.sv ../../rtl/scanout-sdram-controller/tb/pin-model/sdram_pair_model.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -DSIMULATION -Ptb_framebuffer_producer_bl8_write_backend.TEST_WIDTH=1280 -Ptb_framebuffer_producer_bl8_write_backend.TEST_HEIGHT=4 -Ptb_framebuffer_producer_bl8_write_backend.TEST_ADDR_WIDTH=11 -Ptb_framebuffer_producer_bl8_write_backend.TEST_CHUNK_WORDS=128 -Ptb_framebuffer_producer_bl8_write_backend.REQUIRE_PRODUCER_STALL=1 -s tb_framebuffer_producer_bl8_write_backend -o $@ $^

clean:
	rm -rf build
