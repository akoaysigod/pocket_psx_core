# Performance: long loads and frame-rate dips (worktree `sotn-perf`, branch `sotn-perf`)

Date: 2026-10-17. Starting point: `main` at 0.1.4 (core = build cc seed 1). Roadmap items "Long loads" and
"Boss fight/particles cause frame rate to dip".

**Short answer.**

- **Loads** in 0.1.4 are slower than on a PlayStation because the SD card often cannot deliver a sector within
  the 6.7 ms a double-speed drive takes for one. `pocket_cd` asked APF for one sector at a time and the drive
  model waited for it. The read-ahead from the `cd-engine` branch (8-sector ring, up to 4 sectors per APF read;
  in `main` since f0300d8) fixes this, and has been tested on hardware: the "CD late" marker, on almost all the
  time before, no longer showed. Loads then take as long as on a PlayStation. A SotN area load is ~0.7 MB,
  ~2.4 s of reading at double speed. Loading faster than a PlayStation needs MiSTer's CD speed options (forced
  4x-8x data reads, instant seek), which the Pocket build ties off.
- **Frame-rate dips** come from GPU drawing time, and VRAM is the main cost. VRAM is in PSRAM with a 33.9 MHz
  clock: one 64-bit word every 4 GPU clocks, ~11 clocks per access to start. In a GPU benchmark with SotN-like
  primitives, drawing takes 1.4-1.9x as long as the same GPU with a fast DDR3-like VRAM. Small semi-transparent
  polygons and sprites (particles) and lines are the worst case, because every scanline first reads the
  framebuffer row it blends with. The area trims of the GPU (3 dividers instead of 6, shared line multipliers)
  add up to ~11 % to polygons and lines, most for small polygons (sprites are not affected).
- **Fix with the biggest effect for its cost:** run the PSRAM controller on clk3x, so the PSRAM clock is 50.8 MHz.
  The latency code stays the same (allowed up to 52 MHz). In simulation, drawing time falls by 17-27 % in every
  workload. The controller's sequencer is unchanged; a small clock-crossing adapter (`vram_cdc.vhd`) carries the
  requests over (~50-130 ALMs; since the area / timing pass in `main` 4ec214a it fits with ~1,000 ALMs to spare). At 50.8 MHz the read
  data must be sampled inside a ~5 ns window, which moves with temperature and voltage because the PSRAM clock
  leaves the FPGA 3-11 ns after its clk3x edge. With timing constraints on the PSRAM pins (2026-10-22) Quartus
  checks that window and moves the sample point into it with the pins' input delay: ~1.6-1.8 ns of margin each
  side at every corner. **Tested on hardware (2026-10-25), on from 0.2** (`VRAM_CLK3X` in `pocket_psx.vhd`,
  section 4).

## 1. Loads

How a sector reaches the game on the Pocket:

1. `cd_top` models the drive: at double speed a sector every 225,792 clk1x (6.67 ms), plus a seek time from the
   distance (`seekTimeMul`, ~0.1-0.7 s). It asks for each sector at the start of its period (`cd_hps_req`).
2. In 0.1.4, `pocket_cd` sends APF one "data slot read" (target command 0x0180) per sector, 2,352 bytes, and
   passes the sector on when APF has written it.
3. If the sector is not there when the period ends, the drive countdown stops at 127 and waits for it
   (`cd_top.vhd`: `if (sectorFetchState = SFETCH_IDLE or driveDelay > 127)`). Every late sector stretches the
   load by the time it is late.

Measured on hardware (cd-engine worktree, 2026-10-16, test builds with a "CD" marker for late sectors): the
marker was on almost all the time with 0.1.4, so APF reads often take longer than 6.67 ms. With the read-ahead
(`cdeIs1`) the user did not see it at all. `pocket/sim/pocket_cd` in that worktree, with APF latency models of
2-8 ms per command: the old reader was late on 101 of 300 sectors (408 ms of waiting over 2 s of reading), the
read-ahead on 1.

