#!/bin/sh
# Equivalence test of rtl/gte_small.vhd against rtl/gte.vhd using nvc.
# usage: ALTERA_MF_DIR=<compiled altera_mf dir> [NEWFILE=<gte_small.vhd variant>] sim/gte_small/run.sh [NUM_TESTS] [SEED]
set -e
here=$(cd "$(dirname "$0")" && pwd)
rtl="$here/../../rtl"
work="${WORKDIR:-$here/work}"
mkdir -p "$work"
# reference: the original gte renamed to gte_ref, without its trace writer
python3 - "$rtl/gte.vhd" "$work/gte_ref.vhd" <<'PY'
import sys
s = open(sys.argv[1]).read()
s = s.replace('entity gte is', 'entity gte_ref is').replace('architecture arch of gte is', 'architecture arch of gte_ref is')
a = s.index('-- synthesis translate_off'); b = s.index('-- synthesis translate_on')
s = s[:a] + s[b:]
open(sys.argv[2], 'w').write(s)
PY
sed -e "s/^entity gte is/entity gte_small is/" -e "s/^architecture arch of gte is/architecture arch of gte_small is/" "${NEWFILE:-$rtl/gte_small.vhd}" > "$work/gte_small.vhd"
cd "$work"
L="-L . -L ${ALTERA_MF_DIR:-.}"
nvc --std=2008 $L --work=mem -a "$rtl/RamMLAB.vhd" "$rtl/RamM10Kn.vhd"
nvc --std=2008 $L -a "$rtl/pGTE.vhd" "$rtl/pGTEs.vhd" "$rtl/gte_mac0.vhd" "$rtl/gte_mac123.vhd" "$rtl/gte_mac123s.vhd" \
    "$rtl/gte_UNRDivide.vhd" gte_ref.vhd gte_small.vhd "$here/tb_gte_equiv.vhd"
nvc --std=2008 $L -e tb_gte_equiv -gNUM_TESTS=${1:-20000} -gSEED=${2:-1} -r
