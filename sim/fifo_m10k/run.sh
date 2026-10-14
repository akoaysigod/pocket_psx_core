#!/bin/sh
# Equivalence of SyncFifoFallThroughMLAB with M10K => true against M10K => false (nvc + altera_mf models).
# usage: ALTERA_MF_DIR=<dir> [RAMFILE=<RamM10Kn variant>] sim/fifo_m10k/run.sh [NUM_CYCLES] [SEED]
set -e
here=$(cd "$(dirname "$0")" && pwd)
rtl="${RTL_DIR:-$here/../../rtl}"
work="${WORKDIR:-$here/work}"
mkdir -p "$work"; cd "$work"
L="-L . -L ${ALTERA_MF_DIR:-.}"
nvc --std=2008 $L --work=mem -a "$rtl/RamMLAB.vhd" "${RAMFILE:-$rtl/RamM10Kn.vhd}" "$rtl/SyncFifoFallThroughMLAB.vhd"
nvc --std=2008 $L -a "$here/tb_fifo_m10k.vhd"
nvc --std=2008 --ieee-warnings=off $L -e tb_fifo_m10k -gNUM_CYCLES=${1:-200000} -gSEED=${2:-1} -r
