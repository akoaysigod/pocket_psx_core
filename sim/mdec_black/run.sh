#!/bin/sh
# Equivalence test of rtl/mdec_black.vhd against rtl/mdec.vhd using nvc.
# usage: ALTERA_MF_DIR=<dir containing compiled altera_mf> sim/mdec_black/run.sh [NUM_CMDS] [SEED]
# (compile altera_mf from quartus/eda/sim_lib/altera_mf*.vhd with: nvc --std=2008 --work=altera_mf -a ...)
set -e
here=$(cd "$(dirname "$0")" && pwd)
rtl="$here/../../rtl"
work="${WORKDIR:-$here/work}"
mkdir -p "$work"
for v in ref:mdec.vhd new:mdec_black.vhd; do
   name=${v%%:*}; file=${v#*:}
   sed -e "s/entity mdec is/entity mdec_$name is/" -e "s/architecture arch of mdec is/architecture arch of mdec_$name is/" \
       "$rtl/$file" | python3 -c '
import sys
s = sys.stdin.read()
a = s.find("-- synthesis translate_off\n   \n   goutput")
if a != -1:
    b = s.index("-- synthesis translate_on", a)
    s = s[:a] + s[b:]
sys.stdout.write(s)' > "$work/mdec_$name.vhd"
done
cd "$work"
nvc --std=2008 --work=mem -a "$rtl/SyncFifo.vhd" "$rtl/SyncFifoFallThrough.vhd"
nvc --std=2008 -L . -L "${ALTERA_MF_DIR:-.}" -a "$rtl/dpram.vhd" mdec_ref.vhd mdec_new.vhd "$here/tb_mdec_equiv.vhd"
nvc --std=2008 -L . -L "${ALTERA_MF_DIR:-.}" -e tb_mdec_equiv -gNUM_CMDS=${1:-200} -gSEED=${2:-1} -gCE_RAND=${CE_RAND:-1} -r --ieee-warnings=off
