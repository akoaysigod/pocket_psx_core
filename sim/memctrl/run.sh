#!/bin/sh
# Equivalence test of rtl/memctrl.vhd against the upstream memctrl (ref/upstream/rtl/memctrl.vhd).
# usage: [NEWFILE=<memctrl.vhd variant>] [REFFILE=<reference>] sim/memctrl/run.sh [NUM_CYCLES] [SEED]
set -e
here=$(cd "$(dirname "$0")" && pwd)
work="${WORKDIR:-$here/work}"
mkdir -p "$work"
ren() { sed -e "s/entity memctrl is/entity memctrl_$1 is/" -e "s/architecture arch of memctrl is/architecture arch of memctrl_$1 is/"; }
ren ref < "${REFFILE:-$here/../../ref/upstream/rtl/memctrl.vhd}" > "$work/memctrl_ref.vhd"
ren new < "${NEWFILE:-$here/../../rtl/memctrl.vhd}" > "$work/memctrl_new.vhd"
cd "$work"
nvc --std=2008 -a memctrl_ref.vhd memctrl_new.vhd "$here/tb_memctrl.vhd"
nvc --std=2008 -e tb_memctrl -gNUM_CYCLES=${1:-200000} -gSEED=${2:-1} -r --ieee-warnings=off
