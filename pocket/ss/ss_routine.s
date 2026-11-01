# Save-state routine of the Analogue Pocket PSX core (docs/savestates.md). Runs on the PSX CPU from SDRAM 0x200000
# (CPU address 0xA0200000, reached while psx_top's ss_mode passes RAM address bits 22:21), entered
#  - by the hidden save-state interrupt (rtl/cpu.vhd SS_VECTOR): the game's state is collected into the state block,
#    APF reads it with the memories while the core is paused, then the routine returns into the game;
#  - after a reset in restore mode (pocket_psx ss_restore): the memories hold the loaded state, the routine puts the
#    register state back from the state block and returns into the game.
# The control byte at EXP2 0x1F803F00 (ss_mode only) talks to pocket_psx:
#   read:  bit 0 restore boot, bit 1 released (APF read the save), bit 2 quiet (cd_top / all modules idle)
#   write: bit 7 = 1: freeze <= bit 6 (timers, CD), SPU hold <= bit 5;  bit 7 = 0: command in bits 3:0
#          1 entered, 2 captured (pause the core for APF), 3 done (returning into the game), 4 retry (the CD did not
#          come to a stop: returning into the game, ask again), 5 bad state (restore: not this routine's state block)
# Build: pocket/ss/build.sh (llvm-mc, mipsel, MIPS I). Position independent: only relative branches, absolute
# addresses are constants.

        .set    noreorder
        .set    noat
        .text

# ---------------------------------------------------------------- addresses
        .equ    BLOCK_HI,   0xA022          # state block 0xA0220000 (SDRAM 0x220000, bridge 0x50280000, 128 KB)
        .equ    VERIFY_HI,  0xA024          # restore self-check block 0xA0240000 (simulation, see B_FLAGS)
        .equ    IO_HI,      0xBF80          # 0x1F80xxxx through KSEG1
        .equ    CTL,        0x3F00          # control byte 0xBF803F00
        .equ    SPAD_HI,    0x1F80          # scratchpad 0x1F800000 (KUSEG: not reachable through KSEG1)

        .equ    CMD_ENTER,  1
        .equ    CMD_CAPT,   2
        .equ    CMD_DONE,   3
        .equ    CMD_RETRY,  4
        .equ    CMD_BAD,    5
        .equ    CTL_HOLD,   0xE0            # freeze, SPU hold
        .equ    CTL_FREEZE, 0xC0            # freeze, SPU runs
        .equ    CTL_RUN,    0x80            # neither

        .equ    MAGIC,      0x31535350      # "PSS1"
        .equ    VERSION,    2               # 2: + the CD data fifo (version 1 blocks load, with the fifo empty)

# ---------------------------------------------------------------- state block layout (byte offsets)
        .equ    B_MAGIC,    0x000
        .equ    B_VERSION,  0x004
        .equ    B_FLAGS,    0x008           # bit 0: after a restore, collect the restored state into the verify block
        .equ    B_GPR,      0x080           # r0-r31 (k0 is clobbered, as by the BIOS interrupt handler)
        .equ    B_HI,       0x100
        .equ    B_LO,       0x104
        .equ    B_SR,       0x108           # inside the exception (KU / IE stack pushed)
        .equ    B_CAUSE,    0x10C
        .equ    B_EPC,      0x110
        .equ    B_RESUME,   0x114           # EPC, or EPC + 4 past a GTE command (BIOS interrupt handler rule)
        .equ    B_BPC,      0x118
        .equ    B_BDA,      0x11C
        .equ    B_BDAM,     0x120
        .equ    B_BPCM,     0x124
        .equ    B_DCIC,     0x128
        .equ    B_CCTL,     0x12C           # cache control 0xFFFE0130
        .equ    B_MEMC,     0x180           # 1F801000-1F801020 (9 words), 1F801060 at +0x24
        .equ    B_GTED,     0x200           # GTE data registers 0-31
        .equ    B_GTEC,     0x280           # GTE control registers 0-31
        .equ    B_IRQ,      0x300           # I_STAT, I_MASK
        .equ    B_DMA,      0x310           # DPCR, DICR, then channels 0-6: MADR, BCR, CHCR
        .equ    B_TMR,      0x380           # timers 0-2: CURRENT, MODE, TARGET, hidden (offset 0xC)
        .equ    B_PAD,      0x3C0           # JOY_MODE | JOY_CTRL << 16, JOY_BAUD
        .equ    B_GPU,      0x400           # GPUSTAT, GPUREAD, GP1(10h) 0-7
        .equ    B_MDEC,     0x440           # MDECSTAT, control (1F80182C), tables (64 words) at +0x10
        .equ    B_CD,       0x600           # bytes: status, IE, next00, next01, vol11, next10, next11, mute,
                                            #        vol00, vol01, vol10
        .equ    B_CDFCNT,   0x60C           # CD data fifo: number of unread bytes (at B_CDFIFO)
        .equ    B_CDREGS,   0x700           # CD controller engine's register file (64 words; cd_fw.py)
        .equ    B_SPUREG,   0x800           # SPU 1F801C00-1F801EFF
        .equ    B_SPUHID,   0xB00           # SPU window lanes 7, 8, 10, 12 (halfwords)
        .equ    B_SPUVOX,   0xC00           # SPU voice records: 24 x lanes 0-4 (16 bytes per voice)
        .equ    B_SPAD,     0x1000          # scratchpad (1 KB)
        .equ    B_SPUCAP,   0x2000          # on-chip SPU RAM: capture buffers (4 KB)
        .equ    B_SPUREV,   0x3000          # on-chip SPU RAM: reverb area 0x70000-0x7FFFF (64 KB), to 0x12FFF
        .equ    B_CDFIFO,   0x13000         # CD data fifo: the unread bytes (up to 4 KB, the fifo's size)

