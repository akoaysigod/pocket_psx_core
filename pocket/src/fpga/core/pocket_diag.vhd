-- Analogue Pocket: diagnostic page for bring-up, shown instead of the core's picture while Select is held.
-- Own 320x240 timing on clkpix (same APF signalling as before). Row 0 is a blinking bar (screen is live);
-- rows 1..ROWS show one 32-bit value each as 8 hex digits (5x7 font at double size), with a coloured marker
-- on the left per group of rows. Rows are 16 lines high.
-- The values are written as 32-bit words (word r-1 = row r) into a small dual-clock RAM (one M10K) from the
-- source's clock domain and read here as 4-bit digits; the source rewrites them about twice a second (a digit
-- may be wrong for one frame while that happens).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity pocket_diag is
   generic
   (
      ROWS           : integer := 8
   );
   port
   (
      clkpix         : in  std_logic;
      -- row values (word r-1 = row r, ROWS <= 8)
      val_clk        : in  std_logic;
      val_we         : in  std_logic;
      val_addr       : in  std_logic_vector(2 downto 0);
      val_data       : in  std_logic_vector(31 downto 0);
      select_key     : in  std_logic;                                 -- any domain
      -- core picture (from pocket_video, clkpix)
      core_rgb       : in  std_logic_vector(23 downto 0);
      core_de        : in  std_logic;
      core_skip      : in  std_logic;
      core_vs        : in  std_logic;
      core_hs        : in  std_logic;
      -- to the Pocket
      video_rgb      : out std_logic_vector(23 downto 0) := (others => '0');
      video_de       : out std_logic := '0';
      video_skip     : out std_logic := '0';
      video_vs       : out std_logic := '0';
      video_hs       : out std_logic := '0'
   );
end entity;

architecture arch of pocket_diag is

   constant LINE_CLKS : integer := 1707;   -- 26.85 MHz / 1707 / 262 = 60 Hz
   constant FRAME_LNS : integer := 262;
   constant DE_START  : integer := 200;    -- 1280 clocks of DE, a pixel every 4th clock = 320 pixels
   constant ACT_FIRST : integer := 11;     -- 240 active lines
   constant TEXT_X    : integer := 24;     -- first digit; digits on a 16-pixel grid (10 wide + 6 space)

   -- 5x7 hex font, bit 4 = leftmost column
   type tglyph is array(0 to 6) of std_logic_vector(4 downto 0);
   type tfont is array(0 to 15) of tglyph;
   constant FONT : tfont :=
   (
      ("01110", "10001", "10011", "10101", "11001", "10001", "01110"),   -- 0
      ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),   -- 1
      ("01110", "10001", "00001", "00010", "00100", "01000", "11111"),   -- 2
      ("11111", "00010", "00100", "00010", "00001", "10001", "01110"),   -- 3
      ("00010", "00110", "01010", "10010", "11111", "00010", "00010"),   -- 4
      ("11111", "10000", "11110", "00001", "00001", "10001", "01110"),   -- 5
      ("00110", "01000", "10000", "11110", "10001", "10001", "01110"),   -- 6
      ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),   -- 7
      ("01110", "10001", "10001", "01110", "10001", "10001", "01110"),   -- 8
      ("01110", "10001", "10001", "01111", "00001", "00010", "01100"),   -- 9
      ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),   -- A
      ("11110", "10001", "10001", "11110", "10001", "10001", "11110"),   -- B
      ("01110", "10001", "10000", "10000", "10000", "10001", "01110"),   -- C
      ("11100", "10010", "10001", "10001", "10001", "10010", "11100"),   -- D
      ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),   -- E
      ("11111", "10000", "10000", "11110", "10000", "10000", "10000")    -- F
   );

   signal sel_s        : std_logic_vector(1 downto 0) := (others => '0');

   signal h            : integer range 0 to LINE_CLKS - 1 := 0;
   signal v            : integer range 0 to FRAME_LNS - 1 := 0;
   signal row          : integer range 0 to 14 := 0;
   signal row_line     : integer range 0 to 15 := 0;
   signal frames       : unsigned(5 downto 0) := (others => '0');

   signal d_rgb        : std_logic_vector(23 downto 0) := (others => '0');
   signal d_de, d_skip, d_vs, d_hs : std_logic := '0';

   signal show         : std_logic := '0';

   -- digit RAM: read address = (row - 1) * 8 + nibble (nibble 0 = bits 3:0), for the pixel of the NEXT clock
   -- (the RAM registers the address), so q holds the digit of the current pixel
   signal rd_addr      : std_logic_vector(5 downto 0);
   signal rd_q         : std_logic_vector(3 downto 0);

