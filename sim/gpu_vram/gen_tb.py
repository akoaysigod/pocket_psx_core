# Generates tb_gpu_vram.vhd: two complete GPUs (gpu_ref = reference gpu.vhd, gpu_new = current) driven by
# the same CPU bus traffic, each with its own (identically behaving) VRAM model.
import re, sys
rtl = sys.argv[1]
src = open(rtl + '/gpu.vhd').read()
ent = re.search(r'entity gpu is.*?port\s*\((.*?)\);\s*end entity', src, re.S).group(1)
ports = []
for line in ent.split('\n'):
    m = re.match(r'\s*(\w+)\s*:\s*(in|out|inout)\s+([^;:]+?)\s*(:=.*)?;?\s*(--.*)?$', line)
    if m: ports.append((m.group(1), m.group(2), m.group(3).strip()))
DRIVE = {'clk1x': 'clk1x', 'clk2x': 'clk2x', 'clk2xIndex': 'clk2xIndex', 'clkvid': 'clkvid', 'ce': 'ce', 'reset': 'reset',
         'bus_addr': 'bus_addr', 'bus_dataWrite': 'bus_dataWrite', 'bus_read': 'bus_read', 'bus_write': 'bus_write',
         'vram_pause': 'vram_pause', 'videoout_on': "'1'",
         'vram_BUSY': 'm(%d).busy', 'vram_DOUT': 'm(%d).dout', 'vram_DOUT_READY': 'm(%d).ready'}
OUTS = {'bus_dataRead': 'o(%d).bus_dataRead', 'bus_stall': 'o(%d).bus_stall', 'irq_GPU': 'o(%d).irq_GPU', 'irq_VBLANK': 'o(%d).irq_VBLANK',
        'vram_BURSTCNT': 'o(%d).vram_BURSTCNT', 'vram_ADDR': 'o(%d).vram_ADDR', 'vram_DIN': 'o(%d).vram_DIN', 'vram_BE': 'o(%d).vram_BE',
        'vram_WE': 'o(%d).vram_WE', 'vram_RD': 'o(%d).vram_RD', 'video_r': 'o(%d).video_r', 'video_g': 'o(%d).video_g', 'video_b': 'o(%d).video_b',
        'gpu_dmaRequest': 'o(%d).gpu_dmaRequest'}
def tie(t):
    t = t.lower()
    if t.startswith('std_logic_vector') or t.startswith('unsigned') or t.startswith('signed'): return '(others => \'0\')'
    if t.startswith('std_logic'): return "'0'"
    return '(others => \'0\')'
def inst(i, name):
    lines = []
    for n, d, t in ports:
        if d == 'in':
            v = DRIVE.get(n, tie(t))
            if '%d' in v: v = v % i
        else:
            v = OUTS.get(n, 'open')
            if '%d' in v: v = v % i
        lines.append('         %s => %s' % (n, v))
    return '      idut : entity work.%s\n      port map\n      (\n%s\n      );\n' % (name, ',\n'.join(lines))
tpl = open(sys.argv[2]).read()
tpl = tpl.replace('--@REF@', inst(0, 'gpu_ref')).replace('--@NEW@', inst(1, 'gpu_new'))
open(sys.argv[3], 'w').write(tpl)
