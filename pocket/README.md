# PSX core for the Analogue Pocket (test build)

The PSX_MiSTer core, trimmed to fit the Pocket's Cyclone V (5CEBA4F23C8), with a Pocket wrapper:

| Part | Where it lives on the Pocket |
| --- | --- |
| Main RAM, BIOS, SPU RAM | SDRAM (MiSTer's `rtl/sdram.sv`, clk3x) |
| VRAM, memory card 1 | both PSRAMs used side by side as one 32-bit memory (`core/vram_psram.vhd`) |
| CD image | read sector by sector from the game's `.bin` files through APF data slots (`core/pocket_cd.vhd`) |
| Memory card file | APF save slot, loaded into / read back from PSRAM (`core/pocket_memcard.vhd`) |
| Video, audio, controller | `core/pocket_psx.vhd`, `core/core_top.v` |

What was cut compared with MiSTer: save states, CD audio tracks (CD-DA), memory card 2, EXE loading, LibCrypt,
cheats, and the newest CD Pause timing refinement (upstream commit cd17b5a; Pause uses the
fixed timing MiSTer had before). Each change has a simulation test in `sim/` and `pocket/sim/` and is described in
`docs/NIGHT_LOG.md`. See also the top-level `README.md`.

## Build

Quartus Prime Lite (tested with 25.1 in Docker, single-threaded):

    cd pocket/src/fpga && quartus_sh --flow compile ap_core

The Pocket loads the bitstream with the bit order of every byte reversed:

    python3 pocket/tools/rbf_reverse.py output_files/ap_core.rbf ap_core.rbf_r

## Put it on the SD card

    python3 pocket/tools/package.py --rbf ap_core.rbf_r --out SDROOT \
        --bios scph1001.bin --game "path/to/Game.cue" --copy-bins

Then copy the contents of `SDROOT` to the SD card's root. That gives:

    Cores/akoaysigod.PSX/                     bitstream.rbf_r + json files
    Platforms/psx.json
    Assets/psx/common/scph1001.bin
    Assets/psx/common/<game folder>/             (the .bin files)
    Assets/psx/akoaysigod.PSX/Game.json          (instance JSON: what you select in the Pocket menu)

Games must be one `.bin` per track (Redump style). `tools/cue2instance.py GAME.cue` makes the instance JSON on
its own; Pocket Sync and Pupdate make it from `Cores/akoaysigod.PSX/instance-packager.json` for every game folder in
`Assets/psx/common/` (see `Assets/psx/common/HOW_TO_ADD_GAMES.txt`). The memory card is saved per game by the Pocket (128 KB raw card, same format as MiSTer's `.sav`).

## What to look for when testing

1. Core loads, Pocket shows the game list (instance JSONs) and a picture appears. Without a game JSON with
   tracks the BIOS boots to its memory card / CD player menu.
2. Picture: size and position (video modes 256/320/368/512/640 wide, set in `video.json`), colours.
3. Sound: BIOS boot sound.
4. Controls: d-pad, A = Circle, B = Cross, X = Triangle, Y = Square, L/R = L1/R1, Select, Start.
5. Disc: the BIOS logo, then the game starts (Symphony of the Night: Konami logo and the opening movies, then the intro).
6. Memory card: save in game, quit the core, start again, load.

Tested on hardware with build pk20 (2026-10-14): SotN at 60 fps, opening movies, memory card saves.
