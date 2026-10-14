#!/bin/sh
# pocket_video against the APF video rules. usage: pocket/sim/pocket_video/run.sh [MUTATION]
set -e
here=$(cd "$(dirname "$0")" && pwd)
work="${WORKDIR:-$here/work}"; mkdir -p "$work"; cd "$work"
nvc --std=2008 -a "$here/../../src/fpga/core/pocket_video.vhd" "$here/tb_pocket_video.vhd"
nvc --std=2008 --ieee-warnings=off -e tb_pocket_video -gMUTATION=${1:-0} -r
