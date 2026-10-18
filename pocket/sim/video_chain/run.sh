#!/bin/sh
# Core video output (gpu_videoout_async) -> pocket_video: pixels per line the Pocket scaler gets.
# usage: ALTERA_MF_DIR=<compiled altera_mf dir> pocket/sim/video_chain/run.sh [MODE 0-4 = 256/320/368/512/640] [HCROP 0/1] [X1] [X2] [EXPECT]
#   no arguments: all five modes with hCrop off (the Pocket setting), standard display range and two shifted
#   starts; each must give exactly the mode's width on every line
set -e
here=$(cd "$(dirname "$0")" && pwd)
rtl="${RTL_DIR:-$here/../../../rtl}"
core="${CORE_DIR:-$here/../../src/fpga/core}"
work="${WORKDIR:-$here/work}"; mkdir -p "$work"; cd "$work"
L="-L . -L ${ALTERA_MF_DIR:-.}"
nvc --std=2008 $L --work=mem -a "$rtl/dpram.vhd"
# simulation only (as in sim/gpu_vram): to_unsigned of negative values right after reset wraps like the hardware
python3 "$here/../../../sim/gpu_vram/wrap_to_unsigned.py" "$rtl/gpu_videoout_async.vhd" gpu_videoout_async.vhd
nvc --std=2008 $L -a "$rtl/dpram.vhd" "$rtl/pGPU.vhd" "$rtl/gpu_dither.vhd" gpu_videoout_async.vhd "$core/pocket_video.vhd" "$here/tb_video_chain.vhd"
run() {
  nvc --std=2008 $L --ieee-warnings=off -e tb_video_chain -gMODE=$1 -gHCROP=$2 -gX1=$3 -gX2=$4 -gEXPECT=${5:--1} -r 2>&1 | \
    grep -E "lines with|PASS|FAIL" | sed 's/.*Note: //; s/.*Report Note: //'
}
if [ $# -gt 0 ]; then run "$1" "${2:-0}" "${3:-608}" "${4:-3168}" "${5:--1}"; exit; fi
for m in 0 1 2 3 4; do
  for x1 in 608 611 615; do run $m 0 $x1 $((x1 + 2560)); done
done
