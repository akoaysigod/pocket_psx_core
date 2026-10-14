-- Behavioural model of die 0 of an AS1C8M16PL (CellularRAM 1.5, address / data multiplexed).
-- Asynchronous mode (BCR(15) = 1, power-up): the address is latched from {a(21:16), dq} while adv_n is low,
-- writes store dq (byte lanes ub_n/lb_n) when we_n or the chip enable rises, reads drive dq while oe_n is low,
-- but only valid ACCESS_NS after adv_n went low ('X' before).
-- Configuration register writes: an asynchronous write with cre high while the address is latched writes
-- A(15:0) into the BCR when A(19:18) = 10.
-- Synchronous mode (BCR(15) = 0, fixed latency only): a rising clk edge with ce0_n, adv_n low and we_n high
-- starts a read burst at the latched address; with latency code N the word k of the burst is driven T_ACLK after
-- rising edge N + k counted from that edge ('X' from T_KOH after the edge before), while oe_n is low; ce0_n high
-- ends the burst. With we_n low on the start edge it is a write burst: word k is taken (byte lanes ub_n/lb_n) on
-- rising edge N + 1 + k. Asynchronous writes stay allowed (mixed mode) with the clock held still; a write with a
-- clock edge while we_n is low is a burst write.
-- Checks: never both chip enables, no access to a die's last word, setup / hold of adv_n, ce0_n, we_n and the
-- address against the rising clk edges of a burst start, clock period for the latency code, a burst crossing a
-- ROW_WORDS boundary (the real device would insert WAIT states), CE# low longer than tCEM, CE# high shorter than
-- tCBPH, no clock edge during an asynchronous write and no asynchronous read in synchronous mode.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity psram_model is
   generic
   (
      ACCESS_NS : time := 70 ns;
      INIT      : std_logic := 'U';   -- power-up contents
      T_ACLK    : time := 9 ns;       -- clock to output (83 / 48 MHz grades)
      T_KOH     : time := 2 ns;       -- output hold from clock
      T_SP      : time := 3 ns;       -- setup to the clock
      T_CSP     : time := 4 ns;       -- CE# setup to the clock
      T_HD      : time := 2 ns;       -- hold from the clock
      ROW_WORDS : integer := 128
   );
   port
   (
      a     : in    std_logic_vector(21 downto 16);
      dq    : inout std_logic_vector(15 downto 0);
      clk   : in    std_logic := '0';
      cre   : in    std_logic := '0';
      adv_n : in    std_logic;
      ce0_n : in    std_logic;
      ce1_n : in    std_logic;
      oe_n  : in    std_logic;
      we_n  : in    std_logic;
      ub_n  : in    std_logic;
      lb_n  : in    std_logic
   );
end entity;

architecture sim of psram_model is
   type tmem is array(0 to 2 ** 21 - 1) of std_logic_vector(15 downto 0);
   shared variable mem : tmem := (others => (others => INIT));
   signal addr       : integer := 0;
   signal addrFull   : std_logic_vector(21 downto 0) := (others => '0');
   signal creLatched : std_logic := '0';
   signal advTime    : time := 0 ns;
   signal bcr        : std_logic_vector(15 downto 0) := x"9D1F";
   signal driveA     : std_logic_vector(15 downto 0) := (others => 'Z');   -- asynchronous read
   signal driveS     : std_logic_vector(15 downto 0) := (others => 'Z');   -- synchronous read
   signal violations : integer := 0;
   signal writes     : integer := 0;
   signal bursts     : integer := 0;
   signal syncMode   : boolean;
