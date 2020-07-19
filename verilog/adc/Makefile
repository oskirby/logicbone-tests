PROJ=adc
DEVICE=--um5g-45k
SOURCES=top.v adc.v

all: $(PROJ).bit $(PROJ).svf $(PROJ).dfu

$(PROJ).json: $(SOURCES)
	yosys -p "synth_ecp5 -top top -json $@" $^

%_out.config: %.json
	nextpnr-ecp5 --json $< --textcfg $@ $(DEVICE) --package CABGA381 --lpf ../logicbone-rev0.lpf

%.bit: %_out.config
	ecppack --spimode qspi $< $@

%.svf: %_out.config
	ecppack --svf $@ $<

%.dfu: %.bit
	dfu-tool -d 1d50:615d convert dfu $^ $@

prog: ${PROJ}.svf
	openocd -f ../logicbone-jlink.cfg -c "transport select jtag; init; svf $<; exit"

dfu: ${PROJ}.dfu
	dfu-util -d 1d50:615d -a0 -D $<

clean:
	rm -f *.svf *.bit *.dfu *.config *.json

.PHONY: prog clean

