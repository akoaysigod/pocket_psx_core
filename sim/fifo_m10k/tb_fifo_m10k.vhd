-- Equivalence of SyncFifoFallThroughMLAB with M10K => true (RamM10Kn) against M10K => false (RamMLAB),
-- configured as memorymux's write fifo (8 x 70). Random Wr / Rd / Din / reset from rising-edge logic;
-- every output is compared on every rising edge.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

library mem;

entity tb_fifo_m10k is
   generic
   (
      NUM_CYCLES : integer := 200000;
      SEED       : integer := 1
   );
end entity;

architecture sim of tb_fifo_m10k is

   constant W : integer := 70;

   signal clk   : std_logic := '1';
   signal reset : std_logic := '1';
   signal Din   : std_logic_vector(W - 1 downto 0) := (others => '0');
   signal Wr    : std_logic := '0';
   signal Rd    : std_logic := '0';

   signal a_Full, a_NearFull, a_Empty, a_NearEmpty : std_logic;
   signal b_Full, b_NearFull, b_Empty, b_NearEmpty : std_logic;
   signal a_Dout, b_Dout : std_logic_vector(W - 1 downto 0);

   signal done : boolean := false;

begin

   clk <= not clk after 15 ns when not done;

   ia : entity mem.SyncFifoFallThroughMLAB
   generic map (SIZE => 8, DATAWIDTH => W, NEARFULLDISTANCE => 4, NEAREMPTYDISTANCE => 2, M10K => false)
   port map (clk => clk, reset => reset, Din => Din, Wr => Wr, Full => a_Full, NearFull => a_NearFull,
             Dout => a_Dout, Rd => Rd, Empty => a_Empty, NearEmpty => a_NearEmpty);

   ib : entity mem.SyncFifoFallThroughMLAB
   generic map (SIZE => 8, DATAWIDTH => W, NEARFULLDISTANCE => 4, NEAREMPTYDISTANCE => 2, M10K => true)
   port map (clk => clk, reset => reset, Din => Din, Wr => Wr, Full => b_Full, NearFull => b_NearFull,
             Dout => b_Dout, Rd => Rd, Empty => b_Empty, NearEmpty => b_NearEmpty);

   process
      variable s1, s2   : positive;
      variable r        : real;
      variable errors   : integer := 0;
      variable writes   : integer := 0;
      variable reads    : integer := 0;
      variable fulls    : integer := 0;
      variable wrprob   : real := 0.5;
      variable rdprob   : real := 0.5;
      variable l        : line;
   begin
      s1 := SEED; s2 := SEED * 7 + 3;
      for c in 0 to NUM_CYCLES - 1 loop
         wait until rising_edge(clk);
         -- compare what both fifos present at this edge (the consumer samples here)
         if (a_Empty /= b_Empty or a_Full /= b_Full or a_NearFull /= b_NearFull or a_NearEmpty /= b_NearEmpty or
             (a_Empty = '0' and a_Dout /= b_Dout)) then
            errors := errors + 1;
            if (errors <= 10) then
               write(l, string'("MISMATCH cycle ") & integer'image(c)); writeline(output, l);
            end if;
         end if;
         if (a_Empty = '0' and Rd = '1') then reads := reads + 1; end if;
         if (a_Full = '1') then fulls := fulls + 1; end if;
         -- next inputs (driven just after the edge, like rising-edge logic)
         wait for 1 ns;
         uniform(s1, s2, r);
         if (c mod 997 = 0) then   -- phases: bursts of writes, bursts of reads, mixed
            uniform(s1, s2, wrprob); uniform(s1, s2, rdprob);
         end if;
         reset <= '0';
         if (c < 4) then reset <= '1'; elsif (r < 0.0005) then reset <= '1'; end if;
         uniform(s1, s2, r);
         -- like memorymux: never write when full, read only when not empty
         if (r < wrprob and a_Full = '0') then Wr <= '1'; writes := writes + 1; else Wr <= '0'; end if;
         uniform(s1, s2, r);
         if (r < rdprob and a_Empty = '0') then Rd <= '1'; else Rd <= '0'; end if;
         for i in 0 to W - 1 loop
            uniform(s1, s2, r);
            if (r < 0.5) then Din(i) <= '1'; else Din(i) <= '0'; end if;
         end loop;
      end loop;
      write(l, string'("DONE cycles=") & integer'image(NUM_CYCLES) & string'(" writes=") & integer'image(writes) &
               string'(" reads=") & integer'image(reads) & string'(" fullcycles=") & integer'image(fulls) &
               string'(" errors=") & integer'image(errors));
      writeline(output, l);
      if (errors = 0) then write(l, string'("PASS")); else write(l, string'("FAIL")); end if;
      writeline(output, l);
      done <= true;
      wait;
   end process;

end architecture;
