-- Equivalence test: gte_small against the reference gte (renamed gte_ref).
-- Both get identical random register writes, commands and ce stalls; gte_busy
-- is compared every clk2x cycle and all 64 registers are read back and
-- compared after each command.
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use STD.textio.all;

entity tb_gte_equiv is
   generic
   (
      NUM_TESTS : integer := 20000;
      SEED      : integer := 1
   );
end entity;

architecture sim of tb_gte_equiv is

   signal clk1x          : std_logic := '1';
   signal clk2x          : std_logic := '1';
   signal clk1xToggle    : std_logic := '0';
   signal clk1xToggle2x  : std_logic := '0';
   signal clk2xIndex     : std_logic := '0';
   signal ce             : std_logic := '1';
   signal reset          : std_logic := '1';

   signal readAddr       : unsigned(5 downto 0) := (others => '0');
   signal readEna        : std_logic := '0';
   signal writeAddr      : unsigned(5 downto 0) := (others => '0');
   signal writeData      : unsigned(31 downto 0) := (others => '0');
   signal writeEna       : std_logic := '0';
   signal cmdData        : unsigned(31 downto 0) := (others => '0');
   signal cmdEna         : std_logic := '0';

   signal busy_ref       : std_logic;
   signal busy_new       : std_logic;
   signal readData_ref   : unsigned(31 downto 0);
   signal readData_new   : unsigned(31 downto 0);
   signal readMismatches : integer := 0;
   signal mixedCycles    : integer := 0;

   signal busyMismatches : integer := 0;

   type tops is array(0 to 21) of integer;
   constant OPS : tops := (16#01#, 16#06#, 16#0C#, 16#10#, 16#11#, 16#12#, 16#13#, 16#14#, 16#16#, 16#1B#, 16#1C#,
                           16#1E#, 16#20#, 16#28#, 16#29#, 16#2A#, 16#2D#, 16#2E#, 16#30#, 16#3D#, 16#3E#, 16#3F#);

begin

   clk2x <= not clk2x after 5 ns;
   clk1x <= not clk1x after 10 ns;

   process (clk1x)
   begin
      if rising_edge(clk1x) then
         clk1xToggle <= not clk1xToggle;
      end if;
   end process;

   process (clk2x)
   begin
      if rising_edge(clk2x) then
         clk1xToggle2x <= clk1xToggle;
         clk2xIndex    <= '0';
         if (clk1xToggle2x = clk1xToggle) then
            clk2xIndex <= '1';
         end if;
      end if;
   end process;

   iref : entity work.gte_ref
   port map
   (
      clk1x             => clk1x,
      clk2x             => clk2x,
      clk2xIndex        => clk2xIndex,
      ce                => ce,
      reset             => reset,
      WIDESCREEN        => "00",
      TURBO             => '0',
      gte_busy          => busy_ref,
      gte_readAddr      => readAddr,
      gte_readData      => readData_ref,
      gte_readEna       => readEna,
      gte_writeAddr_in  => writeAddr,
      gte_writeData_in  => writeData,
      gte_writeEna_in   => writeEna,
      gte_cmdData       => cmdData,
      gte_cmdEna        => cmdEna,
      loading_savestate => '0',
      SS_reset          => '0',
      SS_DataWrite      => (others => '0'),
      SS_Adr            => (others => '0'),
      SS_wren           => '0',
      SS_rden           => '0',
      SS_DataRead       => open,
      SS_idle           => open,
      debug_firstGTE    => open
   );

   inew : entity work.gte_small
   port map
   (
      clk1x             => clk1x,
      clk2x             => clk2x,
      clk2xIndex        => clk2xIndex,
      ce                => ce,
      reset             => reset,
      WIDESCREEN        => "00",
      TURBO             => '0',
      gte_busy          => busy_new,
      gte_readAddr      => readAddr,
      gte_readData      => readData_new,
      gte_readEna       => readEna,
      gte_writeAddr_in  => writeAddr,
      gte_writeData_in  => writeData,
      gte_writeEna_in   => writeEna,
      gte_cmdData       => cmdData,
      gte_cmdEna        => cmdEna,
      loading_savestate => '0',
      SS_reset          => '0',
      SS_DataWrite      => (others => '0'),
      SS_Adr            => (others => '0'),
      SS_wren           => '0',
      SS_rden           => '0',
      SS_DataRead       => open,
      SS_idle           => open,
      debug_firstGTE    => open
   );

   -- cycle-exact busy comparison
   process (clk2x)
   begin
      if rising_edge(clk2x) then
         if (reset = '0' and busy_ref /= busy_new) then
            if (busyMismatches < 10) then
               report "busy mismatch at " & time'image(now) severity error;
            end if;
            busyMismatches <= busyMismatches + 1;
         end if;
         -- readback output compared every cycle, not only after a read (the reference output is
         -- undefined until its first read; hardware powers up with it at 0)
         if (not is_x(std_logic_vector(readData_ref)) and readData_ref /= readData_new) then
            if (readMismatches < 10) then
               report "readData mismatch at " & time'image(now) & " ref " & to_hstring(std_logic_vector(readData_ref))
                      & " new " & to_hstring(std_logic_vector(readData_new)) severity error;
            end if;
            readMismatches <= readMismatches + 1;
         end if;
      end if;
   end process;

   stim : process
      variable s1, s2      : positive;
      variable r           : real;
      variable errors      : integer := 0;
      variable opcount     : integer := 0;
      variable l           : line;
      variable val         : unsigned(31 downto 0);
      variable op          : integer;
      variable mode        : integer;

      impure function rnd(n : integer) return integer is
      begin
         uniform(s1, s2, r);
         return integer(trunc(r * real(n)));
      end function;

      impure function rnd32 return unsigned is
      begin
         return to_unsigned(rnd(65536), 16) & to_unsigned(rnd(65536), 16);
      end function;

      -- register values: mix of full random, small signed and fixed-point-ish
      impure function rndval return unsigned is
         variable v : unsigned(31 downto 0);
         variable k : integer;
      begin
         k := rnd(4);
         if (k = 0) then
            v := rnd32;
         elsif (k = 1) then
            v := unsigned(to_signed(rnd(2048) - 1024, 16)) & unsigned(to_signed(rnd(2048) - 1024, 16));
         elsif (k = 2) then
            v := unsigned(to_signed(rnd(16384) - 8192, 16)) & unsigned(to_signed(rnd(16384) - 8192, 16));
         else
            v := unsigned(to_signed(rnd(8192) - 4096, 32));
         end if;
         return v;
      end function;

      procedure tick1x(n : integer := 1) is
      begin
         for i in 1 to n loop
            wait until rising_edge(clk1x);
         end loop;
      end procedure;

   begin
      s1 := SEED; s2 := 7919;
      reset <= '1';
      tick1x(4);
      reset <= '0';
      tick1x(2);

      for t in 0 to NUM_TESTS - 1 loop

         -- occasional reset in the middle of the run
         if (rnd(64) = 0) then
            reset <= '1';
            tick1x(1 + rnd(3));
            reset <= '0';
            tick1x;
         end if;

         -- interleaved register traffic: reads right after writes, reads and writes of the
         -- same register in the same cycle, back-to-back reads
         if (rnd(2) = 0) then
            for c in 0 to 20 + rnd(40) loop
               writeEna <= '0'; readEna <= '0';
               if (rnd(2) = 0) then
                  writeAddr <= to_unsigned(rnd(64), 6);
                  writeData <= rndval;
                  writeEna  <= '1';
               end if;
               if (rnd(2) = 0) then
                  if (rnd(3) = 0) then readAddr <= writeAddr; else readAddr <= to_unsigned(rnd(64), 6); end if;
                  readEna <= '1';
               end if;
               mixedCycles <= mixedCycles + 1;
               tick1x;
            end loop;
            writeEna <= '0'; readEna <= '0';
            tick1x;
         end if;

         -- register writes (skip some so state carries between commands)
         for a in 0 to 63 loop
            if (rnd(4) /= 0) then
               writeAddr <= to_unsigned(a, 6);
               writeData <= rndval;
               writeEna  <= '1';
               tick1x;
               writeEna  <= '0';
            end if;
         end loop;

         -- command: random op with random sf/mx/v/cv/lm bits
         op := OPS(rnd(OPS'length));
         val := rnd32;
         val(5 downto 0) := to_unsigned(op, 6);
         cmdData <= val;
         cmdEna  <= '1';
         tick1x;
         cmdEna  <= '0';
         opcount := opcount + 1;

         -- run with random ce stalls until both are idle
         tick1x;
         while (busy_ref = '1' or busy_new = '1') loop
            if (rnd(8) = 0) then ce <= '0'; else ce <= '1'; end if;
            tick1x;
         end loop;
         ce <= '1';
         tick1x(2);

         -- read back and compare all registers
         for a in 0 to 63 loop
            readAddr <= to_unsigned(a, 6);
            readEna  <= '1';
            tick1x;
            readEna  <= '0';
            tick1x;
            if (readData_ref /= readData_new) then
               errors := errors + 1;
               if (errors <= 20) then
                  write(l, string'("MISMATCH test ") & integer'image(t) & string'(" cmd ") & to_hstring(std_logic_vector(cmdData))
                        & string'(" reg ") & integer'image(a) & string'(" ref ") & to_hstring(std_logic_vector(readData_ref))
                        & string'(" new ") & to_hstring(std_logic_vector(readData_new)));
                  writeline(output, l);
               end if;
            end if;
         end loop;

      end loop;

      write(l, string'("DONE tests=") & integer'image(opcount) & string'(" register_mismatches=") & integer'image(errors)
            & string'(" busy_mismatch_cycles=") & integer'image(busyMismatches)
            & string'(" readData_mismatch_cycles=") & integer'image(readMismatches) & string'(" mixed_rw_cycles=") & integer'image(mixedCycles));
      writeline(output, l);
      if (errors = 0 and busyMismatches = 0 and readMismatches = 0) then
         write(l, string'("PASS")); writeline(output, l);
      else
         write(l, string'("FAIL")); writeline(output, l);
      end if;
      std.env.finish;
   end process;

end architecture;
