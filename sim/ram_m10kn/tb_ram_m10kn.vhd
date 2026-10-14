-- Component equivalence: RamM10Kn (M10K on the falling edge) against RamMLAB. Inputs change only
-- just after rising edges (as from rising-edge logic); q is compared just before every rising edge,
-- the only time rising-edge logic samples it. Random writes, reads and same-address collisions.
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use STD.textio.all;

entity tb_ram_m10kn is
   generic (NUM_CYCLES : integer := 200000; SEED : integer := 1; WIDTH : integer := 24; WIDTHAD : integer := 8);
end entity;

architecture sim of tb_ram_m10kn is
   signal clk : std_logic := '0';
   signal wren : std_logic := '0';
   signal data : std_logic_vector(WIDTH-1 downto 0) := (others => '0');
   signal wraddress, rdaddress : std_logic_vector(WIDTHAD-1 downto 0) := (others => '0');
   signal q_ref, q_new : std_logic_vector(WIDTH-1 downto 0);
begin
   clk <= not clk after 15 ns;

   iref : entity work.RamMLAB generic map (width => WIDTH, widthad => WIDTHAD)
      port map (inclock => clk, wren => wren, data => data, wraddress => wraddress, rdaddress => rdaddress, q => q_ref);
   inew : entity work.RamM10Kn generic map (width => WIDTH, widthad => WIDTHAD)
      port map (inclock => clk, wren => wren, data => data, wraddress => wraddress, rdaddress => rdaddress, q => q_new);

   process
      variable s1 : positive := SEED; variable s2 : positive := 999;
      variable r : real; variable l : line;
      variable mism, compared, collisions : integer := 0;
      impure function rnd(n : integer) return integer is begin uniform(s1, s2, r); return integer(trunc(r * real(n))); end function;
   begin
      -- fill so every address holds defined data
      for a in 0 to 2**WIDTHAD - 1 loop
         wait until rising_edge(clk); wait for 1 ns;
         wren <= '1'; wraddress <= std_logic_vector(to_unsigned(a, WIDTHAD));
         data <= std_logic_vector(to_unsigned(rnd(2**16), 16)) & std_logic_vector(to_unsigned(rnd(2**(WIDTH-16)), WIDTH-16));
      end loop;
      wait until rising_edge(clk); wait for 1 ns; wren <= '0';
      for i in 1 to 4 loop wait until rising_edge(clk); end loop;

      for c in 0 to NUM_CYCLES - 1 loop
         -- compare just before the rising edge
         wait until falling_edge(clk); wait for 14 ns;
         if (not is_x(q_ref)) then
            compared := compared + 1;
            if (q_ref /= q_new) then
               mism := mism + 1;
               if (mism <= 10) then
                  write(l, string'("MISMATCH cycle ") & integer'image(c) & string'(" ref ") & to_hstring(q_ref) & string'(" new ") & to_hstring(q_new)); writeline(output, l);
               end if;
            end if;
         end if;
         wait until rising_edge(clk); wait for 1 ns;
         wren <= '0';
         if (rnd(2) = 0) then
            wren <= '1'; wraddress <= std_logic_vector(to_unsigned(rnd(2**WIDTHAD), WIDTHAD));
            data <= std_logic_vector(to_unsigned(rnd(2**16), 16)) & std_logic_vector(to_unsigned(rnd(2**(WIDTH-16)), WIDTH-16));
         end if;
         case rnd(4) is
            when 0 => rdaddress <= wraddress;                           -- same address as the write in flight
            when 1 => null;                                             -- keep reading the same address
            when others => rdaddress <= std_logic_vector(to_unsigned(rnd(2**WIDTHAD), WIDTHAD));
         end case;
         if (wren = '1' and rdaddress = wraddress) then collisions := collisions + 1; end if;
      end loop;
      write(l, string'("DONE compared=") & integer'image(compared) & string'(" mismatches=") & integer'image(mism)); writeline(output, l);
      if (mism = 0 and compared > 1000) then write(l, string'("PASS")); else write(l, string'("FAIL")); end if;
      writeline(output, l);
      std.env.finish;
   end process;
end architecture;