# ---------------------------------------------------------------- I/O registers (offsets from 0xBF800000)
        .equ    I_STAT,     0x1070
        .equ    I_MASK,     0x1074
        .equ    DPCR,       0x10F0
        .equ    DICR,       0x10F4
        .equ    GP0,        0x1810
        .equ    GP1,        0x1814
        .equ    MDEC0,      0x1820
        .equ    MDEC1,      0x1824
        .equ    MDECTAB,    0x1828          # ss_mode: table copy, next word (a write sets the index)
        .equ    MDECCTL,    0x182C          # ss_mode: control bits 31:29
        .equ    SPU,        0x1C00
        .equ    SPUWIN,     0x1F00          # ss_mode: lane n at SPUWIN + 2n
        .equ    CDREG,      0x1800

# COP2 control moves and RFE (not in llvm-mc's MIPS I): register numbers
        .macro  CFC2 rt, rd
        .word   0x48400000 | ((\rt) << 16) | ((\rd) << 11)
        .endm
        .macro  CTC2 rt, rd
        .word   0x48C00000 | ((\rt) << 16) | ((\rd) << 11)
        .endm
        .macro  RFE
        .word   0x42000010
        .endm
# continue at the cached alias (KSEG0) of the next instruction: the routine's loops run from the I-cache instead of
# fetching every instruction from SDRAM (clobbers at, ra)
        .macro  TO_KSEG0
        bal     91f
        nop
91:     lui     $at, 0x2000
        subu    $at, $ra, $at
        addiu   $at, $at, 92f - 91b
        jr      $at
        nop
92:
        .endm

# ================================================================ entry (0xA0200000)
start:
        lui     $k0, IO_HI
        lbu     $k0, CTL($k0)                   # status: bit 0 = restore boot
        nop
        andi    $k0, $k0, 1
        bnez    $k0, restore
        nop

# ================================================================ save
save:
        lui     $k0, BLOCK_HI
        .irp    r, 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,27,28,29,30,31
        sw      $\r, B_GPR+4*\r($k0)
        .endr
        move    $s0, $k0
        lui     $s1, IO_HI
        li      $t0, CMD_ENTER                  # pocket_psx drops the request
        sb      $t0, CTL($s1)
        TO_KSEG0
        mfhi    $t0
        mflo    $t1
        sw      $t0, B_HI($s0)
        sw      $t1, B_LO($s0)
        mfc0    $t0, $12                        # SR
        mfc0    $t1, $13                        # CAUSE
        mfc0    $t2, $14                        # EPC
        mfc0    $t3, $3                         # BPC
        mfc0    $t4, $5                         # BDA
        mfc0    $t5, $9                         # BDAM
        mfc0    $t6, $11                        # BPCM
        mfc0    $t7, $7                         # DCIC
        sw      $t0, B_SR($s0)
        sw      $t1, B_CAUSE($s0)
        sw      $t2, B_EPC($s0)
        sw      $t3, B_BPC($s0)
        sw      $t4, B_BDA($s0)
        sw      $t5, B_BDAM($s0)
        sw      $t6, B_BPCM($s0)
        sw      $t7, B_DCIC($s0)
        lui     $t0, 0x4000                     # routine SR: COP2 usable (GTE), interrupts off
        mtc0    $t0, $12
        nop
        nop

        # resume address: EPC, past a GTE command there (the command was executed; the BIOS handler does the same).
        # The instruction is read through KSEG1; main RAM addresses are folded to 2 MB (ss_mode passes bits 22:21).
        lui     $t3, 0x1FFF
        ori     $t3, $t3, 0xFFFF
        and     $t4, $t2, $t3                   # physical address
        lui     $t5, 0x0080
        sltu    $t6, $t4, $t5
        beqz    $t6, 1f                         # not main RAM (BIOS ROM)
        lui     $t5, 0xA000
        lui     $t7, 0x001F
        ori     $t7, $t7, 0xFFFF
        and     $t4, $t4, $t7
1:      or      $t4, $t4, $t5
        lw      $t6, 0($t4)
        nop
        srl     $t6, $t6, 25
        li      $t7, 0x25                       # COP2 command
        bne     $t6, $t7, 2f
        nop
        addiu   $t2, $t2, 4
2:      sw      $t2, B_RESUME($s0)

        # the CD controller stops at its next clock with nothing in flight (freeze is on since the interrupt). If it
        # does not (an interrupt or a sector came first), return into the game: pocket_psx asks again (retry)
        li      $t1, 1000
7:      lbu     $t0, CDREG($s1)                 # ss_mode: bit 2 = not frozen yet, or the engine runs
        addiu   $t1, $t1, -1
        andi    $t0, $t0, 4
        beqz    $t0, 8f
        nop
        bnez    $t1, 7b
        nop
retry:  li      $t0, CTL_RUN
        sb      $t0, CTL($s1)
        li      $t0, CMD_RETRY
        sb      $t0, CTL($s1)
        b       return_to_game
        nop
