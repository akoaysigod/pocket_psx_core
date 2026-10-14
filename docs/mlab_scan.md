# MLAB / register-bank scan: SPU, DMA, GPU, CD, CPU, memorymux, joypad, timer

Date: 2026-10-12. Branch `pocket-sotn`, working tree as of this scan (GTE skipped).
This is analysis only. Nothing in the repo was edited, and Quartus was not run.

## 0. Assumptions and how the estimates were made

* Cyclone V ALM: one 6-LUT, or two smaller LUTs that share inputs, plus 4 FFs.
  Arrays made only of FFs usually pack at 2 to 4 FFs per ALM. I give a range: FFs/4 (low) to FFs/2 (high).
* One 4:1 mux uses one 6-LUT, so roughly one ALM. An N:1 mux costs about (N-1)/3 ALMs per bit.
  For a variable-index read this is usually bigger than the FFs themselves.
* MLAB: 10 ALMs hold 32 words x 20 bits. One MLAB gives **one** read port. Each extra read port needs another copy.
  Cost per copy is `10 * ceil(W/20) * ceil(D/32)` ALMs. A deeper array also needs an output mux across the 32-deep blocks.
  For shallow arrays (D <= 8) with several read ports, MLAB saves nothing. Several candidates below fail for that reason.
* The repo already has `mem.RamMLAB` (rtl/RamMLAB.vhd). It is `altdpram`, `ram_block_type=MLAB`, with an
  **unregistered read address and output (asynchronous read)** and a write port registered on `inclock`.
  - If `wren/data/wraddress` are driven **combinationally** from the same condition that used to assign
    `arr(i) <= x` in the clocked process, the write commits on the same edge. The data shows on `q` in the next
    cycle, exactly as with the FF array. Read latency is zero. **So these conversions add no cycles.**
  - The existing SPU code drives these ports from *registered* signals. That adds one cycle of write latency,
    which is acceptable there but should not be copied blindly.
  - The sim model (sim/system/src/mem/RamMLAB.vhd) behaves exactly like a FF array with combinational read,
    so equivalence sims with nvc will be meaningful.
  - Mixed-port read-during-write is set to `CONSTRAINED_DONT_CARE`. In practice an asynchronous read during the
    write cycle shows the old data until the edge, which matches FF behaviour. That is not formally guaranteed,
    so check it in sim where the same address can be read and written in one cycle.
  - MLABs cannot be reset. Do not rely on their power-up contents. Every conversion needs an explicit
    clear sequence on reset. The reset sequence in `savestates_reset.vhd` lasts thousands of cycles, so
    7 to 256 clear cycles are hidden.
* **Strongly recommended first step (no new build needed, only the existing report of the last fit).**
  In `*.map.rpt` / `*.syn.rpt`, grep for `uninferred` (Info 276004 "inappropriate RAM size" and
  276007 "asynchronous read logic"). Also read "Resource Utilization by Entity", the
  "Dedicated Logic Registers" column. That shows which arrays below are *really* in FFs today. In particular,
  check `XaRingBufferL/R` (item 1), which Quartus may already have turned into RAM.
  Without a report I cannot tell, and the estimates below assume FFs.

## 1. Ranked summary

