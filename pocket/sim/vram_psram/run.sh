#!/bin/sh
# vram_psram against two PSRAM behavioural models (with board delays).
# usage: [DUT=<vram_psram variant .vhd>] [GENERICS="-gT_OUT=4ns ..."] pocket/sim/vram_psram/run.sh [NUM_REQ] [SEED]
set -e
here=$(cd "$(dirname "$0")" && pwd)
core="$here/../../src/fpga/core"
work="${WORKDIR:-$here/work}"; mkdir -p "$work"; cd "$work"
nvc --std=2008 -a --relaxed "$core/psram_async.vhd" "${DUT:-$core/vram_psram.vhd}" "$here/psram_model.vhd" "$here/tb_vram_psram.vhd"
nvc --std=2008 -H 512m -e tb_vram_psram -gNUM_REQ=${1:-5000} -gSEED=${2:-1} $GENERICS -r
