# Overnight log: SotN-on-Pocket size reduction

Fit numbers come from the larger 5CEBA5 device (real packed ALMs). The Pocket has 18,480 ALMs.
"ALUTs" are synthesis logic counts: deterministic, used to compare one change at a time.

| Step | Validation | Result |
|---|---|---|
| Baseline before tonight (tied-off + savestate reset-only + GTE rewrite + CD cleanup) | earlier | 21,572 ALMs (fit), 75 DSP |
| MDEC black-frame stub | equivalence vs original: 86,280 output words exact, control/DMA timing exact every cycle; two mutations caught | DSP 75 -> **66** (Pocket limit 66). ALMs: fitter noise hides it (22,119); synthesis: MDEC 1,123 -> 612 ALUTs |
| Savestate reset-only module: full-size validation | 2 full resets x 2 SPU-RAM modes, 1,049,602 memory writes, 0 output mismatches (testbench had a handshake bug, fixed) | validated |
| Quartus "aggressive area" optimization (no code change) | n/a | **21,434 ALMs** (vs 22,119 same code in speed mode); timing check still to do |
| SPU noise + pitch-modulation (FM) disabled (SotN never enables them) | new SPU testbench vs original (git HEAD): random register/DMA/SDRAM traffic, every output every cycle | synthesis: SPU -229 ALUTs, -1 DSP (65 now) |
| CD-DA forwarding disabled (SotN never plays CD audio) + BCD divider removed | BCD helper exhaustively checked (128 values) + mutation | synthesis: CD -135 ALUTs |
| SPU register readback: 51 CPU-only registers read from a block-RAM copy | SPU testbench with mid-run resets + savestate-reset writes: 2,000,000 cycles, 26 resets, 100k reads, 0 mismatches; mutations caught (both flag-clear paths removed: 15,780 mismatch cycles; one data bit wrong: 47,068) | synthesis: SPU -348 ALUTs, -81 registers |
| GPU: 6 dividers -> 3 (polygon colour/texture gradients and line setup run a second divider round) | new GPU testbench: original (6 dividers) vs new (3) on the same random command stream with independent stalls; ordered pixel/VRAM-request/palette/draw-mode/done streams must match: 400 polygons = 866,782 pixels and 800 lines = 101,662 pixels identical; 2 mutations caught. Setup gets slower: ~1% (polygons) to ~10% (short lines) in the synthetic test; sprites/rectangles are unaffected | synthesis: GPU -381 ALUTs, -485 registers |
| GTE operand selection restructured (generator tools/gte_codes.py): each of the 248 MAC requests now records small select codes; one 3-14 input multiplexer per field builds the request in the same cycle (was one 58-input multiplexer per field) | GTE testbench: 300 + 20,000 + 20,000 commands exact (busy every cycle, readback every cycle); mutation caught (198 mismatches) | synthesis: **GTE -1,117 ALUTs** (4,469 -> 3,352), registers unchanged |
| GTE latch loads (matrix/vector/translation) via select codes (tools/gte_latch_codes.py) | GTE testbench 300 + 20,000 exact; mutation caught | synthesis: GTE -60 ALUTs |
| Savestate reset sequencer: reset mode made a constant (it was only ever set) -> all savestate write data provably 0 and loading_savestate provably 0, so every module's savestate load/write paths are removed | savestate testbench: 2 full-size runs x 2 SPU-RAM modes, 1,049,602 writes, 0 mismatches | synthesis: **-692 ALUTs, -639 registers** (DMA -398, SPU -233, timer -50, GTE -57, savestates -35) |
| GTE register readback: CPU-only registers read from a block-RAM copy | GTE testbench extended (interleaved reads/writes, same-cycle collisions, mid-run resets, readback compared every cycle): 20,000 tests + 404k mixed cycles exact; 3 mutations caught | synthesis: GTE -650 ALUTs (+1 RAM block) |

Notes
- "ALMs needed" on the big device varies by several hundred between runs (loose packing), so small changes are compared with synthesis ALUTs instead.
- The register-bank scan's top item (CD XA ring buffer) is already in block RAM: no saving there.
- Cheats logic is already removed by synthesis: no saving there.

Synthesis totals (area mode): 31,330 -> 30,928 (SPU/CD cuts) -> 30,191 (GTE readback) -> 29,730 ALUTs (SPU readback).
After GPU dividers: 29,502; after GTE operand restructuring: 28,396 ALUTs.
After GTE latch codes + constant reset mode: **27,765 ALUTs**.
Start of night (speed mode, before MDEC stub): ~32,700 ALUTs.

Milestone fit (everything above except the GPU divider change), 5CEBA5 C8, area mode: **20,391 ALMs**, 65 DSP, 282 RAM blocks.

Timing (Pocket speed grade C8): my first timing check reported huge failures, but they were an error in my
constraints file (clock periods not exact multiples: 2 x 14.763 != 29.525). With exact periods:
clk1x +2.5 ns slack, clk3x +1.6 ns, clk2x -0.95 ns (14 paths, all in the original gpu_poly 32x32 multiplier),
and small hold violations on clk1x->clk2x crossings. That fit was still optimised against the wrong
constraints; the next fit (b7) uses the corrected file.

Fit b7 (adds GPU divider change, corrected clock constraints): **20,224 ALMs**, 65 DSP, 282 RAM blocks.
Timing: setup clk2x -0.15 ns (8 paths, original gpu_poly multiplier), clk1x +1.95, clk3x +1.2.
Hold: ~-1 ns on clk1x<->clk2x crossings (e.g. CPU write data -> GTE registers). Likely an artifact of this
measurement harness (each clock enters on its own pin, so clock skew is not PLL-compensated); to be
re-checked with the real Pocket top, where one PLL generates all three clocks.

## First fit on the actual Pocket FPGA (5CEBA4F23C8), 2026-10-12 morning
State: everything above (27,765 ALUTs in synthesis). Result: **does not fit**:
"Fitter requires 1957 LABs to implement the design, but the device contains only 1848 LABs" (~6% over).
1 LAB = 10 ALMs, so ~1,090 ALMs too many, of which ~400 are this harness's 796 virtual pins.
=> the core alone is ~700 ALMs over, and the Pocket wrapper still needs ~1,000-2,000 ALMs on top:
roughly 2,000-2,500 ALMs (~3,000+ ALUTs) still to cut.

## After the Pocket fit attempt
| Step | Validation | Result |
|---|---|---|
| Savestate write enables for module state (types 0-11, 13) masked to 0: the reset sequence starts at type 12 and never sets them, so every module's savestate write path is removed | savestate testbench: quick + 2 full-size runs (both SPU-RAM modes), 0 mismatches | synthesis: **-473 ALUTs** (SPU -105, DMA -92, GPU -76, CPU -66, CD -65, memctrl -59, ...): 27,292 total |
| Measurement wrapper: Pocket-constant inputs tied (pause 0, hps_busy 0, hasCD 1, lid closed, fastCD 0, videoout_on 1, fastboot 0) and MiSTer-only video outputs (display size/offset, framebuffer mode, frame index, PAL flag) left open | none needed: this is how the Pocket wrapper will drive/use them | -77 ALUTs: 27,215 |
| Experiments not kept: dropping the 11 GTE commands SotN never issued saves only 143 ALUTs (shared datapath); not worth the risk | - | - |
| SPU voice memories (voice registers x2, volumes x2, voice records, envelope counters): MLAB -> M10K clocked on the falling edge (new rtl/RamM10Kn.vhd) | component test RamM10Kn vs RamMLAB: 100,000 edges incl. same-address collisions, 0 mismatches; mutations caught (rising-edge clock: 14,250; DONT_CARE collisions: 46). SPU testbench: 200k + 2,000,000 cycles (16 resets) exact; mutation caught | frees ~370 ALMs of MLAB (measured in the next fit) |

## Second fit on the actual Pocket FPGA (p2), 2026-10-12
State: everything above incl. SPU voice memories in M10K (CPU cache-tag change NOT included). Synthesis 27,087 ALUTs.
Result: still does not fit, but close: **18,520 ALMs needed / 18,480** (1,877 LABs / 1,848).
Of those, 371 ALMs are "unavailable due to virtual I/Os" = this measurement harness's fake pins.
The core itself (psx_mister) is **18,030 ALMs**. Memory ALMs fell 620 -> 320 (SPU change worked: -300).
M10K: **290 / 308 used** (only 18 left; the wrapper also needs some). DSP: 65 / 66.
=> core ~18,030 - ~150 (CPU cache tags, next) = ~17,900. With a ~1,000-1,500 ALM wrapper, the core must get to
~16,500-17,000: about 1,000-1,400 ALMs still to cut, using little or no extra M10K.
Biggest blocks now (ALMs): GPU 5,100 (polygon 2,140), GTE 2,710, SPU 2,590, CPU 2,170, CD 2,120, DMA 1,180.

