#!/bin/sh
# Equivalence test of rtl/savestates_reset.vhd against rtl/savestates.vhd using nvc.
# usage: sim/savestates_reset/run.sh [NUM_RESETS] [FASTSIM 0|1] [SPUSDRAM 0|1] [SEED]
set -e
here=$(cd "$(dirname "$0")" && pwd)
rtl="$here/../../rtl"
work="${WORKDIR:-$here/work}"
mkdir -p "$work"
sed -e 's/entity savestates is/entity savestates_ref is/' -e 's/architecture arch of savestates is/architecture arch of savestates_ref is/' \
    "$rtl/savestates.vhd" > "$work/savestates_ref.vhd"
sed -e 's/entity savestates is/entity savestates_new is/' -e 's/architecture arch of savestates is/architecture arch of savestates_new is/' \
    "$rtl/savestates_reset.vhd" > "$work/savestates_new.vhd"
cd "$work"
nvc --std=2008 -a savestates_ref.vhd savestates_new.vhd "$here/tb_ss_equiv.vhd"
nvc --std=2008 -e tb_ss_equiv -gNUM_RESETS=${1:-3} -gFASTSIM="'${2:-0}'" -gSPUSDRAM="'${3:-1}'" -gSEED=${4:-1} -r --ieee-warnings=off
