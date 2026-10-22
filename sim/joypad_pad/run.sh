#!/bin/sh
# Equivalence test of rtl/joypad_pad.vhd against the joypad_pad before the Pocket trims (ref/pocket/rtl/joypad_pad.vhd,
# = upstream), see tb_joypad_pad.vhd.
# usage: [NEWFILE=<joypad_pad.vhd variant>] [REFFILE=<reference>] [ANYPAD=true] sim/joypad_pad/run.sh [NUM_CYCLES] [SEED]
set -e
here=$(cd "$(dirname "$0")" && pwd)
rtl="$here/../../rtl"
work="${WORKDIR:-$here/work}"
mkdir -p "$work"
ren() { sed -e "s/entity joypad_pad is/entity joypad_pad_$1 is/" -e "s/architecture arch of joypad_pad is/architecture arch of joypad_pad_$1 is/"; }
ren ref < "${REFFILE:-$here/../../ref/pocket/rtl/joypad_pad.vhd}" > "$work/joypad_pad_ref.vhd"
ren new < "${NEWFILE:-$rtl/joypad_pad.vhd}" > "$work/joypad_pad_new.vhd"
cd "$work"
nvc --std=2008 -a "$rtl/pJoypad.vhd" joypad_pad_ref.vhd joypad_pad_new.vhd "$here/tb_joypad_pad.vhd"
nvc --std=2008 --ieee-warnings=off -e tb_joypad_pad -gNUM_CYCLES=${1:-2000000} -gSEED=${2:-1} -gANYPAD=${ANYPAD:-false} -r
