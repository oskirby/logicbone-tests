#!/usr/bin/env python3

import sys
import argparse

from migen import *
from migen.genlib.resetsync import AsyncResetSynchronizer

from litex.build.generic_platform import *
import logicbone


from litex.soc.cores.clock import *
from litex.soc.integration.soc_core import *
from litex.soc.integration.soc_sdram import *
from litex.soc.integration.builder import *
from litex.soc.cores.uart import UARTWishboneBridge
from litex.soc.interconnect import wishbone

from litedram.modules import MT41K512M8, AS4C1GM8
from litedram.phy.ecp5ddrphy import ECP5DDRPHY, ECP5DDRPHYInit
#from ecp5ddrphy import ECP5DDRPHY, ECP5DDRPHYInit
from litedram.init import get_sdram_phy_py_header
from litedram.frontend.bist import LiteDRAMBISTGenerator
from litedram.frontend.bist import LiteDRAMBISTChecker

from liteeth.common import *
from liteeth.phy.ecp5rgmii import LiteEthPHYRGMII
from liteeth.mac import LiteEthMAC
from liteeth.core import LiteEthUDPIPCore

from litescope import LiteScopeAnalyzer

# DDR3TestCRG --------------------------------------------------------------------------------------

class DDR3TestCRG(Module):
    def __init__(self, platform, sys_clk_freq):
        self.clock_domains.cd_init     = ClockDomain()
        self.clock_domains.cd_por      = ClockDomain(reset_less=True)
        self.clock_domains.cd_sys      = ClockDomain()
        self.clock_domains.cd_sys2x    = ClockDomain()
        self.clock_domains.cd_sys2x_i  = ClockDomain(reset_less=True)
        self.clock_domains.cd_sys2x_eb = ClockDomain(reset_less=True)


        # # #

        self.stop = Signal()

        # Clk / Rst
        clk25 = platform.request("refclk")

        # Power on reset
        por_count = Signal(16, reset=2**16-1)
        por_done  = Signal()
        self.comb += self.cd_por.clk.eq(ClockSignal())
        self.comb += por_done.eq(por_count == 0)
        self.sync.por += If(~por_done, por_count.eq(por_count - 1))

        # PLL
        sys2x_clk_ecsout = Signal()
        self.submodules.pll = pll = ECP5PLL()
        pll.register_clkin(clk25, 25e6)
        pll.create_clkout(self.cd_sys2x_i, 2*sys_clk_freq)
        pll.create_clkout(self.cd_init, 24e6)
        self.specials += [
            Instance("ECLKBRIDGECS",
                i_CLK0   = self.cd_sys2x_i.clk,
                i_SEL    = 0,
                o_ECSOUT = sys2x_clk_ecsout),
            Instance("ECLKSYNCB",
                i_ECLKI = sys2x_clk_ecsout,
                i_STOP  = self.stop,
                o_ECLKO = self.cd_sys2x.clk),
            Instance("CLKDIVF",
                p_DIV     = "2.0",
                i_ALIGNWD = 0,
                i_CLKI    = self.cd_sys2x.clk,
                i_RST     = self.cd_sys2x.rst,
                o_CDIVX   = self.cd_sys.clk),
            AsyncResetSynchronizer(self.cd_init, ~por_done | ~pll.locked),
            AsyncResetSynchronizer(self.cd_sys,  ~por_done | ~pll.locked)
        ]
        

# DDR3TestSoC --------------------------------------------------------------------------------------

class DDR3TestSoC(SoCSDRAM):
    csr_map = {
        "ddrphy":    16,
        "analyzer":  17
    }
    csr_map.update(SoCSDRAM.csr_map)
    def __init__(self, toolchain="trellis"):
        platform = logicbone.Platform(toolchain=toolchain, device="85F")
        
        sys_clk_freq = int(75e6)
        SoCSDRAM.__init__(self, platform, clk_freq=sys_clk_freq,
                          cpu_type=None, l2_size=32,
                          with_uart=None,
                          csr_data_width=32,
                          ident="Logicbone test SoC", ident_version=True)

        #self.comb += platform.request("rst_n").eq(1)

        # crg
        crg = DDR3TestCRG(platform, sys_clk_freq)
        self.submodules.crg = crg

        # uart
        self.submodules.bridge = UARTWishboneBridge(platform.request("serial"), sys_clk_freq, baudrate=115200)
        self.add_wb_master(self.bridge.wishbone)

        # sdram
        self.submodules.ddrphy = ECP5DDRPHY(
            platform.request("ddram"),
            sys_clk_freq=sys_clk_freq)
        self.comb += crg.stop.eq(self.ddrphy.init.stop)
        sdram_module = MT41K512M8(sys_clk_freq, "1:2")
        #sdram_module = AS4C1GM8(sys_clk_freq, "1:2")
        self.register_sdram(self.ddrphy,
            sdram_module.geom_settings,
            sdram_module.timing_settings)

        # led blinking
        led_counter = Signal(32)
        self.sync += led_counter.eq(led_counter + 1)
        self.comb += platform.request("user_led", 0).eq(led_counter[26])

        # analyzer
        analyzer_signals = [
            self.ddrphy.dfi.p0,
            self.ddrphy.datavalid,
            #self.ddrphy.burstdet
        ]
        self.submodules.analyzer = LiteScopeAnalyzer(analyzer_signals, 128)

    def generate_sdram_phy_py_header(self):
        f = open("test/sdram_init.py", "w")
        f.write(get_sdram_phy_py_header(
            self.sdram.controller.settings.phy,
            self.sdram.controller.settings.timing))
        f.close()

    def do_exit(self, vns):
        if hasattr(self, "analyzer"):
            self.analyzer.export_csv(vns, "test/analyzer.csv")

