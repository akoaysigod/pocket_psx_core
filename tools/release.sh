#!/bin/sh
# Zip the SD card layout the Analogue Pocket expects (unzip it at the card's root).
# usage: tools/release.sh [NAME|BITSTREAM.rbf_r] [--bios SCPH1001.BIN] [--game GAME.cue [--copy-bins]] ...
#   NAME              a finished build: builds/NAME/pocket/src/fpga/output_files/ap_core.rbf_r
#   BITSTREAM.rbf_r   or a bitstream file directly; neither: the newest build in builds/
#   no options        every file except the copyrighted ones: the core (bitstream, JSON files, LICENSE.txt),
#                     Platforms/psx.json, the game entries ("BIOS (no disc)", Castlevania, the CD player test) and the empty folders
#                     for them: put scph1001.bin in Assets/psx/common and the game's .bin files in
#                     Assets/psx/PSXPort.PSX/Castlevania - Symphony of the Night. Can be shared (GPL: with the source).
#   --bios / --game   also your BIOS / another game's entry (with --copy-bins its .bin files): a complete card for
#                     yourself. Not to be shared (BIOS and game are copyrighted); the file name ends in _personal.
# -> releases/PSXPort.PSX_<version from core.json>_<NAME>[_personal].zip
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
case "$1" in
  "" | --*)
    RBF=$(ls -t "$R"/builds/*/pocket/src/fpga/output_files/ap_core.rbf_r 2>/dev/null | head -1)
    [ -n "$RBF" ] || { echo "no build with a bitstream in builds/ (run tools/build.sh NAME first)"; exit 1; }
    N=$(echo "$RBF" | sed "s|^$R/builds/||; s|/.*||")
    echo "newest build: $N" ;;
  *)
    SRC=$1; shift
    if [ -f "$SRC" ]; then
      RBF=$SRC; N=$(basename "$SRC" .rbf_r)
      case "$N" in bitstream | ap_core) N=$(date +%Y%m%d) ;; esac
    else RBF=$R/builds/$SRC/pocket/src/fpga/output_files/ap_core.rbf_r; N=$SRC; fi
    [ -f "$RBF" ] || { echo "no bitstream at $RBF (build it with tools/build.sh $SRC)"; exit 1; } ;;
esac
V=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["core"]["metadata"]["version"])' \
    "$R/pocket/dist/Cores/PSXPort.PSX/core.json")
S=""
case " $* " in *" --bios "*|*" --game "*) S=_personal ;; esac
python3 "$R/pocket/tools/package.py" --rbf "$RBF" --zip "$R/releases/PSXPort.PSX_${V}_${N}${S}.zip" "$@"
[ -n "$S" ] && echo "contains your BIOS / game: for your own SD card only"
exit 0
