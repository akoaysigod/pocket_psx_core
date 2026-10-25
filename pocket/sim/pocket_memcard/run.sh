#!/bin/sh
# pocket_memcard + vram_psram + PSRAM models: card load, core access, APF read back, with VRAM traffic.
# usage: ALTERA_MF_DIR=<compiled altera_mf dir> [VRAM_PSRAM=<vram_psram variant>] pocket/sim/pocket_memcard/run.sh [CARD_WORDS] [SEED] [GAP] [MUTATION]
#   GENERICS="-gCDC=true": core side on clk2x through vram_cdc, pocket_memcard + vram_psram on clk3x (VRAM_CLK3X)
set -e
here=$(cd "$(dirname "$0")" && pwd)
core="$here/../../src/fpga/core"
work="${WORKDIR:-$here/work}"; mkdir -p "$work"; cd "$work"
L="-L . -L ${ALTERA_MF_DIR:-.}"
nvc --std=2008 $L -a --relaxed "$core/psram_async.vhd" "${VRAM_PSRAM:-$core/vram_psram.vhd}" "$core/vram_cdc.vhd" "${MCFILE:-$core/pocket_memcard.vhd}" \
   "$here/../vram_psram/psram_model.vhd" "$here/tb_pocket_memcard.vhd"
nvc --std=2008 --ieee-warnings=off $L -H 1g -e tb_pocket_memcard -gCARD_WORDS=${1:-2048} -gSEED=${2:-1} -gGAP=${3:-60} -gMUTATION=${4:-0} $GENERICS -r
