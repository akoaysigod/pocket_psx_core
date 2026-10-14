#!/bin/sh
# Equivalence test of the current rtl/spu.vhd against the upstream original (ref/upstream/rtl/spu.vhd).
# usage: ALTERA_MF_DIR=<compiled altera_mf dir> [NEWFILE=<spu.vhd variant>] [REFFILE=<reference spu.vhd>] sim/spu_equiv/run.sh [NUM_CYCLES] [SEED]
set -e
here=$(cd "$(dirname "$0")" && pwd)
rtl="$here/../../rtl"
work="${WORKDIR:-$here/work}"
mkdir -p "$work"
strip() { python3 -c '
import sys
s = sys.stdin.read().replace("entity spu is", "entity spu_%s is" % sys.argv[1]).replace("architecture arch of spu is", "architecture arch of spu_%s is" % sys.argv[1])
a = s.find("   -- synthesis translate_off\n   \n   goutput")
if a == -1: a = s.find("goutput : if")
if a != -1:
    a = s.rfind("-- synthesis translate_off", 0, a + 40)
    b = s.index("-- synthesis translate_on", a)
    s = s[:a] + s[b:]
sys.stdout.write(s)' "$1"; }
strip ref < "${REFFILE:-$here/../../ref/upstream/rtl/spu.vhd}" > "$work/spu_ref.vhd"
strip new < "${NEWFILE:-$rtl/spu.vhd}" > "$work/spu_new.vhd"
cd "$work"
L="-L . -L ${ALTERA_MF_DIR:-.}"
nvc --std=2008 $L --work=mem -a "$rtl/SyncFifo.vhd" "$rtl/SyncFifoFallThrough.vhd" "$rtl/RamMLAB.vhd" "$rtl/RamM10Kn.vhd" "$rtl/dpram.vhd"
nvc --std=2008 $L -a "$rtl/dpram.vhd" "$rtl/spu_gauss.vhd" "$rtl/spu_ram.vhd" spu_ref.vhd spu_new.vhd "$here/tb_spu_equiv.vhd"
nvc --std=2008 $L -e tb_spu_equiv -gNUM_CYCLES=${1:-2000000} -gSEED=${2:-1} -r --ieee-warnings=off
