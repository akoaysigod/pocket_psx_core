-- Boot simulation of the Pocket core (psx_pocket_core as built for the Pocket) running the real BIOS:
-- main RAM / BIOS from ram_model (sdram.sv channel behaviour), SPU RAM from a byte array with ch3-like
-- latency, VRAM and the memory card through vram_psram and two PSRAM chip models, no disc (hasCD = 0).
-- Reports every REPORT_CYCLES clk1x cycles: CPU PC range, video frames, GPU display state, device activity;
-- logs CD-ROM register writes and GPU GP1 writes; writes the core's picture every DUMP_EVERY frames to
-- frame_NNNN.ppm. Stops after RUN_MS simulated milliseconds.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_boot is
   generic
   (
      RUN_MS        : integer := 2000;
      REPORT_CYCLES : integer := 1000000;
      DUMP_EVERY    : integer := 20;
      LOG_IO        : integer := 400;     -- number of CD / GP1 register writes to log
      DEBUG_SS      : integer := 0;       -- > 0: print the reset sequence's idle / pause handshake every DEBUG_SS cycles
      TRACE_IO_N    : integer := 0;       -- log the first TRACE_IO_N CPU accesses to I/O registers (1F80xxxx) with PC
      TRACE_FROM_MS : integer := 0;       -- ... starting at this time
      FAST_SHELL    : boolean := false;   -- skip the BIOS shell copy (see ram_model)
      SKIP_INTRO    : boolean := false    -- skip the shell's boot intro (see ram_model)
   );
end entity;

architecture sim of tb_boot is

   -- clk1x 33.8688 MHz, clk2x and clk3x edge-aligned multiples (as from one PLL), clkvid 53.69 MHz
   constant TICK : time := 2460500 fs;
   -- all three start high and toggle every 6 / 3 / 2 ticks: rising edges coincide every clk1x period, as the
   -- core's clock-crossing logic (clk2xIndex, clk3x index) expects from the PLL
   signal clk1x, clk2x, clk3x : std_logic := '1';
   signal clkvid : std_logic := '0';
   signal done   : boolean := false;
   signal reset  : std_logic := '1';
   signal reset2x : std_logic := '1';

   -- main RAM
   signal ram_dataWrite, ram_dataRead32 : std_logic_vector(31 downto 0);
   signal ram_Adr        : std_logic_vector(24 downto 0);
   signal ram_cntDMA     : std_logic_vector(1 downto 0);
   signal ram_be         : std_logic_vector(3 downto 0);
   signal ram_rnw, ram_ena, ram_dma, ram_cache, ram_done, ram_refresh : std_logic;
   signal ram_dmafifo_adr : std_logic_vector(22 downto 0);
   signal ram_dmafifo_data : std_logic_vector(31 downto 0);
   signal ram_dmafifo_empty, ram_dmafifo_read : std_logic;
   signal cache_wr       : std_logic_vector(3 downto 0);
   signal cache_data     : std_logic_vector(31 downto 0);
   signal cache_addr     : std_logic_vector(7 downto 0);
   signal dma_wr, dma_reqprocessed : std_logic;
   signal dma_data       : std_logic_vector(31 downto 0);
   signal ram_addr27     : std_logic_vector(26 downto 0);

   -- VRAM
   signal ddr_busy, ddr_rd, ddr_we, ddr_dout_ready : std_logic;
   signal ddr_burstcnt   : std_logic_vector(7 downto 0);
   signal ddr_addr       : std_logic_vector(28 downto 0);
   signal ddr_dout, ddr_din : std_logic_vector(63 downto 0);
   signal ddr_be         : std_logic_vector(7 downto 0);
   signal aux_done, card_write : std_logic;
   signal aux_dout       : std_logic_vector(31 downto 0);
   type tcram is record
      a : std_logic_vector(21 downto 16); dq_out, dq_in : std_logic_vector(15 downto 0); dq_oe : std_logic;
      clk, adv_n, cre, ce0_n, ce1_n, oe_n, we_n, ub_n, lb_n : std_logic;
   end record;
   signal c0, c1 : tcram;
   signal dq0, dq1 : std_logic_vector(15 downto 0);

   -- SPU RAM
   signal spu_dataWrite, spu_dataRead : std_logic_vector(31 downto 0) := (others => '0');
   signal spu_Adr        : std_logic_vector(18 downto 0);
   signal spu_be         : std_logic_vector(3 downto 0);
   signal spu_rnw, spu_ena : std_logic;
   signal spu_done       : std_logic := '0';

   -- CD
   signal cd_hps_req     : std_logic;
   signal cd_hps_lba     : std_logic_vector(31 downto 0);

   -- video / sound
   signal hsync, vsync, hblank, vblank, video_ce, video_interlace : std_logic;
   signal video_r, video_g, video_b : std_logic_vector(7 downto 0);
   signal video_hResMode : std_logic_vector(2 downto 0);
   signal snd_l, snd_r   : std_logic_vector(15 downto 0);

   -- statistics (written by their own processes, read by the reporter)
   signal frames, nonblack_frames : integer := 0;
   signal spu_accesses, sound_nonzero, vram_writes, dma_reads, cd_reqs : integer := 0;
   signal cycles : integer := 0;
   signal core_debug : std_logic_vector(255 downto 0);
   signal preload_shell : std_logic := '0';
   signal ddr_rd_cnt, ddr_rdy_cnt : integer := 0;
   signal ddr_last_addr : std_logic_vector(28 downto 0) := (others => '0');

