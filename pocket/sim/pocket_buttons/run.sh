#!/bin/sh
# pocket_buttons (L2 / R2 button combos from Core Settings) against directed scenarios, see tb_pocket_buttons.vhd.
# usage: [DUT=<pocket_buttons.vhd variant>] pocket/sim/pocket_buttons/run.sh [WINDOW_DUT (self check: 1 must FAIL)]
set -e
here=$(cd "$(dirname "$0")" && pwd)
core="$here/../../src/fpga/core"
work="${WORKDIR:-$here/work}"; mkdir -p "$work"; cd "$work"
nvc --std=2008 -a "${DUT:-$core/pocket_buttons.vhd}" "$here/tb_pocket_buttons.vhd"
nvc --std=2008 --ieee-warnings=off -e tb_pocket_buttons -gWINDOW_DUT=${1:-50} -r
