-- Equivalence test: savestates_reset (reset sequence only) against the original
-- savestates with save/load held off. A random environment answers the DDR3,
-- SDRAM, SPU RAM and pause handshakes; every output is compared every clk2x.
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use STD.textio.all;

entity tb_ss_equiv is
   generic
   (
      NUM_RESETS : integer := 3;
      FASTSIM    : std_logic := '0';
      SPUSDRAM   : std_logic := '1';
      SEED       : integer := 1
   );
end entity;

architecture sim of tb_ss_equiv is

   constant NTYPES : integer := 17;

   signal clk1x, clk2x     : std_logic := '1';
   signal clk1xToggle      : std_logic := '0';
   signal clk1xToggle2x    : std_logic := '0';
   signal clk2xIndex       : std_logic := '0';
   signal reset_in         : std_logic := '0';

   signal SS_idle          : std_logic := '1';
   signal system_paused    : std_logic := '0';
   signal hps_busy         : std_logic := '0';
   signal sdram_done       : std_logic := '0';
   signal ram_done         : std_logic := '0';
   signal ddr3_BUSY        : std_logic := '0';
   signal ddr3_DOUT        : std_logic_vector(63 downto 0) := (others => '0');
   signal ddr3_DOUT_READY  : std_logic := '0';
   signal SPURAM_done      : std_logic := '0';
   signal SPURAM_dataRead  : std_logic_vector(15 downto 0) := (others => '0');
   signal rnd_data         : std_logic_vector(31 downto 0) := (others => '0');

   type tout is record
      reset_out, ss_reset, load_done, savestate_busy, savestate_pause, ddr3_savestate : std_logic;
      loading_savestate, ddr3_WE, ddr3_RD, SPURAM_request, SPURAM_rnw : std_logic;
      validSStates : std_logic_vector(3 downto 0);
      SS_DataWrite : std_logic_vector(31 downto 0);
      SS_Adr       : unsigned(18 downto 0);
      SS_wren      : std_logic_vector(NTYPES - 1 downto 0);
      SS_rden      : std_logic_vector(NTYPES - 1 downto 0);
      ddr3_BURSTCNT, ddr3_BE : std_logic_vector(7 downto 0);
      ddr3_ADDR    : std_logic_vector(25 downto 0);
      ddr3_DIN     : std_logic_vector(63 downto 0);
      SPURAM_dataWrite : std_logic_vector(15 downto 0);
      SPURAM_Adr   : std_logic_vector(18 downto 0);
   end record;
   signal o_ref, o_new : tout;

   signal mismatches : integer := 0;
   signal resetsDone : integer := 0;
   signal wrenCount  : integer := 0;