| # | Module | Array (file:line) | Bits | Proposed change | Est. ALM saving (conservative / likely) | Risk |
|---|--------|-------------------|------|-----------------|-------------------------------------|------|
| 1 | CD (cd_xa) | `XaRingBufferL/R` cd_xa.vhd:114-116 | 2x32x16 = 1,024 | One RamMLAB 32x32 (L and R packed). Write at `XaRing_pointer`, read at `XaRing_readpointer`, L/R chosen after the read | **500** / 550-850 (**0 if Quartus already inferred RAM; check the report**) | Low |
| 2 | SPU | Reverb register bank `REVERB_*` spu.vhd:179-213 | 32x16 = 512 (about 464 converted) | Two RamMLAB 32x16 (bus read port and engine read port). Keep mBASE, dAPF1/2 and vLOUT/vROUT in FFs | **250** / 300-450 | Low-Med |
| 3 | DMA | `dmaArray(i).D_MADR`, `D_BCR` dma.vhd:107-121 | 7x(24+32) = 392 | Two RamMLAB 8x56 (bus read and trigger read). One merged write port. CHCR and flags stay in FFs | **250** / 300-450 | Med |
| 4 | GPU | `tagValid` gpu_pixelpipeline.vhd:108 | 256x1 | Store the valid/epoch in the existing tag MLAB. Bulk clear becomes an epoch increment, plus a sweep on wrap and on reset | **150** / 200-300 | Med |
| 5 | CD | `sectorBufferSizes` cd_top.vhd:355 | 8x10 = 80 | 8 valid bits stay in FFs. The 10-bit sizes go to one RamMLAB | **30** / 40-60 | Low-Med |
| - | | **MLAB conversions total** | | | **about 1,180** / 1,400-2,100 | |
| 6 | all | Savestate read muxes (`ss_out` to `SS_DataRead`) | see section 4 | Free once `SS_rden` is constant '0' (true with rtl/savestates_reset.vhd) | **about 850** / up to 1,400 (**0 if the 21.6k fit already used savestates_reset.vhd**) | None |
| 7 | SPU, CPU | SS-only MLAB copies: `RamVoiceRecord` copy 1 (spu.vhd:659, i=1), `iregisterfileSS` (cpu.vhd:586) | - | Pruned automatically when `SS_rden`=0. Otherwise delete them | 60 + 20 (same caveat as #6) | None |
| C1 | SPU (spu_ram) | Voice-cache CAM `cache_voice_starts` spu_ram.vhd:88-89, 361-369 | 24x16 + 24 range compares | Not an MLAB candidate (it is a CAM). **If Pocket SPU RAM uses the SDRAM path, make `useSDRAM`/`SPUSDRAM` a constant '1'** and the whole cache, fetch FSM, 2 cache M10Ks and the out-FIFO disappear | 400-700 (conditional) | Low if the condition holds |
| C2 | GPU | Bilinear-filter tag copies 1-3 + `tagValid` read ports 1-3 (gpu_pixelpipeline.vhd:335-385) | 3x(256x10 MLAB) + 3x256:1 | Tie `textureFilter` to "00" at the top (probably already done with the MiSTer-only options) | about 500 (conditional, probably already banked) | None |

**Bottom line:** the MLAB-style restructures add up to roughly **1.2k ALMs (conservative), up to about 2k**.
The savestate read-mux removal is worth up to about another 0.85-1.4k, but **only if it is not already banked**:
`savestates_reset.vhd` never asserts `SS_rden`, so Quartus should prune all of it once that file is in the build.
Even in the best case this does not reach the 5k target. The rest has to come from logic reduction
(section 6), not storage.

---

## 2. Candidate details

### 2.1 CD-XA resampler ring buffers (top candidate)
* **Where:** cd_xa.vhd:114-116 (declaration). Writes at :452-453 (RESAMPLE_CLEAR, zeros) and :472-473
  (RESAMPLE_WRITERING, `ringInL/R`). Read at :488/:490 (RESAMPLE_READRING).
* **Size:** 2 arrays x 32 words x 16 bits = 1,024 bits.
* **Write:** one address (`XaRing_pointer`) in two mutually exclusive states. L and R are always written together.
  No bulk reset: after `reset`/`XA_reset` the FSM goes to RESAMPLE_CLEAR, which clears one word per cycle.
  This is already MLAB-friendly.
* **Read:** one variable index (`XaRing_readpointer`), one read per cycle, registered into `ringOut`
  with L or R chosen by `resampleDir`.
* **Block RAM today?** No explicit instance or attribute. Quartus *might* infer RAM (registered read), but the
  L/R mux in front of the output register often makes it fall back to logic. **Check the report for "uninferred".**
* **Change:** one `RamMLAB` with width 32 and widthad 5. `wraddress = XaRing_pointer`.
  `data = (ringInR & ringInL)`, or zeros in CLEAR. `wren = (state = CLEAR or state = WRITERING) and not reset`,
  driven combinationally. `rdaddress = XaRing_readpointer`.
  Then `ringOut <= q(15:0)` or `q(31:16)` inside READRING as today. Cost: 2 MLABs (20 ALMs),
  a 16-bit 2:1 mux and 32 data-gating LUTs, about 50 ALMs in total.
* **Saving:** FFs 256-512 ALMs, plus two 32:1 muxes x 16 bits (about 330), minus about 50.
  Conservative **500**, likely 550-850. **Zero if it is already RAM.**
* **Behaviour risk:** none. Same cycle of write and same cycle of read. Timing risk is negligible:
  clk1x, async MLAB read into a register.

### 2.2 SPU reverb register bank
* **Where:** spu.vhd:179-213 (decl). Reset :935-970. SS write :1044-1077 (dead with savestates_reset).
  Bus write :1171-1205. Bus read :1252-1287. Engine uses: soundmul2 in REVERB_PROCOUT, PROCIN and END
  (:2013-2234). L/R selects :2453-2463. `reverb_reqAddr` 14:1 mux :2470-2483. `apf1neg/apf2neg` :2467-2468.
  `reverb_calcAddr` uses mBASE :2490.
* **Size:** 32 regs at 0x1C0-0x1FE (dAPF1 .. vRIN) x 16 = 512 bits, plus vLOUT, vROUT and mBASE.
* **Write:** only from the CPU bus (one port), plus a bulk reset to 0 (and the SS write, which is dead).
* **Read:** (a) the CPU bus read case (variable address, registered); (b) the engine.
  Each engine state step needs **one** register, chosen by `(state, reverb_count, reverbRight)`.
  The exceptions are `mAPF1 - dAPF1` and `mAPF2 - dAPF2` (two registers in the same cycle) and mBASE (used continuously).
* **Block RAM today?** No. All of it is FFs.
* **Change:**
  - Put the 0x1C0-0x1FE window in a 32x16 RamMLAB, address `bus_addr(5 downto 1)`.
    Copy A has `rdaddress = bus_addr(5:1)` and feeds the bus read case.
    Copy B is the engine port, with `rdaddress = f(state, reverb_count, reverbRight)`.
    That function must keep the deliberate swap at :2460 (`dDIFF` takes the **R** register when `reverbRight='0'`).
  - Keep `REVERB_mBASE`, `REVERB_dAPF1/2` (a 32-bit FF shadow written together with the MLAB),
    `REVERB_vLOUT/vROUT` and `VOLUME_LEFT/RIGHT` in FFs.
  - `wren = ce and bus_write and bus_addr in 0x1C0..0x1FE`, driven combinationally (same edge as today).
  - Reset clear: extend the existing `ss_voice_loading` sweep (spu.vhd:837-866). It already runs on
    `SS_reset`, and `savestates_reset.vhd` raises that on every reset. Write 0 to addresses 0-31 of the new MLAB.
* **Saving:** FFs about 116-232. Bus-read mux loses about 31 inputs/bit x 16, about 165. soundmul2 mux about 50.
  reqAddr 14:1 plus 11 L/R 2:1 muxes, about 100-150. Minus about 55 new
  (2 MLABs, address generation, dAPF shadow). Conservative **250**, likely 300-450.
* **Risk:** behaviour unchanged if the write path is combinational and the clear is done.
  One more MLAB async-read delay in front of the reverb address adder chain. At 33.8 MHz this should be fine.
  Verify bit-exactly in sim against the original SPU (reverb on, writes during playback).

### 2.3 DMA channel MADR/BCR
* **Where:** dma.vhd:107-121 (record and array). Reset :285-296. SS :320-329 (dead).
  Bus read :376-389 (index `channel`). Bus write :393-415.
  Trigger read :519-531 (`triggerchannel`, into `dmaSettings`, `ram_Adr`, `directionNeg`).
  Write-back :882-883 and :895-896 (`activeChannel`).
* **Size:** MADR 7x24 + BCR 7x32 = 392 bits. (CHCR 7x32 is mostly constant-0 bits. Its live bits
  (0,1,8-10,16-18,20-22,24,28-30) are read **per channel in parallel** (bits 24 and 28 in the trigger loops
  :368-373 and :441-442), so CHCR stays in FFs. The same goes for request/pending/chopwait.)
* **Write:** two sources: bus write (index `channel`) and end-of-DMA write-back (index `activeChannel`),
  plus a bulk reset. Today, if both fire in one cycle they can hit **different** channels.
  An MLAB has one write port, so the two must be merged: write-back gets priority, as in the current code ordering.
  The CPU is paused while the DMA owns the bus, and `errorDMACPU` flags bus access while `dmaState /= OFF`,
  so a same-cycle collision should never happen. **Add a sim assertion to prove it.**
* **Read:** two variable-index ports (bus `channel`; `triggerchannel`). Both are combinational into registers.
* **Change:** two RamMLAB copies of 8 x 56 (3 MLABs each, 60 ALMs), one per read port.
  The write port is muxed between bus and write-back (56-bit 2:1 plus a 3-bit address).
  `wren` is combinational under `ce` (same edge as today). Clear: a 7-cycle sweep during reset
  (replaces the loop at :287-290).
* **Saving:** FFs about 100-200, per-bit data and enable logic about 100-200, two 7:1 x 56 read muxes about 260,
  minus about 110. Conservative **250**, likely 300-450.
* **Risk:** medium. The write-port merge (prove no collision), the reset sweep, and DMA timing is
  emulation-visible, but no cycles are added.

### 2.4 GPU texture-cache `tagValid`
* **Where:** gpu_pixelpipeline.vhd:108 (`std_logic_vector(0 to 255)`; it does not show up in an "array" grep).
  Set at :488 (same cycle and address as the `tag_wren_a` tag-MLAB write). Bulk clear at :541
  (`clearCacheBuffer`, from `clearCacheTexture`, only in IDLE when the pipeline is idle). Read at :385,
  one port per filter tap (`tag_addr(i)`).
* **Size:** 256 bits. Cost today: 256 FFs (64-128 ALMs), about 256 per-bit set/enable LUTs (about 128 ALMs),
  and **a 256:1 mux per read port** (about 85 ALMs each; 4 ports if the filter is not tied off).
* **Already MLAB:** the tags themselves (`itagram`, :338, 256x10 MLAB per tap).
* **Change:** widen the tag MLAB word from 10 bits to 14 (still 1 MLAB per 32 words, so no extra MLABs).
  The extra 4 bits are an *epoch*. An entry is valid iff `stored_epoch = cur_epoch`. A clear becomes
  `cur_epoch <= cur_epoch + 1` (1 cycle, same timing as today). On reset, and when the epoch would wrap
  (every 15 clears), run a 256-cycle (clk2x) sweep that writes an invalid epoch to every entry.
  This is a new stall, rare and only in IDLE.
* **Saving:** conservative **150**, likely 200-300 (more if the filter ports are live).
* **Risk:** medium. The wrap sweep adds rare GPU stalls of about 128 clk1x cycles. GPU drawing is paced by
  the emulated `drawTiming/targetTiming` counters, so short real-pipeline stalls should be hidden. Verify.

### 2.5 CD `sectorBufferSizes`
* **Where:** cd_top.vhd:355. Reads: `writeSectorPointer+4` (:1916), `writeSectorPointer` (:2854, :2944),
  `readSectorPointer` (:2935-2938). Writes: SPROC_FIRST at `writeSectorPointer` (:2857), COPY_IDLE `<= 0` at
  `readSectorPointer` (:2934). Bulk clear at :2986. SS restore at :2548 (constant now).
* **Change:** most reads are only `/= 0` tests. Keep an 8-bit `sectorBufferValid` in FFs; it handles every
  zero test, the clear-on-copy and the bulk clear. Move the 10-bit size into a 1-MLAB RamMLAB written only at
  SPROC_FIRST and read only at `readSectorPointer` (for `copySize`). One write port, one read port, no reset needed.
* **Saving:** about 30-60. **Risk:** low-medium (both write sites stay legal in one cycle because they now touch
  different storage). Small.

### 2.6 Savestate-only MLAB copies
* `spu.vhd:659`, `gVOICERECORDS` copy i=1: 32x103 MLAB (6 MLABs, 60 ALMs). Its `rdaddress` is `SS_Adr` and its
  only consumer is `SS_DataRead`.
* `cpu.vhd:586`, `iregisterfileSS`: 32x32 MLAB (2 MLABs, 20 ALMs), consumer `SS_DataRead_CPU`.
* Both disappear automatically when `SS_rden` is constant 0. Otherwise delete them.
  Keep the CPU `ss_regs_loading` zero-sweep (cpu.vhd:2753-2771): it clears the register file on reset.

---

## 3. Arrays and register banks that should stay in FFs (checked, not worth MLAB)

| Module | Signal (file:line) | Bits | Why not |
|--------|--------------------|------|---------|
| GPU | `rec_vertices` gpu_poly.vhd:141 | 4x64 | Shallow. Color is written to all 4 at once (:476). All are copied to `vt(0..2)` in parallel (:559-569). MLAB would cost about 120 ALMs, the same as the FFs. |
| GPU | `vt` gpu_poly.vhd:151 | 3x64 | Read many-at-once (sort, diffs, culling). |
| GPU | `t_filterarray_*`, `ttexcolor`, `tcolormults` gpu_pixelpipeline.vhd:84-248 | 4-entry pipeline regs | Parallel datapath, not storage. |
| GPU | `div_array` gpu.vhd:235 | 6 dividers | Logic, not storage (see section 6). |
| SPU | `cache_voice_starts` spu_ram.vhd:88 | 24x16 | Fully-associative compare against all 24 every cycle (CAM). See C1. |
| SPU | `adsr_rate/ticks/step/target` spu.vhd:400-410 | 5x(7+24+16+15) | All 5 phases are computed in parallel every cycle. This is a logic issue (section 6). |
| SPU | `KEYON/KEYOFF/PITCHMODENA/NOISEMODE/REVERBON/ENDX` | 6x32 | Bit-indexed per voice, read and modified per bit. |
| SPU | `voice_adsrWrite/voice_repeatWrite` | 2x24 | Bit flags. |
| SPU | voice regs, volumes, voice records, env counters | - | **Already MLAB** (spu.vhd:598-716). ADPCM samples are already M10K. |
| DMA | `D_CHCR`, request/pending/chopwait | 7x(~14+11) | Per-channel parallel reads (trigger and priority loop). |
| CD | `subdata` / `nextSubdata` cd_top.vhd:375-377 | 2x12x8 | Bulk copy `subdata(i) <= nextSubdata(i)` (:1937, :2044, :2393). |
| CPU | register file, I-cache tags | - | **Already MLAB** (cpu.vhd:539-618). The I-cache data and datacache are already M10K. |
| timer | `timerArray` timer.vhd:54 | 3x~50 | All three counters run every cycle. |
| joypad | `portStates`, `joypads` joypad_pad.vhd:159-163 | small | Inputs or parallel state. |
| memorymux | - | - | No arrays. The write FIFO is already MLAB (`SyncFifoFallThroughMLAB`, memorymux.vhd:446). |

---

## 4. Savestate read muxes (`ss_out` to `SS_DataRead`)

Cost was estimated by parsing every `ss_out(n)(bits) <= x` assignment and counting live sources per output bit.
Cost = sum over bits of (sources-1)/3 ALMs (an upper bound; the conservative figure is about 60% of it):

| Module | words with live data | est. mux ALMs (upper) | conservative |
|--------|----------------------|-----------------------|--------------|
| CPU (cpu.vhd:2788-2792) | 47 | 410 | 250 |
| SPU (spu.vhd:2570-2588, includes the MLAB SS ports) | 36 (+4 MLAB views) | 345 | 210 |
| CD (cd_top.vhd:3296-3300) | 53 | 250 | 150 |
| DMA (dma.vhd:997-998) | 32 | 230 | 140 |
| joypad + joypad_pad | 10 | 70 | 40 |
| GPU (gpu.vhd:2006-2012) | 7 | 47 | 28 |
| timer (timer.vhd:335-336) | 10 | 45 | 27 |
| irq, mdec | - | 5 | 3 |
| **total** | | **about 1,400** | **about 850** |

Status:
* `rtl/savestates_reset.vhd` (untracked, from the other job) never sets `SS_rden_2x`, so `SS_rden` is
  stuck at '0'. Every `SS_DataRead` register then never loads, and Quartus should remove all the muxes above
  plus the SS-only MLABs (item 7). **If the 21.6k fit was built with savestates_reset.vhd, this saving is
  already in that number.** If it was built with the original `savestates.vhd` (still listed in rtl/psx.qip:52),
  the saving is still available. Confirm by checking "Removed registers" for `ss_out`/`SS_DataRead`.
* `SS_wren`: with savestates_reset, `savetype_counter` only runs from 12 to 16 (SCP, CD, -, VRAM, SDRAM).
  So the SS *write* decode in CPU, GPU, DMA, timer, SPU, joypad and irq is also dead and gets pruned.
  CD (`SS_wren(13)`: sector buffers) and memorymux (`SS_wren_SDRam`: RAM clear) stay live by design.
* Status of `ss_in` in the modules you asked about:
  - **SPU, DMA, timer:** no `ss_in` array. SS writes go straight into the real registers under `SS_wren`,
    which is dead, so nothing more to do. `loading_savestate` still gates their reset branches
    (spu.vhd:906, dma.vhd:285, timer.vhd:103). It is cheap, but hard-wire it to '0' if it is not provably
    constant (it is `not resetMode` in savestates_reset).
  - **memorymux:** no `ss_in`. The `SS_rden_SDRam` path (memorymux.vhd:913) is dead. The `SS_wren_SDRam` path is live (reset clear).
  - **GPU:** `ss_gpu_in` / `ss_timing_in` (gpu.vhd:474-475, 1978-1998) are **still signals**, loaded on
    `SS_reset` with defaults (x"0003FC10", x"00C60260"). Bits whose default is 0 are stuck and get pruned.
    The roughly 13 '1' bits survive, and the reset loads into `hDisplayRange`, `vDisplayRange` and the
    GPUSTAT fields (gpu.vhd:563-577, 879-903, 1884-1891) keep a non-constant source.
    Convert them to constants like the cpu/cd_top change. Saving is small, about 10-30 ALMs, but free.

---

## 5. M10K <-> MLAB trades (budget side note)

The shallow FIFOs are inferred through `SyncFifo` / `SyncFifoFallThrough` (registered read) and probably sit in M10K:
cd `ififoParam`/`ififoResponse` 32x8 (cd_top.vhd:826, 1728), SPU `ififoOut` 64x16 (spu.vhd:541),
DMA FIFOs 64x32 and 64x53 (dma.vhd:937, 957), spu_ram out FIFO 32x84 (spu_ram.vhd:442, 3 M10K), and
gpu_line 64x98 (gpu_line.vhd:301, 3 M10K). Moving them to MLAB *costs* about 10-60 ALMs each but frees about 1-3 M10K each.
That only helps if the freed M10Ks then absorb a bigger MLAB/FF structure. Possible targets: CPU `itagram`
256x24 MLAB (about 200 ALMs including the 8:1 output mux) or the SPU `RamVoice` 2x256x16 MLAB (about 230 ALMs).
Both are read asynchronously in the same cycle (`cacheHitTest` cpu.vhd:655, SPU voice state reads), so moving
them to M10K adds a cycle. **High risk; not recommended.**

## 6. Non-MLAB observations (the 5k gap has to come from here)
* **spu_ram voice cache (C1):** 24 entries x (16-bit adder + two 16-bit compares), about 30 ALMs/entry, plus the
  CHECK_CACHE loop. It only matters when `useSDRAM='0'`. Pocket has no DDR3. If SPU RAM sits on the SDRAM
  path, make `SPUSDRAM` a *constant* '1' in the Pocket top so all of it is pruned.
* **SPU ADSR:** spu.vhd:1419-1453 computes ticks and step (shifters) for all 5 phases every cycle, but only the
  current and next phase are used (:1629-1855). Computing on demand for 1-2 phases could save about 100-200 ALMs.
  This is a timing-sensitive restructure.
* **GPU dividers:** 6 parallel dividers shared by line and poly (gpu.vhd:235, 1449). Fewer dividers used
  serially is a known area lever, but it changes drawing latency (hidden only if drawing stays ahead of the
  emulated `targetTiming`).
* **GPU overlay/crosshair** (gpu_overlay.vhd font ROM): make sure they are tied off for Pocket.
