#!/usr/bin/env python3

import os

os.system("dfu-util -d 1d50:6130 -a0 -D build/gateware/logicbone.bit")
