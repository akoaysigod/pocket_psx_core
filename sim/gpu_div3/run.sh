#!/bin/sh
# Equivalence of the 3-divider gpu_poly/gpu_line against the upstream originals (ref/upstream/rtl, 6 dividers).
# usage: ALTERA_MF_DIR=<compiled altera_mf dir> sim/gpu_div3/run.sh MODULE(0=poly,1=line) [NUM_CMDS] [SEED]
set -e
here=$(cd "$(dirname "$0")" && pwd)
rtl="${RTL_DIR:-$here/../../rtl}"
refdir="$here/../../ref/upstream/rtl"
work="${WORKDIR:-$here/work}"
mkdir -p "$work"
for m in poly line; do
  sed -e "s/entity gpu_$m is/entity gpu_${m}_ref is/" -e "s/architecture arch of gpu_$m is/architecture arch of gpu_${m}_ref is/" < "$refdir/gpu_$m.vhd" > "$work/gpu_${m}_ref.vhd"
  sed -e "s/entity gpu_$m is/entity gpu_${m}_new is/" -e "s/architecture arch of gpu_$m is/architecture arch of gpu_${m}_new is/" "$rtl/gpu_$m.vhd" > "$work/gpu_${m}_new.vhd"
done
# simulation only: undriven inout record fields (done/quotient/remainder) default to 'Z' so the
# divider outputs resolve through the port (synthesis connects them directly)
for f in "$work"/gpu_*_ref.vhd "$work"/gpu_*_new.vhd; do
  sed -i.bak -E "s/(div[1-6] +: inout div_type)/\1 := (start => 'Z', done => 'Z', dividend => (others => 'Z'), divisor => (others => 'Z'), quotient => (others => 'Z'), remainder => (others => 'Z'))/" "$f"
done
cd "$work"
L="-L . -L ${ALTERA_MF_DIR:-.}"
nvc --std=2008 $L --work=mem -a "$rtl/SyncFifo.vhd" "$rtl/SyncFifoFallThrough.vhd" "$rtl/RamMLAB.vhd" "$rtl/dpram.vhd"
nvc --std=2008 $L -a "$rtl/pGPU.vhd" "$rtl/divider.vhd" "$rtl/mul9s.vhd" "$rtl/mul32u.vhd" "$rtl/dpram.vhd" \
    gpu_poly_ref.vhd gpu_poly_new.vhd gpu_line_ref.vhd gpu_line_new.vhd "$here/pGpuDivTb.vhd" "$here/gpu_div_harness.vhd" "$here/tb_gpu_div3.vhd"
nvc --std=2008 --ieee-warnings=off -H 512m $L -e tb_gpu_div3 -gMODULE=${1:-0} -gNUM_CMDS=${2:-200} -gSEED=${3:-1} -gSELFTEST=${SELFTEST:-false} -r
