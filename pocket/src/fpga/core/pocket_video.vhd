-- Analogue Pocket: PSX core video (clkvid, one pixel per video_ce) -> APF scaler signals on clkpix.
-- clkpix is clkvid / 2 from the same PLL (APF takes pixel clocks up to ~50 MHz; clkvid is 53.69 MHz). The core
-- gives a pixel at most every 4th clkvid clock, so at most one per clkpix clock: each pixel is held in clkvid and
-- signalled with a toggle; clkpix clocks without a new pixel are marked with skip. APF rules kept: single-clock VS
-- and HS, HS at least 3 clocks after VS, RGB zero outside DE except the scaler slot word right after DE falls
-- (slot 0-4 = width 256/320/368/512/640 in video.json).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pocket_video is
   port
   (
      clkvid         : in  std_logic;
      hblank         : in  std_logic;
      vblank         : in  std_logic;
      hsync          : in  std_logic;
      vsync          : in  std_logic;
      video_ce       : in  std_logic;
      video_r        : in  std_logic_vector(7 downto 0);
      video_g        : in  std_logic_vector(7 downto 0);
      video_b        : in  std_logic_vector(7 downto 0);
      video_hResMode : in  std_logic_vector(2 downto 0);
      clkpix         : in  std_logic;
      video_rgb      : out std_logic_vector(23 downto 0) := (others => '0');
      video_de       : out std_logic := '0';
      video_skip     : out std_logic := '0';
      video_vs       : out std_logic := '0';
      video_hs       : out std_logic := '0'
   );
end entity;

architecture arch of pocket_video is

   -- clkvid side: active area, last active pixel, toggles for new pixel / hsync / vsync
   signal v_de           : std_logic := '0';
   signal v_de_1         : std_logic := '0';
   signal v_rgb         : std_logic_vector(23 downto 0) := (others => '0');
   signal v_pix, v_hs, v_vs : std_logic := '0';
   signal hs_1, vs_1     : std_logic := '0';
   -- clkpix side
   signal p_pix, p_hs, p_vs : std_logic := '0';
   signal p_de_1         : std_logic := '0';
   signal hs_pend        : std_logic := '0';
   signal hs_delay       : integer range 0 to 7 := 0;
   signal vs_age         : integer range 0 to 7 := 7;

begin

   -- clkvid: the core gives a pixel on each video_ce (at most every 4th clkvid clock, so at most one per clkpix
   -- clock); hold it and signal it with a toggle, likewise the sync edges.
   -- DE falls one clkvid clock after the core's blanking starts. The core raises hblank one clock after a line's
   -- last pixel, and clkpix samples every other clkvid clock; lines are 3413 clkvid clocks (odd), so on every
   -- other line clkpix would see the last pixel's toggle only together with DE low and lose it: those lines were
   -- one pixel short and the docked picture showed a stale last column.
   process (clkvid)
   begin
      if rising_edge(clkvid) then
         v_de_1 <= not (hblank or vblank);
         v_de   <= not (hblank or vblank) or v_de_1;
         if (video_ce = '1' and hblank = '0' and vblank = '0') then
            v_rgb <= video_r & video_g & video_b;
            v_pix <= not v_pix;
         end if;
         hs_1 <= hsync;
         vs_1 <= vsync;
         if (hsync = '1' and hs_1 = '0') then v_hs <= not v_hs; end if;
         if (vsync = '1' and vs_1 = '0') then v_vs <= not v_vs; end if;
      end if;
   end process;

   -- clkpix: DE over the active area, skip on clocks without a new pixel, single-clock VS and HS (HS at least
   -- 3 clocks after VS, as APF requires), scaler slot after the falling edge of DE
   process (clkpix)
      variable vs_now : std_logic;
   begin
      if rising_edge(clkpix) then
         p_pix <= v_pix;
         p_hs  <= v_hs;
         p_vs  <= v_vs;

         video_de   <= v_de;
         video_skip <= v_de and not (v_pix xor p_pix);
         p_de_1     <= v_de;

         vs_now   := v_vs xor p_vs;
         video_vs <= vs_now;
         if (vs_now = '1') then
            vs_age <= 0;
         elsif (vs_age < 7) then
            vs_age <= vs_age + 1;
         end if;

         video_hs <= '0';
         if (v_hs /= p_hs) then
            hs_pend  <= '1';
            hs_delay <= 4;
         elsif (hs_delay > 0) then
            hs_delay <= hs_delay - 1;
         elsif (hs_pend = '1' and vs_now = '0' and vs_age >= 3) then
            video_hs <= '1';
            hs_pend  <= '0';
         end if;

         if (v_de = '1') then
            video_rgb <= v_rgb;
         elsif (p_de_1 = '1' and vs_now = '0') then
            -- end of an active line: scaler slot (video.json mode) for this width
            video_rgb <= (others => '0');
            video_rgb(15 downto 13) <= std_logic_vector(to_unsigned(4 - to_integer(unsigned(video_hResMode)), 3));
         else
            video_rgb <= (others => '0');
         end if;
      end if;
   end process;

end architecture;
