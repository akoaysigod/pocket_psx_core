# Phase 1 report: PSX_MiSTer on Analogue Pocket (SotN only)

## Fit result (5CEBA4F23C8, area-optimized, all I/O virtual)
Fitter: **does not fit.**
- Combinational nodes: 44,842 needed vs 36,960 in the device (+21%, before any routing headroom).
- M10K RAM blocks: more than 308 needed vs 308 available. By bits it is only 68% (2.14 Mbit), so the overflow comes from many small or odd-shaped RAMs.
- DSP: synthesis reports 98 blocks vs 66 in the device. The fitter stopped before reporting DSP; some may pack 2-per-block.
- For reference, MIRLO64 on the same chip: 17,806 / 18,480 ALMs (96%).

## Per-module (synthesis, combinational ALUTs / regs / RAM bits / DSP)
| Module | ALUT | Regs | RAM bits | DSP | SotN verdict |
|---|---|---|---|---|---|
| GPU total | 11,862 | 8,659 | 254K | 49 | Keep; nearly all features used. Rewrite candidate for area (poly 3.7K/30 DSP) |
| SPU | 6,876 | 3,940 | 603K | 13 | Keep (reverb used); drop noise/FM; rewrite candidate |
| GTE | 6,268 | 3,204 | 80 | 15 | 11/22 ops used; shared MACs, so ~0.5-1K saved by trimming; serialize to save more |
| CD (incl. XA) | 4,840 | 3,269 | 537K | 6 | XA needed, CD-DA not; candidate for a soft-CPU/firmware controller |
| CPU | 4,033 | 3,466 | 664K | 6 | Keep; RAM bits include the core's extra data cache, which could be shrunk |
| DMA | 2,580 | 1,307 | 5K | 0 | Keep (ch5 unused); oversized for what it does |
| joypad | 1,648 | 1,188 | 2K | 0 | Trim to 1 digital pad (~1K saved) |
| memorymux | 1,333 | 538 | 0 | 0 | Keep |
| MDEC | 1,177 | 863 | 59K | 9 | Small, so keep (FMV; dropping it risks hangs) |
| savestates + statemanager | 1,038 | 791 | 0 | 0 | **Drop** |
| timer, memctrl, irq, sio, exp2 | 815 | 888 | 0 | 0 | Keep |
| cheats | 186 | 186 | 4K | 0 | **Drop** |
| memcard x2 | 174 | 394 | 16K | 0 | Keep 1 |
| **Total** | **43,170** | **28,821** | **2.14M** | **98** | |

## Arithmetic
- Easy SotN-only cuts: savestates, cheats, joypad extras, second memcard, overlays/debug, unused GTE ops, CD-DA, SPU noise/FM: about **3.5-4.5K ALUTs**.
- Pocket additions: APF bridge, SDRAM/PSRAM controllers for VRAM and SPU RAM, video interface: about **+1-2K**.
- To fit with routing headroom (~90% = ~33K comb nodes) we need roughly **-12K** from 44.8K. Easy cuts give about -3K net, which leaves **~9K ALUTs that would have to come from redesigning big blocks** (GPU, SPU, GTE, CD), plus DSP and M10K reductions.

## Memory (DDR3 replacement)
SotN's GPU load is light: about 16K 16x16 sprites/s plus polygons. At 60 fps that is single-digit MB/s of VRAM writes plus 7.4 MB/s scanout at 256x240. Moving VRAM into Pocket SDRAM or PSRAM looks feasible for this game. **Memory bandwidth is not the blocker; logic area is.**

## Verdict
- **No-go** for porting or trimming the existing core: it is about 20-35% too big even after every SotN-specific cut.
- **Conditional go** for a Pocket-specific redesign that reuses CPU, DMA, timers and MDEC, and rewrites the GPU rasterizer, SPU, GTE and CD controller for area: time-multiplexed datapaths, fewer multipliers, and possibly the CD controller as firmware on a small soft CPU (the MIRLO64 approach). That is a multi-month project with hardware testing on the Pocket for every step.
