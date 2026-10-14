library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Area-reduced MAC1-3 request for gte_small.
-- Every MAC1-3 term in the GTE is either a 16x16 signed product or a 32 bit
-- value scaled by a power of two (1, 0x10, 0x1000, 0x10000), so the 32x32
-- multiplier of tMAC123req is replaced by a 16x16 multiplier plus a shifter.
package pGTEs is

   type tMAC123sreq is record
      mulA        : signed(15 downto 0);
      mulB        : signed(15 downto 0);
      shVal       : signed(31 downto 0);
      shAmt       : unsigned(1 downto 0); -- 0: <<0, 1: <<4, 2: <<12, 3: <<16
      isShift     : std_logic;
      add         : signed(44 downto 0);
      sub         : std_logic;
      swap        : std_logic;
      saveShifted : std_logic;
      useIR       : std_logic;
      IRshift     : std_logic;
      IRshiftFlag : std_logic;
      satIR       : std_logic;
      satIRFlag   : std_logic;
      useResult   : std_logic;
      trigger     : std_logic;
   end record;

   constant SH0  : unsigned(1 downto 0) := "00";
   constant SH4  : unsigned(1 downto 0) := "01";
   constant SH12 : unsigned(1 downto 0) := "10";
   constant SH16 : unsigned(1 downto 0) := "11";

   -- product request: a * b + add
   function mreq(a : signed; b : signed; add : signed(44 downto 0);
                 sub, swap, svSh, useIR, IRs, IRsF, satIR, satIRF, uRes, trig : std_logic) return tMAC123sreq;

   -- shift request: (v << sh) + add
   function sreq(v : signed; sh : unsigned(1 downto 0); add : signed(44 downto 0);
                 sub, swap, svSh, useIR, IRs, IRsF, satIR, satIRF, uRes, trig : std_logic) return tMAC123sreq;

end package;

package body pGTEs is

   function mreq(a : signed; b : signed; add : signed(44 downto 0);
                 sub, swap, svSh, useIR, IRs, IRsF, satIR, satIRF, uRes, trig : std_logic) return tMAC123sreq is
      variable r : tMAC123sreq;
   begin
      r.mulA        := resize(a, 16);
      r.mulB        := resize(b, 16);
      r.shVal       := (others => '0');
      r.shAmt       := SH0;
      r.isShift     := '0';
      r.add         := add;
      r.sub         := sub;
      r.swap        := swap;
      r.saveShifted := svSh;
      r.useIR       := useIR;
      r.IRshift     := IRs;
      r.IRshiftFlag := IRsF;
      r.satIR       := satIR;
      r.satIRFlag   := satIRF;
      r.useResult   := uRes;
      r.trigger     := trig;
      return r;
   end function;

   function sreq(v : signed; sh : unsigned(1 downto 0); add : signed(44 downto 0);
                 sub, swap, svSh, useIR, IRs, IRsF, satIR, satIRF, uRes, trig : std_logic) return tMAC123sreq is
      variable r : tMAC123sreq;
   begin
      r.mulA        := (others => '0');
      r.mulB        := (others => '0');
      r.shVal       := resize(v, 32);
      r.shAmt       := sh;
      r.isShift     := '1';
      r.add         := add;
      r.sub         := sub;
      r.swap        := swap;
      r.saveShifted := svSh;
      r.useIR       := useIR;
      r.IRshift     := IRs;
      r.IRshiftFlag := IRsF;
      r.satIR       := satIR;
      r.satIRFlag   := satIRF;
      r.useResult   := uRes;
      r.trigger     := trig;
      return r;
   end function;

end package body;
