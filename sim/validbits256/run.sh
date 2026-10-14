#!/bin/sh
# Component equivalence of rtl/ValidBits256.vhd against plain flip-flops.
# usage: ALTERA_MF_DIR=<compiled altera_mf dir> [NEWFILE=<variant>] sim/validbits256/run.sh [CYCLES] [SEED]
set -e
here=$(cd "$(dirname "$0")" && pwd)
rtl="$here/../../rtl"
work="${WORKDIR:-$here/work}"; mkdir -p "$work"; cd "$work"
L="-L . -L ${ALTERA_MF_DIR:-.}"
nvc --std=2008 $L --work=mem -a "$rtl/RamMLAB.vhd"
nvc --std=2008 $L -a "${NEWFILE:-$rtl/ValidBits256.vhd}" "$here/tb_validbits256.vhd"
nvc --std=2008 $L -e tb_validbits256 -gNUM_CYCLES=${1:-1000000} -gSEED=${2:-1} -r
