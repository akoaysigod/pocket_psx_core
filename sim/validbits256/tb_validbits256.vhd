-- Component equivalence: rtl/ValidBits256.vhd against 256 plain flip-flops with the same set / clear-all /
-- combinational-read behaviour (the texture cache valid bits in gpu_pixelpipeline). Random sets (biased to
-- few groups so words fill up), rare clears, a random read address every cycle plus full sweeps.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_validbits256 is
   generic (NUM_CYCLES : integer := 1000000; SEED : integer := 1);
end entity;

architecture sim of tb_validbits256 is
   signal clk      : std_logic := '0';
   signal clearAll : std_logic := '0';
   signal setEna   : std_logic := '0';
   signal setAddr  : unsigned(7 downto 0) := (others => '0');
   signal rdAddr   : unsigned(7 downto 0) := (others => '0');
   signal q        : std_logic;
   signal ref      : std_logic_vector(0 to 255) := (others => '0');
   signal done     : boolean := false;
begin
   clk <= not clk after 5 ns when not done;

   idut : entity work.ValidBits256
   port map (clk => clk, clearAll => clearAll, setEna => setEna, setAddr => setAddr, rdAddr => rdAddr, q => q);

   -- reference: exactly the original tagValid code shape
   process (clk)
   begin
      if rising_edge(clk) then
         if (setEna = '1') then ref(to_integer(setAddr)) <= '1'; end if;
         if (clearAll = '1') then ref <= (others => '0'); end if;
      end if;
   end process;

   process
      variable s1 : positive := 3 + SEED;
      variable s2 : positive := 99991;
      variable r  : real;
      variable errors, checks, clears, sets : integer := 0;
      variable grp : integer := 0;
      impure function rnd(n : integer) return integer is begin uniform(s1, s2, r); return integer(trunc(r * real(n))); end function;
   begin
      for c in 1 to NUM_CYCLES loop
         -- inputs for the coming edge
         clearAll <= '0'; setEna <= '0';
         if rnd(400) = 0 then clearAll <= '1'; clears := clears + 1; end if;
         if rnd(1000) = 0 then grp := rnd(16); end if;
         if rnd(3) /= 0 then
            setEna <= '1'; sets := sets + 1;
            if rnd(4) /= 0 then setAddr <= to_unsigned(grp * 16 + rnd(16), 8); else setAddr <= to_unsigned(rnd(256), 8); end if;
         end if;
         if (c mod 5000) < 256 then
            rdAddr <= to_unsigned(c mod 5000, 8);                      -- full sweep
         elsif rnd(2) = 0 then
            rdAddr <= to_unsigned(grp * 16 + rnd(16), 8);
         else
            rdAddr <= to_unsigned(rnd(256), 8);
         end if;
         wait until rising_edge(clk);
         wait for 1 ns;
         checks := checks + 1;
         if (q /= ref(to_integer(rdAddr))) then
            errors := errors + 1;
            if errors <= 10 then report "mismatch at cycle " & integer'image(c) & " addr " & integer'image(to_integer(rdAddr)) severity warning; end if;
         end if;
      end loop;
      report "DONE cycles=" & integer'image(NUM_CYCLES) & " sets=" & integer'image(sets) & " clears=" & integer'image(clears) & " errors=" & integer'image(errors);
      if errors = 0 then report "PASS"; else report "FAIL"; end if;
      done <= true;
      wait;
   end process;
end architecture;
