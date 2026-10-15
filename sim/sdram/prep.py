#!/usr/bin/env python3
"""Simulation copy of an sdram.sv for Verilator: renames the module and splits the bidirectional SDRAM_DQ into
SDRAM_DQ_O / SDRAM_DQ_OE (controller drives) and SDRAM_DQ_I (read data), the same register behaviour.
usage: prep.py SRC.sv MODULE_NAME OUT.sv"""
import re
import sys

src, name, out = sys.argv[1:4]
s = open(src).read()
n = 0


def sub(pattern, repl, count=None):
    global s, n
    s, k = re.subn(pattern, repl, s)
    if count is not None and k != count:
        sys.exit('prep.py: %r matched %d times, expected %d' % (pattern, k, count))
    n += k


s, k = re.subn(r'(?m)^module sdram\b', 'module ' + name, s)
assert k == 1, 'module header'
sub(r'inout\s+reg\s+\[15:0\]\s+SDRAM_DQ,',
    'output reg [15:0] SDRAM_DQ_O, output reg SDRAM_DQ_OE = 0, input [15:0] SDRAM_DQ_I,', 1)
sub(r"SDRAM_DQ\s*<=\s*16'bZ;", 'SDRAM_DQ_OE <= 0;', 1)
sub(r'SDRAM_DQ\s*<=\s*(saved_data\[[0-9:]+\]);', r'begin SDRAM_DQ_O <= \1; SDRAM_DQ_OE <= 1; end')
sub(r'dq_reg\s*<=\s*SDRAM_DQ;', 'dq_reg <= SDRAM_DQ_I;', 1)
# the SDRAM_EN = 0 branch (outputs to Z) is dead on the Pocket (SDRAM_EN = 1); Verilator has no tristate regs
sub(r"<=\s*'Z;", "<= '0;", 4)
left = re.findall(r'\bSDRAM_DQ\b', s)
if left:
    sys.exit('prep.py: SDRAM_DQ still used %d times' % len(left))
open(out, 'w').write(s)
