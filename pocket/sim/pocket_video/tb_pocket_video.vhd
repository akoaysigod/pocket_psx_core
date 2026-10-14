-- pocket_video: PSX-like video timing in (clkvid), APF scaler rules checked on the output (clkpix = clkvid / 2,
-- edges aligned). Per mode: pixel every DIV clkvid clocks, WIDTH active pixels per line, a few frames.
-- Checked: per active line DE asserted once, WIDTH non-skip pixels with the right values, skip only with DE,
-- single-clock HS once per line and VS once per frame, HS >= 3 clocks after VS, >= 1 clock gap HS -> DE and
-- DE -> HS, RGB zero outside DE except the scaler slot word right after DE falls, nothing during VS.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_pocket_video is
   generic (MUTATION : integer := 0);
end entity;

architecture sim of tb_pocket_video is
   signal clkvid, clkpix : std_logic := '0';
   signal done : boolean := false;
   signal hblank, vblank, hsync, vsync, ce : std_logic := '0';
   signal r, g, b : std_logic_vector(7 downto 0) := (others => '0');
   signal hres : std_logic_vector(2 downto 0) := "011";
   signal rgb : std_logic_vector(23 downto 0);
   signal de, skip, vs, hs : std_logic;

   constant LINE_CLKS : integer := 3413;
   constant LINES     : integer := 30;     -- short frames for simulation speed
   constant ACT_FIRST : integer := 4;
   constant ACT_LAST  : integer := 25;

   signal mode_div, mode_width : integer := 8;
   signal mode_code : integer := 3;
   signal vs_hpos   : integer := 50;      -- clkvid position of the vsync rising edge in its line
   signal errors    : integer := 0;
   signal lines_checked, frames_checked : integer := 0;
   signal checking  : boolean := false;
