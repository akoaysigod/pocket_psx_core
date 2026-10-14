-- 256 valid bits with single-cycle "clear all", for the Pocket build (replaces 256 flip-flops and
-- their 256:1 read multiplexer). Behaves exactly like:
--    if clearAll then bits := (others => '0'); elsif setEna then bits(setAddr) := '1'; end if;
--    q = bits(rdAddr)   (combinational, shows the state after the last clock edge)
-- The bits are kept as 16 words of 16 in MLAB. "Clear all" only marks every word stale; the first
-- set into a stale word writes the whole word (just that bit), later sets read-modify-write it.
-- A second MLAB copy provides the read port for the read-modify-write.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library mem;

entity ValidBits256 is
   port
   (
      clk      : in  std_logic;
      clearAll : in  std_logic;
      setEna   : in  std_logic;
      setAddr  : in  unsigned(7 downto 0);
      rdAddr   : in  unsigned(7 downto 0);
      q        : out std_logic
   );
end entity;

architecture arch of ValidBits256 is

   signal stale     : std_logic_vector(15 downto 0) := (others => '1');  -- power-up: all bits read 0
   signal wren      : std_logic;
   signal wrData    : std_logic_vector(15 downto 0);
   signal rdWord    : std_logic_vector(15 downto 0);
   signal setWord   : std_logic_vector(15 downto 0);

begin

   wren <= setEna and (not clearAll);

   process (all)
      variable w : std_logic_vector(15 downto 0);
   begin
      if (stale(to_integer(setAddr(7 downto 4))) = '1') then
         w := (others => '0');
      else
         w := setWord;
      end if;
      w(to_integer(setAddr(3 downto 0))) := '1';
      wrData <= w;
   end process;

   iread : entity mem.RamMLAB
   generic map (width => 16, widthad => 4)
   port map (inclock => clk, wren => wren, data => wrData, wraddress => std_logic_vector(setAddr(7 downto 4)),
             rdaddress => std_logic_vector(rdAddr(7 downto 4)), q => rdWord);

   irmw : entity mem.RamMLAB
   generic map (width => 16, widthad => 4)
   port map (inclock => clk, wren => wren, data => wrData, wraddress => std_logic_vector(setAddr(7 downto 4)),
             rdaddress => std_logic_vector(setAddr(7 downto 4)), q => setWord);

   process (clk)
   begin
      if rising_edge(clk) then
         if (clearAll = '1') then
            stale <= (others => '1');
         elsif (setEna = '1') then
            stale(to_integer(setAddr(7 downto 4))) <= '0';
         end if;
      end if;
   end process;

   q <= rdWord(to_integer(rdAddr(3 downto 0))) and (not stale(to_integer(rdAddr(7 downto 4))));

end architecture;
