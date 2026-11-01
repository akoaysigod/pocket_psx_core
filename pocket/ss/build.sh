#!/bin/sh
# Assembles the save-state routine (ss_routine.s) into ss_routine.bin, the APF data slot loaded to SDRAM 0x200000.
# Without OUTDIR it goes to pocket/dist/Assets/psx/akoaysigod.PSX (shipped, in git); with OUTDIR there, together
# with ss_routine.hex (one little-endian word per line, for pocket/sim/boot). Needs llvm-mc, llvm-objdump and
# llvm-objcopy with the MIPS target (Homebrew llvm; LLVM= to point at another bin directory).
# usage: pocket/ss/build.sh [OUTDIR]
set -e
here=$(cd "$(dirname "$0")" && pwd)
out="${1:-$here/../dist/Assets/psx/akoaysigod.PSX}"
llvm="${LLVM:-/opt/homebrew/opt/llvm/bin}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
"$llvm/llvm-mc" -triple=mipsel-unknown-none -mcpu=mips1 -filetype=obj "$here/ss_routine.s" -o "$tmp/ss.o"
if "$llvm/llvm-objdump" -r "$tmp/ss.o" | grep -q R_MIPS; then
   echo "ss_routine.s: relocations left (absolute label references)" >&2
   exit 1
fi
"$llvm/llvm-objcopy" -O binary -j .text "$tmp/ss.o" "$out/ss_routine.bin"
python3 -c '
import struct, sys
d = open(sys.argv[1], "rb").read()
d += b"\0" * (-len(d) % 4)
if len(sys.argv) > 2:
    open(sys.argv[2], "w").write("".join("%08X\n" % w for w in struct.unpack("<%dI" % (len(d) // 4), d)))
print("ss_routine.bin: %d bytes" % len(d))' "$out/ss_routine.bin" ${1:+"$out/ss_routine.hex"}
