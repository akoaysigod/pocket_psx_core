#!/bin/sh
# GPU-level equivalence: REF gpu.vhd (default: ref/upstream/rtl/gpu.vhd) vs current rtl/gpu.vhd, see tb_gpu_vram.tpl.vhd.
# usage: ALTERA_MF_DIR=<compiled altera_mf dir> [REFFILE=<gpu.vhd>] [NEWFILE=<gpu.vhd>] sim/gpu_vram/run.sh [NUM_CMDS] [SEED]
set -e
here=$(cd "$(dirname "$0")" && pwd)
rtl="$here/../../rtl"
work="${WORKDIR:-$here/work}"
mkdir -p "$work"
cat "${REFFILE:-$here/../../ref/upstream/rtl/gpu.vhd}" | \
   sed -e 's/entity gpu is/entity gpu_ref is/' -e 's/architecture arch of gpu is/architecture arch of gpu_ref is/' > "$work/gpu_ref.vhd"
sed -e 's/entity gpu is/entity gpu_new is/' -e 's/architecture arch of gpu is/architecture arch of gpu_new is/' "${NEWFILE:-$rtl/gpu.vhd}" > "$work/gpu_new.vhd"
# simulation only (as in sim/gpu_div3): undriven inout record fields of the divider ports default to 'Z'
for m in poly line; do
   sed -E "s/(div[1-6] +: inout div_type)/\1 := (start => 'Z', done => 'Z', dividend => (others => 'Z'), divisor => (others => 'Z'), quotient => (others => 'Z'), remainder => (others => 'Z'))/" "$rtl/gpu_$m.vhd" > "$work/gpu_$m.vhd"
done
# simulation only: to_unsigned(lineMax - 1) is evaluated with lineMax = 0 right after reset; hardware wraps to 511
python3 "$here/wrap_to_unsigned.py" "$rtl/gpu_videoout_async.vhd" "$work/gpu_videoout_async.vhd"
python3 "$here/gen_tb.py" "$rtl" "$here/tb_gpu_vram.tpl.vhd" "$work/tb_gpu_vram.vhd" "$work/gpu_ref.vhd"
cd "$work"
L="-L . -L ${ALTERA_MF_DIR:-.}"
nvc --std=2008 $L --work=mem -a "$rtl/RamMLAB.vhd" "$rtl/SyncFifo.vhd" "$rtl/SyncFifoFallThrough.vhd" "$rtl/dpram.vhd"
nvc --std=2008 $L -a "$rtl/pGPU.vhd" "$rtl/dpram.vhd" "$rtl/divider.vhd" "$rtl/mul32u.vhd" "$rtl/mul9s.vhd" "$rtl/justifier_sensor.vhd" \
   "$rtl/gpu_crosshair.vhd" "$rtl/gpu_dither.vhd" "$rtl/gpu_overlay.vhd" gpu_videoout_async.vhd "$rtl/gpu_videoout_sync.vhd" \
   "$rtl/gpu_videoout.vhd" "$rtl/gpu_fillVram.vhd" "$rtl/gpu_cpu2vram.vhd" "$rtl/gpu_vram2vram.vhd" "$rtl/gpu_vram2cpu.vhd" \
   gpu_line.vhd "$rtl/gpu_rect.vhd" gpu_poly.vhd "$rtl/ValidBits256.vhd" "$rtl/gpu_pixelpipeline.vhd" \
   gpu_ref.vhd gpu_new.vhd tb_gpu_vram.vhd
nvc --std=2008 --ieee-warnings=off $L -H 1g -e tb_gpu_vram -gNUM_CMDS=${1:-300} -gSEED=${2:-1} -gCOUNT_WRAPS=${COUNT_WRAPS:-true} -r
