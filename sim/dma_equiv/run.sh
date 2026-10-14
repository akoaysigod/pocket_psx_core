#!/bin/sh
# Equivalence test of the current rtl/dma.vhd against the upstream original (ref/upstream/rtl/dma.vhd).
# usage: ALTERA_MF_DIR=<compiled altera_mf dir> [REFFILE=<reference dma.vhd>] sim/dma_equiv/run.sh [NUM_CYCLES] [SEED]
set -e
here=$(cd "$(dirname "$0")" && pwd)
rtl="${RTL_DIR:-$here/../../rtl}"
ref="${REFFILE:-$here/../../ref/upstream/rtl/dma.vhd}"
work="${WORKDIR:-$here/work}"
mkdir -p "$work"
cat "$ref" | sed -e 's/entity dma is/entity dma_ref is/' -e 's/architecture arch of dma is/architecture arch of dma_ref is/' > "$work/dma_ref.vhd"
sed -e 's/entity dma is/entity dma_new is/' -e 's/architecture arch of dma is/architecture arch of dma_new is/' "$rtl/dma.vhd" > "$work/dma_new.vhd"
# simulation only: the 7-bit REP_refresh counter wraps in hardware; nvc stops on the integer overflow
for f in "$work/dma_ref.vhd" "$work/dma_new.vhd"; do
  sed -i.bak 's/                     REP_refresh <= REP_refresh + 1;$/                     REP_refresh <= (REP_refresh + 1) mod 128;/' "$f"
done
cd "$work"
L="-L . -L ${ALTERA_MF_DIR:-.}"
nvc --std=2008 $L --work=mem -a "$rtl/SyncFifo.vhd" "$rtl/SyncFifoFallThrough.vhd" "$rtl/RamMLAB.vhd" "$rtl/RamM10Kn.vhd" "$rtl/dpram.vhd"
nvc --std=2008 $L -a dma_ref.vhd dma_new.vhd "$here/tb_dma_equiv.vhd"
nvc --std=2008 --ieee-warnings=off -H 256m $L -e tb_dma_equiv -gNUM_CYCLES=${1:-1000000} -gSEED=${2:-1} -gREALISTIC=${REALISTIC:-false} -r
