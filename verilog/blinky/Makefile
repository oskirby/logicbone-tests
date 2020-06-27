PROJ=blinky

all: ${PROJ}.bit ${PROJ}.svf

%.json: %.v
	yosys -p "synth_ecp5 -json $@" $<

%_out.config: %.json
	nextpnr-ecp5 --json $< --textcfg $@ --um5g-45k --package CABGA381 --lpf ../logicbone-rev0.lpf

%.bit: %_out.config
	ecppack --spimode qspi $< $@

%.svf : %_out.config
	ecppack --svf $@ $<

prog: ${PROJ}.svf
	openocd -f ../logicbone-jlink.cfg -c "transport select jtag; init; svf $<; exit"

clean:
	rm -f *.svf *.bit *.config *.json

.PHONY: prog clean

