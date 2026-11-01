-- pocket_psx save states, with a stub PSX core (run.sh): APF (clk_74a) writes the save-state routine's data slot,
-- loads a state (bridge writes into the window 0x50000000.., then the load command 0xA4), and saves one (0xA0, then
-- reads of the window like APF: the data of a read is the word fetched by the previous read's bridge_rd). Checks:
--  * the core is held in reset from the first window write, restarts in restore mode, the load ends "ok"
--  * every window write reaches SDRAM channel 3 at its mapped address (main RAM, SPU RAM, state block) or PSRAM
--    (VRAM, read back by the save); writes outside the mapped parts are dropped
--  * the save pauses the core, reads come from SDRAM channel 3 (written words, else the model's pattern) and PSRAM,
--    the read of the last word releases the core, the save ends "ok"
--  * savestate_supported from the start; before the routine's slot a save is refused (no ss_req) and a load ends
--    with an error and lets the core boot
--  * a wake: the state written and the load asked for with the core in reset ends "ok" before APF releases the
--    reset, the routine runs after it; a save asked for meanwhile is refused (acked)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_pocket_ss is
end entity;

architecture sim of tb_pocket_ss is

   constant TICK : time := 2460500 fs;   -- clk1x / 12 (as pocket/sim/boot)
   signal clk1x, clk2x, clk3x : std_logic := '1';
   signal clk_74a, clkvid, clkpix : std_logic := '0';
   signal done : boolean := false;

   signal reset_n_74a, loading_74a : std_logic := '0';
   signal bridge_addr, bridge_wr_data, rd_data : std_logic_vector(31 downto 0) := (others => '0');
   signal bridge_wr, bridge_rd : std_logic := '0';
   signal ss_supported, ss_start, ss_start_ack, ss_start_busy, ss_start_ok, ss_start_err : std_logic := '0';
   signal ss_load, ss_load_ack, ss_load_busy, ss_load_ok, ss_load_err : std_logic := '0';

   -- SDRAM channel 3
   signal ch3_addr : std_logic_vector(26 downto 0);
   signal ch3_din, ch3_dout : std_logic_vector(31 downto 0) := (others => '0');
   signal ch3_be : std_logic_vector(3 downto 0);
   signal ch3_req, ch3_rnw : std_logic;
   signal ch3_ready : std_logic := '0';
   signal ch3_reads : integer := 0;

   type tcram is record
      a : std_logic_vector(21 downto 16); dq_out, dq_in : std_logic_vector(15 downto 0); dq_oe : std_logic;
      clk, adv_n, cre, ce0_n, ce1_n, oe_n, we_n, ub_n, lb_n : std_logic;
   end record;
   signal c0, c1 : tcram;
   signal dq0, dq1 : std_logic_vector(15 downto 0);

   -- SDRAM model: words written through channel 3, direct mapped by word address mod 4093 (tag = the whole address;
   -- the test addresses do not collide); other words read as pattern(address)
   constant SDN : integer := 4093;
   type tdata is array(0 to SDN - 1) of std_logic_vector(31 downto 0);
   type ttag is array(0 to SDN - 1) of integer;
   shared variable sd_data : tdata;
   shared variable sd_tag  : ttag := (others => -1);

   function pattern(w : integer) return std_logic_vector is
   begin
      return std_logic_vector(to_unsigned(((w mod 65536) * 31 + 12345) mod 65536, 16) & to_unsigned(w mod 65536, 16));
   end function;

   function sdram_word(byteaddr : integer) return integer is begin return byteaddr / 4; end function;

   -- window test words: (window offset, SDRAM byte address or -1 = VRAM, -2 = not mapped)
   type tcase is record off : integer; sd : integer; end record;
   type tcases is array(natural range <>) of tcase;
   constant CASES : tcases := (
      (16#000000#, 16#0000000#), (16#000004#, 16#0000004#), (16#1FFFFC#, 16#01FFFFC#),   -- main RAM
      (16#200000#, 16#1000000#), (16#27FFFC#, 16#107FFFC#),                             -- SPU RAM
      (16#280000#, 16#0220000#), (16#29FFFC#, 16#023FFFC#),                             -- state block
      (16#2A0000#, -2),                                                                 -- unused
      (16#300000#, -1), (16#300004#, -1), (16#3FFFF8#, -1)                               -- VRAM
   );

   function wdata(i : integer) return std_logic_vector is
   begin
      return std_logic_vector(to_unsigned(16#C0DE0000# / 65536, 16) & to_unsigned(i * 4097 + 1, 16));
   end function;

   signal errors : integer := 0;
   signal resets_seen : integer := 0;
   signal reqs_seen : integer := 0;

begin

   -- clocks: clk1x / clk2x / clk3x edge aligned (one PLL), clk_74a and clkvid unrelated
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
   clk_74a <= not clk_74a after 6734 ps when not done;
   clkvid  <= not clkvid after 9312 ps when not done;
   process (clkvid) begin if rising_edge(clkvid) then clkpix <= not clkpix; end if; end process;

   dut : entity work.pocket_psx
   port map
   (
      clk_74a => clk_74a, clk1x => clk1x, clk2x => clk2x, clk3x => clk3x, clkvid => clkvid, clkpix => clkpix,
      reset_n_74a => reset_n_74a, pll_locked => '1', loading_74a => loading_74a,
      bridge_addr => bridge_addr, bridge_wr => bridge_wr, bridge_wr_data => bridge_wr_data, bridge_rd => bridge_rd,
      memcard_rd_data => rd_data,
      datatable_addr => open, datatable_q => (others => '0'), datatable_wren => open, datatable_data => open,
      dsr_read => open, dsr_id => open, dsr_offset => open, dsr_bridgeaddr => open, dsr_length => open, dsr_done => '0',
      cont1_key => (others => '0'), loader_overflow => open,
      ss_supported => ss_supported, ss_start => ss_start, ss_start_ack => ss_start_ack, ss_start_busy => ss_start_busy,
      ss_start_ok => ss_start_ok, ss_start_err => ss_start_err, ss_load => ss_load, ss_load_ack => ss_load_ack,
      ss_load_busy => ss_load_busy, ss_load_ok => ss_load_ok, ss_load_err => ss_load_err,
      sdram_init => open, ram_refresh => open, ram_addr => open, ram_din => open, ram_be => open, ram_rd_req => open,
      ram_wr_req => open, ram_dma => open, ram_cntDMA => open, ram_cache => open, ram_dout32 => (others => '0'),
      ram_rd_ready => '0', ram_wr_ready => '0', cache_wr => (others => '0'), cache_data => (others => '0'),
      cache_addr => (others => '0'), dma_wr => '0', dma_reqprocessed => '0', dma_data => (others => '0'),
      dmafifo_adr => open, dmafifo_data => open, dmafifo_empty => open, dmafifo_read => '0',
      ch3_addr => ch3_addr, ch3_din => ch3_din, ch3_be => ch3_be, ch3_req => ch3_req, ch3_rnw => ch3_rnw,
      ch3_dout => ch3_dout, ch3_ready => ch3_ready,
      cram0_a => c0.a, cram0_dq_out => c0.dq_out, cram0_dq_oe => c0.dq_oe, cram0_dq_in => c0.dq_in, cram0_clk => c0.clk,
      cram0_adv_n => c0.adv_n, cram0_cre => c0.cre, cram0_ce0_n => c0.ce0_n, cram0_ce1_n => c0.ce1_n, cram0_oe_n => c0.oe_n,
      cram0_we_n => c0.we_n, cram0_ub_n => c0.ub_n, cram0_lb_n => c0.lb_n,
      cram1_a => c1.a, cram1_dq_out => c1.dq_out, cram1_dq_oe => c1.dq_oe, cram1_dq_in => c1.dq_in, cram1_clk => c1.clk,
      cram1_adv_n => c1.adv_n, cram1_cre => c1.cre, cram1_ce0_n => c1.ce0_n, cram1_ce1_n => c1.ce1_n, cram1_oe_n => c1.oe_n,
      cram1_we_n => c1.we_n, cram1_ub_n => c1.ub_n, cram1_lb_n => c1.lb_n,
      video_rgb => open, video_de => open, video_skip => open, video_vs => open, video_hs => open,
      audio_lrck => '0', sound_left => open, sound_right => open
   );
   dq0 <= c0.dq_out when c0.dq_oe = '1' else (others => 'Z');
   dq1 <= c1.dq_out when c1.dq_oe = '1' else (others => 'Z');
   c0.dq_in <= dq0;
   c1.dq_in <= dq1;
   im0 : entity work.psram_model generic map (INIT => '0')
      port map (a => c0.a, dq => dq0, clk => c0.clk, cre => c0.cre, adv_n => c0.adv_n, ce0_n => c0.ce0_n, ce1_n => c0.ce1_n, oe_n => c0.oe_n, we_n => c0.we_n, ub_n => c0.ub_n, lb_n => c0.lb_n);
   im1 : entity work.psram_model generic map (INIT => '0')
      port map (a => c1.a, dq => dq1, clk => c1.clk, cre => c1.cre, adv_n => c1.adv_n, ce0_n => c1.ce0_n, ce1_n => c1.ce1_n, oe_n => c1.oe_n, we_n => c1.we_n, ub_n => c1.ub_n, lb_n => c1.lb_n);

   -- SDRAM channel 3 (sdram.sv: a request per ch3_req pulse, one ch3_ready pulse later); reads only while the core
   -- is frozen for a save (the stub core makes no SPU RAM requests)
   process (clk1x)
      alias ss_frozen is <<signal .tb_pocket_ss.dut.ss_frozen : std_logic>>;
      variable cnt : integer := -1;
      variable w   : integer;
      variable rw  : integer := 0;
   begin
      if rising_edge(clk1x) then
         ch3_ready <= '0';
         if (ch3_req = '1') then
            w   := to_integer(unsigned(ch3_addr(26 downto 2)));
            cnt := 6;
            if (ch3_rnw = '0') then
               assert ch3_be = "1111" report "ch3 write with byte enables " & to_hstring(ch3_be) severity error;
               sd_data(w mod SDN) := ch3_din;
               sd_tag(w mod SDN)  := w;
               report "ch3 write " & to_hstring(unsigned(ch3_addr)) & " <= " & to_hstring(ch3_din);
            else
               assert ss_frozen = '1' report "ch3 read while the core is not frozen" severity error;
               rw := w;
               ch3_reads <= ch3_reads + 1;
            end if;
         elsif (cnt > 0) then
            cnt := cnt - 1;
         elsif (cnt = 0) then
            cnt := -1;
            ch3_ready <= '1';
            if (sd_tag(rw mod SDN) = rw) then ch3_dout <= sd_data(rw mod SDN); else ch3_dout <= pattern(rw); end if;
         end if;
      end if;
   end process;

   -- rising edges of the core's reset (none may come during a save)
   process
      alias psx_reset is <<signal .tb_pocket_ss.dut.psx_reset : std_logic>>;
   begin
      wait until rising_edge(psx_reset);
      resets_seen <= resets_seen + 1;
   end process;

   -- save requests to the core (rising edges of ss_req)
   process
      alias ss_req is <<signal .tb_pocket_ss.dut.ss_req : std_logic>>;
   begin
      wait until rising_edge(ss_req);
      reqs_seen <= reqs_seen + 1;
   end process;

   -- APF
   process
      alias psx_reset  is <<signal .tb_pocket_ss.dut.psx_reset : std_logic>>;
      alias ss_restore is <<signal .tb_pocket_ss.dut.ss_restore : std_logic>>;
      alias ss_frozen  is <<signal .tb_pocket_ss.dut.ss_frozen : std_logic>>;
      alias ss_released is <<signal .tb_pocket_ss.dut.ss_released : std_logic>>;
      alias ss_hold_reset is <<signal .tb_pocket_ss.dut.ss_hold_reset : std_logic>>;
      variable e    : integer := 0;
      variable got  : std_logic_vector(31 downto 0);
      variable exp  : std_logic_vector(31 downto 0);
      variable prev : integer;
      variable w    : integer;
      variable seen_restore : boolean := false;
      variable r0   : integer := 0;

      procedure clocks(n : integer) is
      begin
         for i in 1 to n loop wait until rising_edge(clk_74a); end loop;
      end procedure;
      procedure bwrite(a : integer; d : std_logic_vector(31 downto 0)) is
      begin
         bridge_addr    <= std_logic_vector(to_unsigned(a, 32));
         bridge_wr_data <= d;
         bridge_wr      <= '1';
         clocks(1);
         bridge_wr      <= '0';
         clocks(80);                          -- APF: about a word every 80 clocks
      end procedure;
      procedure check(cond : boolean; msg : string) is
      begin
         if not cond then
            report msg severity error;
            e := e + 1;
         end if;
      end procedure;
      procedure wait_for(signal s : std_logic; v : std_logic; maxclk : integer; msg : string) is
      begin
         for i in 1 to maxclk loop
            exit when s = v;
            wait until rising_edge(clk_74a);
         end loop;
         check(s = v, msg);
      end procedure;
   begin
      -------------------------------------------------------------- before the routine's slot
      clocks(20);
      check(ss_supported = '1', "savestate_supported not set from the start");
      ss_start <= '1';
      wait_for(ss_start_ack, '1', 1000, "save without the routine: no ack");
      ss_start <= '0';
      wait_for(ss_start_err, '1', 1000, "save without the routine: no error");
      check(reqs_seen = 0, "save without the routine: ss_req raised");
      bwrite(16#50100000#, x"BAD0BAD0");
      ss_load <= '1';
      wait_for(ss_load_ack, '1', 1000, "load without the routine: no ack");
      ss_load <= '0';
      wait_for(ss_load_err, '1', 1000, "load without the routine: no error");
      clocks(10);
      check(ss_hold_reset = '0' and ss_restore = '0', "load without the routine: core still held / in restore mode");

      -- APF loads the data slots with the core in reset: the save-state routine (slot 3, 0x10000000)
      loading_74a <= '1';
      clocks(20);
      for i in 0 to 7 loop
         bwrite(16#10000000# + 4 * i, x"2400" & std_logic_vector(to_unsigned(i, 16)));   -- addiu zero, zero, i
      end loop;
      loading_74a <= '0';
      clocks(200);
      reset_n_74a <= '1';
      wait until psx_reset = '0' for 2 ms;
      check(psx_reset = '0', "the core did not leave reset");
      check(ss_supported = '1', "savestate_supported not set after the routine's slot");
      for i in 0 to 7 loop
         w := 16#200000# / 4 + i;
         check(sd_tag(w mod SDN) = w and sd_data(w mod SDN) = x"2400" & std_logic_vector(to_unsigned(i, 16)),
               "routine word " & integer'image(i) & " not at SDRAM 0x200000");
      end loop;
      clocks(500);

      -------------------------------------------------------------- load
      report "load: writing the window";
      for i in CASES'range loop
         bwrite(16#50000000# + CASES(i).off, wdata(i));
         if (i = 0) then
            clocks(10);
            check(psx_reset = '1', "load: the first window write did not hold the core in reset");
         end if;
      end loop;
      ss_load <= '1';
      wait_for(ss_load_ack, '1', 1000, "load: no ack");
      ss_load <= '0';
      for i in 1 to 200000 loop
         wait until rising_edge(clk_74a);
         if (psx_reset = '0' and ss_restore = '1') then seen_restore := true; end if;
         exit when ss_load_ok = '1' or ss_load_err = '1';
      end loop;
      check(ss_load_ok = '1' and ss_load_err = '0', "load: did not end ok");
      check(seen_restore, "load: the core did not restart in restore mode");
      for i in CASES'range loop
         if (CASES(i).sd >= 0) then
            w := CASES(i).sd / 4;
            check(sd_tag(w mod SDN) = w and sd_data(w mod SDN) = wdata(i),
                  "load: window offset " & to_hstring(to_unsigned(CASES(i).off, 24)) & " not at SDRAM " &
                  to_hstring(to_unsigned(CASES(i).sd, 28)));
         end if;
      end loop;
      w := 16#2A0000# / 4;
      check(sd_tag(w mod SDN) /= w, "load: a write to the unused part reached SDRAM");
      clocks(2000);

      -------------------------------------------------------------- save
      report "save: request";
      r0 := resets_seen;
      ss_start <= '1';
      wait_for(ss_start_ack, '1', 1000, "save: no ack");
      ss_start <= '0';
      for i in 1 to 200000 loop
         wait until rising_edge(clk_74a);
         exit when ss_start_ok = '1' or ss_start_err = '1';
      end loop;
      check(ss_start_ok = '1' and ss_start_err = '0', "save: not ok (frozen)");
      check(ss_frozen = '1', "save: ok but the core is not frozen");
      -- APF reads the window: the written words, an unwritten one (pattern), then the last word (releases the core)
      prev := -1;
      for i in CASES'range loop
         if (CASES(i).sd /= -2) then
            bridge_addr <= std_logic_vector(to_unsigned(16#50000000# + CASES(i).off, 32));
            clocks(4);
            got := rd_data;
            if (prev >= 0) then
               check(got = wdata(prev), "save: window offset " & to_hstring(to_unsigned(CASES(prev).off, 24)) &
                     " read " & to_hstring(got) & " expected " & to_hstring(wdata(prev)));
            end if;
            clocks(1);
            bridge_rd <= '1';
            clocks(1);
            bridge_rd <= '0';
            clocks(88);
            prev := i;
         end if;
      end loop;
      bridge_addr <= std_logic_vector(to_unsigned(16#50000008#, 32));          -- not written: pattern
      clocks(4);
      check(rd_data = wdata(prev), "save: last VRAM word read " & to_hstring(rd_data));
      clocks(1); bridge_rd <= '1'; clocks(1); bridge_rd <= '0'; clocks(88);
      check(ss_frozen = '1', "save: released before the last word");
      bridge_addr <= std_logic_vector(to_unsigned(16#503FFFFC#, 32));
      clocks(4);
      exp := pattern(2);
      check(rd_data = exp, "save: unwritten RAM word 8 read " & to_hstring(rd_data) & " expected " & to_hstring(exp));
      clocks(1); bridge_rd <= '1'; clocks(1); bridge_rd <= '0'; clocks(88);
      for i in 1 to 20000 loop
         wait until rising_edge(clk_74a);
         exit when ss_frozen = '0';
      end loop;
      check(ss_frozen = '0', "save: the read of the last word did not release the core");
      for i in 1 to 20000 loop
         wait until rising_edge(clk_74a);
         exit when ss_released = '0';
      end loop;
      check(ss_released = '0', "save: the routine's done did not end the save");
      check(resets_seen = r0, "save: the core was reset " & integer'image(resets_seen - r0) & " times during the save");
      clocks(5000);
      check(ss_start_err = '0', "save: error after the release");
      check(ch3_reads = 8, "save: " & integer'image(ch3_reads) & " SDRAM reads, expected 8");

      -------------------------------------------------------------- wake: load with the core in reset
      report "wake: APF holds the core in reset, writes the window, asks for the load";
      reset_n_74a <= '0';
      clocks(200);
      for i in CASES'range loop
         bwrite(16#50000000# + CASES(i).off, not wdata(i));
      end loop;
      ss_load <= '1';
      wait_for(ss_load_ack, '1', 1000, "wake: no ack");
      ss_load <= '0';
      for i in 1 to 200000 loop
         wait until rising_edge(clk_74a);
         exit when ss_load_ok = '1' or ss_load_err = '1';
      end loop;
      check(ss_load_ok = '1' and ss_load_err = '0', "wake: the load did not end ok with the core in reset");
      check(ss_restore = '1' and psx_reset = '1', "wake: not waiting in restore mode for the reset to end");
      ss_start <= '1';
      wait_for(ss_start_ack, '1', 1000, "wake: a save during the load was not acked");
      ss_start <= '0';
      wait_for(ss_start_err, '1', 1000, "wake: a save during the load was not refused");
      clocks(20000);
      check(ss_restore = '1', "wake: restore mode ended before the reset");
      reset_n_74a <= '1';
      for i in 1 to 200000 loop
         wait until rising_edge(clk_74a);
         exit when ss_restore = '0';
      end loop;
      check(ss_restore = '0' and psx_reset = '0', "wake: the routine did not run after the reset");
      check(ss_load_ok = '1' and ss_load_err = '0', "wake: the load did not stay ok");
      for i in CASES'range loop
         if (CASES(i).sd >= 0) then
            w := CASES(i).sd / 4;
            check(sd_tag(w mod SDN) = w and sd_data(w mod SDN) = not wdata(i),
                  "wake: window offset " & to_hstring(to_unsigned(CASES(i).off, 24)) & " not at SDRAM " &
                  to_hstring(to_unsigned(CASES(i).sd, 28)));
         end if;
      end loop;
      check(reqs_seen = 1, "wake: " & integer'image(reqs_seen) & " save requests to the core, expected 1");

      report "DONE errors=" & integer'image(e);
      if (e = 0) then report "PASS"; else report "FAIL"; end if;
      done <= true;
      wait;
   end process;

end architecture;