8:
        # an SPU DMA upload still running (channel 4 enabled: between blocks the DMA is idle while the SPU's FIFO is
        # nearly full) would go on while the state is collected and leave its FIFO out of it: retry
        lw      $t0, 0x10C8($s1)                # DMA4 CHCR
        lui     $t1, 0x0100                     # bit 24: transfer enabled / busy
        and     $t0, $t0, $t1
        bnez    $t0, retry
        nop

        # let the SPU run ~7.8 more sample periods (2000 x 3 clocks, a period is 768): pending KEYON / KEYOFF and the
        # ADSR / repeat address write latches are consumed, so writing the registers back later re-arms nothing, and
        # its transfer FIFO drains (128 halfwords after a DMA upload, 24 written per period: the save quiet condition
        # does not wait for the SPU); then hold it
        li      $t0, 2000
3:      addiu   $t0, $t0, -1
        bnez    $t0, 3b
        nop
        li      $t0, CTL_HOLD
        sb      $t0, CTL($s1)
        bal     spu_wait_held
        nop

        bal     collect
        nop
        li      $t0, MAGIC & 0xFFFF
        lui     $t1, MAGIC >> 16
        or      $t0, $t0, $t1
        sw      $t0, B_MAGIC($s0)
        li      $t0, VERSION
        sw      $t0, B_VERSION($s0)
        sw      $zero, B_FLAGS($s0)
        li      $t0, CMD_CAPT                   # pocket_psx pauses the core; APF reads the window
        sb      $t0, CTL($s1)

        # wait for the release (from the I-cache: the core can only pause while the CPU is not fetching)
spin:   lbu     $t0, CTL($s1)
        li      $t1, 32
5:      addiu   $t1, $t1, -1
        bnez    $t1, 5b
        nop
        andi    $t0, $t0, 2                     # released
        beqz    $t0, spin
        nop
        b       resume_game
        nop

# ================================================================ back into the game (s0 = state block, s1 = I/O)
resume_game:
        li      $t0, CTL_RUN                    # timers, CD and SPU run again
        sb      $t0, CTL($s1)
        li      $t0, CMD_DONE
        sb      $t0, CTL($s1)
return_to_game:
        lw      $t0, B_SR($s0)
        lw      $t1, B_HI($s0)
        lw      $t2, B_LO($s0)
        mtc0    $t0, $12                        # the game's SR as inside the exception (IEc = 0)
        mthi    $t1
        mtlo    $t2
        move    $k0, $s0
        .irp    r, 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,27,28,29,30,31
        lw      $\r, B_GPR+4*\r($k0)
        .endr
        lw      $k0, B_RESUME($k0)
        nop
        jr      $k0
        RFE                                     # SR.IEc set again: psx_top leaves ss_mode

# ================================================================ wait until the SPU engine is held in IDLE
spu_wait_held:
        lhu     $t0, SPUWIN+2*7($s1)            # lane 7 bit 8
        nop
        andi    $t0, $t0, 0x100
        beqz    $t0, spu_wait_held
        nop
        jr      $ra
        nop

# ================================================================ collect the state into the block at s0
# (s1 = I/O base; the SPU is held; uses t0-t7, s2-s3; I_STAT is read last)
collect:
        move    $t9, $ra
        # scratchpad
        lui     $t0, SPAD_HI
        addiu   $t1, $s0, B_SPAD
        addiu   $t2, $t0, 0x400
1:      lw      $t3, 0($t0)
        addiu   $t0, $t0, 4
        sw      $t3, 0($t1)
        bne     $t0, $t2, 1b
        addiu   $t1, $t1, 4

        # memory control, RAM size, cache control
        .irp    o, 0x00,0x04,0x08,0x0C,0x10,0x14,0x18,0x1C,0x20
        lw      $t0, 0x1000+\o($s1)
        nop
        sw      $t0, B_MEMC+\o($s0)
        .endr
        lw      $t0, 0x1060($s1)
        nop
        sw      $t0, B_MEMC+0x24($s0)
        lui     $t1, 0xFFFE
        lw      $t0, 0x130($t1)
        nop
        sw      $t0, B_CCTL($s0)

        # GTE
        .irp    n, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
        swc2    $\n, B_GTED+4*\n($s0)
        .endr
        .irp    n, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
        CFC2    8, \n
        nop
        sw      $t0, B_GTEC+4*\n($s0)
        .endr

        # interrupt mask (I_STAT at the end)
        lw      $t0, I_MASK($s1)
        nop
        sw      $t0, B_IRQ+4($s0)

        # DMA
        lw      $t0, DPCR($s1)
        lw      $t1, DICR($s1)
        sw      $t0, B_DMA($s0)
        sw      $t1, B_DMA+4($s0)
        .irp    c, 0,1,2,3,4,5,6
        lw      $t0, 0x1080+16*\c($s1)
        lw      $t1, 0x1084+16*\c($s1)
        lw      $t2, 0x1088+16*\c($s1)
        sw      $t0, B_DMA+8+12*\c($s0)
        sw      $t1, B_DMA+12+12*\c($s0)
        sw      $t2, B_DMA+16+12*\c($s0)
        .endr

        # timers (frozen; in ss_mode MODE reads keep bits 12:11, offset 0xC holds MODE 12:10 and irqDone)
        .irp    n, 0,1,2
        lw      $t0, 0x1100+16*\n($s1)
        lw      $t1, 0x1104+16*\n($s1)
        lw      $t2, 0x1108+16*\n($s1)
        lw      $t3, 0x110C+16*\n($s1)
        sw      $t0, B_TMR+16*\n($s0)
        sw      $t1, B_TMR+16*\n+4($s0)
        sw      $t2, B_TMR+16*\n+8($s0)
        sw      $t3, B_TMR+16*\n+12($s0)
        .endr

        # joypad / memory card port (JOY_STAT is not read: a read clears its ACK bit)
        lw      $t0, 0x1048($s1)                # JOY_CTRL << 16 | JOY_MODE
        lhu     $t1, 0x104E($s1)                # JOY_BAUD
        sw      $t0, B_PAD($s0)
        sw      $t1, B_PAD+4($s0)

        # GPU: status, read latch, GP1(10h) 0-7 (0 / 1 / 6 / 7 only in ss_mode: display start, H / V range,
        # draw mode)
        lw      $t0, GP1($s1)
        lw      $t1, GP0($s1)
        sw      $t0, B_GPU($s0)
        sw      $t1, B_GPU+4($s0)
        .irp    i, 0,1,2,3,4,5,6,7
        lui     $t0, 0x1000
        ori     $t0, $t0, \i
        sw      $t0, GP1($s1)
        lw      $t1, GP0($s1)
        nop
        sw      $t1, B_GPU+8+4*\i($s0)
        .endr

        # MDEC: status, control, table copy (quant 0-31, scale 32-63)
        lw      $t0, MDEC1($s1)
        lw      $t1, MDECCTL($s1)
        sw      $t0, B_MDEC($s0)
        sw      $t1, B_MDEC+4($s0)
        sw      $zero, MDECTAB($s1)
        addiu   $t1, $s0, B_MDEC+0x10
        li      $t2, 64