begin

   iram : altsyncram
   generic map
   (
      address_aclr_b => "NONE", address_reg_b => "CLOCK1", clock_enable_input_a => "BYPASS",
      clock_enable_input_b => "BYPASS", clock_enable_output_b => "BYPASS", intended_device_family => "Cyclone V",
      lpm_type => "altsyncram", numwords_a => 8, numwords_b => 64, operation_mode => "DUAL_PORT",
      outdata_aclr_b => "NONE", outdata_reg_b => "UNREGISTERED", power_up_uninitialized => "FALSE",
      ram_block_type => "M10K", widthad_a => 3, widthad_b => 6, width_a => 32, width_b => 4, width_byteena_a => 1
   )
   port map
   (
      clock0 => val_clk, wren_a => val_we, address_a => val_addr, data_a => val_data,
      clock1 => clkpix, address_b => rd_addr, q_b => rd_q
   );

   process (all)
      variable tx : unsigned(10 downto 0);
      variable d  : integer range 0 to 7;
   begin
      -- pixel of the next clock; outside the text rows the address does not matter
      tx := to_unsigned(h + 1, 11) - DE_START - 4 * TEXT_X;   -- 4 clocks per pixel
      d  := to_integer(tx(8 downto 6));                       -- 16 pixels = 64 clocks per digit
      if (row >= 1) then
         rd_addr <= std_logic_vector(to_unsigned(row - 1, 3)) & std_logic_vector(to_unsigned(7 - d, 3));
      else
         rd_addr <= (others => '0');
      end if;
   end process;

   process (clkpix)
      variable active : boolean;
      variable pix    : integer range 0 to 319;
      variable dig    : integer range 0 to 8;     -- 8 = no digit here
      variable dx     : integer range 0 to 15;
      variable tx     : unsigned(8 downto 0);
      variable nib    : integer range 0 to 15;
      variable lit    : std_logic;
      variable mark   : std_logic_vector(23 downto 0);
   begin
      if rising_edge(clkpix) then
         sel_s <= sel_s(0) & select_key;

         ---------------- own timing
         if (h = LINE_CLKS - 1) then
            h <= 0;
            if (v = FRAME_LNS - 1) then
               v      <= 0;
               frames <= frames + 1;
            else
               v <= v + 1;
            end if;
            if (v >= ACT_FIRST and v < ACT_FIRST + 240) then
               if (row_line = 15) then
                  row_line <= 0;
                  if (row < 14) then row <= row + 1; end if;
               else
                  row_line <= row_line + 1;
               end if;
            else
               row      <= 0;
               row_line <= 0;
            end if;
         else
            h <= h + 1;
         end if;

         active := (v >= ACT_FIRST and v < ACT_FIRST + 240 and h >= DE_START and h < DE_START + 1280);
         d_vs   <= '0';
         d_hs   <= '0';
         if (v = 0 and h = 0) then d_vs <= '1'; end if;
         if (h = 4) then d_hs <= '1'; end if;                 -- 4 clocks after VS
         if (active) then
            d_de   <= '1';
            d_skip <= '0';
            if ((h - DE_START) mod 4 /= 0) then d_skip <= '1'; end if;
            pix := (h - DE_START) / 4;

            -- which digit (if any) this pixel belongs to
            tx  := to_unsigned(pix, 9) - TEXT_X;
            dig := 8;
            dx  := to_integer(tx(3 downto 0));
            if (pix >= TEXT_X and tx(8 downto 7) = "00") then
               dig := to_integer(tx(6 downto 4));
            end if;

            -- row marker colours (pocket_psx rows): PC white, GPU red, DMA blue, IRQ yellow, counts green
            case row is
               when 1              => mark := x"FFFFFF";
               when 2 | 3          => mark := x"FF3030";
               when 4 | 5 | 6      => mark := x"3080FF";
               when 7              => mark := x"FFFF00";
               when others         => mark := x"30FF30";
            end case;

            d_rgb <= x"000000";
            if (row = 0) then
               if (row_line < 12) then
                  if (frames(5) = '1') then d_rgb <= x"00C8FF"; else d_rgb <= x"0030C0"; end if;
               end if;
            elsif (row <= ROWS and row_line < 14) then
               if (pix >= 4 and pix < 14) then
                  d_rgb <= mark;
               elsif (dig < 8 and dx < 10) then
                  nib := to_integer(unsigned(rd_q));
                  lit := FONT(nib)(row_line / 2)(4 - dx / 2);
                  if (lit = '1') then d_rgb <= x"FFFFFF"; end if;
               end if;
            end if;
         else
            d_de   <= '0';
            d_skip <= '0';
            d_rgb  <= (others => '0');
            if (d_de = '1') then
               d_rgb(15 downto 13) <= "001";                 -- scaler slot 1 (320 x 240)
            end if;
         end if;

         ---------------- the core picture, or the diagnostics while Select is held (switched at a frame start)
         if (v = 0 and h = 0) then
            show <= sel_s(1);
         end if;

         if (show = '1') then
            video_rgb <= d_rgb; video_de <= d_de; video_skip <= d_skip; video_vs <= d_vs; video_hs <= d_hs;
         else
            video_rgb <= core_rgb; video_de <= core_de; video_skip <= core_skip; video_vs <= core_vs; video_hs <= core_hs;
         end if;
      end if;
   end process;

end architecture;