begin
   -- both clocks rise in the same delta: clkpix rises on every other clkvid rising edge
   process
   begin
      while not done loop
         clkvid <= '1'; clkpix <= '1'; wait for 9312 ps;
         clkvid <= '0';                wait for 9312 ps;
         clkvid <= '1'; clkpix <= '0'; wait for 9312 ps;
         clkvid <= '0';                wait for 9312 ps;
      end loop;
      wait;
   end process;

   idut : entity work.pocket_video
   port map (clkvid => clkvid, hblank => hblank, vblank => vblank, hsync => hsync, vsync => vsync, video_ce => ce,
             video_r => r, video_g => g, video_b => b, video_hResMode => hres, clkpix => clkpix,
             video_rgb => rgb, video_de => de, video_skip => skip, video_vs => vs, video_hs => hs);

   -- video source (clkvid): registered outputs like the core
   process (clkvid)
      variable h, l, px : integer := 0;
      variable hstart : integer;
   begin
      if rising_edge(clkvid) then
         hstart := 480;
         ce <= '0';
         if (h mod mode_div = 0) then ce <= '1'; end if;
         -- active area: WIDTH pixels starting at hstart (a ce position)
         if (l >= ACT_FIRST and l <= ACT_LAST and h >= hstart and h < hstart + mode_width * mode_div) then
            hblank <= '0';
         else
            hblank <= '1';
         end if;
         if (l >= ACT_FIRST and l <= ACT_LAST) then vblank <= '0'; else vblank <= '1'; end if;
         if (h mod mode_div = 0 and h >= hstart and h < hstart + mode_width * mode_div) then
            px := (h - hstart) / mode_div;
            r <= std_logic_vector(to_unsigned(l, 8));
            g <= std_logic_vector(to_unsigned(px mod 256, 8));
            b <= std_logic_vector(to_unsigned(px / 256, 8));
         end if;
         if (h >= 100 and h < 350) then hsync <= '1'; else hsync <= '0'; end if;
         if ((l = 1 and h >= vs_hpos) or l = 2 or (l = 3 and h < vs_hpos)) then vsync <= '1'; else vsync <= '0'; end if;
         h := h + 1;
         if (h = LINE_CLKS) then h := 0; l := (l + 1) mod LINES; end if;
      end if;
   end process;

   -- APF rule checker (clkpix)
   process (clkpix)
      variable t : integer := 0;
      variable last_vs, last_hs, last_de_rise, last_de_fall : integer := -1000;
      variable de_1 : std_logic := '0';
      variable de_count, pix, line_no : integer := 0;
      variable in_line : boolean := false;
      variable slot_seen : boolean := false;
      variable exp : std_logic_vector(23 downto 0);
      variable e : integer := 0;
      procedure fail(msg : string) is
      begin
         if (e < 20) then report msg & " (t=" & integer'image(t) & ")" severity error; end if;
         e := e + 1;
      end procedure;
   begin
      if rising_edge(clkpix) then
         t := t + 1;
         if (checking) then
            if (vs = '1') then
               if (t - last_vs < 100) then fail("VS more than once"); end if;
               if (rgb /= x"000000") then fail("RGB not zero during VS"); end if;
               last_vs := t;
               frames_checked <= frames_checked + 1;
               line_no := 0;
            end if;
            if (hs = '1') then
               if (t - last_vs < 3) then fail("HS less than 3 clocks after VS"); end if;
               if (de = '1' or de_1 = '1') then fail("HS while DE"); end if;
               if (t - last_de_fall < 2) then fail("HS less than 1 clock after DE fell"); end if;
               if (t - last_hs < 100) then fail("HS more than once per line"); end if;
               last_hs := t;
               line_no := line_no + 1;
            end if;
            if (de = '1' and de_1 = '0') then
               if (t - last_hs < 2) then fail("DE less than 1 clock after HS"); end if;
               last_de_rise := t;
               pix := 0;
            end if;
            if (skip = '1' and de = '0') then fail("skip outside DE"); end if;
            if (de = '1' and skip = '0') then
               -- expected pixel: line number in red (core line), index in green/blue
               exp := rgb(23 downto 16) & std_logic_vector(to_unsigned(pix mod 256, 8)) & std_logic_vector(to_unsigned(pix / 256, 8));
               if (rgb(15 downto 0) /= exp(15 downto 0)) then
                  fail("pixel " & integer'image(pix) & " wrong: " & to_hstring(rgb));
               end if;
               pix := pix + 1;
            end if;
            if (de = '0' and de_1 = '1') then
               last_de_fall := t;
               if (pix /= mode_width) then fail("line with " & integer'image(pix) & " pixels, expected " & integer'image(mode_width)); end if;
               lines_checked <= lines_checked + 1;
               -- slot word now
               exp := (others => '0');
               exp(15 downto 13) := std_logic_vector(to_unsigned(4 - mode_code, 3));
               if (MUTATION = 1) then exp(15 downto 13) := std_logic_vector(to_unsigned(mode_code, 3)); end if;
               if (rgb /= exp) then fail("slot word " & to_hstring(rgb) & " expected " & to_hstring(exp)); end if;
            elsif (de = '0' and vs = '0' and rgb /= x"000000") then
               fail("RGB not zero outside DE: " & to_hstring(rgb));
            end if;
         end if;
         de_1 := de;
         errors <= e;
      end if;
   end process;

   process
      type tModes is array(0 to 4) of integer;
      constant DIVS   : tModes := (10, 8, 7, 5, 4);
      constant WIDTHS : tModes := (256, 320, 368, 512, 640);
      constant CODES  : tModes := (4, 3, 2, 1, 0);
      constant VSPOS  : tModes := (50, 106, 1700, 102, 350);   -- vsync before / just after hsync / mid line
   begin
      for m in 0 to 4 loop
         checking   <= false;
         mode_div   <= DIVS(m);
         mode_width <= WIDTHS(m);
         mode_code  <= CODES(m);
         hres       <= std_logic_vector(to_unsigned(CODES(m), 3));
         vs_hpos    <= VSPOS(m);
         -- let a frame pass, then check two frames
         wait for real(LINES * LINE_CLKS) * 18.624 ns;
         checking <= true;
         wait for 2.0 * real(LINES * LINE_CLKS) * 18.624 ns;
      end loop;
      checking <= false;
      wait for 1 us;
      report "DONE frames=" & integer'image(frames_checked) & " lines=" & integer'image(lines_checked) &
             " errors=" & integer'image(errors);
      if (errors = 0 and lines_checked = 5 * 2 * (ACT_LAST - ACT_FIRST + 1)) then report "PASS"; else report "FAIL"; end if;
      done <= true;
      wait;
   end process;
end architecture;
