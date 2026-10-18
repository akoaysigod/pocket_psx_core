# GPU area: where the ALMs go and what can be saved

Date: 2026-10-17. Worktree `sotn-gpu` (branch `sotn-gpu`, from `main` at 0.1.4).
Fit numbers are from the 0.1.4 fit (build cc seed 1: 18,215 / 18,480 ALMs, 55 / 66 DSP, 254 / 308 M10K).
Synthesis numbers are MAPONLY builds of this worktree (`base_map`, `gpu20_map`).

**Short answer:** there is no large saving in the GPU. A rewrite would not make it much smaller. Quartus already
removes everything that synthesis can prove unused, and the rest is arithmetic that has to stay bit-exact.
Structural changes could give roughly 100-250 ALMs (0.5-1.5 % of the chip), each with its own test.

## 1. Where the GPU's ALMs are

The GPU is the largest block in the core: **4,792 ALMs (26 % of the chip)**, 16 DSP, 29 M10K.

| Part | ALMs | Registers | DSP | What it is |
| --- | ---: | ---: | ---: | --- |
| `gpu_poly` | 1,976 | 2,372 | 13 | triangle / quad setup and rasterizer |
| `gpu.vhd` itself | 545 | 659 | 0 | GP0/GP1 decode, VRAM arbiter, 64-bit pixel write combining |
| `gpu_pixelpipeline` | 514 | 698 | 3 | texture cache, CLUT, blending, dithering (incl. 101 tag MLAB, 52 valid bits) |
| `gpu_line` | 510 | 781 | 0 | lines and polylines |
| dividers (3) | 355 | 614 | 0 | 45 / 25-bit long division, 1 bit per clock, shared by poly and line |
| `gpu_rect` | 272 | 263 | 0 | rectangles / sprites |
| `gpu_videoout` | 272 | 330 | 0 | video timing and output |
| VRAM copy / fill / CPU transfers | 309 | 543 | 0 | `vram2vram`, `vram2cpu`, `cpu2vram`, `fillVram` |
| FIFOs | 36 | | | |

SotN uses almost all of the GPU (`docs/sotn_usage.md`): all polygon kinds, Gouraud lines, every blending mode, 4-,
8- and 15-bit textures, and dithering. Only polylines, 1x1 / 8x8 sprites and flat lines are unused.

## 2. What synthesis already removes (base_map "Registers Removed During Synthesis")

- Unused features: texture filter, reproducible-timing counters and their multiplier (`drawTiming` /
  `targetTiming`), 480p hack, fps counter, the `render24` second line RAM and second output FIFO, timeouts.
- Unused top bits, including registers that only feed themselves: bits 20..31 of `base_*`, `work_*`, the line
  start products and the gradient product; bit 44 of every edge walker (`xStart`, `xEnd`, both steps,
  `boundCoord*`, `vo/vp_diff_base`); constant bits of `baseCoord`.
- Duplicate registers merged: the sign-extension bits of `divStash`, `baseCoord`.

So "narrow the widths" gains are mostly taken already.

## 3. Tried: 20-bit colour and texture interpolators in `gpu_poly` (not adopted)

Idea: only bits 19..4 of the R, G, B, U, V interpolators (`work_*`) are used, and everything on the way there is
`+` and `*`, so 20-bit registers give identical pixels (arithmetic mod 2^20). Change: `dx*` / `dy*` / `base_*` /
`work_*` 32 -> 20 bits, line start operands 32 -> 20 bits, `mul32u` (32 x 32) -> 20 x 13 signed.

Equivalence (`sim/gpu_div3`, `gpu_poly` vs upstream `ref/upstream/rtl/gpu_poly.vhd`, ordered streams of pixels
incl. colour, U/V and sub-texel bits, VRAM reads, palette, draw mode, done):
- seeds 1-15, 300 polygons each: **PASS, 9,580,356 pixels identical, 0 mismatches**
- mutation (bit 19 of every gradient cleared): **FAIL, 303,717 mismatches** (seed 1)
- at 1,000 commands per run the test reports mismatches for the **unchanged** `gpu_poly` too (seeds 2, 3): its
  queues allow at most 65,536 events of drift between reference and new, and the 6-divider reference gets that far
  ahead. Keep runs at 300 commands, as in `NIGHT_LOG.md`.

Synthesis (same tree, both with hCrop on):

| | base_map | gpu20_map | change |
| --- | ---: | ---: | ---: |
| ALMs needed (estimate, whole chip) | 18,001 | 17,974 | -27 |
| `gpu_poly` combinational ALUTs | 2,993 | 3,162 | +169 |
| `gpu_poly` registers | 2,271 | 2,127 | -144 |
| DSP blocks | 55 | 52 | -3 |

Quartus had already removed most of the top bits (section 2). The change only adds the top 12 bits of the ten
gradients (the 144 registers). The narrower multipliers map to plain 27x27 DSPs instead of the 18x18 modes with
built-in adders, and the logic in `gpu_poly` grows. Net: noise-level in ALMs, 3 DSPs saved. Not adopted; the change is kept as
`docs/gpu_poly_20bit.diff` (`git apply docs/gpu_poly_20bit.diff`), in case DSPs ever get short.

## 4. Remaining candidates (structural; estimates, not built)

The estimates in section 3 were too optimistic until measured, so treat these as upper bounds.

| # | Change | Est. ALMs | Risk | Notes |
| --- | --- | ---: | --- | --- |
| 1 | `gpu_line`: drop the receive FIFO and the second copy of each line (`rec_*` and `proc_*`) | 40-60 + 3 M10K | med | polylines must keep working for other games; the FIFO decouples receiving from drawing, so `CmdDone` timing changes |
| 2 | `gpu_poly` vertices: `rec_vertices` (4 x 64 bits) in an MLAB, read into `vt` over 3 clocks | 20-70 | med | +2 clocks per triangle setup; the flat-colour write to all 4 entries needs its own register |
| 3 | `gpu.vhd`: write the pixel combining registers into the output FIFO directly (drop `fifoOut_Din`, 85 flip-flops) | 25-40 | low-med | VRAM writes move one clock earlier; `sim/gpu_vram` compares per clock |
| 4 | `gpu_line` datapath shared with `gpu_poly` (they never run at the same time) | 100-200 | high | edge walkers and colour stepping are the same kind of adders; a merge of two state machines |
| 5 | Dividers: shift registers instead of the 46:1 dividend-bit mux and 46-way quotient-bit decoder | 30-60 | med | `gpu_poly` CALCBOUNDARY2 computes `vo_diff_base` / `vp_diff_base` from `baseStep` taken one clock before `done`, when quotient bit 0 still holds the previous division's value. Keeping that exact needs a 45-bit mux per divider, which eats most of the gain |

## 5. A full rewrite?

Not recommended. Most of the area is arithmetic that has to stay bit-exact with the real PlayStation: 45-bit edge
walkers with 32 fraction bits, three long dividers, and the gradient multipliers. A new design with the same results
needs the same arithmetic, so it would end up at about the same size. It would also lose the upstream behaviour that
many games have exercised, and the equivalence tests that compare against it.

## 6. If space is needed

1. Items 1 and 3 (small, contained, each testable against the current version).
2. Item 4 only if a feature needs a few hundred ALMs and the GPU is the place to take them from.
3. Outside the GPU, the next-largest blocks are GTE 2,523, SPU 2,284, CD 2,005 and CPU 1,968 ALMs.