begin
   syncMode <= bcr(15) = '0';
   dq <= driveS when syncMode else driveA;

   process (adv_n, a, dq, ce0_n, cre)
   begin
      if (adv_n = '0' and ce0_n = '0') then
         if (not is_x(dq) and not is_x(a)) then
            addr       <= to_integer(unsigned(a(20 downto 16)) & unsigned(dq));
            addrFull   <= a & dq;
            creLatched <= cre;
         end if;
      end if;
   end process;

   process (adv_n)
   begin
      if falling_edge(adv_n) then advTime <= now; end if;
   end process;

   -- asynchronous writes: byte enables and data are captured while the write is active (we_n and ce_n low);
   -- the write ends when either rises - the controller releases we_n, ce_n, ub_n/lb_n and dq on the same edge
   process (we_n, ce0_n, dq, lb_n, ub_n, clk)
      variable active   : boolean := false;
      variable clocked  : boolean := false;   -- a clock edge while we_n was low: a burst write, not this one
      variable lbv, ubv : std_logic := '1';
      variable dqv      : std_logic_vector(15 downto 0);
   begin
      if (we_n = '0' and ce0_n = '0') then
         if (not active) then clocked := false; end if;
         active := true;
         lbv := lb_n; ubv := ub_n; dqv := dq;
         if (syncMode and rising_edge(clk)) then clocked := true; end if;
      elsif active then
         active := false;
         if (clocked) then
            null;
         elsif (creLatched = '1') then
            assert addrFull(19 downto 18) = "10" report "register write to a register other than the BCR" severity error;
            if (addrFull(19 downto 18) = "10") then
               bcr <= addrFull(15 downto 0);
               report "BCR <= " & to_hstring(addrFull(15 downto 0));
            end if;
         else
            assert addr /= 2 ** 21 - 1 report "access to the die's last word" severity error;
            assert not is_x(dqv) or (lbv = '1' and ubv = '1') report "write with undefined data" severity error;
            if (lbv = '0') then mem(addr)(7 downto 0)  := dqv(7 downto 0);  end if;
            if (ubv = '0') then mem(addr)(15 downto 8) := dqv(15 downto 8); end if;
            writes <= writes + 1;
         end if;
      end if;
   end process;

   -- asynchronous reads (asynchronous mode only)
   process
   begin
      wait on oe_n, ce0_n, we_n, addr, advTime;
      assert not (ce0_n = '0' and ce1_n = '0') report "both chip enables active" severity error;
      if (oe_n = '0' and ce0_n = '0' and we_n = '1' and not syncMode) then
         if (now - advTime < ACCESS_NS) then
            driveA <= (others => 'X');
            wait for ACCESS_NS - (now - advTime);
            if (oe_n = '0' and ce0_n = '0') then driveA <= mem(addr); end if;
         else
            driveA <= mem(addr);
         end if;
      else
         driveA <= (others => 'Z');
      end if;
   end process;

   -- synchronous burst reads (fixed latency)
   process
      variable active    : boolean := false;
      variable edgeNum   : integer := 0;
      variable base      : integer := 0;
      variable lat       : integer;
      variable w         : integer;
      variable lastRise  : time := -1 us;
      variable startTime : time := 0 ns;
      variable outWord   : std_logic_vector(15 downto 0);
      variable writing   : boolean := false;
      procedure fail(msg : string) is
      begin
         report msg severity error;
         violations <= violations + 1;
      end procedure;
   begin
      wait until rising_edge(clk) or ce0_n'event or oe_n'event;
      if (ce0_n = '1') then
         active := false;
         driveS <= (others => 'Z');
      elsif (oe_n'event and oe_n = '1') then
         driveS <= (others => 'Z');
      elsif rising_edge(clk) and syncMode then
         -- clock period for fixed latency code 3: at most 52 MHz
         if (now - lastRise < 19.2 ns) then fail("PSRAM clock period " & time'image(now - lastRise)); end if;
         lastRise := now;
         if (ce0_n = '0' and adv_n = '0') then
            -- burst start
            if (adv_n'last_event < T_SP) then fail("adv_n setup"); end if;
            if (ce0_n'last_event < T_CSP) then fail("ce_n setup"); end if;
            if (we_n'last_event < T_SP) then fail("we_n setup"); end if;
            if (dq'last_event < T_SP or a'last_event < T_SP) then fail("address setup"); end if;
            if (is_x(dq) or is_x(a)) then fail("undefined address"); end if;
            assert bcr(14) = '1' report "model: only fixed latency is modelled" severity failure;
            active  := true;
            writing := we_n = '0';
            edgeNum := 0;
            base    := to_integer(unsigned(a(20 downto 16)) & unsigned(dq));
            startTime := now;
            bursts  <= bursts + 1;
            -- hold of the burst start inputs
            wait for T_HD;
            if (adv_n'last_event < T_HD or ce0_n'last_event < T_HD or we_n'last_event < T_HD or
                a'last_event < T_HD or dq'last_event < T_HD) then
               fail("hold after the burst start edge");
            end if;
         elsif active then
            edgeNum := edgeNum + 1;
            lat := to_integer(unsigned(bcr(13 downto 11)));
            if (lat = 0) then lat := 8; end if;
            if (writing and edgeNum >= lat + 1) then
               w := base + edgeNum - lat - 1;
               if ((w / ROW_WORDS) /= (base / ROW_WORDS)) then fail("write burst crosses a row boundary at word " & integer'image(w)); end if;
               if (w = 2 ** 21 - 1) then fail("access to the die's last word"); end if;
               if (dq'last_event < T_SP or lb_n'last_event < T_SP or ub_n'last_event < T_SP) then fail("write data setup"); end if;
               if (we_n = '0') then fail("we_n low during a write burst's data"); end if;
               if (lb_n = '0') then
                  if is_x(dq(7 downto 0)) then fail("burst write with undefined data"); end if;
                  mem(w mod 2 ** 21)(7 downto 0) := dq(7 downto 0);
               end if;
               if (ub_n = '0') then
                  if is_x(dq(15 downto 8)) then fail("burst write with undefined data"); end if;
                  mem(w mod 2 ** 21)(15 downto 8) := dq(15 downto 8);
               end if;
               wait for T_HD;
               if (dq'last_event < T_HD or lb_n'last_event < T_HD or ub_n'last_event < T_HD) then fail("write data hold"); end if;
            elsif (not writing and edgeNum >= lat) then
               w := base + edgeNum - lat;
               if ((w / ROW_WORDS) /= (base / ROW_WORDS)) then fail("burst crosses a row boundary at word " & integer'image(w)); end if;
               if (w = 2 ** 21 - 1) then fail("access to the die's last word"); end if;
               outWord := mem(w mod 2 ** 21);
               if (oe_n = '0') then
                  driveS <= transport (others => 'X') after T_KOH;
                  driveS <= transport outWord after T_ACLK;
               end if;
            end if;
         end if;
      end if;
   end process;

   -- CE# low / high times
   process (ce0_n)
      variable tFall, tRise : time := 0 ns;
   begin
      if falling_edge(ce0_n) then
         if (now - tRise < 6 ns and now > 100 ns) then report "CE# high shorter than tCBPH" severity error; end if;
         if (now - tRise < 15 ns and now > 100 ns) then report "CE# high shorter than 15 ns (no refresh opportunity)" severity error; end if;
         tFall := now;
      elsif rising_edge(ce0_n) then
         if (now - tFall > 4 us) then report "CE# low longer than tCEM" severity error; end if;
         tRise := now;
      end if;
   end process;

   process
   begin
      wait on oe_n, ce0_n;
      if (syncMode and oe_n = '0' and ce0_n = '0' and we_n = '1' and clk = '0' and adv_n = '1') then
         -- OE# low in synchronous mode only within a burst (asynchronous reads are not allowed in mixed mode)
         null;
      end if;
   end process;

   process begin for i in mem'range loop mem(i) := (others => '0'); end loop; wait; end process;
end architecture;
