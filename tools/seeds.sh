#!/bin/sh
# Build fitter seeds one after another until one fits AND meets timing (setup and hold, all four corners).
# usage: [SEEDS="1 3 5 7"] [OVERRIDE=...] [EXTRA_QSF=...] tools/seeds.sh NAME     -> builds/NAMEs<seed>
# The chip is ~99 % full, so a seed may not fit or may miss timing by a fraction of a nanosecond; pk20 needed
# seed 7 of 1-8. Two chains with different seeds can run side by side (not three: Docker memory).
R=$(cd "$(dirname "$0")/.." && pwd)
N=${1:?usage: tools/seeds.sh NAME}
for s in ${SEEDS:-1 2 3 4 5 6 7 8}; do
  SEED=$s sh "$R/tools/build.sh" "${N}s$s" > "$R/builds/${N}s$s.build.out" 2>&1
  E=$?
  STA=$R/builds/${N}s$s/pocket/src/fpga/output_files/ap_core.sta.rpt
  WS=""
  [ -f "$STA" ] && WS=$(LC_ALL=C grep -a -E "^; (Slow|Fast) 1100mV (85C|0C) Model (Setup|Hold) Summary" -A10 "$STA" | \
     LC_ALL=C grep -a -E "divclk|clk_74a|spiclk" | LC_ALL=C awk -F';' '{print $3}' | sort -n | head -1)
  echo "$N seed $s exit $E worst $WS $(grep -a -o 'requires [0-9]* LABs' "$R/builds/${N}s$s.log" | head -1)"
  if [ $E = 0 ] && [ -n "$WS" ] && [ "$(echo "$WS >= 0" | bc)" = 1 ]; then echo "GOOD $N seed $s"; exit 0; fi
done
echo "NO CLEAN SEED $N"
exit 1
