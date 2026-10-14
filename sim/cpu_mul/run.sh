#!/bin/sh
# Checks the merged MULT/MULTU multiplier arithmetic in rtl/cpu.vhd. usage: sim/cpu_mul/run.sh [NUM] [SEED] [MUTATE]
set -e
here=$(cd "$(dirname "$0")" && pwd)
work="${WORKDIR:-$here/work}"; mkdir -p "$work"; cd "$work"
nvc --std=2008 -a "$here/tb_cpu_mul.vhd"
nvc --std=2008 -e tb_cpu_mul -gNUM=${1:-2000000} -gSEED=${2:-1} -gMUTATE=${3:-0} -r