begin

   clk2x <= not clk2x after 5 ns;
   clk1x <= not clk1x after 10 ns;

   process (clk1x) begin
      if rising_edge(clk1x) then clk1xToggle <= not clk1xToggle; end if;
   end process;
   process (clk2x) begin
      if rising_edge(clk2x) then
         clk1xToggle2x <= clk1xToggle;
         clk2xIndex <= '0';
         if (clk1xToggle2x = clk1xToggle) then clk2xIndex <= '1'; end if;
      end if;
   end process;

   gdut : for i in 0 to 1 generate
      signal o : tout;
   begin
      gref : if i = 0 generate
         idut : entity work.savestates_ref
         generic map (FASTSIM => FASTSIM, Softmap_SaveState_ADDR => 58720256)
         port map (clk1x => clk1x, clk2x => clk2x, clk2xIndex => clk2xIndex, ce => '1', reset_in => reset_in,
            reset_out => o.reset_out, ss_reset => o.ss_reset, hps_busy => hps_busy, loadExe => '0',
            load_done => o.load_done, validSStates => o.validSStates, savestate_number => 0,
            increaseSSHeaderCount => '0', save => '0', load => '0', savestate_address => 0,
            savestate_busy => o.savestate_busy, SS_idle => SS_idle, system_paused => system_paused,
            savestate_pause => o.savestate_pause, ddr3_savestate => o.ddr3_savestate, useSPUSDRAM => SPUSDRAM,
            SS_DataWrite => o.SS_DataWrite, SS_Adr => o.SS_Adr, SS_wren => o.SS_wren, SS_rden => o.SS_rden,
            SS_DataRead_CPU => rnd_data, SS_DataRead_GPU => rnd_data, SS_DataRead_GPUTiming => rnd_data,
            SS_DataRead_DMA => rnd_data, SS_DataRead_GTE => rnd_data, SS_DataRead_JOYPAD => rnd_data,
            SS_DataRead_MDEC => rnd_data, SS_DataRead_MEMORY => rnd_data, SS_DataRead_TIMER => rnd_data,
            SS_DataRead_SOUND => rnd_data, SS_DataRead_IRQ => rnd_data, SS_DataRead_SIO => rnd_data,
            SS_DataRead_SCP => rnd_data, SS_DataRead_CD => rnd_data, sdram_done => sdram_done,
            loading_savestate => o.loading_savestate, saving_savestate => open,
            ddr3_BUSY => ddr3_BUSY, ddr3_DOUT => ddr3_DOUT, ddr3_DOUT_READY => ddr3_DOUT_READY,
            ddr3_BURSTCNT => o.ddr3_BURSTCNT, ddr3_ADDR => o.ddr3_ADDR, ddr3_DIN => o.ddr3_DIN, ddr3_BE => o.ddr3_BE,
            ddr3_WE => o.ddr3_WE, ddr3_RD => o.ddr3_RD, ram_done => ram_done, ram_data => rnd_data,
            SS_SPURAM_dataWrite => o.SPURAM_dataWrite, SS_SPURAM_Adr => o.SPURAM_Adr,
            SS_SPURAM_request => o.SPURAM_request, SS_SPURAM_rnw => o.SPURAM_rnw,
            SS_SPURAM_dataRead => SPURAM_dataRead, SS_SPURAM_done => SPURAM_done);
         o_ref <= o;
      end generate;
      gnew : if i = 1 generate
         idut : entity work.savestates_new
         generic map (FASTSIM => FASTSIM, Softmap_SaveState_ADDR => 58720256)
         port map (clk1x => clk1x, clk2x => clk2x, clk2xIndex => clk2xIndex, ce => '1', reset_in => reset_in,
            reset_out => o.reset_out, ss_reset => o.ss_reset, hps_busy => hps_busy, loadExe => '0',
            load_done => o.load_done, validSStates => o.validSStates, savestate_number => 0,
            increaseSSHeaderCount => '0', save => '0', load => '0', savestate_address => 0,
            savestate_busy => o.savestate_busy, SS_idle => SS_idle, system_paused => system_paused,
            savestate_pause => o.savestate_pause, ddr3_savestate => o.ddr3_savestate, useSPUSDRAM => SPUSDRAM,
            SS_DataWrite => o.SS_DataWrite, SS_Adr => o.SS_Adr, SS_wren => o.SS_wren, SS_rden => o.SS_rden,
            SS_DataRead_CPU => rnd_data, SS_DataRead_GPU => rnd_data, SS_DataRead_GPUTiming => rnd_data,
            SS_DataRead_DMA => rnd_data, SS_DataRead_GTE => rnd_data, SS_DataRead_JOYPAD => rnd_data,
            SS_DataRead_MDEC => rnd_data, SS_DataRead_MEMORY => rnd_data, SS_DataRead_TIMER => rnd_data,
            SS_DataRead_SOUND => rnd_data, SS_DataRead_IRQ => rnd_data, SS_DataRead_SIO => rnd_data,
            SS_DataRead_SCP => rnd_data, SS_DataRead_CD => rnd_data, sdram_done => sdram_done,
            loading_savestate => o.loading_savestate, saving_savestate => open,
            ddr3_BUSY => ddr3_BUSY, ddr3_DOUT => ddr3_DOUT, ddr3_DOUT_READY => ddr3_DOUT_READY,
            ddr3_BURSTCNT => o.ddr3_BURSTCNT, ddr3_ADDR => o.ddr3_ADDR, ddr3_DIN => o.ddr3_DIN, ddr3_BE => o.ddr3_BE,
            ddr3_WE => o.ddr3_WE, ddr3_RD => o.ddr3_RD, ram_done => ram_done, ram_data => rnd_data,
            SS_SPURAM_dataWrite => o.SPURAM_dataWrite, SS_SPURAM_Adr => o.SPURAM_Adr,
            SS_SPURAM_request => o.SPURAM_request, SS_SPURAM_rnw => o.SPURAM_rnw,
            SS_SPURAM_dataRead => SPURAM_dataRead, SS_SPURAM_done => SPURAM_done);
         o_new <= o;
      end generate;
   end generate;

   -- random environment, driven from the reference's outputs
   env : process (clk2x)
      variable s1 : positive := SEED;
      variable s2 : positive := 31337;
      variable r  : real;
      variable rdPending, spuPending, wrPending : integer := -1;
      variable spuHold : integer := 0;
      impure function rnd(n : integer) return integer is
      begin
         uniform(s1, s2, r); return integer(trunc(r * real(n)));
      end function;
   begin
      if rising_edge(clk2x) then
         ddr3_DOUT_READY <= '0';
         SPURAM_done     <= '0';
         sdram_done      <= '0';
         ram_done        <= '0';
         if (rnd(4) = 0) then ddr3_BUSY <= '1'; else ddr3_BUSY <= '0'; end if;
         if (rnd(16) = 0) then SS_idle <= '0'; else SS_idle <= '1'; end if;
         if (o_ref.savestate_pause = '0') then
            system_paused <= '0';
         elsif (rnd(6) = 0) then
            system_paused <= '1';
         end if;
         rnd_data <= std_logic_vector(to_unsigned(rnd(65536), 16)) & std_logic_vector(to_unsigned(rnd(65536), 16));

         if (o_ref.ddr3_RD = '1' and ddr3_BUSY = '0') then rdPending := 1 + rnd(6); end if;
         if (rdPending = 0) then
            ddr3_DOUT_READY <= '1';
            ddr3_DOUT <= std_logic_vector(to_unsigned(rnd(65536), 16)) & std_logic_vector(to_unsigned(rnd(65536), 16)) &
                         std_logic_vector(to_unsigned(rnd(65536), 16)) & std_logic_vector(to_unsigned(rnd(65536), 16));
         end if;
         if (rdPending >= 0) then rdPending := rdPending - 1; end if;

         if (o_ref.SPURAM_request = '1') then spuPending := 1 + rnd(4); end if;
         -- the SPU answers in the clk1x domain: hold done for one full clk1x cycle (2 clk2x cycles)
         if (spuPending = 0) then SPURAM_done <= '1'; spuHold := 1; SPURAM_dataRead <= std_logic_vector(to_unsigned(rnd(65536), 16));
         elsif (spuHold = 1) then SPURAM_done <= '1'; spuHold := 0; end if;
         if (spuPending >= 0) then spuPending := spuPending - 1; end if;

         if (unsigned(o_ref.SS_wren) /= 0) then wrPending := 1 + rnd(4); end if;
         if (wrPending = 0) then sdram_done <= '1'; ram_done <= '1'; end if;
         if (wrPending >= 0) then wrPending := wrPending - 1; end if;
      end if;
   end process;

   cmp : process (clk2x)
      variable l : line;
   begin
      if rising_edge(clk2x) then
         if (o_ref /= o_new) then
            if (mismatches < 10) then
               write(l, string'("MISMATCH at ") & time'image(now)); writeline(output, l);
            end if;
            mismatches <= mismatches + 1;
         end if;
         if (unsigned(o_ref.SS_wren) /= 0) then wrenCount <= wrenCount + 1; end if;
      end if;
   end process;

   -- heartbeat so long runs can be monitored
   heartbeat : process
      variable l : line;
      alias stype is <<signal .tb_ss_equiv.gdut(0).gref.idut.savetype_counter : integer>>;
      alias scount is <<signal .tb_ss_equiv.gdut(0).gref.idut.count : integer>>;
   begin
      wait for 5 ms;
      write(l, string'("heartbeat ") & time'image(now) & string'(" SS_write_cycles=") & integer'image(wrenCount)
            & string'(" mismatches=") & integer'image(mismatches)
            & string'(" ref_savetype=") & integer'image(stype) & string'(" ref_count=") & integer'image(scount));
      writeline(output, l);
   end process;

   stim : process
      variable l : line;
      variable s1 : positive := SEED + 17;
      variable s2 : positive := 4711;
      variable r  : real;
   begin
      for n in 1 to NUM_RESETS loop
         write(l, string'("progress reset ") & integer'image(n) & string'(" start at ") & time'image(now)
               & string'(" SS_write_cycles=") & integer'image(wrenCount) & string'(" mismatches=") & integer'image(mismatches));
         writeline(output, l);
         reset_in <= '1';
         uniform(s1, s2, r);
         for i in 0 to 10 + integer(r * 200.0) loop wait until rising_edge(clk1x); end loop;
         reset_in <= '0';
         -- wait until the reset sequence has finished (or abort it early on odd runs)
         wait until rising_edge(clk1x) and o_ref.savestate_busy = '1';
         if (n mod 2 = 0) then
            uniform(s1, s2, r);
            for i in 0 to integer(r * 50000.0) loop wait until rising_edge(clk1x); end loop;
         else
            wait until rising_edge(clk1x) and o_ref.savestate_busy = '0';
         end if;
         for i in 0 to 100 loop wait until rising_edge(clk1x); end loop;
      end loop;
      write(l, string'("DONE resets=") & integer'image(NUM_RESETS) & string'(" SS_write_cycles=") & integer'image(wrenCount)
            & string'(" output_mismatch_cycles=") & integer'image(mismatches));
      writeline(output, l);
      if (mismatches = 0 and wrenCount > 0) then write(l, string'("PASS")); else write(l, string'("FAIL")); end if;
      writeline(output, l);
      std.env.finish;
   end process;

end architecture;
