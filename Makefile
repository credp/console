.PHONY: sdram-sim sdram-test

sdram-sim:
	@tools/sdram-model/sdram-sim

sdram-test:
	@python3 -m unittest discover -s tools/sdram-model/tests -v
