-- Core video output (rtl/gpu_videoout_async) into the Pocket video wrapper (pocket_video), as on the Pocket:
-- counts the pixels the scaler gets per line (DE high and skip low on clkpix) for one display mode and
-- horizontal display range. The scaler slot of each mode is 256 / 320 / 368 / 512 / 640 pixels wide; a line
-- with more or fewer pixels leaves columns of the docked picture that the core never writes.
-- Reports every pixel count seen and how many lines had it; PASS when every active line has EXPECT pixels.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pGPU.all;

entity tb_video_chain is
   generic
   (
      MODE   : integer := 0;     -- 0..4 = 256, 320, 368, 512, 640
      HCROP  : integer := 0;
      X1     : integer := 16#260#;
      X2     : integer := 16#C60#;
      EXPECT : integer := -1;    -- pixels per line required for PASS (-1: the mode's width)
      LINES  : integer := 40     -- active lines to check
   );
end entity;

architecture sim of tb_video_chain is
   type tModes is array(0 to 4) of integer;
   constant WIDTHS : tModes := (256, 320, 368, 512, 640);

   signal clk1x, clk2x, clkvid, clkpix : std_logic := '0';
   signal done     : boolean := false;
   signal reset_1x : std_logic := '1';

   signal settings : tvideoout_settings;
   signal reports  : tvideoout_reports;
   signal req2x, reqvid : tvideoout_request;
   signal readAddr : unsigned(10 downto 0);
   signal vout     : tvideoout_out;
   signal ss_in    : tvideoout_ss := ('0', (others => '0'), (others => '0'), (others => '0'), '0', '0', '0', '0');
   signal ss_out   : tvideoout_ss;
   signal allowunpause : std_logic;

   signal rgb  : std_logic_vector(23 downto 0);
   signal de, skip, vs, hs : std_logic;
begin
   -- clkvid 53.69 MHz with clkpix = clkvid / 2 (edges aligned), clk1x 33.87 MHz and clk2x from another PLL
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

   process
   begin
      while not done loop
         clk1x <= '1'; clk2x <= '1'; wait for 7381 ps;
         clk2x <= '0';               wait for 7381 ps;
         clk1x <= '0'; clk2x <= '1'; wait for 7381 ps;
         clk2x <= '0';               wait for 7381 ps;
      end loop;
      wait;
   end process;

   reset_1x <= '0' after 2 us;

   process
   begin
      settings <= (GPUSTAT_VerRes => '0', GPUSTAT_PalVideoMode => '0', GPUSTAT_VertInterlace => '0',
                   GPUSTAT_HorRes2 => '0', GPUSTAT_HorRes1 => "00",
                   GPUSTAT_ColorDepth24 => '0', GPUSTAT_DisplayDisable => '0',
                   vramRange => (others => '0'),
                   hDisplayRange => to_unsigned(X2, 12) & to_unsigned(X1, 12),
                   vDisplayRange => to_unsigned(16 + LINES + 4, 10) & to_unsigned(16, 10),
                   pal60 => '0', syncInterlace => '0', rotate180 => '0', fixedVBlank => '0', vCrop => "00",
                   hCrop => '0', dither24 => '0', render24 => '0');
      case MODE is
         when 0      => settings.GPUSTAT_HorRes1 <= "00";
         when 1      => settings.GPUSTAT_HorRes1 <= "01";
         when 2      => settings.GPUSTAT_HorRes2 <= '1';
         when 3      => settings.GPUSTAT_HorRes1 <= "10";
         when others => settings.GPUSTAT_HorRes1 <= "11";
      end case;
      if (HCROP = 1) then settings.hCrop <= '1'; end if;
      wait;
   end process;

   icore : entity work.gpu_videoout_async
   port map
   (
      clk1x => clk1x, clk2x => clk2x, clkvid => clkvid, ce_1x => '1', reset_1x => reset_1x, softReset_1x => '0',
      savestate_pause_1x => '0', system_paused_1x => '0', allowunpause1x => allowunpause,
      videoout_settings_1x => settings, videoout_reports_1x => reports,
      videoout_request_2x => req2x, videoout_request_vid => reqvid,
      videoout_readAddr => readAddr, videoout_pixelRead => x"7FFF", videoout_pixelRead2 => x"0000",
      overlay_data => (others => '0'), overlay_ena => '0',
      videoout_out => vout, videoout_ss_in => ss_in, videoout_ss_out => ss_out
   );

   iwrap : entity work.pocket_video
   port map
   (
      clkvid => clkvid, hblank => vout.hblank, vblank => vout.vblank, hsync => vout.hsync, vsync => vout.vsync,
      video_ce => vout.ce, video_r => vout.r, video_g => vout.g, video_b => vout.b, video_hResMode => vout.hResMode,
      clkpix => clkpix, video_rgb => rgb, video_de => de, video_skip => skip, video_vs => vs, video_hs => hs
   );

   -- pixels per line as the scaler sees them
   process (clkpix)
      type tCounts is array(0 to 1100) of integer;
      variable counts : tCounts := (others => 0);
      variable de_1   : std_logic := '0';
      variable pix, nlines : integer := 0;
      variable expect_w : integer;
      variable ok : boolean;
   begin
      if rising_edge(clkpix) then
         if (de = '1' and de_1 = '0') then pix := 0; end if;
         if (de = '1' and skip = '0') then pix := pix + 1; end if;
         if (de = '0' and de_1 = '1') then
            counts(pix) := counts(pix) + 1;
            nlines := nlines + 1;
            if (nlines = LINES) then
               if (EXPECT >= 0) then expect_w := EXPECT; else expect_w := WIDTHS(MODE); end if;
               ok := true;
               for i in counts'range loop
                  if (counts(i) > 0) then
                     report "mode " & integer'image(WIDTHS(MODE)) & " hcrop " & integer'image(HCROP) &
                            " x1 " & integer'image(X1) & " x2 " & integer'image(X2) & ": " &
                            integer'image(counts(i)) & " lines with " & integer'image(i) & " pixels";
                     if (i /= expect_w) then ok := false; end if;
                  end if;
               end loop;
               if (ok) then report "PASS"; else report "FAIL (expected " & integer'image(expect_w) & " pixels per line)"; end if;
               done <= true;
            end if;
         end if;
         de_1 := de;
      end if;
   end process;
end architecture;