2:      lw      $t0, MDECTAB($s1)
        addiu   $t2, $t2, -1
        sw      $t0, 0($t1)
        bnez    $t2, 2b
        addiu   $t1, $t1, 4

        # CD: status (index), IE, volume / mute readback (ss_mode, index 1-3), the controller (collect run, register
        # file), index put back
        lbu     $t8, CDREG($s1)
        nop
        sb      $t8, B_CD($s0)
        sb      $zero, CDREG($s1)
        lbu     $t0, CDREG+3($s1)               # index 0: IE
        nop
        sb      $t0, B_CD+1($s0)
        .irp    x, 1,2,3
        li      $t0, \x
        sb      $t0, CDREG($s1)
        lbu     $t0, CDREG+1($s1)
        lbu     $t1, CDREG+2($s1)
        lbu     $t3, CDREG+3($s1)
        sb      $t0, B_CD+3*\x-1($s0)
        sb      $t1, B_CD+3*\x($s0)
        sb      $t3, B_CD+3*\x+1($s0)
        .endr
        li      $t0, 2
        sb      $t0, CDREG($s1)                 # index 2: 1F801801 writes = window control
        li      $t0, 0x80                       # collect run: cd_ctrl's state into the SS_* registers
        sb      $t0, CDREG+1($s1)
        bal     cd_wait
        nop
        sb      $zero, CDREG+1($s1)             # register 0
        sb      $zero, CDREG($s1)               # index 0: 1F801802 reads = register bytes (bits 7:0 first)
        addiu   $t1, $s0, B_CDREGS
        li      $t2, 256
7:      lbu     $t0, CDREG+2($s1)
        addiu   $t2, $t2, -1
        sb      $t0, 0($t1)
        bnez    $t2, 7b
        addiu   $t1, $t1, 1
        # the data fifo: bytes a game left unread (Resident Evil, Einhänder leave a sector's rest for seconds), taken
        # out (window control 0x40: index 0 1F801802 reads, status bit 6 = not empty), then put back in order
        li      $t0, 2
        sb      $t0, CDREG($s1)                 # index 2: window control
        li      $t0, 0x40                       # the data fifo
        sb      $t0, CDREG+1($s1)
        sb      $zero, CDREG($s1)               # index 0
        lui     $t1, B_CDFIFO >> 16
        addu    $t1, $s0, $t1
        addiu   $t1, $t1, B_CDFIFO & 0xFFFF
        move    $t2, $zero
8:      lbu     $t0, CDREG($s1)
        nop
        andi    $t0, $t0, 0x40
        beqz    $t0, 9f
        nop
        lbu     $t0, CDREG+2($s1)
        addiu   $t2, $t2, 1
        sb      $t0, 0($t1)
        b       8b
        addiu   $t1, $t1, 1
9:      sw      $t2, B_CDFCNT($s0)
        bal     cd_fifo_put
        subu    $t1, $t1, $t2
        andi    $t8, $t8, 3
        sb      $t8, CDREG($s1)

        # SPU registers 1F801C00-1F801EFF
        addiu   $t0, $s1, SPU
        addiu   $t1, $s0, B_SPUREG
        li      $t2, 0x180
3:      lhu     $t3, 0($t0)
        addiu   $t0, $t0, 2
        sh      $t3, 0($t1)
        addiu   $t2, $t2, -1
        bnez    $t2, 3b
        addiu   $t1, $t1, 2
        # SPU hidden state: lane 7 (transfer / reverb address high bits, reverb side, IRQ9, saved IRQ), 8 (transfer
        # address), 10 (reverb address), 12 (capture position)
        lhu     $t0, SPUWIN+2*7($s1)
        lhu     $t1, SPUWIN+2*8($s1)
        lhu     $t2, SPUWIN+2*10($s1)
        lhu     $t3, SPUWIN+2*12($s1)
        sh      $t0, B_SPUHID($s0)
        sh      $t1, B_SPUHID+2($s0)
        sh      $t2, B_SPUHID+4($s0)
        sh      $t3, B_SPUHID+6($s0)
        # voice records: lane 6 = voice selects the record, lanes 0-4 read it (bit 14 is ignored)
        li      $t2, 0
        addiu   $t1, $s0, B_SPUVOX
