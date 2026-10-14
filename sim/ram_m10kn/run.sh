#!/bin/sh
# Component equivalence of rtl/RamM10Kn.vhd against rtl/RamMLAB.vhd (nvc + altera_mf models).
# usage: ALTERA_MF_DIR=<dir> sim/ram_m10kn/run.sh [NUM_CYCLES] [SEED] [WIDTH] [WIDTHAD]
set -e
here=$(cd "$(dirname "$0")" && pwd)
rtl="${RTL_DIR:-$here/../../rtl}"
work="${WORKDIR:-$here/work}"
mkdir -p "$work"; cd "$work"
nvc --std=2008 -L "${ALTERA_MF_DIR:-.}" -a "$rtl/RamMLAB.vhd" "$rtl/RamM10Kn.vhd" "$here/tb_ram_m10kn.vhd"
nvc --std=2008 --ieee-warnings=off -L "${ALTERA_MF_DIR:-.}" -e tb_ram_m10kn -gNUM_CYCLES=${1:-200000} -gSEED=${2:-1} -gWIDTH=${3:-24} -gWIDTHAD=${4:-8} -r
