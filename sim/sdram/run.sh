#!/bin/sh
# SDRAM controller test: rtl/sdram.sv ("new") and a reference ("ref", default ref/pk20/rtl/sdram_fifofix.sv: the
# hardware-tested pk20 controller ref/pk20/rtl/sdram.sv plus only the DMA fifo merge fix that rtl/sdram.sv has),
# each with a behavioural SDRAM chip that checks command timing and the same random CPU / cache / DMA / SPU /
# DMA-fifo traffic (harness.sv). Every read is checked against a reference memory, the chip's memory is compared at
# the end, and the latency of each kind of access is printed for both. Verilator 5 (Docker image mirlo-dev, or
# VERILATOR_IMAGE); REFFILE / NEWFILE replace the two controllers.
# usage: sim/sdram/run.sh [SIM_US] [SEED] [GAP_MIN] [LOCKSTEP (1: outputs must match ref on every clock)]
set -e
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
work=${WORKDIR:-$here/work}
mkdir -p "$work"
python3 "$here/prep.py" "${REFFILE:-$repo/ref/pk20/rtl/sdram_fifofix.sv}" sdram_ref "$work/sdram_ref.sv"
python3 "$here/prep.py" "${NEWFILE:-$repo/rtl/sdram.sv}" sdram_new "$work/sdram_new.sv"
cp "$here/tb_sdram.sv" "$here/harness.sv" "$here/altddio_out.sv" "$work/"
docker run --rm --name "sdram_sim_$$" -v "$work:/w" -w /w "${VERILATOR_IMAGE:-mirlo-dev:latest}" sh -c "
  verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -O2 --top-module tb_sdram \
    -GSIM_US=${1:-20000} -GSEED=${2:-1} -GGAP_MIN=${3:-1} -GLOCKSTEP=${4:-1} \
    tb_sdram.sv harness.sv altddio_out.sv sdram_ref.sv sdram_new.sv -o tb > build.log 2>&1 || { tail -40 build.log; exit 1; }
  ./obj_dir/tb"
