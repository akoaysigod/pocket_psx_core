-- Equivalence test: rtl/cd_xa.vhd (cd_xa_new) against the upstream cd_xa (cd_xa_ref). Random XA sectors
-- (all coding modes: 4 / 8 bit, mono / stereo, 18.9 / 37.8 kHz, end-of-file bit) are written into the
-- sector RAM and started like cd_top does, CD-DA samples are fed in between, spu_tick comes every 768
-- clocks, XA_reset and reset now and then; every output is compared on every clock.
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity tb_cd_xa is
   generic
   (
      NUM_CYCLES : integer := 2000000;
      SEED       : integer := 1
   );
end entity;

architecture sim of tb_cd_xa is

   signal clk1x       : std_logic := '1';
   signal reset       : std_logic := '1';
   signal spu_tick    : std_logic := '0';
   signal CDDA_write  : std_logic := '0';
   signal CDDA_data   : std_logic_vector(31 downto 0) := (others => '0');
   signal XA_addr     : integer range 0 to 587 := 0;
   signal XA_data     : std_logic_vector(31 downto 0) := (others => '0');
   signal XA_write    : std_logic := '0';
   signal XA_start    : std_logic := '0';
   signal XA_reset    : std_logic := '0';

   type tOut is record
      XA_eof        : std_logic;
      cdaudio_left  : signed(15 downto 0);
      cdaudio_right : signed(15 downto 0);
   end record;
   signal o_ref, o_new : tOut;

   signal mismatches : integer := 0;
   signal nonzero    : integer := 0;
   signal ticks      : integer := 0;
   signal done       : boolean := false;

begin

   clk1x <= not clk1x after 5 ns when not done;

   iref : entity work.cd_xa_ref
   port map (clk1x => clk1x, reset => reset, spu_tick => spu_tick, CDDA_write => CDDA_write, CDDA_data => CDDA_data,
             XA_addr => XA_addr, XA_data => XA_data, XA_write => XA_write, XA_start => XA_start, XA_reset => XA_reset,
             XA_eof => o_ref.XA_eof, cdaudio_left => o_ref.cdaudio_left, cdaudio_right => o_ref.cdaudio_right);

   inew : entity work.cd_xa_new
   port map (clk1x => clk1x, reset => reset, spu_tick => spu_tick, CDDA_write => CDDA_write, CDDA_data => CDDA_data,
             XA_addr => XA_addr, XA_data => XA_data, XA_write => XA_write, XA_start => XA_start, XA_reset => XA_reset,
             XA_eof => o_new.XA_eof, cdaudio_left => o_new.cdaudio_left, cdaudio_right => o_new.cdaudio_right);

   -- 44.1 kHz sample tick of the SPU (every 768 clk1x)
   process (clk1x)
      variable cnt : integer := 0;
   begin
      if rising_edge(clk1x) then
         spu_tick <= '0';
         cnt := cnt + 1;
         if (cnt = 768) then
            cnt := 0;
            spu_tick <= '1';
         end if;
      end if;
   end process;

   stim : process
      variable s1, s2 : positive;
      variable r : real;
      variable c : integer := 0;
      variable coding : std_logic_vector(7 downto 0);
      variable submode : std_logic_vector(7 downto 0);
      variable gap : integer;
      impure function rnd(n : integer) return integer is
      begin
         uniform(s1, s2, r);
         return integer(floor(r * real(n)));
      end function;
      impure function rnd32 return std_logic_vector is
      begin
         return std_logic_vector(to_unsigned(rnd(65536), 16)) & std_logic_vector(to_unsigned(rnd(65536), 16));
      end function;
      procedure tick is
      begin
         wait until rising_edge(clk1x);
         c := c + 1;
         XA_write <= '0'; XA_start <= '0'; XA_reset <= '0'; CDDA_write <= '0'; reset <= '0';
         -- CD-DA samples now and then (as cd_top sends them for audio tracks)
         if (rnd(3000) = 0) then
            CDDA_write <= '1';
            CDDA_data  <= rnd32;
         end if;
         if (rnd(400000) = 0) then XA_reset <= '1'; end if;
         if (rnd(1500000) = 0) then reset <= '1'; end if;
      end procedure;
   begin
      s1 := SEED; s2 := SEED * 13 + 5;
      for i in 0 to 9 loop wait until rising_edge(clk1x); end loop;
      reset <= '0';
      while (c < NUM_CYCLES) loop
         -- one sector: header word 4 holds the submode (byte 18) and coding (byte 19) at RAM bytes 16-19
         coding  := std_logic_vector(to_unsigned(rnd(256), 8));
         -- mostly valid codings: bits 5:4 = 00 / 01, stereo bits 1:0 = 00 / 01
         if (rnd(8) /= 0) then coding(7 downto 6) := "00"; coding(5) := '0'; coding(1) := '0'; coding(3) := '0'; end if;
         submode := std_logic_vector(to_unsigned(rnd(256), 8));
         if (rnd(16) /= 0) then submode(7) := '0'; end if;
         for w in 0 to 587 loop
            XA_addr  <= w;
            XA_data  <= rnd32;
            if (w = 4) then XA_data <= coding & submode & std_logic_vector(to_unsigned(rnd(65536), 16)); end if;
            XA_write <= '1';
            tick;
         end loop;
         XA_start <= '1';
         tick;
         -- next sector after a while (double speed: ~2 * 2352 bytes per 1/75 s; varied so the FIFOs fill and drain)
         gap := 4000 + rnd(30000);
         for i in 0 to gap loop tick; end loop;
      end loop;
      done <= true;
      wait for 20 ns;
      report "DONE cycles=" & integer'image(c) & " ticks=" & integer'image(ticks) & " nonzero_samples=" & integer'image(nonzero) & " mismatch_cycles=" & integer'image(mismatches);
      if (mismatches = 0 and nonzero > 100) then report "PASS"; else report "FAIL"; end if;
      wait;
   end process;

   check : process (clk1x)
   begin
      if falling_edge(clk1x) then
         if (o_ref /= o_new) then
            if (mismatches < 10) then
               report "mismatch: ref " & std_logic'image(o_ref.XA_eof) & " " & to_hstring(o_ref.cdaudio_left) & " " & to_hstring(o_ref.cdaudio_right) &
                      " new " & std_logic'image(o_new.XA_eof) & " " & to_hstring(o_new.cdaudio_left) & " " & to_hstring(o_new.cdaudio_right) severity warning;
            end if;
            mismatches <= mismatches + 1;
         end if;
         if (spu_tick = '1') then
            ticks <= ticks + 1;
            if (o_ref.cdaudio_left /= 0 or o_ref.cdaudio_right /= 0) then nonzero <= nonzero + 1; end if;
         end if;
      end if;
   end process;

end architecture;
