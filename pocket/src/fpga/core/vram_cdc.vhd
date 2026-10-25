-- Pocket: the core's DDR3-style VRAM port (clk2x side) served by a vram_psram running on clk3x (PSRAM clock
-- clk3x / 2 = 50.8 MHz instead of clk2x / 2 = 33.9 MHz, same latency code 3, allowed up to 52 MHz).
-- clk2x and clk3x come from the same PLL (3 clk3x periods = 2 clk2x periods, rising edges aligned every
-- 29.5 ns), so every crossing below is one register to one register, timed by Quartus as a related-clock path
-- (worst case 4.9 ns); no synchronizer chains.
-- Requests: a QDEPTH-entry queue written on clk2x (busy only when full, so writes can be posted while the
-- PSRAM works), read on clk3x into vram_psram's request port.
-- Read data: vram_psram delivers a 64-bit word at most every 4 clk3x (39 ns) and holds it in ddr_dout until the
-- next one. Each word is announced with a toggle (one clk3x after ddr_dout is set); the first clk2x edge that sees
-- it changed takes ddr_dout (at most 24.6 ns after it was set, 14.8 ns before it can change) and pulses ready.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vram_cdc is
   generic
   (
      QDEPTH : integer := 1   -- 1 or 2 (2 measured no faster with SotN-like GPU traffic)
   );
   port
   (
      clk2x          : in  std_logic;
      clk3x          : in  std_logic;
      -- core side (clk2x)
      a_busy         : out std_logic := '1';
      a_burstcnt     : in  std_logic_vector(7 downto 0);
      a_addr         : in  std_logic_vector(24 downto 0);
      a_dout         : out std_logic_vector(63 downto 0) := (others => '0');
      a_dout_ready   : out std_logic := '0';
      a_rd           : in  std_logic;
      a_din          : in  std_logic_vector(63 downto 0);
      a_be           : in  std_logic_vector(7 downto 0);
      a_we           : in  std_logic;
      -- vram_psram side (clk3x)
      b_busy         : in  std_logic;
      b_burstcnt     : out std_logic_vector(7 downto 0);
      b_addr         : out std_logic_vector(24 downto 0);
      b_dout         : in  std_logic_vector(63 downto 0);
      b_dout_ready   : in  std_logic;
      b_rd           : out std_logic;
      b_din          : out std_logic_vector(63 downto 0);
      b_be           : out std_logic_vector(7 downto 0);
      b_we           : out std_logic
   );
end entity;

architecture arch of vram_cdc is

   constant QBITS : integer := 2;   -- pointer width: one more bit than QDEPTH 2 needs
   type tq is array(0 to QDEPTH - 1) of std_logic_vector(25 + 64 + 8 + 8 + 1 downto 0);   -- rd, addr, din, be, cnt, we
   signal q      : tq;
   signal wp     : unsigned(QBITS - 1 downto 0) := (others => '0');   -- clk2x
   signal rp     : unsigned(QBITS - 1 downto 0) := (others => '0');   -- clk3x
   signal wp_b   : unsigned(QBITS - 1 downto 0) := (others => '0');   -- wp seen on clk3x
   signal rp_a   : unsigned(QBITS - 1 downto 0) := (others => '0');   -- rp seen on clk2x
   signal full   : std_logic;
   signal entry  : std_logic_vector(25 + 64 + 8 + 8 + 1 downto 0);
   signal pend   : std_logic;

   signal rtgl   : std_logic := '0';   -- clk3x: toggles for every read word
   signal rtgl_a : std_logic := '0';   -- clk2x: rtgl as last seen

   function idx(p : unsigned) return integer is begin return to_integer(p) mod QDEPTH; end function;

begin

   ---------------------------------------------------------------- clk2x: queue writes, read data out
   -- full from the registered pointers: a slot freed on clk3x is seen one clk2x later
   full   <= '1' when (wp - rp_a) = QDEPTH else '0';
   a_busy <= full;

   process (clk2x)
   begin
      if rising_edge(clk2x) then
         rp_a <= rp;
         if (full = '0' and (a_rd = '1' or a_we = '1')) then
            q(idx(wp)) <= a_rd & a_addr & a_din & a_be & a_burstcnt & a_we;
            wp <= wp + 1;
         end if;

         rtgl_a       <= rtgl;
         a_dout_ready <= '0';
         if (rtgl_a /= rtgl) then
            a_dout       <= b_dout;
            a_dout_ready <= '1';
         end if;
      end if;
   end process;

   ---------------------------------------------------------------- clk3x: queue to vram_psram, read data in
   pend  <= '1' when wp_b /= rp else '0';
   entry <= q(idx(rp));
   b_rd       <= entry(entry'left) and pend;
   b_addr     <= entry(25 + 64 + 8 + 8 downto 64 + 8 + 8 + 1);
   b_din      <= entry(64 + 8 + 8 downto 8 + 8 + 1);
   b_be       <= entry(8 + 8 downto 8 + 1);
   b_burstcnt <= entry(8 downto 1);
   b_we       <= entry(0) and pend;

   process (clk3x)
   begin
      if rising_edge(clk3x) then
         wp_b <= wp;
         -- vram_psram takes a request on an edge with ddr_busy = '0'
         if (pend = '1' and b_busy = '0') then
            rp <= rp + 1;
         end if;
         if (b_dout_ready = '1') then
            rtgl <= not rtgl;
         end if;
      end if;
   end process;

end architecture;