## After p2
| Step | Validation | Result |
|---|---|---|
| Memory card slot 2 removed (constant MEMCARD2_ON = false in psx_top; outputs tied inactive). The Pocket has one save slot; SotN saves to slot 1 | new sim/memcard2_off: with no card 2 (available/load/mounted 0) joypad_mem + memcard driven with random traffic for 200,000 cycles, 93 resets, 2,034 save requests: 0 active cycles. With a card present the same checker sees activity (199,395 cycles), so it is sensitive | ~50 ALMs + 1 M10K (measured in next build) |
| SPU reverb register file (32 registers at 0x1F801DC0-DFE): the reverb datapath now reads them from two 32x16 MLABs (coefficient port + buffer-address port) instead of 512 flip-flops and two 13-way multiplexers; validity reuses the readback shadow's valid bits (0 until written after reset); dAPF1/dAPF2, vLOUT/vROUT, mBASE stay registers | SPU testbench vs original: 200k cycles exact; mutations caught: left/right swap of dDIFF undone (664,291 mismatch cycles), valid gating removed (161,354); 2M-cycle runs: see below | measured in next build |
| (SPU reverb, continued) | 2M-cycle SPU runs vs original, seeds 1 and 5: 18 resets each, ~164k SPU-RAM requests, 0 mismatch cycles: PASS | - |

## Third fit on the actual Pocket FPGA (p3): **IT FITS** (2026-10-12)
State: p2 + CPU instruction-cache tags moved from MLAB to M10K (falling edge, like the SPU memories).
(Memory card 2 and SPU reverb changes are NOT in p3 yet.)
**Fitter successful on 5CEBA4F23C8: 18,229 ALMs needed / 18,480** (p2: 18,520), 1,809 / 1,848 LABs,
290 / 308 M10K, 65 / 66 DSP. Memory ALMs 320 -> 160. This still includes 371 ALMs of the harness's fake pins,
so the core alone is ~17,860 ALMs; free for the wrapper today: ~620 ALMs (needs ~1,000-1,500 -> keep cutting).
Timing on the Pocket speed grade (C8), with exact clock constraints:
- setup clk1x +0.60 ns, clk3x +0.26 ns, clkvid +6.9 ns, clk2x +0.08 ns at 85C but -0.22 ns at 0C
  (TNS -1.7 ns; the original 32x32 multiplier paths in gpu_poly, same as before)
- hold: clk1x -1.07 ns (TNS -36 ns), clock-crossing paths; expected to be an artefact of this harness
  (three clocks on separate pins instead of one PLL) - to be re-checked in the real Pocket top.

## After p3 (in build p4)
| Step | Validation | Result |
|---|---|---|
| Register census tool (tools/census.sh: every flip-flop of a fitted build, grouped by module and signal) | - | biggest groups: GPU texture-cache valid bits 256, DMA channel registers ~550, GPU dividers ~580, CPU multiplier inputs 256 (duplicated into DSP blocks), slot-2 memory card leftovers ~200 |
| CPU cache-tag M10K timing check: the new half-cycle path into the tag memory | p3 timing: +1.57 ns slack on that path | OK |
| Memory card slot 2, joypad side (joypad_mem2) also removed under MEMCARD2_ON | memcard2_off test extended to the received-data byte: 200,000 cycles, 105 resets: inert | measured in p4 |
| CPU: MULT and MULTU share one 33x33 signed multiplier (operands sign- or zero-extended) instead of separate signed and unsigned 32x32 multipliers | new sim/cpu_mul: 4,000,338 checks (13x13 corner values + 2M random pairs, both instructions) exact; mutation (MULT zero-extended) caught 15,164 errors | measured in p4 (also saves DSP blocks) |
Not pursued: fewer GPU dividers. Each division is ~46 clk2x cycles; the current sharing already adds ~0.7 us per
shaded or textured polygon, one divider would add ~2 us per polygon. Not worth the slowdown risk.

## After p4 (for build p5)
| Step | Validation | Result |
|---|---|---|
| GTE matrices (RT/LL/LC) and translation vectors (TR/BK/FC): the datapath reads them from 12 small MLABs addressed by a registered select code, instead of latching copies into ~900 flip-flops. Safe because these control registers are only written by CTC2, which the CPU stalls while the GTE is busy (checked in cpu.vhd: CTC2/MTC2 stall on gte_busy or a GTE command in execute; CTC2 and a command can never reach the GTE in the same cycle). The "garbage matrix" entries computed from data registers (RGBC, IR0) are still latched | GTE testbench vs original gte.vhd (it also only writes while the GTE is idle, like the CPU): 2,000 + 20,000 (seed 1, 399k mixed read/write cycles) commands exact; mutations caught: wrong garbage-matrix source (43 register mismatches), valid gating removed (17), translation code-3 value 1 instead of 0 (61). (A 4th mutation turned out to be equivalent: MLAB entry 3 is never written so it reads 0 anyway.) | measured in p5 |
| PS-X EXE side-loading sequencer in memorymux disabled (constant EXE_LOAD_ON = false; loadExe is tied to '0' on the Pocket, so loadExe_latched can never become '1' and those states are never entered) | code reading (single entry point, guarded); file analyses cleanly | measured in p5 |
| (GTE, continued) | second 20,000-command run (seed 9, 408k mixed cycles): exact. PASS | - |
| CD: LibCrypt copy-protection check disabled (constant LIBCRYPT_ON = false). The key comes from the track table and is 0 for SotN USA, so the check (16 key bits x 2 sector-number comparisons) can never trigger; only some PAL games use LibCrypt | logical: the original condition is an OR of (key bit AND compare); with key 0 it is always false | measured in p5 |
| CD: CD-DA position-report sender also gated by CDDA_ON (its only trigger, processCDDASector, is already never set with CDDA_ON = false; synthesis could not prove the report counter stays 0, so the counter, the 8-byte report mux and the CD-DA peak-volume trackers were still built) | code reading: processCDDASector is assigned only '0' and (under CDDA_ON) '1'; CDDA_outcnt is only set under processCDDASector | measured in p5 |

## Fourth fit on the Pocket FPGA (p4): fits, 17,883 ALMs (2026-10-12)
State: p3 + memory card slot 2 removal (both halves), SPU reverb MLABs, CPU multiplier merge.
Synthesis 26,248 ALUTs (p3 27,000), 62 DSP (-3), M10K 282 / 308 (-8).
Fit: **17,883 ALMs needed / 18,480** (p3 18,229: -346), 1,807 / 1,848 LABs; still incl. 371 ALMs of harness pins.
Side effect worth knowing: the multiplier merge freed DSP blocks and Quartus moved a gpu_poly multiplier from
logic into a DSP (gpu_poly -312 ALUTs with no change of its own).
Timing (C8): clk1x +1.25 ns, clk3x -0.03 ns, clk2x **-2.48 ns**. Worst paths:
- CPU -> GTE register write (clk1x -> clk2x): includes -2.49 ns clock skew between the harness's separate clock pins;
  with a PLL this skew is near zero. => the harness now gets its clocks from the repo PLL (PLL=1 in qbuild.sh,
  tools/make_pll_harness.py, tools/pocket_pll.sdc) so crossings are timed realistically from p5 on.
- GPU VRAM read-burst setup (gpu.vhd, vramState -> reqVRAMwrap, unchanged original logic): 16.2 ns of logic+routing in
  a 14.76 ns period. It passed in p3 and fails in p4 depending on placement. The Pocket's C8 is the slowest speed
  grade (DE10-Nano is I7), so this original path is marginal there. To do before a real Pocket build: pipeline it
  and/or build with a timing-oriented optimisation mode now that there is area headroom.
| GPU texture-cache valid bits (256 flip-flops + 256:1 read mux + 256 set enables): new rtl/ValidBits256.vhd keeps them as 16 MLAB words of 16 bits plus 16 "stale" flags; clear-all marks all words stale in one cycle, the first set into a stale word rewrites the word, later sets read-modify-write it (second MLAB copy as read port). Same set / clear-all / combinational-read behaviour as the flip-flops; set and clear happen in different pipeline states | new sim/validbits256: component vs 256 flip-flops, 200k + 2,000,000 cycles (1.33M sets, 5,014 clear-alls, random + sweep reads) exact; mutations caught: stale gating removed from reads (2,713 errors), stale ignored in read-modify-write (32,261) | measured in p6 |

