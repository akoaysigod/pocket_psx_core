# Pocket wrapper plan (what remains after the core fits)

The shrunk core (`psx_mister` with MiSTer options tied off) talks to the outside world through the
interfaces below. On MiSTer they are served by the MiSTer framework (SDRAM controller, DDR3, the
Linux side for CD images and memory cards). On the Pocket each one needs a replacement.
Starting point for the Pocket side: Analogue's openFPGA core template (apf_top, core_bridge_cmd,
data table), which all openFPGA cores use (its licence explicitly allows GPL cores).
Do NOT copy MIRLO64's own glue: it is Apache-2.0, which cannot be combined with this GPL-2 core.

| Core interface | On MiSTer | Pocket replacement | Difficulty |
|---|---|---|---|
| Main RAM (2 MB, `ram_*`, DMA FIFO, cache refill) | MiSTer SDRAM controller (16-bit SDRAM) | Pocket SDRAM is also 16-bit SDRAM: port the MiSTer controller, retime for the Pocket chip | medium |
| VRAM (1 MB, GPU over `DDRAM_*`, 64-bit bursts) | DDR3 | **No DDR3 on Pocket.** Options: second bank/port of the same SDRAM (bandwidth shared with main RAM), or the Pocket's PSRAM (slower). Needs a bandwidth study against SotN's GPU load. This is the biggest open design question. | hard |
| SPU RAM (512 KB, `spuram_*`) | SDRAM (option tied on) | SDRAM, behind the same controller/arbiter | medium |
| CD image (`cd_hps_*`: request LBA, receive 2352-byte sector as 16-bit words) + track table (`trackinfo_*`) | Linux side reads the .bin/.cue | Bridge "data slot" reads from the SD card into a sector buffer, on demand (the ~600 MB image does not fit in RAM). Track table built from the .cue at load time (or a fixed table for SotN's two tracks). Read latency must keep up with 2x speed (150 sectors/s). | hard |
| Memory card 1 (`memcard1_*`, 128 KB) | Linux side file | Pocket save slot: load into RAM at start, write back on change/exit | medium |
| Video (`video_r/g/b`, sync, blank, `video_ce`, interlace, width/height) | MiSTer scaler | Pocket scaler: RGB + sync + DE at a pixel clock; PSX modes 256/320/512/640 x 240 and 480i need entries in video.json and a pixel-clock strategy | medium |
| Audio (`sound_out_left/right`, 16-bit, 44.1 kHz) | MiSTer audio | I2S to the Pocket audio codec | easy |
| Controller (`Key*` for pad 1) | MiSTer joystick | APF `cont1_key` bits -> PSX digital pad buttons | easy |
| BIOS (512 KB) | loaded by Linux side into SDRAM | data slot loaded into SDRAM at start (user supplies their own BIOS file) | easy |
| Clocks | MiSTer PLL: 33.8688 MHz x1/x2/x3 + video clock | Pocket PLL from the 74.25 MHz board clock; the three core clocks must be exact multiples from one PLL | easy |

Logic budget: the wrapper itself (bridge, data table, SDRAM controller + arbiter, CD sector streaming,
video/audio glue) is roughly 1,000-2,000 ALMs in other Pocket cores. The core must leave that much room.

## Decisions so far (2026-10-12, after the core fits with ~1,540 ALMs free)

Template: Analogue openFPGA core template (github.com/open-fpga/core-template). Its APF licence says the MIT/GPL
terms prevail where a core needs them, so a GPL core can use it.

Pocket memories (from core_top.v): one 16-bit SDRAM (64 MB, dram_*), two 16-bit cellular RAMs / PSRAM
(16 MB each, cram0_*/cram1_*, address/data multiplexed: cram_a[21:16] + dq), one 16-bit SRAM (256 KB, sram_*).

Memory map:
- SDRAM: PSX main RAM 2 MB + BIOS 512 KB + SPU RAM 512 KB, through the repo's own MiSTer SDRAM controller
  (rtl/sdram.sv, 16-bit, clk3x = 101.6 MHz), exactly as the MiSTer single-SDRAM setup (SPUSDRAM = 1).
- PSRAM pair as one 32-bit memory: everything the core puts on its DDR3 port. The core uses
  ddr3_ADDR(27:20) as region: 0x00 VRAM (1 MB), 0x04 VRAM mirror (only for 24-bit render / 480p hack, off),
  0x01 memory card 1 (128 KB). The reset sequence also reads 4 savestate headers at 0x38/0x3C/0x40/0x44
  (results unused); with region bits [2:0] these alias onto VRAM and are harmless.
  => PSRAM 32-bit word address = {region[2:0], byte_addr[19:2]} (8 MB used of 32 MB).
  Controller: start from agg23's MIT-licensed analogue-pocket-utils ip/mem/psram.sv (async, ~70 ns per access;
  two chips in parallel ~57 MB/s, more with page reads) behind an adapter that accepts the core's DDR3-style
  requests (64-bit words, BURSTCNT up to 128, BE mask). Rough SotN VRAM traffic estimate from the profile:
  30-50 MB/s average (16x16 sprites ~4 Mpixel/s + 256x240 scanout + clears): async should be workable, a
  synchronous-burst PSRAM controller is the upgrade path if the GPU stalls too much.
- SRAM: free (could hold the memory card instead of PSRAM).
- SPU RAM: on MiSTer with one SDRAM, SPUSDRAM = 0 puts SPU RAM in DDR3. The Pocket build keeps SPUSDRAM = 1
  (separate spuram_* port; all area numbers assume this) and serves it from the SDRAM controller's channel 3
  (MiSTer uses ch3 only for BIOS/EXE download and cheats; on the Pocket: BIOS download at boot, SPU RAM after),
  at an SDRAM offset away from main RAM. ch3 has 32-bit data, byte enables and a ready strobe = spuram_done.
- Clocks: MiSTer pll = 33.8688 / 67.7376 / 101.6064 MHz (clk1x/2x/3x, fractional, 50 MHz ref) and
  pll2 = 53.693175 MHz video clock. Pocket: same outputs from the 74.25 MHz board clock (fractional PLL).
- First hardware milestone: boot to the PlayStation BIOS menu (no disc): needs SDRAM + BIOS data slot,
  PSRAM VRAM, video to the Pocket scaler, audio, controller. Then: CD image streaming, memory card save slot.
