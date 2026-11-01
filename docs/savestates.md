# Save states (branch ss-feasibility)

This line is save states only. Branch ss-speed is ss-feasibility with the speed-settings branch merged in
(untested, not asked for): the hardware test builds up to 2026-10-30 (seed-4 zip, release candidate 4bf34f4, the
diagnostic build) were ss-speed, but speed-settings stays out of this line until it is looked at again. Builds
now come from ss-feasibility (and ss-diag-f: ss-feasibility + the diagnostics page).

Status (2026-11-01): works on hardware (963385f seed 9, released as version 0.3). How it got there (from seed 4):
- First try: "Saves not supported": core.json had `sleep_supported` false (fixed; the core now also reports
  support from the start, see "Bridge window").
- With `sleep_supported` true: save and load work in a quiet place in Symphony of the Night. During its music a
  save failed after ~2 s ("Save Failed"; the game ran on, the music stopped and came back ~1 s after).
- With the drive hold (the drive starts no read while a save is asked for; diagnostic build and release candidate
  4bf34f4): during music still "Save Failed". The diagnostics page: the routine was never entered; of cd_top's
  quiet conditions only "sector fetch idle" never held, and APF made no data slot read in those 2 s. A read that
  had started before the save waited for APF, which delivers nothing while it waits for the save. The CD's
  `SS_idle` could not hold either (it waits for no drive event within 1,024 clocks, and the hold keeps the event
  waiting at 0). A sleep (the Pocket takes a state, then resumes it on wake) worked once on the release candidate.
- Now: a save may be taken while a sector fetch waits; `ss_quiet` no longer includes the CD's `SS_idle`, and while
  the freeze is on the CD counts as idle for the core's pause too; when a freeze ends cd_top fetches the last
  read's sector again (a load used to leave the datapath reset: a state saved while the drive reads would have gone
  on reading at LBA 1); pocket_cd drops a request the core withdraws by a reset; a core that does not pause after
  "captured" ends the save with an error instead of hanging (see "CD").
- ss-feasibility release candidate (258945e, seed 5; save states only): save and load during Symphony of the
  Night's music work on hardware, and so do sleep / wake. In Resident Evil Director's Cut and Einhänder a save failed
  after ~2 s ("Save Failed", in game, also where no sound played). The diagnostics page (Resident Evil, in a room):
  the routine was never entered; every quiet condition held at some point but the CD's, and of the CD's only "data
  fifo empty" never held (no sector requests in the 2 s). These games leave bytes unread in the data fifo for
  seconds (a request for data loads the fifo only when it is empty; writing 0 to the request register empties it),
  so the fifo is now part of a state (see "CD").
- Release candidate 963385f (seed 9, the data fifo in the state): save states work on hardware (2026-11-01), and
  states saved by the previous release candidate (version 1) load.

The save / restore round trip
in the whole-core boot simulation passes (the restored state matches the saved one but for four cosmetic register
fields), `pocket_psx`'s APF path passes its testbench, the CD controller is cycle-exact against the reference on all
four scripts. The ss-speed build fits and meets timing on every corner (seed 4: 18,000 ALMs, see "Builds"); next
is the hardware test below.

## How it works

A hidden interrupt makes the PSX CPU run a MIPS routine kept in SDRAM above main RAM. The routine saves (or puts back)
everything a game can read and write through the normal registers: GPRs, COP0, GTE, scratchpad, the I/O registers.
Hardware exists only for the state the CPU can't see or can't set, through windows open only while the routine runs
(`ss_mode`), so games see no difference. APF reads (save) or writes (load) main RAM, SPU RAM and VRAM directly over
the bridge while the core is frozen or held in reset; nothing is copied through the core. A snapshot is only taken
at a quiet moment (no command, interrupt, DMA, GPU command, MDEC frame or CD sector in flight), so in-flight state
never has to be saved.

Why this fits when upstream's mechanism doesn't: upstream (`rtl/savestates.vhd`) reads and writes every register of
every module through its own path (readback muxes 850-1,400 ALMs, load paths 692 ALUTs, write enables 473 ALUTs, a
sequencer ~700 ALUTs) and copies the memories through the core: ~2,000-2,600 ALMs against ~1,050 free.

### Save (APF command 0xA0)