4:      ori     $t0, $t2, 0x4000
        sh      $t0, SPUWIN+2*6($s1)
        lhu     $t3, SPUWIN+2*0($s1)
        lhu     $t4, SPUWIN+2*1($s1)
        lhu     $t5, SPUWIN+2*2($s1)
        lhu     $t6, SPUWIN+2*3($s1)
        lhu     $t7, SPUWIN+2*4($s1)
        sh      $t3, 0($t1)
        sh      $t4, 2($t1)
        sh      $t5, 4($t1)
        sh      $t6, 6($t1)
        sh      $t7, 8($t1)
        addiu   $t2, $t2, 1
        li      $t0, 24
        bne     $t2, $t0, 4b
        addiu   $t1, $t1, 16
        # on-chip SPU RAM: lane 13 sets the pointer, lane 14 reads the next halfword (capture 2,048, reverb 32,768)
        sh      $zero, SPUWIN+2*13($s1)
        addiu   $t1, $s0, B_SPUCAP
        li      $t2, 2048
5:      lhu     $t0, SPUWIN+2*14($s1)
        addiu   $t2, $t2, -1
        sh      $t0, 0($t1)
        bnez    $t2, 5b
        addiu   $t1, $t1, 2
        li      $t0, 0x8000
        sh      $t0, SPUWIN+2*13($s1)
        li      $t2, 32768 / 4
6:      lhu     $t0, SPUWIN+2*14($s1)
        lhu     $t3, SPUWIN+2*14($s1)
        lhu     $t4, SPUWIN+2*14($s1)
        lhu     $t5, SPUWIN+2*14($s1)
        addiu   $t2, $t2, -1
        sh      $t0, 0($t1)
        sh      $t3, 2($t1)
        sh      $t4, 4($t1)
        sh      $t5, 6($t1)
        bnez    $t2, 6b
        addiu   $t1, $t1, 8

        # I_STAT last: it holds every interrupt raised up to here
        lw      $t0, I_STAT($s1)
        nop
        sw      $t0, B_IRQ($s0)
        jr      $t9
        nop

# ================================================================ wait until the CD controller is frozen and idle
cd_wait:
        lbu     $t0, CDREG($s1)
        nop
        andi    $t0, $t0, 4
        bnez    $t0, cd_wait
        nop
        jr      $ra
        nop

# ================================================================ put t2 bytes from t1 into the CD data fifo
# (window control 0x40, index 1: 1F801801 writes; ends at window control 0 = register 0, index 2; uses t0-t2)
cd_fifo_put:
        li      $t0, 2
        sb      $t0, CDREG($s1)                 # index 2: window control
        li      $t0, 0x40                       # the data fifo
        sb      $t0, CDREG+1($s1)
        li      $t0, 1
        sb      $t0, CDREG($s1)                 # index 1
        beqz    $t2, 2f
        nop
1:      lbu     $t0, 0($t1)
        addiu   $t2, $t2, -1
        sb      $t0, CDREG+1($s1)
        bnez    $t2, 1b
        addiu   $t1, $t1, 1
2:      li      $t0, 2
        sb      $t0, CDREG($s1)
        jr      $ra
        sb      $zero, CDREG+1($s1)             # window control: register 0 (the register file again)

# ================================================================ restore
restore:
        lui     $s0, BLOCK_HI
        lui     $s1, IO_HI
        # a state block of this routine's format? If not (another version's save), report it and stop here: the
        # memories are already the loaded ones, the core has to be reset
        lw      $t0, B_MAGIC($s0)
        lw      $t1, B_VERSION($s0)
        li      $t2, MAGIC & 0xFFFF
        lui     $t3, MAGIC >> 16
        or      $t2, $t2, $t3
        bne     $t0, $t2, 1f
        li      $t2, VERSION
        beq     $t1, $t2, 2f
        li      $t2, 1                          # version 1: the same but for the CD data fifo
        beq     $t1, $t2, 2f
        nop
1:      li      $t0, CMD_BAD
        sb      $t0, CTL($s1)
3:      b       3b
        nop
2:
        lui     $t0, 0x4001                     # COP2 usable, cache isolated (IsC)
        mtc0    $t0, $12
        nop
        nop
        # invalidate the I-cache (a reset does not clear its tags): with IsC a store to each line invalidates it
        lui     $t1, 0x8000
        li      $t2, 256
1:      sw      $zero, 0($t1)
        addiu   $t2, $t2, -1
        bnez    $t2, 1b
        addiu   $t1, $t1, 16
        lui     $t0, 0x4000                     # COP2 usable
        mtc0    $t0, $12
        nop
        nop
        TO_KSEG0

        # memory control, RAM size, cache control
        .irp    o, 0x00,0x04,0x08,0x0C,0x10,0x14,0x18,0x1C,0x20
        lw      $t0, B_MEMC+\o($s0)
        nop
        sw      $t0, 0x1000+\o($s1)
        .endr
        lw      $t0, B_MEMC+0x24($s0)
        nop
        sw      $t0, 0x1060($s1)
        lw      $t0, B_CCTL($s0)
        lui     $t1, 0xFFFE
        sw      $t0, 0x130($t1)

        # scratchpad
        lui     $t0, SPAD_HI
        addiu   $t1, $s0, B_SPAD
        addiu   $t2, $t0, 0x400
