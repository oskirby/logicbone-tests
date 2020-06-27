from nmigen import *
from nmigen.back.pysim import *
from logicbone_platform import *

class TestModule(Elaboratable):
    def __init__(self):
        self.count = Signal(32, reset=0)

    def elaborate(self, platform):
        m = Module()
        m.d.sync += self.count.eq(self.count+1)
        if platform is not None:
            led0 = platform.request("led", 0)
            led1 = platform.request("led", 1)
            led2 = platform.request("led", 2)
            led3 = platform.request("led", 3)
            m.d.comb += led0.o.eq(self.count[22])
            m.d.comb += led1.o.eq(~self.count[22])

        return m

if __name__ == "__main__":
    dut = TestModule()
    LogicbonePlatform().build(dut, ecppack_opts="--spimode qspi")
