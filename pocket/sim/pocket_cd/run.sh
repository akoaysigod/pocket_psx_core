#!/bin/sh
# pocket_cd (CD image streaming) against an APF / core model.
# usage: ALTERA_MF_DIR=<compiled altera_mf dir> [DUT=<pocket_cd.vhd variant>] pocket/sim/pocket_cd/run.sh [NUM_REQ] [SEED] [LAYOUT] [MUTATION]
set -e
here=$(cd "$(dirname "$0")" && pwd)
core="$here/../../src/fpga/core"
rtl="$here/../../../rtl"
work="${WORKDIR:-$here/work}"; mkdir -p "$work"; cd "$work"
L="-L . -L ${ALTERA_MF_DIR:-.}"
nvc --std=2008 $L --work=mem -a "$rtl/RamMLAB.vhd" "$rtl/dpram.vhd"
nvc --std=2008 $L -a --relaxed "${DUT:-$core/pocket_cd.vhd}" "$here/tb_pocket_cd.vhd"
nvc --std=2008 --ieee-warnings=off $L -H 512m -e tb_pocket_cd -gNUM_REQ=${1:-60} -gSEED=${2:-1} -gLAYOUT=${3:-0} -gMUTATION=${4:-0} -r
