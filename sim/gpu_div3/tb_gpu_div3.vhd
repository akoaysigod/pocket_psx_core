-- Equivalence test for the GPU divider sharing: the original gpu_poly/gpu_line with six dividers
-- against the Pocket version with three. Both get the same random command stream, each in its own
-- GPU environment with independent random stalls (setup now takes longer, so timing differs).
-- The ordered streams of output events (pixels, VRAM line reads, palette/draw-mode updates,
-- command done) must be identical.
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use STD.textio.all;
use work.pGpuDivTb.all;

entity tb_gpu_div3 is
   generic
   (
      MODULE   : integer := 0;
      NUM_CMDS : integer := 200;
      SEED     : integer := 1;
      SELFTEST : boolean := false   -- true: compare the original against itself (testbench sanity check)
   );
end entity;

architecture sim of tb_gpu_div3 is
   signal clk2x : std_logic := '1';
   signal reset : std_logic := '1';
   signal ev_valid_ref, ev_valid_new : std_logic_vector(5 downto 0);
   signal ev_ref, ev_new : t_ev_array;
   signal cmds_ref, cmds_new : integer;
   signal fin_ref, fin_new : std_logic;
begin
   clk2x <= not clk2x after 5 ns;
   reset <= '0' after 100 ns;

   iref : entity work.gpu_div_harness
   generic map (MODULE => MODULE, IS_NEW => false, NDIV => 6, NUM_CMDS => NUM_CMDS, SEED => SEED, ENVSEED => SEED + 1000)
   port map (clk2x => clk2x, reset => reset, ev_valid => ev_valid_ref, ev_data => ev_ref, cmds_done => cmds_ref, finished => fin_ref);

   inew : entity work.gpu_div_harness
   generic map (MODULE => MODULE, IS_NEW => not SELFTEST, NDIV => 3 + 3 * boolean'pos(SELFTEST), NUM_CMDS => NUM_CMDS, SEED => SEED, ENVSEED => SEED + 2000)
   port map (clk2x => clk2x, reset => reset, ev_valid => ev_valid_new, ev_data => ev_new, cmds_done => cmds_new, finished => fin_new);

   cmp : process (clk2x)
      constant QN : integer := 65536;  -- ref/new may drift apart by at most this many events per stream
      type t_q is array(0 to QN - 1) of std_logic_vector(127 downto 0);
      type t_qs is array(0 to 5) of t_q;
      type t_int6 is array(0 to 5) of integer;
      variable qref, qnew : t_qs;
      variable wr, wn, compared : t_int6 := (others => 0);
      variable mism : integer := 0;
      variable l : line;
      variable cyc : integer := 0;
      variable allEq : boolean;
   begin
      if rising_edge(clk2x) then
         cyc := cyc + 1;
         for t in 0 to 5 loop
            if (ev_valid_ref(t) = '1') then qref(t)(wr(t) mod QN) := ev_ref(t); wr(t) := wr(t) + 1; end if;
            if (ev_valid_new(t) = '1') then qnew(t)(wn(t) mod QN) := ev_new(t); wn(t) := wn(t) + 1; end if;
            -- stream 2 (line-buffer read enables) repeats during pipeline stalls, so it depends on
            -- timing even for identical designs (checked with SELFTEST); it is not compared
            while (t /= 2 and compared(t) < wr(t) and compared(t) < wn(t)) loop
               if (qref(t)(compared(t) mod QN) /= qnew(t)(compared(t) mod QN)) then
                  if (mism < 10) then
                     write(l, string'("MISMATCH stream ") & integer'image(t) & string'(" event ") & integer'image(compared(t))
                           & string'(" ref ") & to_hstring(qref(t)(compared(t) mod QN)) & string'(" new ") & to_hstring(qnew(t)(compared(t) mod QN)));
                     writeline(output, l);
                  end if;
                  mism := mism + 1;
               end if;
               compared(t) := compared(t) + 1;
            end loop;
         end loop;
         if (cyc mod 2000000 = 0) then
            write(l, string'("progress cmds ref/new ") & integer'image(cmds_ref) & string'("/") & integer'image(cmds_new)
                  & string'(" pixels ") & integer'image(compared(0)) & string'(" mismatches ") & integer'image(mism));
            writeline(output, l);
         end if;
         if (fin_ref = '1' and fin_new = '1') then
            allEq := true;
            for t in 0 to 5 loop if (t /= 2 and wr(t) /= wn(t)) then allEq := false; end if; end loop;
            write(l, string'("DONE module=") & integer'image(MODULE) & string'(" commands=") & integer'image(NUM_CMDS)
                  & string'(" pixels=") & integer'image(wr(0)) & string'("/") & integer'image(wn(0))
                  & string'(" vramreq=") & integer'image(wr(1)) & string'("/") & integer'image(wn(1))
                  & string'(" lineena=") & integer'image(wr(2)) & string'("/") & integer'image(wn(2))
                  & string'(" pal=") & integer'image(wr(3)) & string'(" drawmode=") & integer'image(wr(4))
                  & string'(" done=") & integer'image(wr(5)) & string'("/") & integer'image(wn(5))
                  & string'(" mismatches=") & integer'image(mism) & string'(" cycles=") & integer'image(cyc));
            writeline(output, l);
            if (mism = 0 and allEq and wr(0) > 0) then write(l, string'("PASS")); else write(l, string'("FAIL")); end if;
            writeline(output, l);
            std.env.finish;
         end if;
      end if;
   end process;
end architecture;