2:      lw      $t3, 0($t1)
        addiu   $t1, $t1, 4
        sw      $t3, 0($t0)
        addiu   $t0, $t0, 4
        bne     $t0, $t2, 2b
        nop

        # GPU
        lw      $t2, B_GPU($s0)                 # GPUSTAT
        lui     $t0, 0x0100                     # GP1(01h) reset the command FIFO
        sw      $t0, GP1($s1)
        lui     $t0, 0x0200                     # GP1(02h) acknowledge the IRQ
        sw      $t0, GP1($s1)
        srl     $t3, $t2, 23                    # GP1(03h) display off = GPUSTAT 23
        andi    $t3, $t3, 1
        lui     $t0, 0x0300
        or      $t0, $t0, $t3
        sw      $t0, GP1($s1)
        srl     $t3, $t2, 29                    # GP1(04h) DMA direction = GPUSTAT 30:29
        andi    $t3, $t3, 3
        lui     $t0, 0x0400
        or      $t0, $t0, $t3
        sw      $t0, GP1($s1)
        lw      $t3, B_GPU+8+4*0($s0)           # GP1(05h) display start
        lui     $t0, 0x0500
        or      $t0, $t0, $t3
        sw      $t0, GP1($s1)
        lw      $t3, B_GPU+8+4*1($s0)           # GP1(06h) horizontal range
        lui     $t0, 0x0600
        or      $t0, $t0, $t3
        sw      $t0, GP1($s1)
        lw      $t3, B_GPU+8+4*6($s0)           # GP1(07h) vertical range
        lui     $t0, 0x0700
        or      $t0, $t0, $t3
        sw      $t0, GP1($s1)
        srl     $t3, $t2, 17                    # GP1(08h) display mode: GPUSTAT 22:17 -> 5:0, 16 -> 6, 14 -> 7
        andi    $t3, $t3, 0x3F
        srl     $t4, $t2, 10
        andi    $t4, $t4, 0x40
        or      $t3, $t3, $t4
        srl     $t4, $t2, 7
        andi    $t4, $t4, 0x80
        or      $t3, $t3, $t4
        lui     $t0, 0x0800
        or      $t0, $t0, $t3
        sw      $t0, GP1($s1)
        lw      $t3, B_GPU+8+4*7($s0)           # GP0(E1h) draw mode
        lui     $t0, 0xE100
        or      $t0, $t0, $t3
        sw      $t0, GP0($s1)
        lw      $t3, B_GPU+8+4*2($s0)           # GP0(E2h) texture window
        lui     $t0, 0xE200
        or      $t0, $t0, $t3
        sw      $t0, GP0($s1)
        lw      $t3, B_GPU+8+4*3($s0)           # GP0(E3h) drawing area top left
        lui     $t0, 0xE300
        or      $t0, $t0, $t3
        sw      $t0, GP0($s1)
        lw      $t3, B_GPU+8+4*4($s0)           # GP0(E4h) drawing area bottom right
        lui     $t0, 0xE400
        or      $t0, $t0, $t3
        sw      $t0, GP0($s1)
        lw      $t3, B_GPU+8+4*5($s0)           # GP0(E5h) drawing offset
        lui     $t0, 0xE500
        or      $t0, $t0, $t3
        sw      $t0, GP0($s1)
        srl     $t3, $t2, 11                    # GP0(E6h) mask bits = GPUSTAT 12:11
        andi    $t3, $t3, 3
        lui     $t0, 0xE600
        or      $t0, $t0, $t3
        sw      $t0, GP0($s1)
        lui     $t0, 0x0100                     # GP0(01h) clear the texture cache
        sw      $t0, GP0($s1)
        srl     $t3, $t2, 24                    # GPU IRQ flag: GP0(1Fh)
        andi    $t3, $t3, 1
        beqz    $t3, 3f
        lui     $t0, 0x1F00
        sw      $t0, GP0($s1)
3:
        # MDEC tables: command 2 (quant tables, luma + chroma: 32 words), command 3 (scale table: 32 words)
        lui     $t0, 0x4000
        ori     $t0, $t0, 1
        bal     mdec_put
        nop
        addiu   $t5, $s0, B_MDEC+0x10
        li      $t6, 32
4:      lw      $t0, 0($t5)
        bal     mdec_put
        addiu   $t5, $t5, 4
        addiu   $t6, $t6, -1
        bnez    $t6, 4b
        nop
        lui     $t0, 0x6000
        bal     mdec_put
        nop
        li      $t6, 32
5:      lw      $t0, 0($t5)
        bal     mdec_put
        addiu   $t5, $t5, 4
        addiu   $t6, $t6, -1
        bnez    $t6, 5b
        nop
        lw      $t0, B_MDEC+4($s0)              # control: DMA enables (bits 30:29)
        lui     $t1, 0x6000
        and     $t0, $t0, $t1
        sw      $t0, MDEC1($s1)

        # SPU (held since the reset). Voice registers: ADSR / repeat address writes arm no latch in ss_mode
        addiu   $t0, $s1, SPU
        addiu   $t1, $s0, B_SPUREG
        li      $t2, 192
6:      lhu     $t3, 0($t1)
        addiu   $t1, $t1, 2
        sh      $t3, 0($t0)
        addiu   $t2, $t2, -1
        bnez    $t2, 6b
        addiu   $t0, $t0, 2
        # control registers, not KEYON / KEYOFF (consumed before the save), ENDX (window), the transfer FIFO and
        # the read-only ones
        .irp    o, 0x180,0x182,0x184,0x186,0x190,0x192,0x194,0x196,0x198,0x19A,0x1A2,0x1A4,0x1A6,0x1AA,0x1AC,0x1B0,0x1B2,0x1B4,0x1B6
        lhu     $t0, B_SPUREG+\o($s0)
        nop
        sh      $t0, SPU+\o($s1)
        .endr
        # reverb registers
        addiu   $t0, $s1, SPU+0x1C0
        addiu   $t1, $s0, B_SPUREG+0x1C0
        li      $t2, 32
