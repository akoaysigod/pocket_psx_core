#!/bin/sh
# Exhaustive check of cd_top's divider-free helpers. usage: sim/cd_arith/run.sh
set -e
here=$(cd "$(dirname "$0")" && pwd)
work="${WORKDIR:-$here/work}"
mkdir -p "$work"
python3 - "$here/../../rtl/cd_top.vhd" "$here/tb_cd_arith.vhd" "$work/tb_cd_arith.vhd" <<'PY'
import sys
src = open(sys.argv[1]).read()
a = src.index('   function getSectorsPerTrack')
b = src.index('   end function;', src.index('function toBCD7')) + len('   end function;')
tb = open(sys.argv[2]).read().replace('   --INSERT_NEW_FUNCTIONS', src[a:b])
open(sys.argv[3], 'w').write(tb)
PY
cd "$work"
nvc --std=2008 -a tb_cd_arith.vhd -e tb_cd_arith -r
