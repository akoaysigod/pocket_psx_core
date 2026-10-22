#!/bin/sh
# Equivalence test of rtl/cd_xa.vhd against the upstream cd_xa (ref/upstream/rtl/cd_xa.vhd), see tb_cd_xa.vhd.
# usage: ALTERA_MF_DIR=<compiled altera_mf dir> [NEWFILE=<cd_xa.vhd variant>] [REFFILE=<reference>] sim/cd_xa/run.sh [NUM_CYCLES] [SEED]
set -e
here=$(cd "$(dirname "$0")" && pwd)
rtl="$here/../../rtl"
work="${WORKDIR:-$here/work}"
mkdir -p "$work"
ren() { sed -e "s/entity cd_xa is/entity cd_xa_$1 is/" -e "s/architecture arch of cd_xa is/architecture arch of cd_xa_$1 is/"; }
ren ref < "${REFFILE:-$here/../../ref/upstream/rtl/cd_xa.vhd}" > "$work/cd_xa_ref.vhd"
ren new < "${NEWFILE:-$rtl/cd_xa.vhd}" > "$work/cd_xa_new.vhd"
cd "$work"
L="-L . -L ${ALTERA_MF_DIR:-.}"
nvc --std=2008 $L --work=mem -a "$rtl/SyncFifo.vhd" "$rtl/SyncFifoFallThrough.vhd" "$rtl/dpram.vhd"
nvc --std=2008 $L -a "$rtl/dpram.vhd" "$rtl/cd_xa_zigzag.vhd" cd_xa_ref.vhd cd_xa_new.vhd "$here/tb_cd_xa.vhd"
nvc --std=2008 --ieee-warnings=off $L -e tb_cd_xa -gNUM_CYCLES=${1:-2000000} -gSEED=${2:-1} -r