How much data a load is (SotN disc, ISO 9660 directory, `/ST/<area>/`):

| Area files | Size | Reading at 2x (307 KB/s) |
| --- | ---: | ---: |
| `ARE.BIN` + `F_ARE.BIN` + `SD_ZKARE.VB/VH` (Colosseum) | 728 KB | 2.4 s |
| `CAT.BIN` + `F_CAT.BIN` + `SD_ZKCAT.VB/VH` (Catacombs) | 723 KB | 2.4 s |
| `CEN.BIN` + `F_CEN.BIN` + `SD_ZKCEN.VB/VH` | 496 KB | 1.6 s |

So a PlayStation also takes ~2 s for an area change. On 0.1.4 every late sector adds to that.

Going faster than a PlayStation: `cd_top` has MiSTer's options, all tied off in `psx_pocket_core.vhd`:

- `FORCECDSPEED` (2x / 4x / 6x / 8x data reads). It only applies while data is read: `allow_speedhack` is
  cleared while XA audio is decoded or the MDEC works, so music and movies keep their speed. At 4x, an area
  load is ~1.2 s. 8x needs a sector every 1.7 ms from the SD card, about the limit of the read-ahead (4
  sectors per 2-8 ms APF read).
- `INSTANTSEEK`: no seek time (SotN's area files are close together, so this saves ~0.1-0.3 s per load).
- `fastCD`: ~0.3 ms per sector (most likely too fast for the SD card; the drive then waits for the sector).

These are speed hacks: most games load fine, some rely on drive timing. As Core Settings (interact.json, like
the L2 / R2 pickers), the user can switch them per game. Cost: the drive delay becomes a mux of the speed
constants, and `ignoreDMACDTiming` comes back in `psx_top` / `dma`; not measured yet. On the `cd-engine` branch
the drive logic is firmware (`rtl/cd_fw/cd_fw.py`, `ld_readspeed`), so there the options are a firmware change
and one more input port.

## 2. Frame-rate dips

### Benchmark (`sim/gpu_perf`)

The real GPU (`rtl/gpu.vhd` and everything below it) draws command lists made by `gen_cmds.py`. Its VRAM is
one of:

- `MEM=0`: the Pocket path, `vram_psram.vhd` with two PSRAM models and board delays (4 ns out, 3 ns in).
- `MEM=1`: a fast DDR3-like memory, first word `FAST_LAT` clk2x after the request (12 by default), then one
  word per clk2x, and writes taken at one per clk2x. This stands in for MiSTer's DDR3, whose real latency is
  not known here; `FAST_LAT=24` is shown too.
- `MEM=3`: `vram_cdc.vhd` + `vram_psram.vhd` on clk3x, PSRAM clock 50.8 MHz.

GP0 words go into the GPU's FIFO as fast as it takes them (as the linked-list DMA does), so the GPU never
waits for commands. The display runs at 256 x 240, and its line reads compete for VRAM as in the game. Each
workload is one segment, timed from its first word until the GPU and VRAM are idle. `GPU=up` builds the
upstream `gpu.vhd`, `gpu_poly.vhd` and `gpu_line.vhd` (`ref/upstream/rtl`, 6 dividers, parallel line
multipliers) instead. `PROF=1` prints clocks per `gpu_poly` / `gpu_rect` state.

    ALTERA_MF_DIR=$PWD/sim/altera_lib [GPU=cur|up] [MEM=0|1|3] [FAST_LAT=12] [PROF=1] sh sim/gpu_perf/run.sh [segments]

The "PSX" column is a rough estimate from a mednafen-style cost model (GPU clock 53.69 MHz). A sprite costs 1
clock per pixel, +1/2 with semi-transparency. A polygon costs 2 per pixel when shaded or textured. Setup time
is not counted, so for small primitives the PlayStation is really slower than this column says. Use it for
scale only: the reliable comparisons are between the rows of this benchmark.

### Results (us to draw each workload)

| Workload (SotN-like) | Pixels | PSRAM 33.9 MHz (0.1.4) | PSRAM 50.8 MHz (`vram_cdc`) | Fast VRAM, lat 12 | Fast VRAM, lat 24 | Upstream GPU, PSRAM 33.9 | Upstream GPU, 50.8 | PSX est. |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 240 16x16 opaque tiles (one background layer) | 61,440 | 2,967 | 2,171 (-27 %) | 1,757 | 2,399 | 2,967 | 2,171 | 1,144 |
| 240 16x16 semi-transparent tiles | 61,440 | 5,372 | 4,063 (-24 %) | 2,822 | | 5,372 | | 1,716 |
| 60 32x32 opaque sprites | 57,165 | 3,817 | 2,846 (-25 %) | 1,987 | | 3,817 | | 1,065 |
| 60 32x32 semi-transparent sprites | 56,068 | 5,171 | 3,828 (-26 %) | 2,568 | 3,769 | 5,171 | 3,818 | 1,566 |
| 200 16x16 semi-transparent sprites | 49,776 | 5,731 | 4,281 (-25 %) | 2,969 | | 5,731 | | 1,391 |
| 400 8x8 semi-transparent sprites | 25,232 | 3,697 | 2,940 (-20 %) | 2,202 | | 3,697 | | 705 |
| 60 32x32 Gouraud textured quads, opaque | 61,224 | 4,459 | 3,569 (-20 %) | 2,974 | 3,907 | 4,395 | 3,395 | 2,281 |
| 60 32x32 Gouraud textured quads, semi-transparent | 61,812 | 7,057 | 5,332 (-24 %) | 3,825 | 5,484 | 6,885 | 5,167 | 2,302 |
| 300 12x12 Gouraud textured quads, semi-transparent | 42,180 | 9,018 | 7,505 (-17 %) | 6,296 | 8,525 | 8,137 | 6,632 | 1,571 |
| 200 16x16 Gouraud quads, semi-transparent | 50,622 | 6,066 | 4,640 (-24 %) | 3,610 | | 5,759 | 4,324 | 1,886 |
| 300 24-pixel Gouraud lines, semi-transparent | 6,695 | 2,838 | 2,334 (-18 %) | 1,784 | 2,695 | 2,621 | 2,112 | 187 |
| 2 full-screen flat semi-transparent quads | 122,880 | 4,826 | 3,568 (-26 %) | 2,510 | | 4,827 | 3,561 | 3,433 |

A frame is 16.7 ms. The hardware profile from 2026-10-13 (pk14, normal SotN play) showed the GPU busy 40-55 %
of the time, which matches a couple of tile layers and sprites from this table. A scene that adds a few hundred
small semi-transparent quads or sprites takes another 5-10 ms on the Pocket, and the game drops to 30 fps.

### Where the time goes

- **VRAM occupancy.** With the 33.9 MHz PSRAM, VRAM is busy 80-90 % of the drawing time in every workload. With
  the fast memory it is 30-60 %.
- **Semi-transparency.** Each scanline of a semi-transparent primitive first reads the framebuffer row it blends
  with (`REQUESTLINE` -> `READWAIT` in `gpu_rect` / `gpu_poly` / `gpu_line`), and only then draws. For the 32x32
  semi-transparent quads on PSRAM, the profile shows 49 % of the time in `READWAIT` + `REQUESTLINE` and 43 % in
  `PROCPIXELS`.
- **Texture cache fills** are single-word reads (`reqVRAMSize = 1`): ~15 clk2x each on the PSRAM. For textured
  workloads they are about a quarter of the VRAM time (estimated from the request counts).
- **Setup per triangle.** Each division round is 49 clk2x. With 3 dividers a textured Gouraud triangle needs 5
  rounds (boundary, colour x2, texture x2) instead of upstream's 3: +98 clk2x (1.4 us) per triangle. That is
  why small polygons lose the most to the area trims (-10 % for 12x12 quads).
- **Writes** are fine: the GPU makes a 64-bit word every 4 clk2x, and the PSRAM write burst keeps up.
  Suspending a burst write (stopping the PSRAM clock while it waits for the next word; the CellularRAM datasheet
  allows a stopped clock in a burst) was tried and measured no faster, at either clock.

## 3. What can be done

| # | Change | Effect (benchmark) | Cost | Risk |
| --- | --- | --- | --- | --- |
| 1 | CD read-ahead (`pocket_cd.vhd` ring of 8 sectors, merged in main f0300d8 with the CD engine) | loads as on a PlayStation | block RAM for the ring, some ALMs | tested on hardware; done |
| 2 | VRAM controller on clk3x (PSRAM 50.8 MHz), `vram_cdc.vhd` (this branch, `VRAM_CLK3X`) | -17 to -27 % drawing time | ~50-130 ALMs; on main 4ec214a 17,416 needed of 18,480 (seed 1; main alone 17,362) | read capture met with pin constraints, ~1.6-1.8 ns each side (section 4); tested on hardware, on in 0.2; new clk2x <-> clk3x paths (related clocks, 4.9 ns, met) |
| 3 | CD speed options as Core Settings (`FORCECDSPEED`, `INSTANTSEEK`) | area loads ~2x faster at 4x | not measured (mux + DMA timing bypass) | per-game compatibility (it is a hack on MiSTer too) |
| 4 | Framebuffer row for line N+1 read while line N draws (semi-transparent rect / poly / line), into the second line RAM | hides most of `READWAIT`; bounded by VRAM occupancy, so more useful after 2 | 2 M10K, state machine changes in three drawers | medium; hazards are only between primitives, which already wait (`REQUESTFIRST`) |
| 5 | Back to 6 dividers / parallel line multipliers (upstream) | -2 to -11 %, mostly small polygons | ~350 ALMs, +16 DSP | low (upstream logic) |
| 6 | PSRAM clock 67.7 MHz (clk2x through a DDIO output, fixed latency code 5, read data taken on the falling edge) | more bandwidth than 2, similar latency (not simulated) | ~0 ALMs | estimated read capture margin under 2 ns with tACLK 9 ns; needs I/O constraints and hardware checks |
| 7 | Texture cache fills of 2-4 words | fewer fills for sprites wider than 16 texels (4-bit) | cache tag logic | particles are mostly narrow, small gain there |

Order I would take: 1 (done, merged), 2 (done, 0.2), then 4 if the dips are
still there, 3 if loads should be faster than the PlayStation.

## 4. State of this branch

- `pocket/src/fpga/core/vram_cdc.vhd` (new), `pocket_psx.vhd`: `VRAM_CLK3X` puts `vram_psram` and the memory
  card's PSRAM side on clk3x behind `vram_cdc`. True from 0.2; false = the 0.1.4 path. The `.qip` lists
  the new file.
  `vram_cdc` is one request register (a second entry measured no faster) and a toggle for each read word; the
  read word itself is taken straight from `vram_psram`'s `ddr_dout`, which holds it for 4 clk3x.
- PSRAM pin timing. `tools/psram_io.tcl` (with `tools/sta.sh`) prints the datasheet times of the cram pins for
  each corner. Until the constraints of point 4, Quartus did not check this interface; the margins in points 1-3
  are worked out by hand from those times, tACLK <= 9 ns and tKOH >= 2 ns (psram_model).
  1. Core registers on both sides (0.1.4, and the first clk3x builds): clock-to-output of `cram0_clk` 10.1-10.7
     ns at slow 85C, 2.9-4.5 ns at fast 0C; dq setup ~4.2 ns (slow). A word is taken on the clk edge that raises
     the next PSRAM clock. At 33.9 MHz that is 29.5 ns after the edge that made the PSRAM send it: margin
     29.5 - 4.3 - 9.9 - 9 = +6.4 ns. At 50.8 MHz it is 19.7 ns: -3.7 ns. `pocket/sim/vram_psram` with those
     delays (`-gT_OUT=10ns -gT_IN=4ns`) agrees: 33.9 MHz PASS, 50.8 MHz 15,926 read errors.
  2. All PSRAM registers in the I/O cells (`perf_v3`): the read side would be fine, but the write-burst decision
     (`slotAddr = bAddr + 1`, the read-start `remaining` compare) cannot reach the byte-enable output registers at
     the chip edge in one clk3x. Slow 85C setup -2.36 ns (seed 2, which fits; seed 1 needs 1,852 LABs).
  3. Outputs in core registers, read data taken on the FALLING clk3x edge by I/O-cell input registers (`IN_REG`,
     the current code; it needs `set_instance_assignment -name FAST_INPUT_REGISTER ON -to cram0_dq[*]` and the
     same for `cram1_dq[*]` in `ap_core.qsf`, there from 0.2). In
     simulation, T_OUT + T_IN from 5 to 14 ns pass and 3.5 and 16 ns fail. With perf_v2's pin times: setup
     about +3.6 ns at slow 85C, but hold only about +0.3 ns at fast 0C. Word k is held until PSRAM edge k+1 +
     tKOH, and edge k+1 leaves the FPGA as early as 2.9 ns after the rising edge, while the falling edge is 4.9
     ns after it. Too thin to try.
  4. Constraints (option 1, 2026-10-22): `core/core_constraints.sdc` now describes the interface when the
     dqIn registers exist (VRAM_CLK3X): generated clocks `psram_clk` (on `o_clk`, clk3x / 2) and `cram0_clk` /
     `cram1_clk` (on the pins, so the clock's delay out of the FPGA is included), `set_input_delay` on `cram*_dq`
     (max tACLK 9 + board, min tKOH 2), `set_output_delay` on address / control / write data (tSP 3, tCSP 4,
     tHD 2, board), multicycles for the falling-edge capture (setup 24.6 ns, hold 4.92 ns) and the outputs (setup
     9.84 ns, hold -9.84 ns), and `psram_hold_guard` (1.5 ns) asking the fitter for extra read hold margin, so it
     moves the sample point into the window with the dq input delay chains. Board delays 0-0.5 ns each way
     (`psram_brd`, not measured). Checked on `perf4ec_v3x_s1` (no delay chains, constraints only read by the
     analyzer): read setup +4.31 ns (slow 85C), read hold +0.40 ns (fast 0C), write setup +1.11 ns (slow 85C),
     write hold +5.7 ns. Quartus's figure for read hold is better than the hand estimate (-0.1 ns) because it
     pairs each pin with its own clock path instead of the worst of all pins.
  5. Option 2, kept for later: a fourth output of the core PLL at the clk3x frequency, shifted ~100 degrees
     (~2.8 ns; the VCO period is 1.64 ns, so the step is 0.2 ns), clocking the dqIn registers, with the word moved
     to clk3x on the next rising edge (~7 ns later). Unlike the delay chain, a PLL phase does not change with
     temperature and voltage, so it keeps the whole window (~2 ns each side by the pin times above). Costs: the
     PLL regenerated (a free output counter not checked), one more global clock, one more clock crossing, the
     testbenches given the shifted clock; ~0 ALMs. Worth doing if the delay chains cannot give ~1 ns each side.
     Not needed so far: the delay chains give 1.6-1.8 ns and 0.2 works on hardware.
  Fit with these constraints (`perf4ec_sdc_s1`, main 4ec214a + VRAM_CLK3X true + FAST_INPUT_REGISTER on
     `cram*_dq`, seed 1): the fitter set the input delay chains of all 32 dq pins to D1 16 / D3_0 7. Read setup
     +1.63 ns (slow 85C; +2.40 slow 0C), read hold +1.84 ns (fast 0C: 0.34 reported beyond the 1.5 ns guard), so
     the sample point sits near the middle of the window. The chains add ~1.4 ns at fast 0C and ~2.7 ns at slow
     85C. Writes: setup +2.12 ns (slow 85C), hold +6.9 ns. The rest of the design meets every corner too (worst
     setup +0.759 clk3x slow 85C, worst hold +0.031 clk1x fast 0C, no critical warnings): 17,430 ALMs needed,
     1,843 LABs, 273 M10K, 57 DSP. `pocket/sim/vram_psram` at the matching delays (T_OUT + T_IN 11.5 + 2 and
     3.3 + 2 ns, seeds 1 / 2 and 1 / 3): PASS, no read errors, no PSRAM model violations, 62 ns per read word.
     Test package: `releases/akoaysigod.PSX_0.1.4_perf4ec_sdc_s1.zip` (not committed; built with the OVERRIDE of
     `pocket_psx.vhd` and the two FAST_INPUT_REGISTER lines, see NIGHT_LOG).
  6. Hardware test of that package (2026-10-25): works. On from 0.2: `VRAM_CLK3X` true, FAST_INPUT_REGISTER on
     `cram*_dq` in `ap_core.qsf`. Release build `v02_s1` (seed 1, the branch as it is): same synthesis, fit and
     timing reports as `perf4ec_sdc_s1`; the bitstream differs only in the APF build ID (`apf/build_id.mif`, build
     date and time). `releases/akoaysigod.PSX_0.2_v02_s1.zip`.
- Tests (current code, falling-edge capture):
  - `pocket/sim/vram_psram` `GENERICS="-gCDC=true -gIN_REG=true -gT_OUT=.. -gT_IN=.."`, 5,000 requests each
    (random reads / bursts / byte-enable writes, sequential runs with gaps, aux traffic): board + FPGA delays
    10 + 4, 11 + 2 and 6 + 2 ns (seeds 2, 3, 1): every read word right, no PSRAM model violations, 62 ns per read
    word (33.9 MHz: 88). 13 + 3 ns fails (setup), 3 + 0.5 ns fails (hold). Mutations caught: the adapter's queue
    may overfill (5,743 read errors); `IN_REG` data used one clk early (10,507 core and 425 aux read errors).
  - `pocket/sim/pocket_memcard` `GENERICS="-gCDC=true"`: FAILS (read mismatches). That testbench has no board
    delays at all, the far end of the hold problem in point 3. With the earlier rising-edge `IN_REG` (data
    sampled on the edge that raises the next PSRAM clock) it passed, seeds 1 / 2 / 7, but that version fails at
    the real slow-corner delays. Its self-check mutation (`MUTATION=1`) was caught then (2,112 APF errors).
  - With the testbenches' defaults (`CDC` false: the 0.1.4 path, not what 0.2 builds), both tests give the same results
    as before.
- Builds (details in `docs/NIGHT_LOG.md`): the design is at the edge of the chip, so whether a variant fits
  depends on the fitter seed. 1,848 LABs are available; the clk3x variants needed 1,848-1,858. The variant that
  fit (`perf_v2`, seed 1, 18,264 ALMs) has the core-register read capture of point 1, so it is not for hardware.
  On main 4ec214a (area / timing pass merged) the current code (falling-edge `IN_REG`, FAST_INPUT_REGISTER on
  `cram*_dq`) fits with seed 1 (`perf4ec_v3x_s1`): 17,416 ALMs needed (main's own seed 1: 17,362), 863
  recoverable, 273 M10K, 57 DSP. Setup met (worst +0.361 ns, clk3x slow 85C); hold -0.025 ns at fast 0C on
  `pocket_psx` `l_addr` -> `sdram` `ch3buf_addr` (clk1x -> clk3x, the APF loader path; a seed matter, not this
  change). Its PSRAM pin times (cram_clk out 9.6-10.9 ns slow 85C / 3.3-4.7 ns fast 0C, dq setup <= 0.55 ns,
  hold <= 2.08 ns slow / 0.51 ns fast) put the read sample point between 0.7 and 4.8 ns after the clk3x rising
  edge, before board delays; the falling edge (4.9 ns) gives setup +4.2 ns (slow 85C) but hold about -0.1 ns +
  board delay (fast 0C). Moving the sample to ~2.8 ns (input delay chain ~2 ns, or a phase-shifted clock) would
  leave ~2 ns each side: that is point 4 above.
