# SotN (SLUS-00067) hardware usage: 32 min session, PCSX-Redux interpreter
Raw counters: play_prof_204752.txt (+ attract_prof.txt, play_prof_session1.txt)

## GPU (52.9M GP0 cmds)
- Dominant: 0x7d 16x16 raw-textured sprites (31.3M, background tiles); 0x64-67 variable sprites (1.1M).
- Gouraud textured quads 0x3c-3f (3.7M) and tris 0x34-36; gouraud untextured 0x38-3b; flat 0x20/28/2c; gouraud lines 0x51-53.
- Fills 0x02, CPU->VRAM 0xa0 (527k), VRAM->VRAM 0x80 (776), VRAM->CPU 0xc0 (108).
- NOT used: polylines (0x48-4f, 0x58-5f), 1x1 dots (0x68-6f), 8x8 sprites (0x70-77), 16x16 other than 0x7d, flat untextured lines (0x40-47).
- All 4 semi-transparency modes used; 4-bit, 8-bit and 15-bit textures used; dithering used.
- Display modes: 256x240 (gameplay), 320x240, 512x240, 640x240, 320x240 24-bit (FMV), 640x480 interlaced.
- Takeaway: nearly the whole GPU feature set is needed; only small primitive variants can go.

## GTE: 11 of 22 ops used
Used: RTPS, RTPT, NCLIP, DPCS, MVMVA, NCDS, NCCS, SQR, AVSZ3, AVSZ4, GPF.
Unused: OP, INTPL, CDP, NCDT, CC, NCS, NCT, DCPL, DPCT, NCCT, GPL.
The core's GTE shares MAC datapaths (gte_mac0/gte_mac123), so dropping these saves control logic only.

## CD
- Commands: Getstat, Setloc, ReadN, ReadS, Pause, Init, Demute, Setfilter, Setmode, GetlocL, SeekL, Test, GetID, ReadTOC.
- **Never Play (0x03): no CD-DA.** Track 2 is never played.
- Double speed always; XA-ADPCM with filter (mode 0xc8) for music: 30k XA sectors. The XA decoder is required.

## MDEC: used for FMV only (DMA ch0/1). Could be dropped if FMVs are skipped (risky: game expects MDEC status).
## SPU: reverb used (master + per-voice masks, CD-audio reverb bit seen). No noise, no FM/pitch modulation.
## DMA: ch0, 1, 2 (block + linked list), 3, 4, 6. Not ch5 (PIO).
## Timers: basic modes on T1/T2.
