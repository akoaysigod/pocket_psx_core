#!/bin/sh
# Summary of a finished build: resources, slack per clock and corner, biggest modules.
# usage: tools/report.sh NAME [N_MODULES]
R=$(cd "$(dirname "$0")/.." && pwd)
O=$R/builds/${1:?usage: tools/report.sh NAME [N_MODULES]}/pocket/src/fpga/output_files
LC_ALL=C grep -a -E "^; (Logic utilization \(ALMs needed|Total LABs|M10K blocks|Total DSP Blocks)" "$O/ap_core.fit.rpt" | head -4
echo "slack (ns) per clock; core0/1/2 = clk1x/2x/3x, video0/1 = clkvid/clkpix:"
LC_ALL=C grep -a -E "^; (Slow|Fast) 1100mV (85C|0C) Model (Setup|Hold) Summary" -A10 "$O/ap_core.sta.rpt" | \
  LC_ALL=C awk -F';' '/Summary/ {h=$2; gsub(/^ +| +$|1100mV |Model |Summary/,"",h); next}
                      /divclk|clk_74a|spiclk/ {c=$2; gsub(/ /,"",c); s=$3; gsub(/ /,"",s);
                        sub(/ic\|ipll_core\|altera_pll_i\|general\[/,"core",c); sub(/ic\|ipll_video\|altera_pll_i\|general\[/,"video",c);
                        sub(/\]\.gpll~PLL_OUTPUT_COUNTER\|divclk/,"",c); printf "  %-18s %-14s %8s\n", h, c, s}'
echo "ALMs per module (psx_top children):"
n=$(LC_ALL=C grep -a -n "^; Fitter Resource Utilization by Entity" "$O/ap_core.fit.rpt" | head -1 | cut -d: -f1)
LC_ALL=C awk -v s="$n" 'NR>s+3 && NR<s+5000 && /^; /' "$O/ap_core.fit.rpt" | \
  LC_ALL=C awk -F';' 'NF>15 {h=$(NF-3); gsub(/ /,"",h); if (h ~ /\|psx_top:ipsx_top\|[^|]+$/ || h ~ /\|pocket_psx:ipsx\|[^|]+$/ || h ~ /^\|?core_top:ic\|[^|]+$/) {split($3,a,"("); sub(/.*\|/,"",h); printf "%9.1f  %s\n", a[1], h}}' | \
  sort -rn | head -"${2:-20}"
