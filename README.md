# PSX core on the Analogue Pocket

A PlayStation core for the Analogue Pocket, made by trimming the MiSTer PSX core until it fits the Pocket's FPGA
(Cyclone V 5CEBA4F23C8: 18,480 ALMs, 308 M10K, 66 DSP), with a Pocket wrapper for SDRAM, PSRAM, video, audio,
controller, CD images from the SD card and memory card saves. The trims were chosen with Symphony of the Night
(USA, SLUS-00067) as the test game; other games may use features that were removed.

Based on [MiSTer-devel/PSX_MiSTer](https://github.com/MiSTer-devel/PSX_MiSTer) at commit `cd17b5a`
(2026-08-21), GPL-2.0 (see `LICENSE`). Upstream originals of the files the equivalence tests compare against are
in `ref/upstream/rtl/`.

## Licences

- The PSX core (`rtl/`), the Pocket wrapper code written for this port and the tests: GPL, see `LICENSE`
  (GPL-2.0, as upstream PSX_MiSTer; a few upstream files such as `rtl/sdram.sv` say GPL-3.0 or later in their
  headers). Sharing the source or a built bitstream means sharing it under the GPL, with the source available.
- `pocket/src/fpga/apf/`: Analogue Pocket Framework, under Analogue's licence (header of each file and the Pocket
  EULA), for building Pocket cores; GPL terms prevail where they apply.
- `pocket/src/fpga/core/sound_i2s.sv`, `sync_fifo.sv` and `psram_async.vhd` (a port of `psram.sv`): MIT, Adam
  Gastineau ([agg23/analogue-pocket-utils](https://github.com/agg23/analogue-pocket-utils)); the notice is in
  each file.
- `pocket/dist/Cores/akoaysigod.PSX/icon.bin` and `pocket/dist/Platforms/_images/psx.bin`: made from a photo of a
  PlayStation by TheShutterVision on [Pexels](https://www.pexels.com/photo/psx-console-on-white-background-9690066/)
  ([Pexels License](https://www.pexels.com/license/)), converted with `pocket/tools/png2pocket.py`. "PlayStation" and
  its logo are trademarks of Sony.
- Not included and not redistributable: the BIOS (Sony), game images, and Intel's `altera_mf` simulation library
  (`sim/altera_lib`).
