#!/bin/sh
# Shows memory card slot 2 never does anything when no card is present (justifies removing imemcard2).
# usage: ALTERA_MF_DIR=<dir with compiled altera_mf> sim/memcard2_off/run.sh [CYCLES] [SEED] [MUTATE]
set -e
here=$(cd "$(dirname "$0")" && pwd)
rtl="$here/../../rtl"
work="${WORKDIR:-$here/work}"
mkdir -p "$work"; cd "$work"
nvc --std=2008 -L . -L "${ALTERA_MF_DIR:-.}" -a "$rtl/dpram.vhd" "$rtl/joypad_mem.vhd" "$rtl/memcard.vhd" "$here/tb_memcard2_idle.vhd"
nvc --std=2008 -L . -L "${ALTERA_MF_DIR:-.}" -e tb_memcard2_idle -gNUM_CYCLES=${1:-200000} -gSEED=${2:-1} -gMUTATE=${3:-0} -r --ieee-warnings=off