begin

   ---------------------------------------------------------------- clocks / reset
   process
      variable n : integer := 0;
   begin
      while not done loop
         wait for TICK;
         n := n + 1;
         if (n mod 2 = 0) then clk3x <= not clk3x; end if;
         if (n mod 3 = 0) then clk2x <= not clk2x; end if;
         if (n mod 6 = 0) then clk1x <= not clk1x; end if;
         if (n = 12 * 1000) then n := 0; end if;
      end loop;
      wait;
   end process;
   clkvid <= not clkvid after 9312 ps when not done;

   process (clk1x)
   begin
      if rising_edge(clk1x) then
         cycles <= cycles + 1;
         if (cycles = 200) then reset <= '0'; end if;
      end if;
   end process;
   process (clk2x)
   begin
      if rising_edge(clk2x) then
         if (cycles > 20) then reset2x <= '0'; end if;
      end if;
   end process;

   ---------------------------------------------------------------- the core
   idut : entity work.psx_pocket_core
   port map
   (
      clk1x => clk1x, clk2x => clk2x, clk3x => clk3x, clkvid => clkvid, reset => reset, isPaused => open,
      ram_refresh => ram_refresh, ram_dataWrite => ram_dataWrite, ram_dataRead32 => ram_dataRead32, ram_Adr => ram_Adr,
      ram_cntDMA => ram_cntDMA, ram_be => ram_be, ram_rnw => ram_rnw, ram_ena => ram_ena, ram_dma => ram_dma,
      ram_cache => ram_cache, ram_done => ram_done,
      ram_dmafifo_adr => ram_dmafifo_adr, ram_dmafifo_data => ram_dmafifo_data, ram_dmafifo_empty => ram_dmafifo_empty,
      ram_dmafifo_read => ram_dmafifo_read,
      cache_wr => cache_wr, cache_data => cache_data, cache_addr => cache_addr,
      dma_wr => dma_wr, dma_reqprocessed => dma_reqprocessed, dma_data => dma_data,
      DDRAM_BUSY => ddr_busy, DDRAM_BURSTCNT => ddr_burstcnt, DDRAM_ADDR => ddr_addr, DDRAM_DOUT => ddr_dout,
      DDRAM_DOUT_READY => ddr_dout_ready, DDRAM_RD => ddr_rd, DDRAM_DIN => ddr_din, DDRAM_BE => ddr_be, DDRAM_WE => ddr_we,
      hasCD => '0',
      trackinfo_data => (others => '0'), trackinfo_addr => (others => '0'), trackinfo_write => '0',
      resetFromCD => open,
      cd_hps_req => cd_hps_req, cd_hps_lba => cd_hps_lba, cd_hps_ack => '0', cd_hps_write => '0',
      cd_hps_data => (others => '0'),
      spuram_dataWrite => spu_dataWrite, spuram_Adr => spu_Adr, spuram_be => spu_be, spuram_rnw => spu_rnw,
      spuram_ena => spu_ena, spuram_dataRead => spu_dataRead, spuram_done => spu_done,
      memcard_changed => open, saving_memcard => open,
      memcard1_load => '0', memcard_save => '0', memcard1_mounted => '0', memcard1_available => '1',
      memcard1_rd => open, memcard1_wr => open, memcard1_lba => open, memcard1_ack => '0', memcard1_write => '0',
      memcard1_addr => (others => '0'), memcard1_dataIn => (others => '0'), memcard1_dataOut => open,
      hsync => hsync, vsync => vsync, hblank => hblank, vblank => vblank, video_ce => video_ce,
      video_interlace => video_interlace, video_r => video_r, video_g => video_g, video_b => video_b,
      video_hResMode => video_hResMode,
      KeyTriangle => '0', KeyCircle => '0', KeyCross => '0', KeySquare => '0', KeySelect => '0', KeyStart => '0',
      KeyRight => '0', KeyLeft => '0', KeyUp => '0', KeyDown => '0', KeyR1 => '0', KeyR2 => '0', KeyR3 => '0',
      KeyL1 => '0', KeyL2 => '0', KeyL3 => '0',
      sound_out_left => snd_l, sound_out_right => snd_r, debug_out => core_debug
   );

   ---------------------------------------------------------------- main RAM / BIOS
   ram_addr27 <= "00" & ram_Adr;
   iram : entity work.ram_model
   generic map (FAST_SHELL => FAST_SHELL, SKIP_INTRO => SKIP_INTRO)
   port map
   (
      clk => clk1x, clk3x => clk3x, addr => ram_addr27, req => ram_ena, ram_dma => ram_dma, ram_dmacnt => ram_cntDMA,
      ram_iscache => ram_cache, rnw => ram_rnw, be => ram_be, di => ram_dataWrite, do32 => ram_dataRead32,
      done => ram_done, cache_wr => cache_wr, cache_data => cache_data, cache_addr => cache_addr,
      dma_wr => dma_wr, dma_data => dma_data, reqprocessed => dma_reqprocessed,
      ram_dmafifo_adr => ram_dmafifo_adr, ram_dmafifo_data => ram_dmafifo_data, ram_dmafifo_empty => ram_dmafifo_empty,
      ram_dmafifo_read => ram_dmafifo_read, preload_shell => preload_shell
   );
   preload_shell <= '1' when (core_debug(255 downto 224) = x"BFC0700C") else '0';   -- CPU PC (debug_out row 8)

   ---------------------------------------------------------------- SPU RAM (sdram.sv ch3: request pulse, one ready pulse later)
   process (clk1x)
      type tspu is array(0 to 2 ** 19 - 1) of natural range 0 to 255;
      variable mem : tspu := (others => 0);
      variable cnt : integer := -1;
      variable a   : integer;
      variable w   : boolean;
   begin
      if rising_edge(clk1x) then
         spu_done <= '0';
         if (spu_ena = '1') then
            a   := to_integer(unsigned(spu_Adr));
            w   := spu_rnw = '0';
            cnt := 6;
            if w then
               for i in 0 to 3 loop
                  if (spu_be(i) = '1') then mem((a + i) mod 2 ** 19) := to_integer(unsigned(spu_dataWrite(i * 8 + 7 downto i * 8))); end if;
               end loop;
            end if;
            spu_accesses <= spu_accesses + 1;
         elsif (cnt > 0) then
            cnt := cnt - 1;
         elsif (cnt = 0) then
            cnt := -1;
            spu_done <= '1';
            for i in 0 to 3 loop
               spu_dataRead(i * 8 + 7 downto i * 8) <= std_logic_vector(to_unsigned(mem((a + i) mod 2 ** 19), 8));
            end loop;
         end if;
      end if;
   end process;

   ---------------------------------------------------------------- VRAM / memory card in PSRAM
   ivram : entity work.vram_psram
   generic map (CLOCK_SPEED => 67.7376)
   port map (clk => clk2x, reset => reset2x, ddr_busy => ddr_busy, ddr_burstcnt => ddr_burstcnt, ddr_addr => ddr_addr(24 downto 0),
             ddr_dout => ddr_dout, ddr_dout_ready => ddr_dout_ready, ddr_rd => ddr_rd, ddr_din => ddr_din, ddr_be => ddr_be,
             ddr_we => ddr_we, aux_req => '0', aux_we => '0', aux_addr => (others => '0'), aux_din => (others => '0'),
             aux_dout => aux_dout, aux_done => aux_done, card_write => card_write,
             cram0_a => c0.a, cram0_dq_out => c0.dq_out, cram0_dq_oe => c0.dq_oe, cram0_dq_in => c0.dq_in, cram0_clk => c0.clk,
             cram0_adv_n => c0.adv_n, cram0_cre => c0.cre, cram0_ce0_n => c0.ce0_n, cram0_ce1_n => c0.ce1_n, cram0_oe_n => c0.oe_n,
             cram0_we_n => c0.we_n, cram0_ub_n => c0.ub_n, cram0_lb_n => c0.lb_n,
             cram1_a => c1.a, cram1_dq_out => c1.dq_out, cram1_dq_oe => c1.dq_oe, cram1_dq_in => c1.dq_in, cram1_clk => c1.clk,
             cram1_adv_n => c1.adv_n, cram1_cre => c1.cre, cram1_ce0_n => c1.ce0_n, cram1_ce1_n => c1.ce1_n, cram1_oe_n => c1.oe_n,
             cram1_we_n => c1.we_n, cram1_ub_n => c1.ub_n, cram1_lb_n => c1.lb_n);
   dq0 <= c0.dq_out when c0.dq_oe = '1' else (others => 'Z');
   dq1 <= c1.dq_out when c1.dq_oe = '1' else (others => 'Z');
   c0.dq_in <= dq0;
   c1.dq_in <= dq1;
   im0 : entity work.psram_model generic map (INIT => '0')
      port map (a => c0.a, dq => dq0, clk => c0.clk, cre => c0.cre, adv_n => c0.adv_n, ce0_n => c0.ce0_n, ce1_n => c0.ce1_n, oe_n => c0.oe_n, we_n => c0.we_n, ub_n => c0.ub_n, lb_n => c0.lb_n);
   im1 : entity work.psram_model generic map (INIT => '0')
      port map (a => c1.a, dq => dq1, clk => c1.clk, cre => c1.cre, adv_n => c1.adv_n, ce0_n => c1.ce0_n, ce1_n => c1.ce1_n, oe_n => c1.oe_n, we_n => c1.we_n, ub_n => c1.ub_n, lb_n => c1.lb_n);

   ---------------------------------------------------------------- activity counters
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         if (snd_l /= x"0000" or snd_r /= x"0000") then sound_nonzero <= sound_nonzero + 1; end if;
         if (ram_ena = '1' and ram_dma = '1') then dma_reads <= dma_reads + 1; end if;
         if (cd_hps_req = '1') then cd_reqs <= cd_reqs + 1; end if;
      end if;
   end process;
   process (clk2x)
   begin
      if rising_edge(clk2x) then
         if (ddr_we = '1' and ddr_busy = '0') then vram_writes <= vram_writes + 1; end if;
         if (ddr_rd = '1' and ddr_busy = '0') then ddr_rd_cnt <= ddr_rd_cnt + 1; ddr_last_addr <= ddr_addr; end if;
         if (ddr_dout_ready = '1') then ddr_rdy_cnt <= ddr_rdy_cnt + 1; end if;
      end if;
   end process;

   ---------------------------------------------------------------- CD-ROM / GP1 register write log
   process (clk1x)
      alias pc       is <<signal .tb_boot.idut.ipsx.ipsx_top.icpu.PC : unsigned(31 downto 0)>>;
      alias cd_wr    is <<signal .tb_boot.idut.ipsx.ipsx_top.imemorymux.bus_cd_write : std_logic>>;
      alias cd_addr  is <<signal .tb_boot.idut.ipsx.ipsx_top.imemorymux.bus_cd_addr : unsigned(3 downto 0)>>;
      alias cd_data  is <<signal .tb_boot.idut.ipsx.ipsx_top.imemorymux.bus_cd_dataWrite : std_logic_vector(7 downto 0)>>;
      alias gpu_wr   is <<signal .tb_boot.idut.ipsx.ipsx_top.imemorymux.bus_gpu_write : std_logic>>;
      alias gpu_addr is <<signal .tb_boot.idut.ipsx.ipsx_top.imemorymux.bus_gpu_addr : unsigned(3 downto 0)>>;
      alias gpu_data is <<signal .tb_boot.idut.ipsx.ipsx_top.imemorymux.bus_gpu_dataWrite : std_logic_vector(31 downto 0)>>;
      variable n : integer := 0;
      variable l : line;
   begin
      if rising_edge(clk1x) then
         if (n < LOG_IO) then
            if (cd_wr = '1') then
               write(l, string'("IO cyc ")); write(l, cycles); write(l, string'(" pc ")); hwrite(l, std_logic_vector(pc));
               write(l, string'(" CD reg ")); write(l, to_integer(cd_addr)); write(l, string'(" <= ")); hwrite(l, cd_data);
               writeline(output, l); flush(output);
               n := n + 1;
            end if;
            if (gpu_wr = '1' and gpu_addr(2) = '1') then
               write(l, string'("IO cyc ")); write(l, cycles); write(l, string'(" pc ")); hwrite(l, std_logic_vector(pc));
               write(l, string'(" GP1 <= ")); hwrite(l, gpu_data);
               writeline(output, l); flush(output);
               n := n + 1;
            end if;
         end if;
      end if;
   end process;

   ---------------------------------------------------------------- picture capture (clkvid)
   process (clkvid)
      type tframe is array(0 to 1023, 0 to 511) of std_logic_vector(23 downto 0);
      variable fb       : tframe;
      variable x, y     : integer := 0;
      variable maxx     : integer := 0;
      variable hb_1, vb_1 : std_logic := '1';
      variable nb       : boolean := false;
      variable f        : integer := 0;
      file pf           : text;
      variable l        : line;
      variable st       : file_open_status;
      variable name     : string(1 to 14);
      variable img      : string(1 to 4);
   begin
      if rising_edge(clkvid) then
         if (video_ce = '1' and hblank = '0' and vblank = '0') then
            if (x < 1024 and y < 512) then fb(x, y) := video_r & video_g & video_b; end if;
            if (video_r /= x"00" or video_g /= x"00" or video_b /= x"00") then nb := true; end if;
            x := x + 1;
            if (x > maxx) then maxx := x; end if;
         end if;
         if (hblank = '1' and hb_1 = '0') then
            if (x > 0) then y := y + 1; end if;
            x := 0;
         end if;
         if (vblank = '1' and vb_1 = '0') then
            f := f + 1;
            frames <= f;
            if nb then nonblack_frames <= nonblack_frames + 1; end if;
            if (DUMP_EVERY > 0 and f mod DUMP_EVERY = 0 and y > 0 and maxx > 0) then
               img := integer'image(10000 + f)(2 to 5);
               name := "frame_" & img & ".ppm";
               file_open(st, pf, name, write_mode);
               write(l, string'("P3 ")); write(l, maxx); write(l, string'(" ")); write(l, y); write(l, string'(" 255"));
               writeline(pf, l);
               for j in 0 to y - 1 loop
                  for i in 0 to maxx - 1 loop
                     write(l, to_integer(unsigned(fb(i, j)(23 downto 16)))); write(l, character'(' '));
                     write(l, to_integer(unsigned(fb(i, j)(15 downto 8))));  write(l, character'(' '));
                     write(l, to_integer(unsigned(fb(i, j)(7 downto 0))));   write(l, character'(' '));
                  end loop;
                  writeline(pf, l);
               end loop;
               file_close(pf);
               write(l, string'("wrote ")); write(l, name); write(l, string'(" ")); write(l, maxx); write(l, character'('x')); write(l, y);
               if nb then write(l, string'(" (not black)")); else write(l, string'(" (black)")); end if;
               writeline(output, l); flush(output);
            end if;
            y := 0; x := 0; maxx := 0; nb := false;
         end if;
         hb_1 := hblank;
         vb_1 := vblank;
      end if;
   end process;

   ---------------------------------------------------------------- CPU I/O register access trace
   gtrace : if TRACE_IO_N > 0 generate
      process (clk1x)
         alias pc     is <<signal .tb_boot.idut.ipsx.ipsx_top.icpu.PC : unsigned(31 downto 0)>>;
         alias m_req  is <<signal .tb_boot.idut.ipsx.ipsx_top.imemorymux.mem_in_request : std_logic>>;
         alias m_data is <<signal .tb_boot.idut.ipsx.ipsx_top.imemorymux.mem_in_isData : std_logic>>;
         alias m_rnw  is <<signal .tb_boot.idut.ipsx.ipsx_top.imemorymux.mem_in_rnw : std_logic>>;
         alias m_addr is <<signal .tb_boot.idut.ipsx.ipsx_top.imemorymux.mem_in_addressData : unsigned(31 downto 0)>>;
         alias m_wd   is <<signal .tb_boot.idut.ipsx.ipsx_top.imemorymux.mem_in_dataWrite : std_logic_vector(31 downto 0)>>;
         alias m_done is <<signal .tb_boot.idut.ipsx.ipsx_top.imemorymux.mem_done : std_logic>>;
         alias m_rd   is <<signal .tb_boot.idut.ipsx.ipsx_top.imemorymux.mem_dataRead : std_logic_vector(31 downto 0)>>;
         variable n : integer := 0;
         variable pend : boolean := false;
         variable l : line;
         variable last_a : unsigned(31 downto 0) := (others => '1');
         variable rep_n : integer := 0;
      begin
         if rising_edge(clk1x) then
            if (pend and m_done = '1') then
               write(l, string'(" -> ")); hwrite(l, m_rd); writeline(output, l); flush(output);
               pend := false;
            end if;
            -- also the shell's GPU queue indices (head 80079298, tail 8007929C)
            if (n < TRACE_IO_N and now >= TRACE_FROM_MS * 1 ms and m_req = '1' and m_data = '1' and m_rnw = '0' and
                (m_addr = x"80079298" or m_addr = x"8007929C")) then
               if pend then writeline(output, l); pend := false; end if;
               write(l, string'("QUE cyc ")); write(l, cycles); write(l, string'(" pc ")); hwrite(l, std_logic_vector(pc));
               write(l, string'(" W ")); hwrite(l, std_logic_vector(m_addr)); write(l, string'(" <= ")); hwrite(l, m_wd);
               writeline(output, l); flush(output);
               n := n + 1;
            end if;
            if (n < TRACE_IO_N and now >= TRACE_FROM_MS * 1 ms and m_req = '1' and m_data = '1' and m_addr(28 downto 16) = to_unsigned(16#1F80#, 13)) then
               -- collapse polling: same address read again is counted, printed every 256 repeats
               if (m_rnw = '1' and m_addr = last_a) then
                  rep_n := rep_n + 1;
               else
                  rep_n := 0;
               end if;
               if (rep_n mod 256 = 0) then
                  if pend then writeline(output, l); end if;
                  write(l, string'("IOT cyc ")); write(l, cycles); write(l, string'(" pc ")); hwrite(l, std_logic_vector(pc));
                  if (m_rnw = '1') then write(l, string'(" R ")); else write(l, string'(" W ")); end if;
                  hwrite(l, std_logic_vector(m_addr));
                  if (rep_n > 0) then write(l, string'(" x")); write(l, rep_n); end if;
                  if (m_rnw = '0') then
                     write(l, string'(" <= ")); hwrite(l, m_wd); writeline(output, l); flush(output);
                  else
                     pend := true;
                  end if;
                  n := n + 1;
               end if;
               last_a := m_addr;
            end if;
         end if;
      end process;
   end generate;

   ---------------------------------------------------------------- reset sequence handshake (debug)
   gdbg : if DEBUG_SS > 0 generate
      process (clk1x)
         alias i_gpu  is <<signal .tb_boot.idut.ipsx.ipsx_top.SS_Idle_gpu : std_logic>>;
         alias i_mdec is <<signal .tb_boot.idut.ipsx.ipsx_top.SS_Idle_mdec : std_logic>>;
         alias i_cd   is <<signal .tb_boot.idut.ipsx.ipsx_top.SS_Idle_cd : std_logic>>;
         alias i_spu  is <<signal .tb_boot.idut.ipsx.ipsx_top.SS_idle_spu : std_logic>>;
         alias i_pad  is <<signal .tb_boot.idut.ipsx.ipsx_top.SS_idle_pad : std_logic>>;
         alias i_irq  is <<signal .tb_boot.idut.ipsx.ipsx_top.SS_idle_irq : std_logic>>;
         alias i_cpu  is <<signal .tb_boot.idut.ipsx.ipsx_top.SS_idle_cpu : std_logic>>;
         alias i_gte  is <<signal .tb_boot.idut.ipsx.ipsx_top.SS_idle_gte : std_logic>>;
         alias i_dma  is <<signal .tb_boot.idut.ipsx.ipsx_top.SS_idle_dma : std_logic>>;
         alias p_ing  is <<signal .tb_boot.idut.ipsx.ipsx_top.pausing : std_logic>>;
         alias p_ss   is <<signal .tb_boot.idut.ipsx.ipsx_top.savestate_pause : std_logic>>;
         alias r_int  is <<signal .tb_boot.idut.ipsx.ipsx_top.reset_intern : std_logic>>;
         alias ss_typ is <<signal .tb_boot.idut.ipsx.ipsx_top.isavestates.savetype_counter : integer>>;
         alias ss_cnt is <<signal .tb_boot.idut.ipsx.ipsx_top.isavestates.count : integer>>;
         alias ss_req is <<signal .tb_boot.idut.ipsx.ipsx_top.isavestates.SS_SPURAM_request : std_logic>>;
         alias ss_dn  is <<signal .tb_boot.idut.ipsx.ipsx_top.isavestates.SS_SPURAM_done : std_logic>>;
         alias ss_sdd is <<signal .tb_boot.idut.ipsx.ipsx_top.isavestates.sdram_done : std_logic>>;
         alias ss_wr  is <<signal .tb_boot.idut.ipsx.ipsx_top.isavestates.SS_wren : std_logic_vector(16 downto 0)>>;
         variable l : line;
         variable k : integer := 0;
      begin
         if rising_edge(clk1x) then
            k := k + 1;
            if (k mod DEBUG_SS = 0) then
               write(l, string'("SS cyc ")); write(l, k);
               write(l, string'(" idle gpu/mdec/cd/spu/pad/irq/cpu/gte/dma "));
               write(l, i_gpu); write(l, i_mdec); write(l, i_cd); write(l, i_spu); write(l, i_pad); write(l, i_irq);
               write(l, i_cpu); write(l, i_gte); write(l, i_dma);
               write(l, string'(" pausing ")); write(l, p_ing); write(l, string'(" ss_pause ")); write(l, p_ss);
               write(l, string'(" reset_intern ")); write(l, r_int);
               write(l, string'(" ddr rd ")); write(l, ddr_rd_cnt); write(l, string'(" rdy ")); write(l, ddr_rdy_cnt);
               write(l, string'(" last ")); hwrite(l, ddr_last_addr); write(l, string'(" busy ")); write(l, ddr_busy);
               write(l, string'(" rd ")); write(l, ddr_rd); write(l, string'(" vramwr ")); write(l, vram_writes);
               write(l, string'(" spu ")); write(l, spu_accesses);
               write(l, string'(" | ss type ")); write(l, ss_typ); write(l, string'(" count ")); write(l, ss_cnt);
               write(l, string'(" spureq ")); write(l, ss_req); write(l, string'(" spudone ")); write(l, ss_dn);
               write(l, string'(" sdram_done ")); write(l, ss_sdd); write(l, string'(" wren ")); write(l, ss_wr);
               writeline(output, l); flush(output);
            end if;
         end if;
      end process;
   end generate;

   ---------------------------------------------------------------- progress reports, end
   process (clk1x)
      alias pc     is <<signal .tb_boot.idut.ipsx.ipsx_top.icpu.PC : unsigned(31 downto 0)>>;
      alias dispoff is <<signal .tb_boot.idut.ipsx.ipsx_top.igpu.GPUSTAT_DisplayDisable : std_logic>>;
      alias m_req   is <<signal .tb_boot.idut.ipsx.ipsx_top.imemorymux.mem_in_request : std_logic>>;
      alias m_data  is <<signal .tb_boot.idut.ipsx.ipsx_top.imemorymux.mem_in_isData : std_logic>>;
      alias m_rnw   is <<signal .tb_boot.idut.ipsx.ipsx_top.imemorymux.mem_in_rnw : std_logic>>;
      alias m_addr  is <<signal .tb_boot.idut.ipsx.ipsx_top.imemorymux.mem_in_addressData : unsigned(31 downto 0)>>;
      type tlast is array(0 to 7) of unsigned(31 downto 0);
      variable last_a : tlast := (others => (others => '0'));
      variable last_p : tlast := (others => (others => '0'));
      variable last_r : std_logic_vector(0 to 7) := (others => '0');
      variable li     : integer := 0;
      variable pmin, pmax : unsigned(31 downto 0) := (others => '0');
      variable first : boolean := true;
      variable l : line;
      variable k : integer := 0;
   begin
      if rising_edge(clk1x) then
         k := k + 1;
         -- last 8 CPU data accesses (address, read/write, PC)
         if (m_req = '1' and m_data = '1') then
            last_a(li) := m_addr; last_p(li) := pc; last_r(li) := m_rnw;
            li := (li + 1) mod 8;
         end if;
         if (k mod 64 = 0 and reset = '0') then
            if first then pmin := pc; pmax := pc; first := false; end if;
            if (pc < pmin) then pmin := pc; end if;
            if (pc > pmax) then pmax := pc; end if;
         end if;
         if (k mod REPORT_CYCLES = 0) then
            write(l, string'("t=")); write(l, now / 1 ms); write(l, string'(" ms pc ")); hwrite(l, std_logic_vector(pc));
            write(l, string'(" range ")); hwrite(l, std_logic_vector(pmin)); write(l, character'('-')); hwrite(l, std_logic_vector(pmax));
            write(l, string'(" frames ")); write(l, frames); write(l, string'(" nonblack ")); write(l, nonblack_frames);
            write(l, string'(" dispoff ")); write(l, dispoff); write(l, string'(" il ")); write(l, video_interlace);
            write(l, string'(" hres ")); write(l, video_hResMode);
            write(l, string'(" vramwr ")); write(l, vram_writes); write(l, string'(" spu ")); write(l, spu_accesses);
            write(l, string'(" snd ")); write(l, sound_nonzero); write(l, string'(" dma ")); write(l, dma_reads);
            write(l, string'(" cdreq ")); write(l, cd_reqs);
            writeline(output, l);
            write(l, string'("   debug_out: flips ")); hwrite(l, core_debug(31 downto 0));
            write(l, string'(" vbusy ")); hwrite(l, core_debug(63 downto 32));
            write(l, string'(" vid ")); hwrite(l, core_debug(95 downto 64));
            write(l, string'(" rd ")); hwrite(l, core_debug(127 downto 96));
            write(l, string'(" gbusy ")); hwrite(l, core_debug(159 downto 128));
            write(l, string'(" cstall ")); hwrite(l, core_debug(191 downto 160));
            write(l, string'(" zero ")); hwrite(l, core_debug(223 downto 192));
            write(l, string'(" pc ")); hwrite(l, core_debug(255 downto 224));
            writeline(output, l);
            write(l, string'("   last data accesses:"));
            for i in 0 to 7 loop
               write(l, character'(' '));
               if (last_r((li + i) mod 8) = '1') then write(l, character'('R')); else write(l, character'('W')); end if;
               hwrite(l, std_logic_vector(last_a((li + i) mod 8))); write(l, character'('@'));
               hwrite(l, std_logic_vector(last_p((li + i) mod 8)));
            end loop;
            writeline(output, l); flush(output);
            first := true;
         end if;
         if (now > RUN_MS * 1 ms) then
            report "END";
            done <= true;
            std.env.finish;
         end if;
      end if;
   end process;

end architecture;
