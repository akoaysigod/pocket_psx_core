-- Equivalence test: rtl/memctrl.vhd (memctrl_new) against the upstream memctrl (memctrl_ref): random CPU
-- reads and writes on both register buses (never in the same clock, as memorymux decodes them), random ce
-- gaps and resets; every output is compared on every clock.
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity tb_memctrl is
   generic
   (
      NUM_CYCLES : integer := 200000;
      SEED       : integer := 1
   );
end entity;

architecture sim of tb_memctrl is

   signal clk1x          : std_logic := '1';
   signal ce             : std_logic := '1';
   signal reset          : std_logic := '1';
   signal bus_addr       : unsigned(5 downto 0) := (others => '0');
   signal bus_dataWrite  : std_logic_vector(31 downto 0) := (others => '0');
   signal bus_read       : std_logic := '0';
   signal bus_write      : std_logic := '0';
   signal bus2_addr      : unsigned(3 downto 0) := (others => '0');
   signal bus2_dataWrite : std_logic_vector(31 downto 0) := (others => '0');
   signal bus2_read      : std_logic := '0';
   signal bus2_write     : std_logic := '0';

   type tOut is record
      bus_dataRead, bus2_dataRead : std_logic_vector(31 downto 0);
      errorBuswidth : std_logic;
      spu, cd, bios, ex1, ex2, ex3 : unsigned(13 downto 0);
      com0, com1, com2, com3 : unsigned(3 downto 0);
      spuon : std_logic;
      spuval : unsigned(3 downto 0);
   end record;
   signal o_ref, o_new : tOut;

   signal mismatches : integer := 0;
   signal reads      : integer := 0;
   signal nonzero    : integer := 0;
   signal done       : boolean := false;

begin

   clk1x <= not clk1x after 5 ns when not done;

   gdut : for k in 0 to 1 generate
      signal o : tOut;
   begin
      gref : if k = 0 generate
         idut : entity work.memctrl_ref
         port map (clk1x => clk1x, ce => ce, reset => reset,
            bus_addr => bus_addr, bus_dataWrite => bus_dataWrite, bus_read => bus_read, bus_write => bus_write, bus_dataRead => o.bus_dataRead,
            bus2_addr => bus2_addr, bus2_dataWrite => bus2_dataWrite, bus2_read => bus2_read, bus2_write => bus2_write, bus2_dataRead => o.bus2_dataRead,
            errorBuswidth => o.errorBuswidth, spu_memctrl => o.spu, cd_memctrl => o.cd, bios_memctrl => o.bios, ex1_memctrl => o.ex1,
            ex2_memctrl => o.ex2, ex3_memctrl => o.ex3, com0_delay => o.com0, com1_delay => o.com1, com2_delay => o.com2, com3_delay => o.com3,
            dma_spu_timing_on => o.spuon, dma_spu_timing_value => o.spuval,
            loading_savestate => '0', SS_reset => '0', SS_DataWrite => (others => '0'), SS_Adr => (others => '0'), SS_wren => '0', SS_rden => '0', SS_DataRead => open);
         o_ref <= o;
      end generate;
      gnew : if k = 1 generate
         idut : entity work.memctrl_new
         port map (clk1x => clk1x, ce => ce, reset => reset,
            bus_addr => bus_addr, bus_dataWrite => bus_dataWrite, bus_read => bus_read, bus_write => bus_write, bus_dataRead => o.bus_dataRead,
            bus2_addr => bus2_addr, bus2_dataWrite => bus2_dataWrite, bus2_read => bus2_read, bus2_write => bus2_write, bus2_dataRead => o.bus2_dataRead,
            errorBuswidth => o.errorBuswidth, spu_memctrl => o.spu, cd_memctrl => o.cd, bios_memctrl => o.bios, ex1_memctrl => o.ex1,
            ex2_memctrl => o.ex2, ex3_memctrl => o.ex3, com0_delay => o.com0, com1_delay => o.com1, com2_delay => o.com2, com3_delay => o.com3,
            dma_spu_timing_on => o.spuon, dma_spu_timing_value => o.spuval,
            loading_savestate => '0', SS_reset => '0', SS_DataWrite => (others => '0'), SS_Adr => (others => '0'), SS_wren => '0', SS_rden => '0', SS_DataRead => open);
         o_new <= o;
      end generate;
   end generate;

   stim : process
      variable s1, s2 : positive;
      variable r : real;
      variable x : integer;
      impure function rnd(n : integer) return integer is
      begin
         uniform(s1, s2, r);
         return integer(floor(r * real(n)));
      end function;
      impure function rnd32 return std_logic_vector is
      begin
         return std_logic_vector(to_unsigned(rnd(65536), 16)) & std_logic_vector(to_unsigned(rnd(65536), 16));
      end function;
   begin
      s1 := SEED; s2 := SEED * 7 + 3;
      for c in 0 to NUM_CYCLES - 1 loop
         bus_read <= '0'; bus_write <= '0'; bus2_read <= '0'; bus2_write <= '0';
         reset <= '0';
         if (c < 4 or rnd(20000) = 0) then reset <= '1'; end if;
         ce <= '1';
         if (rnd(8) = 0) then ce <= '0'; end if;
         x := rnd(10);
         -- addresses: mostly aligned words 0-9, sometimes unaligned or out of range
         if (rnd(4) = 0) then bus_addr <= to_unsigned(rnd(64), 6); else bus_addr <= to_unsigned(rnd(10) * 4, 6); end if;
         if (rnd(4) = 0) then bus2_addr <= to_unsigned(rnd(16), 4); else bus2_addr <= "0000"; end if;
         bus_dataWrite  <= rnd32;
         bus2_dataWrite <= rnd32;
         case (x) is
            when 0 | 1 | 2 => bus_read   <= '1';
            when 3 | 4     => bus_write  <= '1';
            when 5         => bus2_read  <= '1';
            when 6         => bus2_write <= '1';
            when others    => null;
         end case;
         wait until rising_edge(clk1x);
      end loop;
      done <= true;
      wait for 20 ns;
      report "DONE cycles=" & integer'image(NUM_CYCLES) & " reads=" & integer'image(reads) & " nonzero_reads=" & integer'image(nonzero) & " mismatch_cycles=" & integer'image(mismatches);
      if (mismatches = 0) then report "PASS"; else report "FAIL"; end if;
      wait;
   end process;

   check : process (clk1x)
   begin
      if falling_edge(clk1x) then
         -- the reference's read registers are undefined until its first enabled clock after power-up
         if (o_ref /= o_new and not (is_x(o_ref.bus_dataRead) or is_x(o_ref.bus2_dataRead))) then
            if (mismatches < 10) then
               report "mismatch: ref " & to_hstring(o_ref.bus_dataRead) & " " & to_hstring(o_ref.bus2_dataRead) &
                      " new " & to_hstring(o_new.bus_dataRead) & " " & to_hstring(o_new.bus2_dataRead) severity warning;
            end if;
            mismatches <= mismatches + 1;
         end if;
         if (bus_read = '1' or bus2_read = '1') then reads <= reads + 1; end if;
         if (o_ref.bus_dataRead /= x"00000000" or o_ref.bus2_dataRead /= x"00000000") then nonzero <= nonzero + 1; end if;
      end if;
   end process;

end architecture;
