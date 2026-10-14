#!/bin/sh
# Compile the Pocket core with Quartus Prime 25.1 in Docker.
# usage: [SEED=n] [ELAB=1 | MAPONLY=1] [OVERRIDE="src=dst ..."] [EXTRA_QSF="..."] tools/build.sh NAME
#   ELAB=1     analysis & elaboration only (finds HDL errors in ~1 minute)
#   MAPONLY=1  synthesis only (resource estimate)
#   OVERRIDE   files copied over the build copy before compiling (dst relative to the build folder)
#   EXTRA_QSF  lines appended to ap_core.qsf (e.g. set_global_assignment -name FITTER_EFFORT "STANDARD FIT")
# rtl/ and pocket/ are copied to builds/NAME (same layout, so the qip's ../../../rtl paths work) and compiled there.
# Log: builds/NAME.log. Bitstream: builds/NAME/pocket/src/fpga/output_files/ap_core.rbf and ap_core.rbf_r (bit
# order reversed, the file the Pocket loads).
# Needs Docker with ghcr.io/nikleberg/quartus:25.1 and a container holding the Cyclone V device files (created from
# ghcr.io/nikleberg/quartus:25.1-cyclonev), named mirlo-cyclonev or given in QUARTUS_DEVICES.
# Quartus runs single-threaded: under Rosetta (Apple Silicon) its parallel helpers hang. A fit needs ~2 GB of
# Docker memory; with ~8 GB, run at most two builds at a time.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
N=${1:?usage: tools/build.sh NAME}
B=$R/builds/$N
rm -rf "$B"; mkdir -p "$B"; cd "$B"
cp -R "$R/pocket" pocket
cp -R "$R/rtl" rtl
for o in $OVERRIDE; do cp "${o%%=*}" "${o#*=}"; echo "override ${o#*=}"; done
printf "\nset_global_assignment -name NUM_PARALLEL_PROCESSORS 1\n" >> pocket/src/fpga/ap_core.qsf
[ -n "$SEED" ] && printf "set_global_assignment -name SEED %s\n" "$SEED" >> pocket/src/fpga/ap_core.qsf
[ -n "$EXTRA_QSF" ] && printf "%s\n" "$EXTRA_QSF" >> pocket/src/fpga/ap_core.qsf
STEPS="quartus_sh --flow compile ap_core"
[ -n "$MAPONLY" ] && STEPS="quartus_map --parallel=1 ap_core"
[ -n "$ELAB" ] && STEPS="quartus_map --parallel=1 --analysis_and_elaboration ap_core"
set +e
docker run --rm --name "q_$N" --platform linux/amd64 --entrypoint bash \
  --volumes-from "${QUARTUS_DEVICES:-mirlo-cyclonev}" -v "$B:/b" -w /b/pocket/src/fpga \
  ghcr.io/nikleberg/quartus:25.1 -c "$STEPS" > "$R/builds/$N.log" 2>&1
E=$?
echo "BUILD EXIT $E"
F=$B/pocket/src/fpga/output_files/ap_core.rbf
[ -f "$F" ] && python3 "$R/pocket/tools/rbf_reverse.py" "$F" "${F}_r" && echo "wrote ${F}_r"
exit $E