1. pocket_psx raises `ss_req`; psx_top passes it to the CPU as `ss_irq` only while `ss_quiet` (the modules'
   `SS_idle` but the SPU's and the CD's, and cd_top's quiet: no command, response, interrupt or buffered sector, no
   sector being processed or copied, engine idle, no command delay running; a sector fetch may be on its way and the
   data fifo may hold bytes, see "CD"). The SPU's `SS_idle` (IDLE before tick 760, nothing stashed, FIFOs empty)
   does not come on the Pocket: with SPU RAM in SDRAM every voice is paced to 24 clocks and the engine barely keeps
   up with its sample periods (in the boot simulation it fell 15 samples behind). The routine handles the SPU itself
   (step 3).
2. The CPU takes it like a hardware interrupt (only with SR.IEc = 1; not visible in CAUSE) and fetches from
   `SS_VECTOR` = 0xA0200000. psx_top sets `ss_mode` (RAM address bits 22:21 pass through: the CPU reaches SDRAM
   0x200000-0x7FFFFF) and `ss_freeze` (the timers stop; the CD controller stops at its next clock with nothing in
   flight, see "CD").
3. The routine (`pocket/ss/ss_routine.s`, from SDRAM 0x200000, state block at SDRAM 0x220000) stores the GPRs (k0 is
   clobbered, as by the BIOS interrupt handler) and reports "entered", then runs from the cached alias (KSEG0):
   - HI / LO, COP0, the resume address (EPC, past a GTE command there, as the BIOS handler does);
   - waits for the CD freeze; if the CD does not come to a stop (an interrupt or a sector came first) it returns
     into the game and reports "retry": pocket_psx asks again. It also retries while an SPU DMA upload is running
     (channel 4 enabled: between blocks the DMA can be idle with the SPU's FIFO nearly full);
   - lets the SPU run ~7.8 more sample periods (pending KEYON / KEYOFF and the ADSR / repeat-address write latches
     are consumed, and its transfer FIFO drains: up to 128 halfwords after a DMA upload, 24 written per period),
     then holds it in IDLE (held, the SPU counts as idle for the core's pause, whatever it was behind by);
   - collects: scratchpad, memory control, cache control, GTE, I_MASK, DMA, timers, joypad port, GPU (status,
     GP1(10h) 0-7), MDEC (status, control, table copy), CD (IE, volumes, mute, the controller's register file after
     the firmware's collect run, the data fifo's unread bytes: taken out and put back), SPU registers, hidden SPU
     state, voice records, the 68 KB of SPU RAM that live on chip; I_STAT last;
   - reports "captured": pocket_psx pauses the core and answers APF "ok". The pause waits for the modules'
     `SS_idle`; while the freeze is on the CD counts as idle there (a sector fetch may still be on its way, see
     "CD"). A core that has not paused ~2 s after "captured" ends the save with an error and the routine returns.
4. APF reads the 4 MB window. Its read of the last word releases the core: the routine releases the freezes,
   reports "done" and returns (`jr k0; rfe`). If APF never reads the last word the core is released after ~16 s
   (the read itself takes ~1.2 s or more). A save that has not started after ~2 s (no quiet moment with interrupts
   enabled) ends with an error.

### Load (APF writes the window, then 0xA4)

1. The first bridge write into the window holds the core in reset. SDRAM parts go through the BIOS loader FIFO on
   SDRAM channel 3, VRAM through pocket_memcard's aux port.
2. 0xA4 releases the reset in restore mode: the reset sequence skips the memory clear and keeps the CPU in reset
   until it is through (between its reset pulses the CPU would otherwise run while the sequencer uses the
   memories), then the CPU starts at `SS_VECTOR` with `ss_mode`, `ss_freeze` and the SPU hold on.
   The block starts with "PSS1" and a version (2: with the CD data fifo; a version 1 block loads with the fifo empty);
   a block without them ends the load with an error (the CPU then waits in the routine: load another state or reset
   the core). Bump the version when the block layout or the CD firmware's register allocation (`rtl/cd_fw/cd_fw.py`)
   changes.
3. The routine invalidates the I-cache (a reset does not clear its tags), then puts back: memory control, scratchpad,
   GPU (GP1 01-08, GP0 E1-E6, texture cache flush, IRQ flag), MDEC tables (commands 2 and 3) and control, SPU
   (registers with no key-on / ADSR latch arming, hidden state, records, on-chip RAM), timers (MODE, TARGET,
   CURRENT, then the flags), joypad port, CD (register file, the firmware's apply run, the data fifo's bytes, IE,
   volumes, mute, index), DMA (DPCR, channels, DICR with its flags), GTE (control, then data but SXYP / IRGB / ORGB /
   LZCR), I_MASK, I_STAT last, COP0 debug registers, then releases the freezes, reports "done" and returns into the
   game. As the freeze ends cd_top fetches the drive's last sector again (its datapath was reset, see "CD").

On a wake from sleep the state and the 0xA4 can come while APF still holds the core in reset (zenibako/openfpgaCore#1:
both are there before its OS starts), and APF may wait for the result before it releases the reset: a load that
finds the core held by APF answers "ok" once the data is written, and the routine runs when the reset ends (the
load's ~2 s time-out counts only while the core runs). A request while another one runs is refused (acked with an
error: APF waits for the ack, so an unanswered request would stop the bridge).

### Bridge window (savestate_addr 0x50000000, 4 MB)

| Offset | Contents | Where |
|---|---|---|
| 0x000000-0x1FFFFF | main RAM | SDRAM 0x0000000 (channel 3) |
| 0x200000-0x27FFFF | SPU RAM | SDRAM 0x1000000 (the on-chip 68 KB are in the state block) |
| 0x280000-0x29FFFF | the routine's state block (128 KB) | SDRAM 0x0220000 (128 KB aligned: the offset is OR-ed in) |
| 0x2A0000-0x2FFFFF | unused | - |
| 0x300000-0x3FFFFF | VRAM | PSRAM region 0 (pocket_memcard) |

The routine is data slot 3 (`ss_routine.bin` in `Assets/psx/akoaysigod.PSX/`, bridge 0x10000000 -> SDRAM
0x200000, required). `savestate_supported` is always set: APF asks once, when the core loads, and keeps the answer
(first hardware try: reporting support only once the slot was written was not enough). Without the routine a save
is refused and a load ends with an error (the core then boots afresh). core.json's `sleep_supported` has to be
true: with false the Pocket greys out Memories ("Saves not supported") whatever the core answers, and with true it
also takes a state when the Pocket sleeps and loads it on wake. About 1.2 s per save or load at
APF's worst-case bridge rate (88 clk_74a per word). (ss-speed only: with speed-settings the core pauses while the
Pocket menu is open, except while a state is saved or loaded: the routine has to run.)

### Hidden state and how each part is handled

| Module | Hidden state | Handled by |
|---|---|---|
| CPU | pipeline, EPC / CAUSE / BadVaddr | the interrupt drains the pipeline; EPC etc. are only live inside handlers |
| IRQ | I_STAT (the CPU can only acknowledge) | in `ss_mode` an I_STAT write loads it |
| DMA | DICR flags 30:24 (write 1 to clear) | in `ss_mode` a DICR write loads them |
| Timers | MODE 12:10 (cleared by reads), irqDone | in `ss_mode` MODE reads keep 12:11; offset 0xC reads / loads 12:10 and irqDone; `ss_freeze` stops counting |
| GPU | display start, H / V range, drawMode incl. flip bits | GP1(10h) 0, 1, 6, 7 in `ss_mode` |
| MDEC | quant / scale tables, DMA enables | table copy readback at 1F801828 (auto-increment), control at 1F80182C |
| SPU | voice records, ENDX, IRQ9, transfer / reverb / capture pointers, on-chip SPU RAM | window 0x1F801F00-0x1F801F1F, hold bit |
| CD | the controller (cd_ctrl registers, engine register file), the data fifo's unread bytes | see "CD" |
| pad / memory card | protocol state between bytes | excluded by the quiet condition |

### CD

The controller's state is the engine's register file (the firmware's variables, `rtl/cd_fw/cd_fw.py`) and cd_ctrl's
registers. On `ss_freeze`, cd_top stops cd_ctrl (its `ce`) at the first clock with nothing in flight, no pulse shown
and no engine run starting (stopping in the middle of a one-clock pulse would hold it on). In `ss_mode`, with the
controller stopped and its engine idle:

- 1F801800 bit 2 = not stopped yet, or the engine runs;
- 1F801801 index 2 write = window control: 0x00-0x3F register index, 0x40 the data fifo (cd_ctrl: register 0),
  0x80 collect run, 0x81 apply run;
- 1F801801 index 1 write = a byte of a register (bits 31:24 first; the fourth stores it, index + 1); with 0x40 a
  byte into the data fifo;
- 1F801802 index 0 read = the next byte of a register (bits 7:0 first; after the fourth, index + 1); with 0x40 the
  data fifo's next byte (1F801800 bit 6: not empty).

The data fifo (what the CPU reads at 1F801802 or by DMA after asking for a sector's data) may hold bytes at a
snapshot: Resident Evil and Einhänder leave bytes there for seconds (on hardware the fifo was not empty once in a
save's 2 s), and the quiet condition never held. The routine takes the bytes out into the state block (count at
0x60C, bytes at 0x13000, at most the fifo's 4 KB; a copy holds at most 2,340), puts them back in order, and a load
puts them in after the apply run. The sector copy into the fifo is idle at a snapshot (quiet).

The collect run copies what is not in the variables (cd_ctrl's flags, work and drive delays, sector pointers;
with speed-settings also allow_speedhack) into four registers; the apply run writes cd_ctrl's registers back from
the variables and those (as the commit does, without the pulses). The firmware also keeps readLBA in a register
now. Firmware: 1,940 of 2,048 words (ss-speed 1,935). The XA / CD-DA buffers and the datapath's last header are not
kept (see below).

While a save is asked for (`ss_req`, from APF's 0xA0 until the routine is entered, again after a retry) cd_ctrl
starts no sector read (`drive_hold`: the drive event waits with driveDelay at 0). With CD audio playing the drive
reads one sector after the other; a read whose sector is not in pocket_cd's read-ahead waits for APF, and APF
delivers nothing while it waits for the save (the diagnostics page: no data slot read in the 2 s of a failed save,
the fetch never idle; the music stopped). The read that is due starts as soon as the hold ends; a state saved
meanwhile has it due, so after a load it starts at once.

The sector datapath is not part of a state, so a fetch may still be on its way when the snapshot is taken (cd_top's
quiet waits only for the sector processing, the copy and the subchannel computation; the CD's `SS_idle`, which also
waits for the fetch and for no drive event within 1,024 clocks, is not in `ss_quiet`). The datapath holds the drive's
last read: lastReadSector, the raw sector (processed at the next drive event), its subchannel (copied at that event)
and its track. readLBA is always the LBA of the last readOnDisk (cd_fw.py sets it only in runs that pulse it), so
when a freeze ends cd_top fetches readLBA again: after a load (datapath reset, controller put back) that puts the
datapath back, before the drive's next event, which waits for the fetch; after a save the fetch finds the sector
cached (cd_hps_lba) and skips it. Without it a state saved while the drive reads went on at LBA 1 after a load.
The fetch can wait for APF until the load is done. The re-fetch is armed after the fetch state machine (a fetch
starting in that clock takes the buffered LBA, the re-fetch follows it), and a reset clears a read asked for
before it. The core's pause (after "captured") waits for the modules' `SS_idle`, the CD's included, which a
waiting fetch keeps low: while the freeze is on the CD counts as idle there, else such a save would never pause
(and with no answer for APF, not even end).

pocket_cd drops a request the core withdraws before its sector is sent: a load resets the core while the old
request's data slot read is still running (APF serves it after the load), and the sector, sent then, would answer
the restored core's first request.

### Accepted compromises

- Video timing phase is not saved: one stuttered or torn frame after a load.
- SPU: decoded-sample buffers and interpolation history (a short click per playing voice), adsrTicks (the next
  envelope step comes one tick early), sweep counters, the main volume sweep position.
- XA / CD-DA buffers are dropped: an audio gap of up to one XA sector after a load. GetlocL's header is stale until
  the next data sector.
- A save waits for a quiet moment: normally well under one sector period; if the CD does not stop the routine retries.
  The drive reads no sector meanwhile: CD audio pauses for that long.
- After a load the drive's next sector waits for the fetch of its last one (from pocket_cd's ring, or APF once the
  load is done).
- The memory card is not part of a save state (as on MiSTer).
- k0 is clobbered (the BIOS interrupt handler clobbers it too). GPUREAD keeps the routine's last GP1(10h) answer.
- The SPU audio holds while the routine runs (a few ms per save, plus APF's ~1.2 s read while frozen).
- An SPU DMA-read prefetch (the output FIFO, transfer mode 3) is not kept: a game reading SPU RAM back by DMA right
  across a save would skip up to 32 halfwords after the load.

## Tests

- `pocket/sim/pocket_ss` (new): pocket_psx with a stub core playing the routine's handshake. APF writes the routine's
  slot, loads a state into the window, then saves one and reads it back. PASS. It found three bugs, fixed:
  APF's acks were set and cleared in the same clock (APF waits for an ack: the Pocket would have hung on the first
  save or load); the state block at 0x210000 was not aligned to its 128 KB (the upper half landed on the lower);
  the save-state reader's wait state counted as "loader busy", which is part of the core's reset (every APF read
  of RAM during a save would have reset the core). Also fixed by reading: the reader's ch3_ready reached the SPU's
  RAM port while frozen. On ss-speed it also checks the save and the load with the Pocket menu open.
- `pocket/sim/boot`: FAST_RESET (simulation only: no memory clear) and save states: SS_SAVE_MS saves at that time and
  dumps the memories while frozen; SS_LOAD restores from such a dump; SS_VERIFY makes the routine collect the restored
  state again into 0x240000, which `pocket/ss/compare.py` compares with the saved block.
- `pocket/sim/pocket_memcard` (the memory card engine was reworked for the VRAM window): PASS on main and on the
  branch (default configuration; CDC=true fails on main too: the PSRAM models answer that path's reads with 'Z').
- `sim/cd_equiv` FREEZE (the engine against the reference controller, every output every clock) after the CD
  changes: script 0 (BIOS-like boot) on ss-feasibility, scripts 1 (SotN-like loading + XA), 2 (CD audio) and 3
  (random commands) on ss-speed: PASS, 0 mismatches each.
- `sim/cd_equiv` SSMS=550 on script 1 (CPUSRC=1): the CD save, a reset of the controller and the restore in the
  middle of the script give the same summary as the run without (74 interrupts, 46 sectors, data checksum, 61
  sector requests, audio checksum, no XA underrun), 2,484 clocks later.
- `pocket/sim/pocket_cd` WITHDRAW=n: requests dropped while APF reads their sector, each followed by one for another
  sector. The old pocket_cd answered that one with the dropped request's sector (word errors); now PASS.
- `sim/cd_equiv` script 4 (SotN music; XAMS=600: Setloc 1150 + ReadS at 617 ms, the seek, then XA) with SSMS=800
  (the save in the seek) and DBGMS=795 (the sector requests): after the restore the old cd_top read LBA 0, 1, 2, ...
  (the datapath's lastReadSector was 0): no XA sector, no audio. Now the re-fetch of 1150, then 1151, 1152, ...:
  3 XA sectors, 5,813 audio samples, audio checksum 58362, as without the save (24 sector requests: 23 + the
  re-fetch). SSMS=1100 (the save while XA streams, after the request for 1153): the old cd_top read LBA 1, 2, ...
  after the restore (1 XA sector, 32 audio samples: the music stopped); now 1153 again, then 1154, ...: all 3 XA
  sectors, 3,497 audio samples (the rest of the XA sector playing at the save is dropped, see "Accepted
  compromises"). The same numbers with b5988f2's cd_top and with b551bcf's (re-fetch after the case, reset clear).
- `sim/cd_equiv` SPLIT=300 on script 1 (CPUSRC=1): each sector's last 300 bytes are read at the next interrupt
  poll, as by a game that leaves bytes in the data fifo. SSMS=550 SSFIFO=1 saved at 1,192 ms with 300 bytes in the
  fifo (the old quiet condition waited for an empty one): the same interrupts, sectors, bytes and data checksum as
  the run without a save (74, 46, 94,208, 68225). SSNOFIFO=1 (the restore leaves the fifo empty): data checksum
  74083, so the test sees lost bytes. One non-silent audio sample fewer (10,605 of 10,606) and the re-fetch's extra
  sector request, as with SSMS=550 without SPLIT (fifo empty at the save): the save's length shifts the audio
  against the SPU tick (with SSNOFIFO's shorter restore the audio matches). SSMS=550 gives the same output with the
  cd_top before the change (fc0a252), timestamps included.
- `pocket/sim/boot` without a save (main vs the branch, FAST_SHELL, FAST_RESET): identical reports through 118 ms.
- `pocket/sim/boot` with a save requested at 100 ms: it never started. A probe of every idle condition showed
  interrupts enabled and every module idle but the SPU, whose `SS_idle` did not hold once in 200 ms (the reason the
  quiet condition no longer includes it). Inside the SPU: IDLE in 81 of 67,738 clocks, stashedSamples at its
  maximum (15) throughout: the engine did not keep up with its sample periods.
- `gte_UNRDivide` with the table as a ROM: bit-exact against the old divider (every divisor, 334,000 random
  operand pairs).
- `pocket/sim/boot` round trip (both branches, identical): saved at 100 ms in the BIOS shell (captured at 124.4 ms,
  the core paused and released at the next frame, the shell runs on), restored from that dump (done at 36.2 ms, the
  shell runs on), the restored state collected again and compared with the saved block (`pocket/ss/compare.py`):
  main RAM, SPU RAM, VRAM, scratchpad, the on-chip SPU RAM, memory and cache control, GTE control, I_STAT /
  I_MASK, DMA, timers, joypad, the CD (with the controller's register file), SPU hidden state and voice records
  identical. Left: GTE LZCR (derived from LZCS when it is written back: 32 for 0, as on hardware), GPUSTAT bits 31
  and 13 (video timing phase), MDECSTAT's words-remaining field (this MDEC shows 16 after any table upload), the
  KEYOFF read-back value (KEYON / KEYOFF are not written back). The round trip found three hardware bugs: the SPU
  never idle for the quiet condition, the held SPU never idle for the pause, and the CPU running during a restore
  boot's reset sequence.
- `pocket/sim/boot` round trip with the version 2 routine (963385f, the CD data fifo): captured at 124.4 ms, restore
  done at 36.2 ms, the same four differences; the fifo was empty in the BIOS shell (count 0, compared).

## Hardware test (first run)

Unzip the release at the SD card's root: it has `Assets/psx/akoaysigod.PSX/ss_routine.bin` (required by data.json:
without it the Pocket does not start the core).

1. BIOS shell (no disc): Memories -> save; the shell keeps running. Move the cursor, then load the memory: the shell
   comes back as it was.
2. A game: save during play with music, play on a bit, load. Check the picture, music, sound effects, controls.
   Save while the game loads from the CD (a room / level change): the save may take a moment (it waits for a quiet
   moment), then load it.
3. Load after restarting the core (and after a power cycle): a cold core.
4. The memory card as usual (save in a game, restart, check the save): pocket_memcard was reworked to also serve
   the VRAM part of a state, and its clk3x VRAM path is not covered by the simulations.
5. Expected after a load: one torn frame, a short click per playing voice, up to one XA sector of silence.
6. If the Pocket reports an error, or the picture freezes: which step, and whether the core still runs afterwards.
7. Sleep (power button) during a game, then wake: the game should come back where it was ("Resuming...").

## Builds

| Build | ALMs | LABs | M10K | Timing |
|---|---|---|---|---|
| release 0.2 (1d2a8b6, seed 1) | 17,430 / 18,480 (94 %) | 1,843 | 273 | met |
| prototype hardware (`builds/ss_fit1`) | 18,198 (98 %) | 1,846 | 275 | setup met, hold -0.004 ns (existing SPU path) |
| ss-speed with the CD part (`sssps1`, seeds 1 and 2) | 18,415 needed | 1,861 / 1,848 | 275 | does not fit |
| + area changes (`ssp2s1`) | 17,970 | 1,838 | 289 | setup -0.045 ns (clk3x) |
| final design (ss-speed 6134206, `ssp5s1`) | 18,056 (98 %) | 1,844 | 289 | setup met (>= 0.465 ns), hold -0.002 ns (1 path) |
| same, seeds 2 / 3 (`ssp5s2`, `ssp5s3`) | 18,047 / 18,016 | 1,848 / 1,840 | 289 | setup met; hold -0.023 / -0.045 ns (clk2x) |
| same, seed 4 (`ssp5s4`): the test build | 18,000 (97 %) | 1,840 | 289 | met on every corner: setup +0.061 ns, hold +0.017 ns |
| ss-speed 4bf34f4 (+ support from the start, drive hold), seed 2 (`ssp6s2`): release candidate | 18,018 (98 %) | 1,837 | 289 | met on every corner (worst +0.010 ns); seed 1 -0.392 ns |
| ss-diag 828f99b (+ diagnostics page, MDEC stub: no FMVs), seed 2 (`ssd2s2`): diagnostic test build | 17,976 (97 %) | 1,846 | 275 | met on every corner (worst +0.014 ns); seed 1 -0.023 ns |
| ss-speed a37b19c (the fetch / re-fetch and pause fixes; with speed-settings: not used), seed 1 (`ssp7s1`) | 18,033 (98 %) | - | 289 | met on every corner (+0.013 ns); seed 2 (before the pause fix) -0.032 ns |
| ss-feasibility 258945e (save states only: the fetch / re-fetch and pause fixes), seed 5 (`ssf1s5`): release candidate | 18,063 (98 %) | 1,844 | 289 | met on every corner (worst +0.014 ns, hold); seeds 2 / 1 / 3 / 4: -1.462 / -0.037 / -0.050 / -0.034 ns (each on another clock: routing at 98 %, seed 2's paths GPU / VRAM into gpu reqVRAMremain) |
| ss-feasibility 963385f (+ the CD data fifo in the state), seed 1 (`ssf2s1`): interim test build | 18,006 (97 %) | 1,842 | 289 | setup met; hold -0.017 ns (Fast 0C, savestates ss_reset_2x -> ss_reset, clk2x -> clk1x; MiSTer's path) and -0.002 ns (dma fifoOut) |
| same, seeds 2-8 (`ssf2s2`-`ssf2s8`) | 18,025-18,118 | 1,838-1,843 | 289 | none met: hold -0.022 / -0.051 / -0.047 / -0.096 ns (seeds 2 / 3 / 6 / 8: mdec, gpu_pixelpipeline stage 3 -> 4), setup -0.350 / -1.054 / -0.309 ns (seeds 4 / 5 / 7: cpuPaused -> sdram, GPU, vram_cdc -> gpu vram_BURSTCNT); no failing path in cd_top, clk1x met setup in every seed |
| same, seed 9 (`ssf2s9`): version 0.3 | 18,074 (98 %) | 1,842 | 289 | met on every corner (worst +0.003 ns, hold clk2x; setup +0.070 ns) |

Zips (gitignored, `releases/`): `akoaysigod.PSX_0.3_ss-feasibility-963385f_seed9.zip` (version 0.3: the seed 9
bitstream with the 0.3 core.json / info.txt; works on hardware). The earlier test zips (ss-speed 6134206 seed 4,
ssdiag seed 2 with rtl/mdec_black.vhd over rtl/mdec.vhd, ss-speed 4bf34f4 seed 2, ss-feasibility 258945e seed 5,
ssdiag-f seed 2, 963385f seed 1) are deleted (2026-11-01). Rebuild with `SEED=n tools/build.sh NAME` at the commit,
then `tools/release.sh NAME`.

Area changes that made it fit: pocket_cd's sector ring sliced 8K x 1 (32 M10K instead of 19, no 19:1 output mux:
-224 ALUTs), gte_UNRDivide's table as a 512-entry M10K ROM, the SPU window reading voice records from the RAM
directly. The hold misses of the seeds are in existing paths (gpu_pixelpipeline stage 3 -> 4, vram_cdc -> the
gpu_videoout line buffer): routing congestion at 98 %, not the save-state logic.

Synthesis (same-tree MAPONLY): release 26,698 ALUTs; prototype `ss_hw1` 27,398; with the CD part `ss_hw2` 27,532.

## What is left

1. Cosmetic differences after a load (see "Tests"): MDECSTAT's words-remaining field could be put back by the
   routine (feed the MDEC the missing words), KEYON / KEYOFF read-back values would need hardware.
2. Sleep / wake: on (core.json `sleep_supported` is what turns Memories on); worked on hardware (release
   candidates 4bf34f4 and 258945e).