7:      lhu     $t3, 0($t1)
        addiu   $t1, $t1, 2
        sh      $t3, 0($t0)
        addiu   $t2, $t2, -1
        bnez    $t2, 7b
        addiu   $t0, $t0, 2
        # hidden state (after the registers that set it: mBASE, transfer address, SPUCNT)
        lhu     $t0, B_SPUHID($s0)
        nop
        sh      $t0, SPUWIN+2*7($s1)
        lhu     $t0, B_SPUHID+2($s0)
        nop
        sh      $t0, SPUWIN+2*8($s1)
        lhu     $t0, B_SPUREG+0x19C($s0)        # ENDX
        nop
        sh      $t0, SPUWIN+2*9($s1)
        lhu     $t0, B_SPUHID+4($s0)
        nop
        sh      $t0, SPUWIN+2*10($s1)
        lhu     $t0, B_SPUREG+0x19E($s0)
        nop
        sh      $t0, SPUWIN+2*11($s1)
        lhu     $t0, B_SPUHID+6($s0)
        nop
        sh      $t0, SPUWIN+2*12($s1)
        # voice records: lanes 0-4, then lane 6 = 0x8000 | voice stores them
        li      $t2, 0
        addiu   $t1, $s0, B_SPUVOX
8:      lhu     $t3, 0($t1)
        lhu     $t4, 2($t1)
        lhu     $t5, 4($t1)
        lhu     $t6, 6($t1)
        lhu     $t7, 8($t1)
        sh      $t3, SPUWIN+2*0($s1)
        sh      $t4, SPUWIN+2*1($s1)
        sh      $t5, SPUWIN+2*2($s1)
        sh      $t6, SPUWIN+2*3($s1)
        sh      $t7, SPUWIN+2*4($s1)
        ori     $t0, $t2, 0x8000
        sh      $t0, SPUWIN+2*6($s1)
        addiu   $t2, $t2, 1
        li      $t0, 24
        bne     $t2, $t0, 8b
        addiu   $t1, $t1, 16
        # on-chip SPU RAM
        sh      $zero, SPUWIN+2*13($s1)
        addiu   $t1, $s0, B_SPUCAP
        li      $t2, 2048
9:      lhu     $t0, 0($t1)
        addiu   $t2, $t2, -1
        sh      $t0, SPUWIN+2*14($s1)
        bnez    $t2, 9b
        addiu   $t1, $t1, 2
        li      $t0, 0x8000
        sh      $t0, SPUWIN+2*13($s1)
        li      $t2, 32768 / 4
10:     lhu     $t0, 0($t1)
        lhu     $t3, 2($t1)
        lhu     $t4, 4($t1)
        lhu     $t5, 6($t1)
        sh      $t0, SPUWIN+2*14($s1)
        sh      $t3, SPUWIN+2*14($s1)
        sh      $t4, SPUWIN+2*14($s1)
        sh      $t5, SPUWIN+2*14($s1)
        addiu   $t2, $t2, -1
        bnez    $t2, 10b
        addiu   $t1, $t1, 8

        # timers (frozen): MODE (clears the counter), TARGET, CURRENT, then MODE 12:10 and irqDone
        .irp    n, 0,1,2
        lw      $t1, B_TMR+16*\n+4($s0)
        lw      $t2, B_TMR+16*\n+8($s0)
        lw      $t0, B_TMR+16*\n($s0)
        lw      $t3, B_TMR+16*\n+12($s0)
        sw      $t1, 0x1104+16*\n($s1)
        sw      $t2, 0x1108+16*\n($s1)
        sw      $t0, 0x1100+16*\n($s1)
        sw      $t3, 0x110C+16*\n($s1)
        .endr

        # joypad / memory card port
        lw      $t0, B_PAD($s0)
        lw      $t2, B_PAD+4($s0)
        srl     $t1, $t0, 16
        sh      $t0, 0x1048($s1)                # JOY_MODE
        sh      $t1, 0x104A($s1)                # JOY_CTRL
        sh      $t2, 0x104E($s1)                # JOY_BAUD

        # CD controller: it stops at its next clock with nothing in flight (freeze is on since the reset); an
        # interrupt it raised since the reset would keep it from that, so acknowledge interrupts and empty the
        # response fifo meanwhile (its state is replaced anyway). Then the register file and the apply run.
12:     li      $t0, 1
        sb      $t0, CDREG($s1)                 # index 1
        li      $t0, 0x1F
        sb      $t0, CDREG+3($s1)               # acknowledge all
        sb      $zero, CDREG($s1)               # index 0
        lbu     $t0, CDREG($s1)
        nop
        andi    $t1, $t0, 0x20                  # response fifo not empty
        beqz    $t1, 13f
        nop
        lbu     $t1, CDREG+1($s1)               # read a response byte
        b       12b
        nop
13:     andi    $t0, $t0, 4                     # not frozen yet / engine runs
        bnez    $t0, 12b
        nop
        li      $t0, 2
        sb      $t0, CDREG($s1)                 # index 2: window control
        sb      $zero, CDREG+1($s1)             # register 0
        li      $t0, 1
        sb      $t0, CDREG($s1)                 # index 1: 1F801801 writes = register bytes (bits 31:24 first)
        addiu   $t1, $s0, B_CDREGS
        li      $t2, 64
