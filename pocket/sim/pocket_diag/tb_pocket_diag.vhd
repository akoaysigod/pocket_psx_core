-- pocket_diag (hex page) while the core sends frames of its own (core_vs pulsing): with Select held its own
-- 320x240 frames must follow the APF video rules (as tb_pocket_video): DE once per active line with 320
-- non-skip pixels, single-clock HS / VS, HS >= 3 clocks after VS, >= 1 clock gap HS -> DE and DE -> HS, RGB
-- zero outside DE except the slot word (slot 1). Every pixel of the text rows is checked against the font for
-- the values given (white glyph pixels, black elsewhere, a non-black marker on the left of each row).
-- With Select released the core's signals must come through; held again, the diagnostics again.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_pocket_diag is
end entity;

architecture sim of tb_pocket_diag is
   constant ROWS : integer := 8;
   signal clkpix : std_logic := '0';
   signal done   : boolean := false;
   signal values : std_logic_vector(ROWS * 32 - 1 downto 0);
   signal vclk   : std_logic := '0';
   signal vwe    : std_logic := '0';
   signal vaddr  : std_logic_vector(2 downto 0) := (others => '0');
   signal vdata  : std_logic_vector(31 downto 0) := (others => '0');
   signal rgb    : std_logic_vector(23 downto 0);
   signal de, skip, vs, hs : std_logic;
   signal sel    : std_logic := '1';
   signal checking : boolean := false;
   signal core_vs : std_logic := '0';
   signal errors, lines, frames, glyph_on : integer := 0;

   type tglyph is array(0 to 6) of std_logic_vector(4 downto 0);
   type tfont is array(0 to 15) of tglyph;
   constant FONT : tfont :=
   (
      ("01110", "10001", "10011", "10101", "11001", "10001", "01110"), ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
      ("01110", "10001", "00001", "00010", "00100", "01000", "11111"), ("11111", "00010", "00100", "00010", "00001", "10001", "01110"),
      ("00010", "00110", "01010", "10010", "11111", "00010", "00010"), ("11111", "10000", "11110", "00001", "00001", "10001", "01110"),
      ("00110", "01000", "10000", "11110", "10001", "10001", "01110"), ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
      ("01110", "10001", "10001", "01110", "10001", "10001", "01110"), ("01110", "10001", "10001", "01111", "00001", "00010", "01100"),
      ("01110", "10001", "10001", "11111", "10001", "10001", "10001"), ("11110", "10001", "10001", "11110", "10001", "10001", "11110"),
      ("01110", "10001", "10000", "10000", "10000", "10001", "01110"), ("11100", "10010", "10001", "10001", "10001", "10010", "11100"),
      ("11111", "10000", "10000", "11110", "10000", "10000", "11111"), ("11111", "10000", "10000", "11110", "10000", "10000", "10000")
   );