## Fifth fit on the Pocket FPGA (p5), first one with the PLL harness: fits, 17,479 ALMs (2026-10-12)
State: p4 + GTE matrix/translation MLABs + EXE loader off + LibCrypt off + CD-DA report sender off.
Synthesis 25,807 ALUTs (p4 26,248; GTE -216 ALUTs / -628 flip-flops, CD -203, memorymux -107), 18,737 registers.
Fit: **17,479 ALMs needed / 18,480** (p4 17,883: -404), 1,796 / 1,848 LABs, 282 M10K, 62 DSP.
Harness pins still cost 370 ALMs => **core alone ~17,110 ALMs, ~1,370 ALMs free for the Pocket wrapper**.
Timing with the core clocks from a PLL (realistic clock skew):
- all hold checks now pass (the earlier hold violations were the harness's separate clock pins, as suspected)
- setup: clk1x +1.35 ns, clk3x +3.17 ns, clk2x -0.13 ns (85C) / -0.57 ns (0C), TNS -1.0 / -4.5 ns
- the only failing paths: GPU VRAM read-burst setup (gpu.vhd, vram_pause/vramState -> reqVRAMwrap), original logic.
  Options for the real build: timing-oriented fitter settings (there is now area headroom), another seed, or
  computing the wrap length one cycle earlier for the two requesters that can wrap (VRAM->VRAM, VRAM->CPU).

## Sixth fit on the Pocket FPGA (p6): fits, 17,312 ALMs (2026-10-12)
State: p5 + texture-cache valid bits in ValidBits256. Synthesis 25,603 ALUTs (GPU -239), 18,472 registers.
Fit: **17,312 ALMs needed / 18,480** (p5 17,479: -167); harness pins 370 => **core ~16,940 ALMs, ~1,540 free**.
M10K 282 / 308, DSP 62 / 66. Timing (PLL harness): all hold OK; setup clk1x +1.37, clk3x +2.69,
clk2x -0.47 (85C) / -0.98 (0C): still only the GPU VRAM wrap-length path (gpu.vhd -> reqVRAMwrap).

## Pocket wrapper, started (2026-10-12)
- Template (open-fpga/core-template) downloaded to psx_pocket_work/ref/core-template; agg23's MIT
  analogue-pocket-utils (PSRAM controller, I2S) to ref/analogue-pocket-utils. Plan details in POCKET_WRAPPER_PLAN.md.
- New in the repo: pocket/src/fpga/core/psram_async.vhd (VHDL port of agg23's psram.sv, MIT notice kept) and
  pocket/src/fpga/core/vram_psram.vhd (serves the core's DDR3-style port - VRAM and memory card buffer - from
  the two PSRAMs as one 32-bit memory). Test: pocket/sim/vram_psram (behavioural PSRAM model with 70 ns access
  time, chip-enable and last-word checks): 500 requests / 5,100 words exact; mutations caught (wrong byte lane
  on write: 21 errors, swapped halves on read: 15, sampling 2 cycles before the access time: all 2,589 reads).
  Throughput in this async mode: ~266 ns per 64-bit word (~30 MB/s) - fine for booting, likely the first thing
  to speed up (page-mode or synchronous burst reads) if SotN's GPU stalls on VRAM.
- No Verilog simulator is installed, so new wrapper logic is written in VHDL and simulated with nvc.

## GPU VRAM wrap-length timing fix + seventh fit (p7): fits, timing met (2026-10-12)
- rtl/gpu.vhd: the wrap length for VRAM->VRAM / VRAM->CPU reads (reqVRAMwrap) is now computed from registered
  copies of x position and size in the cycle after the request is accepted (wrapPend/wrapXPos/wrapSize), and the
  READVRAM state uses that value directly when it is needed in the same cycle (wrapEff). Backup:
  gpu.before_wrapfix.vhd. Test: new sim/gpu_vram (whole GPU, original vs changed, each with its own VRAM model,
  GP0 fills, CPU->VRAM, VRAM->VRAM and VRAM->CPU with forced wraps, every VRAM request/data compared per cycle).
- p7 (p6 + wrap fix), PLL harness, C8: **17,374 ALMs**, all timing met: clk2x +0.763 (85C) / +0.449 (0C),
  clk1x +0.729, clk3x +1.516; all hold positive.
- rtl/gte_small.vhd now declares `entity gte` (so the Pocket file list can use it in place of gte.vhd);
  sim/gte_small/run.sh renames it back for the comparison: 2,000 random commands, seed 3: PASS.
- Pocket project build tool: tools/pbuild.sh NAME (copies repo pocket/ + rtl/, quartus_sh --flow compile,
  single-threaded, writes the bit-reversed .rbf_r with tools/rbf_reverse.py). ap_core.qsf: MUX_RESTRUCTURE AUTO
  and fitter register duplication OFF (the template's settings cost area; p7 fitted without them).

## First real Pocket build (pk1): APF top + PLLs + SDRAM + PSRAM + video/audio wrapper, compiles, fits, timing met
- tools/pbuild.sh pk1 (repo pocket/src/fpga/ap_core, Quartus 25.1 Lite, single-threaded): 17,972 / 18,480 ALMs (97 %),
  286 / 308 M10K, 62 / 66 DSP, 224 / 224 pins, 2 PLLs. All clocks meet setup/hold (worst setup +1.36 ns clk2x at 0C,
  worst hold +0.028 ns). bitstream: builds/pk1/pocket/src/fpga/output_files/ap_core.rbf_r (BIOS-only wrapper:
  no CD, no memory card, no SDRAM fast I/O registers - superseded by pk2).
- Fixes on the way: psram_async used VHDL-2008 maximum() on reals (Quartus: not declared) -> local maxr();
  ap_core.qsf had no final newline (appended line broke the qsf); MUX_RESTRUCTURE AUTO + no fitter register
  duplication (area). ap_core.qsf now also puts the SDRAM pins' registers in the I/O cells (as MiSTer's sys.tcl).

## CD streaming for the Pocket (pocket/src/fpga/core/pocket_cd.vhd)
- Replaces MiSTer's HPS side: reads the track file sizes from the APF data slot table, builds the track table,
  sends trackinfo (same layout as Main_MiSTer psx.cpp for a one-file-per-track cue: track 1 at LBA 150, audio
  tracks with their 2 s pregap inside the file), then serves each cd_hps sector request with APF target command
  0x0180 (data slot read, 2352 bytes) into a sector buffer and passes it to the core like hps_io does (ack high
  during the block, one write per 16-bit word). Core held in reset until the table is built.
- Test pocket/sim/pocket_cd (APF + core models): SotN layout (229,020 + 18,995 sectors; trackinfo total 248,165,
  MM:SS 55:08, track 2 50:57 audio) 30 requests incl. edges PASS; 5-track layout 150 requests PASS; no disc PASS.
  Mutations caught: track boundary off by one (read past end of slot), halves swapped (18,816 word errors),
  TB self-check (7,612).
- Game selection: data.json slot 0 = instance JSON (one per game), tracks = deferred slots 16..39;
  pocket/tools/cue2instance.py makes the instance JSON from a .cue (tested on the SotN cue; it maps the renamed
  .bin files by "(Track N)").

## Memory card 1 saves (pocket/src/fpga/core/pocket_memcard.vhd + vram_psram aux port)
- The core keeps the live card in its DDR3 region 1 = PSRAM region 1 on the Pocket, so APF's nonvolatile save
  slot (0x20000000, 128 KB raw card = MiSTer .sav format) is loaded straight into that PSRAM region while the
  core is in reset, and read back from it when APF saves (agg23 data_unloader protocol + sequential prefetch).
- vram_psram: aux port (single 32-bit accesses) taken right after each core access, in idle cycles, and between
  the halves of core read bursts; vram_psram no longer reset with the core (only PLL lock).
- Test pocket/sim/pocket_memcard (APF + core + PSRAM models, random VRAM traffic incl. 64-word bursts all the
  time): load, core reads card through its DDR port, core writes card ("game saves"), APF reads back:
  PASS for gaps 30/36/45/60 clocks between APF reads (APF is ~75 clocks per word), up to 4,160 words.
  Found and fixed on the way: aux starvation by back-to-back core writes, slow fetch behind core bursts
  (-> prefetch), stale prefetch after a non-sequential jump, TB phase race. Mutations caught: no burst
  interleave, wrong card base (core reads wrong), no prefetch invalidation on core writes (stale word),
  TB self-check. At an (unrealistic) 20-clock gap 2 of 1,088 reads are late.

## Video to the Pocket scaler: pixel clock halved (pocket/src/fpga/core/pocket_video.vhd)
- APF docs: pixel clock 1 MHz to ~50 MHz; we were sending clkvid (53.69 MHz). Now the video PLL also makes
  clkpix = clkvid / 2 (26.85 MHz, same PLL, edges aligned) + 90 degree copy; each core pixel (at most every 4th
  clkvid clock) is held and signalled with a toggle, clkpix clocks without a new pixel get skip.
- Also enforced: HS at least 3 clocks after VS (PSX vsync can start just after hsync / mid line), RGB zero
  outside DE except the scaler-slot word right after DE falls, nothing on RGB during VS (feature bits = 0).
- Test pocket/sim/pocket_video: 5 widths (256/320/368/512/640, pixel every 10/8/7/5/4 clkvid), vsync before /
  just after hsync / mid line, 2 frames each, every APF rule checked each clkpix clock: 220 lines PASS.
  Mutations caught: wrong slot code, HS-after-VS guard removed (2 violations).

## pk2 (CD + memory card + SDRAM I/O registers): does not fit - 19,219 ALMs needed / 18,480
- with hasCD tied to 0 (pk1) Quartus had removed the core's CD logic; live again: core +1,182 ALUTs, plus
  pocket_cd 496, pocket_memcard 150, vram_psram aux +73.
- The template qsf had SAFE_STATE_MACHINE, pre-mapping resynthesis, WYSIWYG remap, physical synthesis
  (combo, retiming, async pipelining), LCELL insertion: core 17,592 ALMs vs ~17,000 in p7 with the p7 settings.
- pk3: qsf back to the measurement-build settings (+ registers packed MINIMIZE AREA), pocket_cd slimmed
  (trackinfo / dsr_id / divisor registers removed, same tests pass incl. mutations), video fix.
  Synthesis 27,720 ALUTs (pk2 28,526), estimate 18,175 ALMs.

## DMA D_MADR / D_BCR in MLABs (rtl/dma.vhd), for the fit
- 7 channels x (24 + 32) bits = 392 flip-flops + two 7:1 read muxes -> 2 x 2 RamMLAB (two read ports: CPU read
  by bus address, transfer start by trigger channel), one combinational write port (savestate write, else
  end-of-transfer write-back, else CPU write, same priority as before), valid bits for reset = 0.
  CHCR stays in flip-flops (bits 24 / 28 of all channels are read every clock). Not in the savestate readback
  any more (savestates are off on the Pocket, SS_rden constant 0).
- One write per clock is enough because the CPU is paused while a transfer runs (psx_top keeps cpuPaused high
  through the write-back clock; the original even flags CPU accesses during DMA as errorDMACPU).
- sim/dma_equiv got a REALISTIC mode (no CPU register traffic while the CPU is paused for DMA). Strict mode
  (CPU writes during transfers, impossible in the console) shows the expected 48 mismatch cycles in 200k,
  each one flagged by a new sim-only assertion. Realistic: seed 1 200k cycles 7,971 transfers PASS; seed 2
  2M cycles 38,436 transfers 11 resets PASS; seed 3 0 mismatches until 1.3M cycles where the TB produced an
  illegal MDEC direction (same assertion in reference and new design at the same clock).
  Mutations caught: valid bits ignored, trigger read port wrong (both crash the TB on garbage counts), no
  write-back (587,487 mismatch clocks).

## pk3 / pk4 fits
- pk3 (measurement-build settings, slim CD, video fix): 18,540 ALMs needed / 18,480 (1,877 / 1,848 LABs): 60 over.
- For pk4:
  * DMA D_MADR / D_BCR in MLAB (above): dma -136 ALUTs, -378 registers.
  * CD Pause timing back to the fixed upstream values (before commit cd17b5a "improve Pause timing accuracy with
    SPT model": its rotation model needed a registered multiply and 27-bit delay arithmetic, plus the subq
    drop-back on Pause). GetLocP's disc position model (comparison form of the SPT table) is unchanged.
    Restored block compared line by line with upstream cd17b5a^ (drive_stop placement as upstream).
    cd_top -187 ALUTs.
  * vram_psram: ddr_dout / aux_dout straight from the PSRAM controllers' output registers (-96 registers);
    vram_psram 1,000 requests and memory card runs (gap 36 and 60) PASS again.
  pk4 synthesis 26,819 ALUTs / 20,624 registers (pk3 27,720 / 21,130), estimate 17,459 ALMs (pk3 18,175).
- DMA mutation check corrected: seeds 3 and 5 stop on TB stimulus limits (illegal MDEC direction / requestedDwords
  overflow) in the reference and the new design at the same clock, so mutations must use a seed that runs
  clean (seed 2, 2M cycles): trigger-port mutation 5,150,075 mismatch clocks (caught); no-write-back caught
  (seed 6, 587,487). Valid-bits-ignored is equivalent here: the core's reset sequence writes zeros to every
  register through the savestate path (as in the TB), so stale MLAB contents never survive a reset; the
  valid bits stay as a safety net (power-up, reset without that sequence).
- **pk4 fits and meets timing**: 17,962 / 18,480 ALMs (97 %), 1,835 / 1,848 LABs, all clocks: worst setup
  +0.453 ns (clk3x), worst hold +0.038 ns, no critical warnings. This is the first complete Pocket build
  (core + CD streaming + memory card saves + video fix + SDRAM I/O registers).
- SD card folder: psx_pocket_work/SD_pk4 (pocket/tools/package.py): Cores/PSXPort.PSX (bitstream.rbf_r + json),
  Platforms/psx.json, Assets/psx/common/scph1001.bin, Assets/psx/PSXPort.PSX/{BIOS (no disc).json,
  Castlevania - Symphony of the Night.json + folder with the two .bin files}.
- GPU wrap-length fix (gpu.vhd, in p7..pk4) confirmed by sim/gpu_vram (original vs changed GPU, per-clock compare
  of every VRAM request and data): seed 7 10 commands (29 read bursts, 4 wrapping) and seed 8 15 commands
  (56 read bursts, 8 wrapping) 0 mismatch clocks; mutation A on seed 8: 816 mismatch clocks (caught).
  The earlier 40/100-command runs are still running after 2 h (large random transfers); more 15-command seeds too.

## First hardware test (pk4): BIOS (no disc) -> black screen, no sound
- Checked in code: data-slot "loading" flag clears (requestwrite is a pulse), bridge byte order is little-endian
  (first BIOS word 0x3C080013 = lui t0,0x13).
- Diagnostic build pk5 (pocket/src/fpga/core/pocket_diag.vhd): 20-bar status screen with its own 320x240 timing,
  shown while the core gives no frames or Select is held; BIOS word count + checksum as received (expected
  sum 0xF67ECB99, byte-swapped 0x1F24C5FB), SDRAM read-back of the BIOS after loading, sticky activity flags.
  pocket/sim/pocket_diag: APF video rules over 2 frames (480 lines) + bar colours PASS.
- pk5 seed 1: 18,177 ALMs, small timing misses at the extreme corners; seed 2 (pbuild.sh SEED=2) pk5s2:
  18,186 ALMs, all timing met (worst setup +0.450, hold +0.015). Bitstream for the user: SD_pk5_diag.

## Second hardware test (pk5s2): thin coloured lines on black, no bars
- Photo: one line near the top (red, white, blue), one red line near the bottom, rest black. Cause found in
  code: pocket_diag only took over while the core gave no vsync, but the GPU makes video timing as soon as the
  core leaves reset (BIOS running or not), so the photo is the core's own picture, not the bars. The GPU starts
  with the display enabled (SS_reset zeroes ss_gpu_in, as upstream), so it shows whatever is in VRAM.
- pk6: bars shown by default, Select held = core picture (switch at a diagnostics frame start). Second column
  R1..R19 (pocket_psx diag_status 21..39): BIOS fetch beyond 4 KB / 64 KB / upper half, main RAM written / read
  / read above 64 KB / above 192 KB, DMA used RAM, SPU RAM used, VRAM written, non-black pixel, interlaced mode,
  CD sector requested, memory card read; "now" flags (previous 0.12 s window): vsync, BIOS fetch, RAM read,
  sound, any button. pocket/sim/pocket_diag (now with run.sh): rules + both columns + Select switching with
  the core sending vsync: PASS; mutations (column index, Select inverted) caught.
- pk6 seed 2: 1,851 LABs needed of 1,848 (no fit) -> seed sweep 1, 3, 4, 5.
- pk6s1 (seed 1) fits: 18,274 / 18,480 ALMs, all timing met (worst setup +0.298 clk3x, worst hold +0.024),
  no critical warnings. Bitstream for the user: SD_pk6_diag/Cores/PSXPort.PSX/bitstream.rbf_r.

## Third hardware test (pk6s1): bars readable - BIOS stalls in a RAM loop before the logo
- Left column all green except 18 (sound): BIOS arrives intact, SDRAM read-back matches, core runs, VRAM works.
- Right column: BIOS past 4 KB / 64 KB yes, upper half no; RAM written/read (also above 192 KB = stack) yes;
  DMA never; SPU RAM yes (the SPU reads its RAM itself, so not informative); VRAM written yes; picture never
  non-black; no interlace; no CD request; no memory card read. Now: frames yes, BIOS code no, RAM reads yes.
- **Cause found (memorymux.vhd, my EXE-loader trim):** the EXE_LOAD_ON gate was also put on
  EXE_WRITE_PREWAIT, which despite its name is the external-bus (SPU / CD / EXP) recovery wait before a write,
  entered when a write follows a RecP device access within com0_delay clocks (SPU delay register 0x200931E1 has
  RecP; COM_DELAY 0x31125 -> com0 = 5). Gated off, ext_state stays there forever: the posted write never
  happens and the next external access hangs memorymux. Uncached BIOS code (BFC0040C: 4 back-to-back SPU sh)
  is too slow to trigger it (each uncached fetch ~25 clocks); cached kernel code in RAM triggers it. Verified
  only by code reading back then - the lesson: name-based gating needs a simulation.
  Fix: EXE_WRITE_PREWAIT restored to upstream (comment added). Other code-reading-only trims re-checked:
  LibCrypt off (key 0 for SotN) and CD-DA report sender (only trigger already off) are fine for booting.
- CD-DA: CDDA_ON = false (from an early step, "SotN never plays CD audio") also drops CD-DA playback. Track 2 of
  SotN USA is 4:11 of audio, very likely "I Am the Wind" (ending credits). To restore if area allows.
- pk7 (memorymux fix, core picture by default, bars while Select is held): seed sweep running.
- New full boot simulation pocket/sim/boot (tb_boot.vhd, ram_model.vhd, run.sh): psx_pocket_core with the
  Pocket source set + vram_psram + PSRAM models + main RAM model (sdram.sv channel behaviour, from upstream's
  sdram_model3x) + SPU RAM model, real BIOS, no disc; PC range / frames / device counters every 1M clk1x,
  CD + GP1 write log, PPM frame dumps. ~7k clk1x cycles/s (5 ms in ~30 s). Runs: boot_fixed (current rtl) and
  boot_bug (RTL_OVERRIDE=memorymux.prewait_bug.vhd), 3,000 ms each.
- pk7s1 (seed 1) fits: 18,214 ALMs, all timing met (worst slack +0.038 ns), no critical warnings. SD_pk7/Cores/PSXPort.PSX/bitstream.rbf_r.

## Fourth hardware test (pk7s1, memorymux fix): unchanged
- Photo with Select held: same bars as pk6 (only "button held" now green). The PREWAIT bug was real but is not
  (the only) cause of the hang.
- Boot sim fixes: (1) stdout flushed per line (nvc buffers when redirected); (2) clocks must start high so that
  clk1x/clk2x/clk3x rising edges coincide as from the PLL - with clk1x rising on clk2x falling edges the core's
  clk2xIndex hand-offs fail and the reset sequence hung at the SPU RAM clear (savetype 14): a sim artefact.
  Debug probe (DEBUG_SS=n): pause/idle handshake, DDR reads, savestate type/count. The reset sequence clears SPU
  RAM, VRAM and RAM (~10M clk1x, ~25 min of simulation) before the CPU starts.
- Reports now also list the CPU's last 8 data accesses (R/W address @ PC).
- Reviewer agent (read-only) launched at the user's request to cross-check trims, glue vs PSX.sv, the BIOS
  boot path and the build reports.

## 2026-10-13 morning: boot sim works; prime suspect SDRAM 128-bit reads
- (Both I and the reviewer agent were paused for hours by the account usage limit overnight.)
- Boot sim (fixed clocks) completes the reset sequence (~200 ms: SPU RAM, VRAM, RAM clear), then the BIOS:
  POST F,E,1,2, kernel copy BFC10000->A0000500 (~236-265 ms), POST 3,4, kernel code in RAM (PC 000027A8, POST
  1,3,4,5,6,2), timers/I_MASK init, POST 5,6,7, shell memcpy(80030000, BFC18000, 67FF0) from ~290 ms to ~2.9 s
  (uncached byte copy), then the shell runs at 8005xxxx (3 s: still in an early delay loop, display off).
  Fixed and old-memorymux-bug runs identical. I/O trace (boot_trace.log): no GPU/CD/SIO access before POST 7.
- Hardware (no BIOS upper-half read, no BIOS fetch "now", RAM reads "now") therefore stops between the kernel
  copy and POST 7, i.e. at the first cached execution from RAM. VRAM/SPU-RAM/RAM write bars were explained by
  the core's own reset sequence clearing those memories.
- Reviewer agent (read-only) report: rtl/sdram.sv issues every ch1 READ with auto precharge (A10=1) and then,
  for 128-bit reads (cache line fill / DMA), three more READs to the same row while the bank auto-precharges -
  illegal per SDR spec; MiSTer's chips tolerate it, the Pocket's 1.8 V mobile SDRAM apparently not. Its sim with a
  model where only the first of the four READs returns data reproduces the hardware picture exactly (exception
  ~180 cycles after the first cached fill, wild execution in RAM, no POST 3). Single 32-bit reads (BIOS fetch,
  the read-back test) are unaffected. Also: two AUTO REFRESH one clock apart to the single chip (nCS tied), and
  WRITE+auto precharge -> next ACTIVE only 3 clocks (29.5 ns < tWR + tRP).
- sdram.sv fixes (verified by reading, no Verilog simulator here): ch1 128-bit reads without auto precharge,
  last READ (IDLE_4) with A10 and one extra idle clock; parameter SINGLE_CHIP (core_top: 1) -> STATE_RFSH is a
  NOP and waits one clock longer (tRFC ~79 ns); writes with auto precharge go to IDLE_3 (4 clocks to the next
  ACTIVE). Backup: sdram.before_timing.sv.
- New diagnostics (pk8/pk9): hex page while Select is held (pocket_diag.vhd rewritten; bars removed): rows 1-4
  PC samples, 5 last non-IRQ exception EPC, 6 its CAUSE, 7 exception count | IRQ count, 8 SR, 9 POST code,
  10 last SDRAM read address, 11 last I/O register access. cpu.vhd debug ports, psx_top debug_out (POST captured
  from EXP2 writes to 1F802041), psx_mister / psx_pocket_core debug_out, pocket_psx snapshots every 2^24 clk1x.
  pocket/sim/pocket_diag: every pixel of the text rows checked against the font; mutations (digit order,
  mirrored glyphs, Select inverted) caught. BIOS read-back + checksums removed from the loader (job done).
- pk8 = hex page only (baseline), pk9 = pk8 + sdram fixes.
- pk8 (hex page, 11 rows): no fit on seeds 1-5 (1857-1861 LABs needed). Page slimmed to 8 rows (PC x4, EPC,
  CAUSE (BD + code), POST | exceptions | interrupts, last SDRAM read), samples written straight into the
  snapshot; pocket_diag tb PASS. pk9 = that + sdram.sv fixes: seed 1 fits but clk3x setup -0.293 ns
  (memorymux ram_rnw/ram_ena (clk1x) -> SDRAM_A I/O output registers, existing upstream path, placement
  dependent); seed 2: 18,2xx ALMs, all corners met (worst +0.005 ns), no critical warnings ->
  SD_pk9/Cores/PSXPort.PSX/bitstream.rbf_r.
- boot_dbg sim confirms the debug outputs (PC, POST 02 after F,E,1,2, last I/O 1F802040) before hardware.

## Hardware test pk9 (SDRAM fix): BIOS boots! Menu appears, then freezes
- Boot sound plays, SCE intro, MAIN MENU / MEMORY CARD / CD PLAYER drawn (stray lines at top/bottom), no
  animation, buttons ignored. Hex page: PC 80050CD4 x3 / 80050BD0, last exception = syscall (normal), POST 02?,
  149 exceptions, 0x0B6E interrupts, last SDRAM read 0x8514.
- 80050C68.. is the libgpu command queue (64 entries, head 80079298 / tail 8007929C): the CPU waits for a free
  slot; 80051300 checks a 240-VSync timeout ("GPU timeout" -> ResetGraph(1), returns -1). So the GPU/DMA2 queue
  does not drain in the menu on hardware (intro works). StoreImage (GP0 C0, VRAM->CPU) exists at 80050968.
- Boot sim with shortcuts (FAST_SHELL: shell memcpy replaced by an instant preload, SPU-clear busy-wait 240->24,
  simulation only): intro runs (sound, DMA, GPU, interlace, display on at ~1.3 s). Very slow (~5 min per 30 ms).
- pk10 diagnostics: GPU (GPUSTAT), DMA (CH2 CHCR, state/channel/working MADR, DICR), IRQ (I_STAT/I_MASK) debug
  ports; POST | GPU resets (GP1 00h count) | interrupts; values in a dual-clock M10K (pocket_diag), digit RAM
  read one clock ahead; tb checks every pixel; mutations (no lookahead, nibble order) caught. GPU internal
  state row dropped (area). Fit attempts: pk10/pk10b/pk10c 1850-1859 LABs; pk10d seeds 2/1/3 fit with
  -0.034/-0.022/-0.301 ns; seed 4: 18,152 ALMs, +0.011 ns, no critical warnings -> SD_pk10.
- Debug values validated in sim during the intro: CHCR2 00000401, DICR 00840000, I_MASK 009, POST 07.
- libgpu details: drain routine 80050DAC (called from the enqueue when DMA2 idle, and from the DMA2-complete
  callback through the driver table at 8007920C) -> waits GPUSTAT bit 28, GP1(04000000), calls the queued
  function. Timeout (80051300, deadline = VSync counter 80079D9C + 240) calls ResetGraph(1) = CHCR2 401,
  GP1 04000000 / 02000000 / 01000000 -- NOT GP1(00); so pk10's "GPU resets" byte (GP1 00 count) only counts
  ResetGraph(0). Distinguish "GPU/DMA stuck, timeout every 4 s" (IRQ count advances) from "interrupts dead"
  (IRQ count frozen, VSync counter stuck -> timeout never fires) with two photos a few seconds apart.
- Shell main (80030000): POST 1F802041 writes 0 / 1 / 2 (and 5 on the disc path) via 80030788; intro =
  80040490 (calls 800404F0 animation loop). Sim shortcut SKIP_INTRO (ram_model: 80040490 = jr ra) added;
  run boot_skip (WORKDIR psx_pocket_work/boot_skip) started to reach the menu in sim.

## Hardware test pk10 (photos IMG_1912/1913, 5 s apart; identical except PC)
- PC 800513CC / 80051318 (libgpu queue-full wait loop + its timeout check), GPUSTAT 564E200D (idle, ready for
  cmd + DMA, 640x480i, display on), DMA2 CHCR 00000401 (not busy), DMA state 080F2224 (idle, ch 2, MADR
  0F2224), DICR 84840000 (ch2 IRQ flag + master flag set), I_STAT 009 / I_MASK 04D (VBLANK + DMA pending and
  enabled), POST 02, GP1(00) count 02, interrupt count 0x0B6E -- frozen, and exactly the same as pk9.
- => GPU and DMA are idle; interrupts are pending but no longer taken; the CPU spins in the queue-full wait
  whose drain needs the DMA2 IRQ and whose timeout needs the VSync IRQ => deadlock. Deterministic (IRQ #2926).
  Last non-IRQ exception (pk9) = syscall at 8005AA14 = ExitCriticalSection, so most likely the CPU is inside
  an interrupt handler (IEc = 0) when it hits the full queue (a callback enqueueing GPU work), which a fast GPU
  never lets happen; the Pocket GPU is slower (VRAM in async PSRAM; 640x480i display reads ~60 % of it).
- pk11 diagnostics: row 3 = CPU SR, row 5 = EPC of the last interrupt, row 6 = EPC of the last other
  exception, row 8 byte 2 = GP1(01) count (ResetGraph(1) / timeout) instead of GP1(00). Build pk11 started.
- pk11 seed 4: 18,110 ALMs, 295 M10K, worst slack +0.066 ns, no critical warnings -> SD_pk11 (not yet sent:
  user asked first to try SotN on pk10). Root cause found statically meanwhile: the menu's VBlank event handler
  8003D390 (OpenEvent(F2000003 RCnt3/VBlank, EvMdINTR, ...), runs in IRQ context) calls PutDrawEnv /
  PutDispEnv / DrawOTag (8004F434 / 8004F4EC / 8004F3E0) -> libgpu enqueue -> waits forever when the queue is
  full (drain needs the DMA2 IRQ, timeout needs the VSync IRQ). Queue fills because our GPU is several times
  slower than a PS1 (VRAM in async PSRAM).

## SotN runs on hardware (pk10)! Intro playable but slow motion most of the time
- User played through the intro on pk10 (BIOS -> SotN boot works, CD streaming works). Performance: "slow
  motion most of the time, occasionally playable speed". Expected: VRAM (async PSRAM) bandwidth.
- GTE ruled out (gte_small busy timing cycle-exact vs gte.vhd in sim/gte_small); GPU divider sharing only adds
  a round for polygon gradients (SotN is mostly sprites).
- pk12 = profiling build (rows: page flips | VBlanks per 0.5 s; VRAM busy; VRAM reads video out; VRAM reads GPU;
  GPU write pending; GPU has work; CPU stalled; PC; occupancy rows as bits 24:1 of 2^25-clk2x windows,
  0x1000000 = 100 %). Seed 4: 1851 LABs (1 over); seed 2 running. (A careless pkill of nvc sims also killed
  the seed loop's wrapper; the loop itself survived. Kill by PID only.)
- New VRAM controller pocket/src/fpga/core/vram_psram_sync.vhd (not yet in the build; vram_psram.vhd is the old
  one until pk12 is done): AS1C4M16PL datasheet (endrich.com PDF, text via PDFKit) -> BCR 0x5D1F via CRE
  (sync burst, fixed latency code 3 = first data on the 4th PSRAM clock after the address clock, <= 52 MHz on all
  speed grades), PSRAM clock = clk2x/2 from a register, commands on its falling edges, data taken on the clk
  edge that raises the next PSRAM clock (margin: T_OUT + T_IN <= ~20.5 ns), reads split at 32-word boundaries
  (no row crossing, CE# low << tCEM), async writes kept (mixed mode, clock still), CE# high >= 2 clk between
  accesses (refresh opportunity > 15 ns).
- psram_model.vhd extended (BCR via CRE, fixed-latency sync bursts with tACLK 9 / tKOH 2, setup/hold, clock
  period, row crossing, tCEM, CE# high >= 15 ns, no clock during async writes); tb_vram_psram with board delays
  + aux traffic. Old controller: 284 ns per read word, new: 84 ns (3.4x), writes 133 -> 106 ns (accept latency).
  Passes delays 0/0 .. 8/10 ns, seeds 2/7/9, row 32; fails as expected at 12/10 ns; row 16 flagged; mutations
  caught: first data step 7 / 11, BCR latency code 2, CE# gap 1 clk (refresh opportunity).
- CAUTION for the user: once a sync build has run, the PSRAM stays in sync mode until power-off; async-only
  builds (pk10-12) and other cores' async PSRAM reads may misbehave until the Pocket is powered off.
- boot_sync (menu sim with the new controller) started next to boot_skip (old controller) for comparison.
- vram_psram_sync2.vhd: sync reads + synchronous burst WRITES (fixed latency: data taken on PSRAM edges 5, 6, ...
  after the address edge, like reads; byte lanes per word), one-word core request slot so the next write can be
  taken while a burst runs; a write to the next 64-bit word in the same 32-word block continues the burst (4 clk
  per word); aux writes = one-word burst ending after the first PSRAM word. Model extended (burst writes with
  setup/hold, row check; an "async" write with a clock edge while WE# low is a burst write). tb: SEQ_PCT write
  runs. With 60 % runs: async 196 ns/write 285 ns/read word; sync 146 / 84; sync2 93 / 84 (76 ns/write with 95 %
  runs). sync2 passes delays 0/0 .. 8/10, seeds 4/11, row 32; mutations caught: half order, continuation step,
  row split (model), WE# held low.
- Builds in parallel (Docker 7.7 GB, ~2 GB each): pk12 (old controller, profiling), pk13 (= pk12 + sync reads,
  pbuild2.sh OVERRIDE), pk14 (= pk12 + sync2). Full-system sims boot_sync (sync) and boot_sync2 (sync2) running.
- Fit trouble: pk12 seeds 1-6: 1849-1853 LABs, seed 5 fit with hold -0.100 (fast corner, 1 path); pk13 seeds
  1/2 no fit, 3 fit with clk3x setup -0.629; pk14 seeds 1-5 no fit (1850-1855). Profiler too big (~130 ALMs).
  Slimmed: 5 counters sampled every 16th clk2x (21 bits), no wrq / VBlank rows, flips 8 bits; rows now:
  flips | vbusy | vid | rd | gbusy | cstall | 0 | PC, occupancy shown x8 (0x1000000 = 100 %). Fat version saved
  as psx_top.pk12_fat.vhd. Builds pk12b / pk13b / pk14b (seedsx.sh, seeds 1-8) running in parallel.
- Full-system sims: boot_skip (async), boot_sync, boot_sync2 all pass the reset VRAM clear (131072 words) with
  no model errors and reach the shell.
- pk12b (old controller + slim profiler) never fits (1857-1862 LABs, seeds 1-8) - dropped. Staged test builds:
  SD_pk13 = pk13b seed 3 (sync reads; 18,231 ALMs; slow-85C setup -0.069 ns on the clk1x->clk3x SDRAM request
  path cpuPaused/ram_rnw/ram_ena -> SDRAM_A, the long-known marginal path), SD_pk14 = pk14b seed 2 (sync reads +
  burst writes; 18,211 ALMs; only fast-0C hold -0.001 ns in clk_74a). Seeds continue for clean versions.
  Robust fix idea for the SDRAM path: register ch1/ch2 requests + address/data in clk3x (+9.8 ns per access);
  sdram.sv has no chip-level testbench yet.
- SD_pk13 replaced by pk13b seed 4 (clean: +0.011 ns, 0 critical warnings).
- Menu sims (boot_skip / boot_sync / boot_sync2, restarted 18:08-18:40) were invalid: tb_boot's FAST_SHELL
  preload trigger read the PC from debug_out(31:0), which became the profiler's flips row -> shell never loaded
  -> CPU ran into empty RAM -> BIOS unresolved-exception loop (A0:40, BFC0D8E0) at ~0.3 s. Testbench bug only
  (hardware unaffected). Fixed (PC = debug_out(255:224)), all three restarted ~20:30 with the slim profiler.
  Useful bit from the invalid runs: VRAM busy during the reset VRAM clear window: async 7.4 %, sync 5.9 %,
  sync2 1.4 % (burst writes ~5x faster), profiler counters plausible.

## Hardware: pk14 "ran pretty flawlessly" (one brief slowdown), pk13 about the same - SotN playable!
- User noticed the game did not save from the previous play-through. Saves never verified on hardware
  (pocket_memcard: APF nonvolatile slot 2 at 0x20000000, card in PSRAM region 1, written back by APF on core
  exit through bridge reads). Asked: did they save at a save room, how did they leave the core, is there a
  .sav under Saves/ on the SD card.
- pk14 hardware: BIOS no-disc menu now loads and works (no freeze) -> the menu deadlock was the slow GPU.
- pk14 profile photos (IMG_1917/1918, SotN gameplay): flips 0x1E = 30 per 0.5 s = 60 fps; VRAM busy 42 % / 31 %
  (video 6 %, GPU reads 18 % / 13 %), GPU has work 55 % / 40 %, CPU stalled 58 % / 59 %. => GPU has ~2x headroom;
  performance done (no need for 67.7 MHz PSRAM). User: saving does NOT work - no .sav on the SD card after
  quitting the core through the menu.

## Saves: two bugs found (pk15)
1. APF data slot size table: APF saves a nonvolatile slot with the size in the core's datatable (entry = data
   slot INDEX in data.json; agg23's SNES writes its save size continuously, "Data slot index 1, not id 1").
   We never wrote it -> without a save at start, size 0 -> no .sav written. Fix (pocket_psx): after pocket_cd's
   table scan (cd_ready = 1) port a writes word 5 (index 2 = memory card) = 0x20000 every clock.
2. pocket_memcard test (tb_pocket_memcard, now with the PSRAM clock connected and VRAM_PSRAM override) FAILED with
   both sync controllers: apf_errors 772 (sync2) / 1029 (sync): APF read-back got the previous word because aux
   accesses waited for a whole 32-word read part (~1.1 us > APF's ~0.9 us per word). Fix in sync2: a core read
   part ends after the current 64-bit word when an aux request waits (remaining/rAddr rolled back), write bursts
   do not continue while aux waits, card_write pulses when a card word is actually written (not when queued -
   otherwise a prefetch could be served before the queued card write and keep a stale word). memcard tests pass
   (seeds 1, 7), vram tb passes (87 ns/read word); mutation: no early termination -> 772 errors again.
- vram_psram.vhd is now the sync2 controller (old async: vram_psram.before_sync.vhd, pk13 variant:
  vram_psram_sync_pk13.vhd in the work folder). pk15 = this + save size fix + slim profiler; seeds a:1,3,5,7 /
  b:2,4,6,8 running.
- pk15 (sync2+aux fix+save size+slim profiler): seeds 1-4,6,8 no fit (1849-1854 LABs). Profiler now behind constant POCKET_PROFILE (false) in psx_top (rows 1-7 zero, PC row kept). pk16 = pk15 without profiler: seeds a 1,3,5,7 / b 2,4,6,8 (b starts after pk15 seed 5).
- pk16a seed 7: 18,188 ALMs, +0.014 ns, 0 critical warnings -> SD_pk16 (sync2 + aux fix + save size, profiler off). Other pk16 seeds: -0.10..-0.94 (clk3x SDRAM path).

## pk16 on hardware: memory card SAVE WORKS (user: 'ok that worked' after the save test: save in castle, quit, .sav on SD, reload).

## Next phase (2026-10-14): user wants no commit yet; remove debugging; asks about bringing back FMVs (MDEC).
- pocket_psx: DIAG_PAGE constant (false): pocket_diag + snapshot logic in an if-generate, picture passed through
  with one clkpix register. Quartus elaboration OK. pk17 = release build (no diag, no profiler) seeds running.
- MDEC area (pk16 fit): mdec_black stub 282 ALMs / 4 M10K / 0 DSP; full MDEC (phase 1): ~1,177 ALMs, 9 DSP.
  Free in pk16: 292 ALMs (LAB-limited), 4 DSP, 13 M10K. DSP users: gpu_poly 29, spu 12, gte 9, cd_top 5 (xa 2),
  cpu 3, pixelpipeline 3, pocket_cd 1. Debug removal frees ~150-200 ALMs. pk17mdec = MAPONLY with full MDEC to
  measure the delta.
- Menu sims (FAST_SHELL + SKIP_INTRO, fixed preload) with async / sync / sync2 all reached 3.5 s with the display still off and no DMA (identical in all three): the SKIP_INTRO shortcut (80040490 = jr ra) breaks the shell's menu setup in sim. Stopped; hardware shows the menu works with pk14. SKIP_INTRO is not trustworthy.
- Full MDEC synthesis (pk17mdec, MAPONLY, no debug): 71 DSP (> 66), ALM estimate 17,991 (pk16: 17,791 -> fit 18,188).
  MDEC: 1,061 ALUTs / 9 DSP / 57,280 bits vs stub 584 / 0 / 29,696.
- gpu_poly: per-line start values (base + dx*x + dy*y for R,G,B,U,V) now one channel per clock with 2 shared
  multipliers in 5 clocks after PREPARELINE (lineStep); PROCPIXELS waits for lineStep = 5. sim/gpu_div3 (vs HEAD
  original, 300 random commands) PASS seeds 1/2/3 (631-686k pixels identical); mutation "no wait" caught
  (282,605 mismatches); mutation "always add dx*x" not exercised (no polygons starting at x < 0 in the harness).
- pk18map (full MDEC + shared multipliers, no debug): 55 DSP (gpu_poly 29 -> 13), ALM estimate 17,949. pk18 full
  build seeds 1-8 started (OVERRIDE mdec.vhd -> mdec_black.vhd slot). pk17 seed 1 = old gpu_poly, later seeds
  include the shared multipliers.
- pk18 (full MDEC, unpipelined line mults): seeds 1-8 no fit (1854-1862 LABs). pk17 seeds 3/5 (with the
  unpipelined line mults) failed timing by -4.2/-3.5 ns: mux + 32x14 multiply + 2 adds in one clk2x cycle.
- gpu_poly line mults now a 3-stage pipeline (operands lpDx/lpDy, products lpX/lpY, sum), lineStep 0..7,
  PROCPIXELS waits for 7. gpu_div3 equivalence PASS seeds 1/2/3; mutation (wait >= 6) caught (173,595).
- pbuild2.sh: EXTRA_QSF env appended to the qsf. pk18b (default) and pk18c (FITTER_EFFORT STANDARD FIT +
  ALM_REGISTER_PACKING_EFFORT HIGH) seeds 1-4 running.
- pk18b seeds 1-4: 1858-1862 LABs; pk18c seeds 1-4: 1856-1861 LABs. No fit. pk18bs1: 18,360 ALMs, M10K 308/308,
  44 memory LABs (323.5 memory ALMs: gte 120, pixelpipeline 56, dma 56, memorymux 33.5, cpu 32, spu 16, pocket_cd 10).
- FOUND: cpu datacache (16384x32 = 64 M10K) is dead on Pocket (TURBO_CACHE = '0') but was kept because
  dcache_read_data feeds the spad_cache_dataread mux. cpu.vhd: mux selects scratchpad when TURBO_CACHE = '0'
  (identical behaviour; the data was only used on scratchpad hits). Frees 64 M10K.
- With free M10K: RamMLAB -> RamM10Kn for dma (madr/bcr x2), spu irvCoef/irvAddr, memorymux write fifo
  (SyncFifoFallThroughMLAB generic M10K, memorymux sets true). Backups *.before_m10kn.vhd, cpu.before_dcache.vhd.
- sim/fifo_m10k (new): fifo M10K vs MLAB, 200k cycles seeds 1-3 PASS; mutation (RamM10Kn on rising edge) FAIL
  36,585 errors. dma_equiv / spu_equiv vs HEAD running (run.sh now compiles RamM10Kn; ALTERA_MF_DIR = altera_lib).
- tools/m10kn_clocks.tcl (quartus_sta -t): launch clocks of all paths into RamM10Kn ports. pk16as7: only
  general[0] (clk1x) for cpu itagram + spu RAMs, as required.
- pk19 = full MDEC + all of the above: seeds 1,3,5,7 / 2,4,6,8 running.
- Sims for pk19 changes: fifo_m10k PASS seeds 1-3 (+ mutation caught). dma_equiv: M10K dma vs MLAB dma
  (REFFILE=dma.before_m10kn.vhd, aggressive mode) PASS seeds 1,2 (300k); vs HEAD REALISTIC PASS seeds 1-3 (1M).
  (vs HEAD non-realistic seed 2 mismatches = the known CPU-write-during-write-back case, same with the MLAB version.)
  spu_equiv vs HEAD PASS seeds 1,2 (2M cycles, reverb on, 0 mismatches).
- pk19 seed 2: FITS (18,179 ALMs, 1,847/1,848 LABs, 55 DSP) but clk1x setup -2.316 (TNS -4.6) and video[1] hold
  -0.622. tools/worst_paths.tcl (per-corner worst paths) running on it.
- pk19 seed 1 also fits (-2.215). Failing paths (tools/worst_paths.tcl): cpu decodeJumpTarget / lateReadTarget ->
  memorymux write fifo RamM10Kn (half cycle): writeFifo_Wr used mem_in_request, which contains the fetch logic.
  m10kn_clocks.tcl on pk19s2: all paths into every RamM10Kn launch from clk1x only (good).
- Fix: cpu output mem_writeRequest = mem4_request and not mem4_rnw and (memoryMuxBusy = '0' or mem_done = '1')
  (= mem_request and not mem_rnw, since mem_rnw = '0' needs mem4_request = '1'); memorymux input
  mem_in_writeRequest drives writeFifo_Wr; psx_top wires it. Sim-only assertion in memorymux checks equality each
  clock (boot sim with RTL_OVERRIDE keeping it). Backups *.before_wrreq.vhd.
- Video hold -0.622 (pocket_video v_rgb clkvid -> video_rgb clkpix): harmless (changes only with the v_pix toggle;
  that clkpix edge is a skip pixel). core_constraints.sdc: set_false_path v_rgb -> video_rgb. Re-ran quartus_sta on
  pk19s2 with it: video hold +0.45/+0.43/+0.18/+0.17 (clean).
- pk19 seeds stopped; pk20 (= pk19 + write-request fix, old SDC) seeds 1,3,5,7 / 2,4,6,8 running.
- pk20 (MDEC + write-request fix): every seed fits (18,220 ALMs). clk1x half-cycle path fixed. Results:
  s1 -0.130 / s3 -0.141 (clk3x setup: cpuPaused / memorymux ram_ena -> sdram SDRAM_A~reg0 DDIO cell: ~5 ns of
  IDLE priority/address mux logic + 3.6 ns route to the pin register, 9.8 ns budget), s2 hold -0.344, s4 -0.25,
  s5 setup clean, hold -0.045 fast-0C (sdram ch1_dout clk3x -> dma_data clk1x; pixelpipeline stage3_cg ->
  stage4_cg), s6 setup clean, hold -0.089 clk3x.
- Boot sim (400 ms, RTL_OVERRIDE memorymux with the assertion kept, severity failure): no mismatch between
  mem_in_writeRequest and mem_in_request and not mem_in_rnw through BIOS start + kernel copy.
- pk20 seed 7: CLEAN at all corners (worst +0.016), 18,152 ALMs, 251/308 M10K, 55 DSP, 0 critical warnings,
  includes the v_rgb false path. m10kn_clocks.tcl: every RamM10Kn input launches from clk1x only, worst +0.741.
  -> SD_pk20/Cores/PSXPort.PSX/bitstream.rbf_r (sha256 2bd38075cae6...). Full MDEC (FMVs), no diag page, no
  profiler. pk20 seed 8 died out of memory (quartus_sta ran next to two fits); pk20f (STANDARD FIT) stopped.
- Repo psx_pocket.qip now lists rtl/mdec.vhd (was mdec_black.vhd + OVERRIDE); elaboration OK.
- Optional margin for later (not in pk20): gte_small imatram/itrram -> RamM10Kn (work folder
  gte_small.m10kn.vhd, would free ~15 LABs); sim/gte_small vs original gte PASS seed 1 (20,000 tests).
- pk20 on hardware (user): works; loaded an existing save, saved and loaded again OK.

## 2026-10-14: project moved to its own folder (sotn)
- User doesn't want commits in the PSX_MiSTer clone. Copied to /Users/tony/sideProjects/other_people/sotn:
  rtl/ (all 80 files + pll dirs), pocket/, the 13 Pocket sims (sim/), sim/altera_lib (gitignored), notes (docs/),
  LICENSE, BIOS + game (gitignored). Upstream originals that sims took from git (dma, spu, gpu, gpu_poly,
  gpu_line @ cd17b5a) are in ref/upstream/rtl; dma_equiv / spu_equiv / gpu_div3 / gpu_vram read them by default.
- tools/: build.sh (was pbuild2.sh, repo-relative, builds/ in the repo), seeds.sh (seed loop with the
  all-corner check), sta.sh + worst_paths.tcl / m10kn_clocks.tcl / path_detail.tcl, report.sh.
- README.md (top level) written; pocket/README.md and dist info.txt no longer say FMVs are black.
- git init, nothing committed (user commits). PSX_MiSTer and psx_pocket_work left as they were; this log
  continues here (docs/NIGHT_LOG.md).
- Verification of the new tree: ELAB OK; SEED=7 tools/build.sh pk20check = same fit and timing as pk20s7
  (18,152 ALMs, 251 M10K, 55 DSP, worst +0.016, identical slack tables and per-entity fit, 0 critical warnings;
  assembler checksum 0x07D87312 vs 0x07D87391: only build_id.mif (date stamp) differs). Sims from sotn:
  fifo_m10k, ram_m10kn, dma_equiv (REALISTIC, ref/upstream), spu_equiv (ref/upstream), gpu_div3 poly PASS;
  boot sim same progress as before. package.py into a scratch SDROOT: same layout as the user's card.
- README: Licences section (GPL core, Analogue APF licence, agg23 MIT files) and Roadmap (L2/R2 on the handheld:
  input.json allows only the 8 Pocket buttons, core already passes L2/R2; CD-DA; SDRAM path for easier rebuilds).
- README roadmap item 1 rewritten: L2/R2 via Core Settings (interact.json, like MIRLO64's Z/L/R pickers); user only saw R2 missing from the Controls list (input.json limit), Dock R2 in-game untested. No build for now (user's choice).
- tools/release.sh + package.py --zip: core-only zip (shareable, LICENSE.txt in the core folder) or _personal zip with BIOS/game; releases/ gitignored. Tested with pk20check: zips intact, bitstream and JSONs identical to the sources.
- release zip now has the full SD layout minus copyrighted files: pocket/dist gained Assets/psx/PSXPort.PSX/{BIOS (no disc).json, Castlevania - Symphony of the Night.json} (file names as on the user's card, without (USA)); package.py copies all of dist and adds the empty folders Assets/psx/common and the game folder; tools/release.sh with no argument uses the newest build. Checked: unzip + BIOS + game .bins = the _personal zip, identical.

## 2026-10-14: roadmap item 3, SDRAM request path (clk1x -> clk3x -> SDRAM_A I/O registers)
- New test sim/sdram (Verilator 5 in the mirlo-dev image): rtl/sdram.sv vs ref/pk20/rtl/sdram.sv, each with a
  behavioural SDRAM chip (command timing checks: tRCD tRP tRAS tRC tRRD tWR tRFC tMRD, auto precharge, bus
  contention, refresh rate) and the same random traffic as the Pocket core drives it (memorymux single / cache-line
  reads, byte-enable writes, pipelined DMA reads like dma.vhd, SPU ch3, DMA write fifo, refreshForce); every read
  checked against a reference memory, chip memory compared at the end, latency histograms; LOCKSTEP compares all
  controller outputs of both on every clock. prep.py splits SDRAM_DQ for Verilator.
- Findings in the pk20 controller (pre-existing, same upstream): (1) AUTO REFRESH from STATE_IDLE_1 can come one
  clock short of tWR + tRP after a WRITE with auto precharge (counted as a warning, ~65 per 4 ms of heavy
  traffic); (2) a cache line's last cache_wr can carry the next request's cache_addr when that request is accepted
  exactly 12/14 clk3x after the line (only if the core asks again 1 clk1x after ready; GAP_MIN 0/1).
- Variant 1, request buffering (archived as psx_pocket_work/sdram.rqbuf_variant.sv): ch1/ch2 registered on the
  clk3xIndex edge, started one clk3x later, early ready / dma_done at bit 7 in phase 2 ({dq_reg, ch1_dout[15:0]}).
  Correct (0 errors, avoids race 2), but latency mixed vs pk20 (4 ms seed 1, clk1x means: read 3.82/4.00,
  DMA 4.97/5.24, cache line 4.87/4.72, write 1.81/1.73, SPU write 4.77/4.51): transactions end one clk3x later.
  Not used.
- Variant 2 (rtl/sdram.sv now): same behaviour, restructured. ch1/ch2 no longer set SDRAM_A / SDRAM_BA / command /
  chip in the STATE_IDLE priority chain; ch3 sets them at the top of STATE_IDLE without looking at ch1/ch2, and
  one assignment after the case overrides them for a ch1/ch2 start (state == IDLE, no refresh, fifo empty,
  ch1_req|ch1_rq|ch2_req|ch2_rq). The late request reaches the I/O registers through the last multiplexer only.
  sim/sdram LOCKSTEP 4 ms seed 1: 0 clocks with a difference, identical latency tables. Battery (4 seeds x 20 ms
  gap 2, gap 1 and 0, two mutations) and builds sdA_s1 / sdA_s3 (pk20 seeds 1 and 3 missed by 0.13-0.14 ns) running.
- sim/sdram fixes: the DMA fifo producer did nothing at first (Verilator 5.020 dropped the always block's updates
  through a function with an inout argument; pure function now) - the first lockstep results had no fifo traffic.
  Coverage counters added (idle clocks where ch1/ch2 decides against the fifo / ch3 / refresh). Fifo writes now
  stay in the 2 MByte main RAM like the real DMA (the merge compares address bits [20:10] only).
- FOUND (pre-existing, upstream logic): RW2 merges the next DMA fifo word into the open row also at the end of a
  ch2 (CPU) write (ch = 1 for both), comparing against lastbank = the row of the last FIFO write: a fifo word
  arriving during a CPU write to another row went into the CPU's row (pk20 in the test: 556 / 44 errors on seeds
  4 / 1). Probably never on hardware (the CPU is paused while the DMA fills the fifo). Fix: saved_fifo (set by a
  fifo start, cleared by ch1/ch2/ch3 starts) gates the merge. ref/pk20/rtl/sdram_fifofix.sv = pk20 + only this
  fix, the default lockstep reference of sim/sdram/run.sh.
- Battery (rtl/sdram.sv = restructure + fifo fix vs pk20 + fifo fix): gap 2 seeds 1-4 x 20 ms PASS, lockstep 0;
  gap 1 / 0: identical in both (only the known cache-line race); mutations caught: no ch1_rq/ch2_rq in the
  override (127,961 clocks differ), no dmafifo priority (7,384), no fifo fix (556 errors); pk20 original shows
  the bug (556 errors).
- Builds of the restructure (without the fifo fix, which is off the critical path): sdA_s1: clk3x setup +0.182
  (pk20 seed 1: -0.130), worst clk3x path now refresh_count -> SDRAM_A (the 14-bit refresh compare); clk1x slow-0C
  setup -0.418 on spu RamM10Kn irvAddr -> ram_Adr (half-cycle path of the pk19 MLAB->M10K move, placement
  dependent: passed in pk20s7); fast-corner hold -0.025. sdA_s3: all setup met (pk20 seed 3: -0.141), only hold
  -0.074 / -0.055 at fast corners.
- refresh_due: registered (refresh_count > cycles_per_refresh) computed from the next value (rc_next, blocking
  temp for every refresh_count assignment); used in STATE_IDLE / IDLE_1 and the override. sim/sdram lockstep
  seeds 1, 4 (gap 2), 6 (gap 0): 0 differences; mutation "computed from refresh_count" (one clock late) caught
  (354,292 clocks differ).
- sdB = final controller (restructure + fifo fix + refresh_due): seeds 1-4 building.
- sdB (restructure + fifo fix + refresh_due) seeds 1-4: s1 +0.015, s2 +0.024, s4 +0.027 (all corners clean),
  s3 -0.013 (fast-0C hold only); setup >= 0.07 everywhere, the spu irvAddr half-cycle path did not show up. (pk20
  controller: 1 clean seed of 8.) sdB_s4: 18,223 ALMs, 1,847 LABs, 251 M10K, 0 critical warnings, RamM10Kn inputs
  from clk1x only (+1.478). -> releases/PSXPort.PSX_0.1.0_sdB_s4.zip, for the hardware test.