14:     lbu     $t3, 3($t1)
        lbu     $t4, 2($t1)
        lbu     $t5, 1($t1)
        lbu     $t6, 0($t1)
        sb      $t3, CDREG+1($s1)
        sb      $t4, CDREG+1($s1)
        sb      $t5, CDREG+1($s1)
        sb      $t6, CDREG+1($s1)
        addiu   $t2, $t2, -1
        bnez    $t2, 14b
        addiu   $t1, $t1, 4
        li      $t0, 2
        sb      $t0, CDREG($s1)
        li      $t0, 0x81                       # apply run
        sb      $t0, CDREG+1($s1)
        bal     cd_wait
        nop
        # the data fifo's unread bytes (none in a version 1 block)
        lw      $t0, B_VERSION($s0)
        li      $t1, 1
        beq     $t0, $t1, 15f
        lui     $t1, B_CDFIFO >> 16
        addu    $t1, $s0, $t1
        addiu   $t1, $t1, B_CDFIFO & 0xFFFF
        lw      $t2, B_CDFCNT($s0)
        bal     cd_fifo_put
        nop
15:
        # CD: IE, volumes (applied ones first, then the pending ones), mute, index
        lbu     $t2, B_CD($s0)
        li      $t0, 1
        sb      $t0, CDREG($s1)
        lbu     $t0, B_CD+1($s0)
        nop
        sb      $t0, CDREG+2($s1)               # index 1: IE
        li      $t0, 2
        sb      $t0, CDREG($s1)
        lbu     $t0, B_CD+8($s0)                # applied L -> L
        lbu     $t1, B_CD+9($s0)                # applied L -> R
        sb      $t0, CDREG+2($s1)
        sb      $t1, CDREG+3($s1)
        li      $t0, 3
        sb      $t0, CDREG($s1)
        lbu     $t0, B_CD+4($s0)                # applied R -> R
        lbu     $t1, B_CD+10($s0)               # applied R -> L
        sb      $t0, CDREG+1($s1)
        sb      $t1, CDREG+2($s1)
        lbu     $t0, B_CD+7($s0)                # mute; bit 5 applies the volumes
        nop
        ori     $t0, $t0, 0x20
        sb      $t0, CDREG+3($s1)
        li      $t0, 2
        sb      $t0, CDREG($s1)
        lbu     $t0, B_CD+2($s0)                # pending L -> L
        lbu     $t1, B_CD+3($s0)                # pending L -> R
        sb      $t0, CDREG+2($s1)
        sb      $t1, CDREG+3($s1)
        li      $t0, 3
        sb      $t0, CDREG($s1)
        lbu     $t0, B_CD+6($s0)                # pending R -> R
        lbu     $t1, B_CD+5($s0)                # pending R -> L
        sb      $t0, CDREG+1($s1)
        sb      $t1, CDREG+2($s1)
        andi    $t2, $t2, 3
        sb      $t2, CDREG($s1)

        # DMA (after the devices): DPCR, channels, DICR (ss_mode: loads the flags too)
        lw      $t0, B_DMA($s0)
        nop
        sw      $t0, DPCR($s1)
        .irp    c, 0,1,2,3,4,5,6
        lw      $t0, B_DMA+8+12*\c($s0)
        lw      $t1, B_DMA+12+12*\c($s0)
        lw      $t2, B_DMA+16+12*\c($s0)
        sw      $t0, 0x1080+16*\c($s1)
        sw      $t1, 0x1084+16*\c($s1)
        sw      $t2, 0x1088+16*\c($s1)
        .endr
        lw      $t0, B_DMA+4($s0)
        nop
        sw      $t0, DICR($s1)

        # GTE: control registers (FLAG last), then the data registers but SXYP (15, pushes the FIFO), IRGB (28,
        # sets IR1-3), ORGB / LZCR (29 / 31, read only)
        .irp    n, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
        lw      $t0, B_GTEC+4*\n($s0)
        nop
        CTC2    8, \n
        .endr
        .irp    n, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,16,17,18,19,20,21,22,23,24,25,26,27,30
        lwc2    $\n, B_GTED+4*\n($s0)
        .endr

        # interrupts: mask, then I_STAT (ss_mode: loads it) last
        lw      $t0, B_IRQ+4($s0)
        nop
        sw      $t0, I_MASK($s1)
        lw      $t0, B_IRQ($s0)
        nop
        sw      $t0, I_STAT($s1)

        # self-check (simulation): collect the restored state into the verify block
        lw      $t0, B_FLAGS($s0)
        nop
        andi    $t0, $t0, 1
        beqz    $t0, 11f
        nop
        lui     $s0, VERIFY_HI
        bal     collect
        nop
        lui     $s0, BLOCK_HI
11:
        # COP0 debug registers and the software interrupt bits, last (a breakpoint must not hit the routine)
        lw      $t0, B_BPC($s0)
        lw      $t1, B_BDA($s0)
        lw      $t2, B_BDAM($s0)
        lw      $t3, B_BPCM($s0)
        lw      $t4, B_CAUSE($s0)
        lw      $t5, B_DCIC($s0)
        mtc0    $t0, $3
        mtc0    $t1, $5
        mtc0    $t2, $9
        mtc0    $t3, $11
        mtc0    $t4, $13
        mtc0    $t5, $7
        b       resume_game
        nop

# ================================================================ MDEC command / parameter word t0 (waits while
# the input FIFO is full; uses t7)
mdec_put:
        lw      $t7, MDEC1($s1)
        nop
        srl     $t7, $t7, 30
        andi    $t7, $t7, 1
        bnez    $t7, mdec_put
        nop
        jr      $ra
        sw      $t0, MDEC0($s1)