begin
   clkpix <= not clkpix after 18624 ps when not done;

   -- every nibble value in several positions: row r = r * 0x01234567 + 0x89ABCDEF (mod 2^32)
   gval : for r in 1 to ROWS generate
      values(r * 32 - 1 downto (r - 1) * 32) <= std_logic_vector(resize(to_unsigned(r, 32) * x"01234567" + x"89ABCDEF", 32));
   end generate;

   idut : entity work.pocket_diag
   generic map (ROWS => ROWS)
   port map (clkpix => clkpix, val_clk => vclk, val_we => vwe, val_addr => vaddr, val_data => vdata, select_key => sel,
             core_rgb => x"123456", core_de => '1', core_skip => '0', core_vs => core_vs, core_hs => '0',
             video_rgb => rgb, video_de => de, video_skip => skip, video_vs => vs, video_hs => hs);

   -- the values written into the page's RAM from another clock (33.9 MHz), once at the start
   vclk <= not vclk after 14763 ps when not done;
   process
   begin
      wait for 100 ns;
      for r in 1 to ROWS loop
         wait until rising_edge(vclk);
         vwe <= '1'; vaddr <= std_logic_vector(to_unsigned(r - 1, 3)); vdata <= values(r * 32 - 1 downto (r - 1) * 32);
      end loop;
      wait until rising_edge(vclk);
      vwe <= '0';
      wait;
   end process;

   -- the core's frames: a vsync pulse every 400000 clocks, unrelated to the diagnostics' own timing
   process (clkpix)
      variable n : integer := 0;
   begin
      if rising_edge(clkpix) then
         core_vs <= '0';
         n := n + 1;
         if (n = 400000) then n := 0; core_vs <= '1'; end if;
      end if;
   end process;

   process (clkpix)
      variable t : integer := 0;
      variable last_vs, last_hs, last_de_fall : integer := -100000;
      variable de_1 : std_logic := '0';
      variable pix, line_in_frame : integer := 0;
      variable e, gon : integer := 0;
      variable chk : boolean := false;
      variable row, rl, d, x0, nib, idx : integer;
      variable exp_on, exp_black, exp_mark : boolean;
      procedure fail(msg : string) is
      begin
         if (e < 20) then report msg & " (t=" & integer'image(t) & ")" severity error; end if;
         e := e + 1;
      end procedure;
   begin
      if rising_edge(clkpix) and not checking then
         last_vs := -100000; last_hs := -100000; last_de_fall := -100000;
         line_in_frame := 0;
         chk := false;
         de_1 := '0';
      elsif rising_edge(clkpix) then
         t := t + 1;
         if (vs = '1') then
            if (chk and line_in_frame /= 240) then fail("frame with " & integer'image(line_in_frame) & " active lines"); end if;
            if (last_vs > 0) then chk := true; frames <= frames + 1; end if;
            if (t - last_vs < 1000) then fail("VS more than once"); end if;
            if (rgb /= x"000000") then fail("RGB during VS"); end if;
            last_vs := t;
            line_in_frame := 0;
         end if;
         if (chk) then
            if (hs = '1') then
               if (t - last_vs < 3) then fail("HS < 3 after VS"); end if;
               if (de = '1' or de_1 = '1') then fail("HS with DE"); end if;
               if (t - last_de_fall < 2) then fail("HS < 1 clock after DE"); end if;
               if (t - last_hs < 100) then fail("HS twice in a line"); end if;
               last_hs := t;
            end if;
            if (de = '1' and de_1 = '0') then
               if (t - last_hs < 2) then fail("DE < 1 clock after HS"); end if;
               pix := 0;
            end if;
            if (skip = '1' and de = '0') then fail("skip outside DE"); end if;
            if (de = '1' and skip = '0') then
               -- expected picture
               row := line_in_frame / 16; rl := line_in_frame mod 16;
               exp_on := false; exp_black := true; exp_mark := false;
               if (row = 0) then
                  exp_black := rl >= 12;
                  if (rl < 12 and rgb /= x"00C8FF" and rgb /= x"0030C0") then fail("row 0 not blue: " & to_hstring(rgb)); end if;
               elsif (row <= ROWS and rl < 14) then
                  if (pix >= 4 and pix < 14) then
                     exp_mark := true; exp_black := false;
                  else
                     for dd in 0 to 7 loop
                        x0 := 24 + dd * 16;
                        if (pix >= x0 and pix < x0 + 10) then
                           idx := (row - 1) * 32 + (7 - dd) * 4;
                           nib := to_integer(unsigned(values(idx + 3 downto idx)));
                           exp_on := FONT(nib)(rl / 2)(4 - (pix - x0) / 2) = '1';
                        end if;
                     end loop;
                  end if;
               end if;
               if (exp_mark) then
                  if (rgb = x"000000") then fail("row marker black at row " & integer'image(row)); end if;
               elsif (exp_on) then
                  if (rgb /= x"FFFFFF") then fail("glyph pixel not white at row " & integer'image(row) & " x " & integer'image(pix)); end if;
                  gon := gon + 1;
               elsif (exp_black and rgb /= x"000000") then
                  fail("pixel not black at row " & integer'image(row) & " line " & integer'image(rl) & " x " & integer'image(pix) & ": " & to_hstring(rgb));
               end if;
               pix := pix + 1;
            end if;
            if (de = '0' and de_1 = '1') then
               last_de_fall := t;
               lines <= lines + 1;
               line_in_frame := line_in_frame + 1;
               if (pix /= 320) then fail("line with " & integer'image(pix) & " pixels"); end if;
               if (rgb /= x"002000") then fail("slot word " & to_hstring(rgb)); end if;
            elsif (de = '0' and vs = '0' and rgb /= x"000000") then
               fail("RGB outside DE " & to_hstring(rgb));
            end if;
         end if;
         de_1 := de;
         errors <= e;
         glyph_on <= gon;
      end if;
   end process;

   process
      constant FRAME : time := 262 * 1707 * 37248 ps;
      variable bad : integer := 0;
      variable cvs_1 : std_logic := '0';
   begin
      -- Select held from the start: diagnostics from the first frame start after the synchroniser
      wait for 1.1 * FRAME;
      checking <= true;
      wait for 4 * FRAME + 1 us;
      -- Select released: the core's signals (constant DE, RGB 123456) after the next diagnostics frame start
      checking <= false;
      sel <= '0';
      wait for 1.1 * FRAME;
      for i in 1 to 100000 loop
         wait until rising_edge(clkpix);
         -- outputs are registered: VS follows the core's VS of the previous clock
         if (rgb /= x"123456" or de /= '1' or vs /= cvs_1) then bad := bad + 1; end if;
         cvs_1 := core_vs;
      end loop;
      -- held again: diagnostics
      sel <= '1';
      wait for 1.1 * FRAME;
      checking <= true;
      wait for 4 * FRAME;
      report "DONE frames=" & integer'image(frames) & " lines=" & integer'image(lines) & " errors=" & integer'image(errors) &
             " glyph_pixels=" & integer'image(glyph_on) & " select_bad=" & integer'image(bad);
      if (errors = 0 and bad = 0 and lines >= 4 * 240 and glyph_on > 1000) then report "PASS"; else report "FAIL"; end if;
      done <= true;
      wait;
   end process;
end architecture;
