#!/bin/sh
# pocket_diag: APF video rules, every text pixel, Select switching. usage: ALTERA_MF_DIR=<dir> pocket/sim/pocket_diag/run.sh
set -e
here=$(cd "$(dirname "$0")" && pwd)
work="${WORKDIR:-$here/work}"; mkdir -p "$work"; cd "$work"
L="-L . -L ${ALTERA_MF_DIR:-.}"
nvc --std=2008 $L -a "$here/../../src/fpga/core/pocket_diag.vhd" "$here/tb_pocket_diag.vhd"
nvc --std=2008 --ieee-warnings=off $L -e tb_pocket_diag -r
