#!/bin/sh
# Run a timing-analysis script on a finished build (same Docker setup as tools/build.sh).
# usage: tools/sta.sh NAME SCRIPT.tcl      e.g. tools/sta.sh pk20s7 tools/worst_paths.tcl
#   worst_paths.tcl   worst setup/hold paths per clock and corner (slack < 0.3 ns)
#   m10kn_clocks.tcl  launch clocks of every path into a RamM10Kn (must be that RAM's own clock only)
#   path_detail.tcl   full detail of the worst path into the SDRAM address/bank pins (-> builds/NAME/.../path_detail*.out)
#   psram_sta.tcl     PSRAM pin timing (VRAM_CLK3X builds): worst read / write path per corner
#   psram_io.tcl      PSRAM pin datasheet times (clock-to-output, setup / hold) per corner
# Don't run it next to two fits: three Quartus processes exceed Docker's memory.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
N=${1:?usage: tools/sta.sh NAME SCRIPT.tcl}
T=$(cd "$(dirname "${2:?usage: tools/sta.sh NAME SCRIPT.tcl}")" && pwd)/$(basename "$2")
B=$R/builds/$N
docker run --rm --name "q_sta_$N" --platform linux/amd64 --entrypoint bash \
  --volumes-from "${QUARTUS_DEVICES:-mirlo-cyclonev}" -v "$B:/b" -v "$T:/script.tcl:ro" -w /b/pocket/src/fpga \
  ghcr.io/nikleberg/quartus:25.1 -c "quartus_sta -t /script.tcl" 2>&1 | \
  grep -a -v -E "^ *Info|^$"
