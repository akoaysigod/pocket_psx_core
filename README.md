# Castlevania: Symphony of the Night on the Analogue Pocket

A PlayStation core for the Analogue Pocket, made by trimming the MiSTer PSX core until it fits the Pocket's FPGA
(Cyclone V 5CEBA4F23C8: 18,480 ALMs, 308 M10K, 66 DSP), with a Pocket wrapper for SDRAM, PSRAM, video, audio,
controller, CD images from the SD card and memory card saves. The trims were chosen for Symphony of the Night
(USA, SLUS-00067); other games may use features that were removed.

Based on [MiSTer-devel/PSX_MiSTer](https://github.com/MiSTer-devel/PSX_MiSTer) at commit `cd17b5a`
(2026-08-21), GPL-2.0 (see `LICENSE`). Upstream originals of the files the equivalence tests compare against are
in `ref/upstream/rtl/`.

## Vibes

This was 99.99% vibe coded by Opus 5.5 over the course of 3 days or so on the pro plan. For those that are curious, $328.47 in API costs apparently over 7 hours and 18 minutes. A lot of it was waiting for builds and or simulations to complete which costed next to nothing. I have an ARM mac so the tooling does not run natively and is painfully slow in a docker container. Not much to say, I really like SotN and wanted to see if it could run on the Pocket. I may look at a few other games in the future to see how they run on this but I've no intentions of really working on this more outside of fixing any issues that are SotN specific.

## Licences

- The PSX core (`rtl/`), the Pocket wrapper code written for this port and the tests: GPL, see `LICENSE`
  (GPL-2.0, as upstream PSX_MiSTer; a few upstream files such as `rtl/sdram.sv` say GPL-3.0 or later in their
  headers). Sharing the source or a built bitstream means sharing it under the GPL, with the source available.
- `pocket/src/fpga/apf/`: Analogue Pocket Framework, under Analogue's licence (header of each file and the Pocket
  EULA), for building Pocket cores; GPL terms prevail where they apply.