# BaseSoC ------------------------------------------------------------------------------------------

class BaseSoC(SoCSDRAM):
    csr_map = {
        "ddrphy":    16,
    }
    csr_map.update(SoCSDRAM.csr_map)
    def __init__(self, toolchain="trellis", **kwargs):
        platform = logicbone.Platform(toolchain=toolchain)
        sys_clk_freq = int(48e6)
        SoCSDRAM.__init__(self, platform, clk_freq=sys_clk_freq,
                          cpu_type="vexriscv",
                          integrated_rom_size=0x8000,
                          ident="Logicbone test SoC",
                          **kwargs)

        # crg
        if not self.integrated_main_ram_size:
            crg = DDR3TestCRG(platform, sys_clk_freq)
        else:
            crg = RGMIITestCRG(platform, sys_clk_freq)
        self.submodules.crg = crg

        # sdram
        self.submodules.ddrphy = ECP5DDRPHY(
            platform.request("ddram"),
            sys_clk_freq=sys_clk_freq)
        self.add_constant("ECP5DDRPHY", None)
        self.comb += crg.stop.eq(self.ddrphy.init.stop)
        sdram_module = MT41K512M8(sys_clk_freq, "1:2")
        self.register_sdram(self.ddrphy,
            sdram_module.geom_settings,
            sdram_module.timing_settings)

        # led blinking
        led_counter = Signal(32)
        self.sync += led_counter.eq(led_counter + 1)
        self.comb += platform.request("user_led", 0).eq(led_counter[26])


class LED(SoCCore):
    
    def __init__(self, toolchain="trellis", **kwargs):
        platform = logicbone.Platform(toolchain=toolchain)
        sys_clk_freq = int(10e6)
    
        SoCCore.__init__(self, platform, clk_freq=sys_clk_freq,
                          cpu_type=None,
                          integrated_rom_size=0,
                          ident="Logicbone test SoC",
                          **kwargs)

        # crg
        crg = DDR3TestCRG(platform, sys_clk_freq)
        self.submodules.crg = crg

        
        led = platform.request("user_led", 0)
        btn = platform.request("usr_btn", 0)
        # led blinking
        led_counter = Signal(32)
        latch = Signal(32)
        self.sync += [
            If(latch == 0xFFFF0000,
                led_counter.eq(led_counter + 1)
            ),
            latch.eq(Cat(btn,latch[0:31]))
            
        ]
        self.comb += [
            led.eq(~led_counter[0]),
        ]


# BISTSoC --------------------------------------------------------------------------------------
class BISTSoC(BaseSoC):
    csr_map = {
        "sdram_generator": 20,
        "sdram_checker":   21
    }
    csr_map.update(BaseSoC.csr_map)
    def __init__(self, **kwargs):
        BaseSoC.__init__(self, **kwargs)
        self.submodules.sdram_generator = LiteDRAMBISTGenerator(self.sdram.crossbar.get_port())
        self.submodules.sdram_checker = LiteDRAMBISTChecker(self.sdram.crossbar.get_port())

# Build --------------------------------------------------------------------------------------------

def main():

    toolchain = "trellis"

    if "ddr3_test" in sys.argv[1:]:
        soc = DDR3TestSoC(toolchain=toolchain)
    elif "base" in sys.argv[1:]:
        soc = BaseSoC(toolchain=toolchain)
    elif "bist" in sys.argv[1:]:
        soc = BISTSoC(toolchain=toolchain)
    elif "led" in sys.argv[1:]:
        soc = LED(toolchain=toolchain)
    else:
        print("missing target, supported: (ddr3_test, base, ethernet, bist)")
        exit(1)
    builder = Builder(soc, output_dir="build", csr_csv="test/csr.csv")
    vns = builder.build()
    if isinstance(soc, DDR3TestSoC):
        soc.do_exit(vns)
        soc.generate_sdram_phy_py_header()
    
if __name__ == "__main__":
    main()
