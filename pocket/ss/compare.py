#!/usr/bin/env python3
"""Compares a save (dump A, taken while the core was frozen) with the state a restore from it put back (dump B,
taken when the restore was done, with the routine's self-check: the restored state collected into 0x240000).

usage: compare.py <dir>/<prefix A> <dir>/<prefix B>     (files <prefix>_ram.hex, _spu.hex, _vram0.hex, _vram1.hex)
"""
import struct
import sys

BLOCK, VERIFY = 0x220000, 0x240000

# collected regions of the state block: (name, offset, length in bytes, word size)
REGIONS = [
    ('memctrl', 0x180, 0x28, 4), ('cache control', 0x12C, 4, 4),
    ('GTE data', 0x200, 0x80, 4), ('GTE control', 0x280, 0x80, 4),
    ('I_STAT / I_MASK', 0x300, 8, 4), ('DMA', 0x310, 0x5C, 4), ('timers', 0x380, 0x30, 4),
    ('joypad', 0x3C0, 8, 4), ('GPU', 0x400, 0x28, 4), ('MDEC', 0x440, 0x110, 4), ('CD', 0x600, 11, 1),
    ('CD data fifo count', 0x60C, 4, 4),
    ('CD controller', 0x700, 0x100, 4),
    ('SPU registers', 0x800, 0x300, 2), ('SPU hidden', 0xB00, 8, 2), ('SPU voice records', 0xC00, 0x180, 2),
    ('scratchpad', 0x1000, 0x400, 4), ('SPU capture RAM', 0x2000, 0x1000, 2), ('SPU reverb RAM', 0x3000, 0x10000, 2),
]

NAMES = {
    ('GPU', 0x400): 'GPUSTAT', ('GPU', 0x404): 'GPUREAD', ('I_STAT / I_MASK', 0x300): 'I_STAT',
    ('I_STAT / I_MASK', 0x304): 'I_MASK', ('DMA', 0x310): 'DPCR', ('DMA', 0x314): 'DICR',
    ('MDEC', 0x440): 'MDECSTAT', ('MDEC', 0x444): 'MDEC control',
}
for i in range(8):
    NAMES[('GPU', 0x408 + 4 * i)] = 'GP1(10h) %d' % i
for c in range(7):
    for j, r in enumerate(('MADR', 'BCR', 'CHCR')):
        NAMES[('DMA', 0x318 + 12 * c + 4 * j)] = 'ch%d %s' % (c, r)
for t in range(3):
    for j, r in enumerate(('CURRENT', 'MODE', 'TARGET', 'hidden')):
        NAMES[('timers', 0x380 + 16 * t + 4 * j)] = 'timer%d %s' % (t, r)
for v in range(24):
    for j, r in enumerate(('currentAddr', 'adpcmLast0', 'adpcmLast1', 'samplePos', 'lane4')):
        NAMES[('SPU voice records', 0xC00 + 16 * v + 2 * j)] = 'voice%d %s' % (v, r)
SPU_REGS = {0x188: 'KEYON', 0x18A: 'KEYON hi', 0x18C: 'KEYOFF', 0x18E: 'KEYOFF hi', 0x19C: 'ENDX', 0x19E: 'ENDX hi',
            0x1AA: 'SPUCNT', 0x1AE: 'SPUSTAT', 0x1B8: 'CURVOL L', 0x1BA: 'CURVOL R'}
for o, n in SPU_REGS.items():
    NAMES[('SPU registers', 0x800 + o)] = n
for o in range(0, 0x180, 2):
    NAMES.setdefault(('SPU registers', 0x800 + o), 'voice%d +%X' % (o // 16, o % 16))
for o in range(0x200, 0x260, 2):
    NAMES[('SPU registers', 0x800 + o)] = 'voice%d current volume %s' % ((o - 0x200) // 4, 'LR'[(o // 2) % 2])


def load(name):
    words = [int(l, 16) for l in open(name)]
    return b''.join(struct.pack('<I', w) for w in words)


def load16(name):
    return [int(l, 16) for l in open(name)]


def main():
    a, b = sys.argv[1], sys.argv[2]
    ra, rb = load(a + '_ram.hex'), load(b + '_ram.hex')
    hdr = struct.unpack_from('<III', ra, BLOCK)
    print('state block: magic %08X version %d flags %X' % hdr)
    gpr = struct.unpack_from('<32I', ra, BLOCK + 0x80)
    print('saved: SR %08X CAUSE %08X EPC %08X resume %08X' % struct.unpack_from('<4I', ra, BLOCK + 0x108))
    print('GPRs: ' + ' '.join('%08X' % g for g in gpr))
    diffs = 0
    for name, off, length, ws in REGIONS:
        fmt = {1: 'B', 2: 'H', 4: 'I'}[ws]
        n = length // ws
        va = struct.unpack_from('<%d%s' % (n, fmt), ra, BLOCK + off)
        vb = struct.unpack_from('<%d%s' % (n, fmt), rb, VERIFY + off)
        bad = [(i, x, y) for i, (x, y) in enumerate(zip(va, vb)) if x != y]
        print('%-18s %s' % (name, 'same' if not bad else '%d differences' % len(bad)))
        for i, x, y in bad[:12]:
            o = off + i * ws
            print('    +%05X %-28s saved %0*X restored %0*X' % (o, NAMES.get((name, o), ''), 2 * ws, x, 2 * ws, y))
        diffs += len(bad)
    n = struct.unpack_from('<I', ra, BLOCK + 0x60C)[0] if hdr[1] >= 2 else 0   # version 2: the CD data fifo
    fa, fb = ra[BLOCK + 0x13000:BLOCK + 0x13000 + n], rb[VERIFY + 0x13000:VERIFY + 0x13000 + n]
    print('%-18s %d bytes, %s' % ('CD data fifo', n, 'same' if fa == fb else 'DIFFERENT'))
    diffs += fa != fb
    same = ra[:0x200000] == rb[:0x200000]
    print('main RAM (2 MB): %s' % ('same' if same else 'DIFFERENT'))
    if not same:
        bad = [i for i in range(0, 0x200000, 4) if ra[i:i + 4] != rb[i:i + 4]]
        print('    %d words differ, first at %s' % (len(bad), ', '.join('%06X' % i for i in bad[:8])))
    for suffix in ('_spu.hex', '_vram0.hex', '_vram1.hex'):
        x, y = open(a + suffix).read(), open(b + suffix).read()
        print('%-16s %s' % (suffix[1:-4], 'same' if x == y else 'DIFFERENT'))
    print('%d differences in the collected registers' % diffs)


main()