- `pocket/src/fpga/core/sound_i2s.sv`, `sync_fifo.sv` and `psram_async.vhd` (a port of `psram.sv`): MIT, Adam
  Gastineau ([agg23/analogue-pocket-utils](https://github.com/agg23/analogue-pocket-utils)); the notice is in
  each file.
- Not included and not redistributable: the BIOS (Sony), game images, and Intel's `altera_mf` simulation library
  (`sim/altera_lib`).

## Status (build sdB seed 4, 2026-10-15)

Tested on hardware: the game runs at full speed (60 fps), the opening movies (FMVs) play, memory card saves work
(saved per game by the Pocket, quit the core to write the file).

Not supported:
- **CD audio tracks (CD-DA).** SotN plays none: its music, very likely including the ending song, is XA-ADPCM,
  which works. Silent: the BIOS CD player and track 2 (a spoken "this is a PlayStation disc" warning followed by
  music, for people who put the disc in a CD player).
- Save states, memory card 2, EXE loading, LibCrypt, cheats, the newest CD Pause timing refinement (upstream `cd17b5a`).

After a build from this core has run, the Pocket's PSRAM stays in synchronous mode until power-off: power the
Pocket off before switching to another core.

## Roadmap

1. **L2 / R2 on the handheld: done in branch `controls`, to be tested on hardware (build ctl seed 1).** (R2 =
   turn into the wolf in SotN, after the Soul of Wolf; L2 is not used by Alucard.) The Pocket's Controls list only
   has its own 8 buttons (`input.json` allows at most 8 entries), so L2 / R2 come from button combos chosen in Core
   Settings (`interact.json`, like MIRLO64's pickers), "R2 button" and "L2 button":
   - Dock R2 / L2 only (default): no change.
   - Select + R1 / Select + L1: hold Select, press R1 (L1). R1 (L1) alone stays instant; Select (the map) is sent
     as a tap when released without a combo.
   - L1 + R1: press both within 50 ms (3 frames). A lone L1 / R1 press (mist, bat) then waits those 50 ms before
     it reaches the game.
   A docked controller's L2 / R2 pass in every setting. The logic is `pocket/src/fpga/core/pocket_buttons.vhd`
   (test: `pocket/sim/pocket_buttons`); room came from moving the GTE's translation-vector RAMs (`itrram` in
   `rtl/gte_small.vhd`) into M10K, the same change the `cd-audio` branch uses.
2. **CD audio (CD-DA).** Turned off with `CDDA_ON = false` in `rtl/cd_top.vhd`, because SotN never plays an audio
   track (its music is XA-ADPCM). That silences the BIOS CD player and track 2 (the disc's spoken CD-player warning
   and music). Bringing it back means turning `CDDA_ON` on again (the CD-DA output path and report packets in
   `cd_top`) and checking that `pocket_cd.vhd` streams audio sectors from the track 2 `.bin` fast enough.
   - Room: the chip is full (18,152 of 18,480 ALMs, 1,846 of 1,848 LABs). Moving the GTE's matrix and
     translation RAMs (`imatram` / `itrram` in `rtl/gte_small.vhd`) from `RamMLAB` to `RamM10Kn` frees ~15 LABs
     (57 M10K blocks are free). It is a two-line change and already passed `sim/gte_small` (seed 1) in a trial.
     Then measure what CD-DA needs with `MAPONLY=1`.
   - Test: an equivalence test of `cd_top.vhd` against upstream (like `sim/dma_equiv`), then the BIOS CD player
     on hardware.
3. **Easier rebuilds: done in `rtl/sdram.sv`, tested on hardware (build sdB seed 4, 2026-10-15: movies,
   gameplay, save / quit / reload).** The SDRAM address
   path (clk1x request -> address pin registers, 9.8 ns) no longer limits: the late CPU request now enters the
   address / command registers through the last multiplexer only, and the refresh check is a register. The
   behaviour is unchanged clock for clock (`sim/sdram`, lockstep). 3 of 4 seeds now meet timing everywhere (the
   4th misses by 13 ps of hold), against 1 of 8 before. The new SDRAM test also found and fixed a DMA write bug
   (a DMA word arriving during a CPU write could be written into the CPU's row; probably never happens on the
   console, where the CPU waits during DMA). Still known: the refresh after a write with auto precharge comes one
   clock short of tWR + tRP (as upstream); a cache line's last words can get the next request's line address if
   the core asks again one clk1x after ready (as upstream); the SPU reverb address RAM (`irvAddr`, falling-edge
   M10K) feeds three adders in half a clk1x and can still fail on some seeds.

## Layout

| Path | What |
| --- | --- |
| `rtl/` | the PSX core (MiSTer sources, trimmed). The build uses the 68 files listed in `pocket/src/fpga/psx_pocket.qip`; the others are upstream originals used by tests (e.g. `gte.vhd`, `savestates.vhd`) |
| `pocket/src/fpga/` | Quartus project (`ap_core.qpf`), APF framework (`apf/`), Pocket wrapper (`core/`) |
| `pocket/dist/` | Pocket JSON files (`Cores/PSXPort.PSX`, `Platforms/psx.json`) |
| `pocket/tools/` | `package.py` (SD card folders), `cue2instance.py` (game JSON), `rbf_reverse.py` |
| `pocket/sim/`, `sim/` | simulation tests (nvc), see below |
| `ref/upstream/rtl/` | upstream versions of `dma`, `spu`, `gpu`, `gpu_poly`, `gpu_line` (references for the tests) |
| `tools/` | build in Docker, seed search, timing reports |
| `docs/` | `NIGHT_LOG.md` (every change, its test and its measurement, in order), SotN hardware usage, notes |

Main pieces of the Pocket wrapper (`pocket/src/fpga/core/`):

| Part | Where it lives on the Pocket |
| --- | --- |
| Main RAM, BIOS, SPU RAM | SDRAM (`rtl/sdram.sv`, clk3x = 101.6 MHz) |
| VRAM, memory card | both PSRAMs side by side as one 32-bit memory, synchronous burst mode (`vram_psram.vhd`) |
| CD image | read sector by sector from the game's `.bin` files through APF data slots (`pocket_cd.vhd`) |
| Memory card file | APF save slot, loaded into / written back from PSRAM (`pocket_memcard.vhd`) |
| Video, audio, controller | `pocket_video.vhd`, `sound_i2s.sv`, `pocket_psx.vhd`, `core_top.v` |

## Build

Needs Docker with the image, only because I have an ARM mac, `ghcr.io/nikleberg/quartus:25.1` and a container holding the Cyclone V device files
(created from `ghcr.io/nikleberg/quartus:25.1-cyclonev`, by default named `mirlo-cyclonev`; another name can be
given in `QUARTUS_DEVICES`). Quartus runs single-threaded (its parallel helpers hang under Rosetta on Apple
Silicon); one full build takes about 35 minutes and ~2 GB of Docker memory.

    tools/build.sh NAME              # full build -> builds/NAME/pocket/src/fpga/output_files/ap_core.rbf_r
    ELAB=1 tools/build.sh NAME       # HDL check only (~1 minute)
    MAPONLY=1 tools/build.sh NAME    # synthesis only (resource estimate)
    SEED=4 tools/build.sh NAME       # fitter seed (the tested build sdB = seed 4; pk20 was seed 7)

The chip is about 99 % full: depending on the fitter seed, a build may not fit or may miss timing by a fraction of a
nanosecond (with the SDRAM change most seeds pass). `tools/seeds.sh NAME` tries seeds until one fits and meets timing at all four corners (two chains with
different `SEEDS="..."` can run side by side). Then:

    tools/report.sh NAME                          # resources, slack per clock and corner, biggest modules
    tools/sta.sh NAME tools/worst_paths.tcl       # worst paths
    tools/sta.sh NAME tools/m10kn_clocks.tcl      # check the falling-edge RAMs (RamM10Kn) are fed by their own clock only

## Put it on the SD card

    tools/release.sh            # newest build -> releases/PSXPort.PSX_<version>_<build>.zip

The zip has the full layout the Pocket expects, with every file except the copyrighted ones. Unzip it at the SD card's
root, then put your own files in the two empty folders:

    Cores/PSXPort.PSX/                         bitstream.rbf_r, JSON files, LICENSE.txt
    Platforms/psx.json
    Assets/psx/common/                         <- your BIOS, named scph1001.bin (512 KB)
    Assets/psx/PSXPort.PSX/BIOS (no disc).json      boots the BIOS menu without a disc
    Assets/psx/PSXPort.PSX/Castlevania - Symphony of the Night.json
    Assets/psx/PSXPort.PSX/Castlevania - Symphony of the Night/
                                               <- Castlevania - Symphony of the Night (Track 1).bin and (Track 2).bin

The game entry expects the track files named exactly like that (Redump names with "(USA)" must be renamed, or make a
new entry from the `.cue` with `pocket/tools/cue2instance.py`). The zip can be shared (with the source, GPL).

Other forms:

    tools/release.sh NAME                       # a given build in builds/
    tools/release.sh path/to/bitstream.rbf_r    # a given bitstream file
    tools/release.sh NAME --bios SCPH1001.BIN \
        --game "Castlevania - Symphony of the Night/Castlevania - Symphony of the Night.cue" --copy-bins
                                                # with your BIOS and game in it: ..._personal.zip, don't share it
    python3 pocket/tools/package.py --rbf BITSTREAM.rbf_r --out SDROOT [--bios ...] [--game ... --copy-bins]
                                                # the same layout as a folder

To update only the core on a card that already has everything, copying `bitstream.rbf_r` to `Cores/PSXPort.PSX/` is
enough.

The BIOS (`SCPH1001.BIN`) and the game files are not part of this repository (`.gitignore`); bring your own.

## Tests

The changes to the core were checked in simulation against the upstream originals, most also with a deliberately
broken variant to show the test catches errors; `docs/NIGHT_LOG.md` lists each change with its test. The tests use [nvc](https://github.com/nickg/nvc)
and Intel's `altera_mf` library compiled for nvc in `sim/altera_lib` (not in git: compile `altera_mf_components.vhd`
and `altera_mf.vhd` from a Quartus installation into a library named `altera_mf` there).

    ALTERA_MF_DIR=$PWD/sim/altera_lib sh sim/dma_equiv/run.sh 300000 1
    ALTERA_MF_DIR=$PWD/sim/altera_lib sh sim/spu_equiv/run.sh 2000000 1
    BIOS=$PWD/SCPH1001.BIN ALTERA_MF_DIR=$PWD/sim/altera_lib sh pocket/sim/boot/run.sh 400   # BIOS boot, ms

Each `run.sh` has its usage on the first lines. `sim/`: equivalence of the trimmed modules (CD helpers, CPU
multiplier, DMA, GPU dividers and VRAM, GTE, MDEC stub, memory card 2 removal, RAM primitives, reset-only save
states, SPU). `pocket/sim/`: the Pocket wrapper (PSRAM controller with a PSRAM model, CD reader, memory card, L2 / R2 button combos,
video, diagnostics page) and a full BIOS boot of the whole core.

`sim/sdram` tests the SDRAM controller (`rtl/sdram.sv`, SystemVerilog) with [Verilator](https://verilator.org) 5 in
Docker (the `mirlo-dev` image, or `VERILATOR_IMAGE`): it and a reference controller each get a behavioural SDRAM
chip that checks command timing and the same random CPU / cache / DMA / SPU / DMA-fifo traffic; every read is
checked, and with `LOCKSTEP` both must drive the same outputs on every clock:

    sh sim/sdram/run.sh 20000 1 2        # 20 ms, seed 1, at least 2 clk1x between CPU requests
