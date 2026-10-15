-- Testbench for pocket/src/fpga/core/pocket_buttons.vhd (L2 / R2 button combos), with a short millisecond
-- (CLK_PER_MS clocks) so the windows take few clocks; checks at millisecond points away from the edges and
-- "never" checks (a key must not show for even one clock during a whole scenario):
--  * both pickers 0: random keys, the output equals the input one clock later on every clock
--  * Select + R1 / L1: Select held back and sent as a pulse only without a combo; the combo gives R2 / L2 only,
--    also when Select is released first; R1 held before Select stays R1; L1 passes when only R2 uses Select
--  * L1 + R1: lone press held for the window then passes; tap replayed after release; second press inside the
--    window gives the combo only, outside it both pass; both pickers on L1 + R1 give L2 and R2
--  * dock L2 / R2 pass in every mode; changing a picker during a press leaves no key stuck; both modes at once
-- WINDOW_DUT replaces the module's window (self check: 1 ms must fail).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_pocket_buttons is
   generic
   (
      CLK_PER_MS : integer := 20;
      WINDOW_DUT : integer := 50
   );
end entity;

architecture sim of tb_pocket_buttons is

   constant K_L1  : integer := 8;
   constant K_R1  : integer := 9;
   constant K_L2  : integer := 10;
   constant K_R2  : integer := 11;
   constant K_SEL : integer := 14;

   signal clk      : std_logic := '0';
   signal done     : boolean := false;
   signal cfg_r2   : std_logic_vector(1 downto 0) := "00";
   signal cfg_l2   : std_logic_vector(1 downto 0) := "00";
   signal keys_in  : std_logic_vector(15 downto 0) := (others => '0');
   signal keys_out : std_logic_vector(15 downto 0);

   signal clr      : std_logic := '0';
   signal ever     : std_logic_vector(15 downto 0) := (others => '0');
   signal check_pass : std_logic := '0';
   signal last_in  : std_logic_vector(15 downto 0) := (others => '0');
   signal pass_errors : integer := 0;

begin

   clk <= not clk after 5 ns when not done;

   idut : entity work.pocket_buttons
   generic map (CLK_PER_MS => CLK_PER_MS, WINDOW_MS => WINDOW_DUT, TAP_MS => 50, SELECT_MS => 100)
   port map (clk => clk, cfg_r2 => cfg_r2, cfg_l2 => cfg_l2, keys_in => keys_in, keys_out => keys_out);

   -- keys seen since the last clr
   process (clk)
   begin
      if rising_edge(clk) then
         if (clr = '1') then
            ever <= (others => '0');
         else
            ever <= ever or keys_out;
         end if;
         last_in <= keys_in;
         if (check_pass = '1' and keys_out /= last_in) then
            if (pass_errors < 5) then
               report "pass-through: out " & to_hstring(keys_out) & " expected " & to_hstring(last_in) severity error;
            end if;
            pass_errors <= pass_errors + 1;
         end if;
      end if;
   end process;

   process
      variable errors : integer := 0;
      variable checks : integer := 0;
      variable s1, s2 : positive := 7;
      variable u      : real;
      variable k      : std_logic_vector(15 downto 0);

      procedure clocks(n : integer) is
      begin
         for i in 1 to n loop wait until rising_edge(clk); end loop;
      end procedure;

      procedure ms(n : real) is
      begin
         clocks(integer(n * real(CLK_PER_MS)));
      end procedure;

      procedure key(b : integer; v : std_logic) is
      begin
         keys_in(b) <= v;
         wait until rising_edge(clk);
      end procedure;

      procedure chk(b : integer; v : std_logic; what : string) is
      begin
         checks := checks + 1;
         if (keys_out(b) /= v) then
            report what & ": key " & integer'image(b) & " is " & std_logic'image(keys_out(b)) severity error;
            errors := errors + 1;
         end if;
      end procedure;

      procedure never(b : integer; what : string) is
      begin
         checks := checks + 1;
         if (ever(b) /= '0') then
            report what & ": key " & integer'image(b) & " showed" severity error;
            errors := errors + 1;
         end if;
      end procedure;

      procedure start(what : string) is
      begin
         report what;
         keys_in <= (others => '0');
         ms(200.0);                   -- everything settled and released
         clr <= '1';
         wait until rising_edge(clk);
         clr <= '0';
      end procedure;

      procedure setcfg(r2, l2 : std_logic_vector(1 downto 0)) is
      begin
         keys_in <= (others => '0');
         ms(200.0);
         cfg_r2  <= r2;
         cfg_l2  <= l2;
         ms(5.0);
      end procedure;

   begin
      ms(5.0);

      ---------------- pickers 0 / 0: pass-through on every clock
      report "pass-through, random keys";
      check_pass <= '1';
      for n in 1 to 20000 loop
         k := keys_in;
         for b in 0 to 15 loop
            uniform(s1, s2, u);
            if (u < 0.05) then k(b) := not k(b); end if;
         end loop;
         keys_in <= k;
         wait until rising_edge(clk);
      end loop;
      check_pass <= '0';

      ---------------- R2 = Select + R1
      setcfg("01", "00");
      start("Select tap");
      key(K_SEL, '1'); ms(20.0); chk(K_SEL, '0', "Select held back");
      key(K_SEL, '0'); ms(5.0); chk(K_SEL, '1', "Select pulse start");
      ms(85.0); chk(K_SEL, '1', "Select pulse 90 ms");
      ms(15.0); chk(K_SEL, '0', "Select pulse over");
      never(K_R1, "Select tap"); never(K_R2, "Select tap");

      start("Select + R1, R1 released first");
      key(K_SEL, '1'); ms(10.0); key(K_R1, '1'); ms(5.0);
      chk(K_R2, '1', "combo R2"); chk(K_R1, '0', "combo R1");
      ms(50.0); key(K_R1, '0'); ms(2.0); chk(K_R2, '0', "R2 after R1 release");
      ms(10.0); key(K_SEL, '0'); ms(150.0);
      never(K_R1, "Select + R1"); never(K_SEL, "Select + R1");

      start("Select + R1, Select released first");
      key(K_SEL, '1'); ms(10.0); key(K_R1, '1'); ms(10.0); key(K_SEL, '0'); ms(30.0);
      chk(K_R2, '1', "R2 after Select release"); chk(K_R1, '0', "R1 after Select release");
      key(K_R1, '0'); ms(2.0); chk(K_R2, '0', "R2 released"); ms(120.0);
      never(K_R1, "Select first"); never(K_SEL, "Select first");

      start("R1 alone");
      key(K_R1, '1'); ms(1.0); chk(K_R1, '1', "R1 at once"); ms(50.0);
      key(K_R1, '0'); ms(1.0); chk(K_R1, '0', "R1 released"); never(K_R2, "R1 alone");

      start("R1 held, then Select");
      key(K_R1, '1'); ms(10.0); key(K_SEL, '1'); ms(10.0);
      chk(K_R1, '1', "R1 stays R1"); chk(K_R2, '0', "no R2");
      key(K_SEL, '0'); ms(5.0); chk(K_SEL, '1', "Select pulse (no combo)");
      key(K_R1, '0'); ms(120.0); never(K_R2, "R1 then Select");

      start("Select + L1 while only R2 uses Select");
      key(K_SEL, '1'); ms(10.0); key(K_L1, '1'); ms(5.0);
      chk(K_L1, '1', "L1 passes"); chk(K_L2, '0', "no L2");
      key(K_L1, '0'); ms(5.0); key(K_SEL, '0'); ms(5.0); chk(K_SEL, '1', "Select pulse");
      ms(110.0); never(K_L2, "Select + L1");

      start("dock R2");
      key(K_R2, '1'); ms(2.0); chk(K_R2, '1', "dock R2"); key(K_R2, '0'); ms(2.0); chk(K_R2, '0', "dock R2 off");

      ---------------- R2 and L2 = Select + R1 / L1
      setcfg("01", "01");
      start("Select + L1 -> L2");
      key(K_SEL, '1'); ms(10.0); key(K_L1, '1'); ms(5.0);
      chk(K_L2, '1', "combo L2"); chk(K_L1, '0', "combo L1"); chk(K_R2, '0', "no R2");
      key(K_L1, '0'); key(K_SEL, '0'); ms(120.0);
      never(K_L1, "Select + L1"); never(K_SEL, "Select + L1");

      ---------------- R2 = L1 + R1
      setcfg("10", "00");
      start("L1 tap");
      key(K_L1, '1'); ms(20.0); chk(K_L1, '0', "L1 held in the window");
      key(K_L1, '0'); ms(5.0); chk(K_L1, '1', "tap replay start");
      ms(35.0); chk(K_L1, '1', "tap replay 40 ms"); ms(15.0); chk(K_L1, '0', "tap replay over");
      never(K_R2, "L1 tap"); never(K_R1, "L1 tap");

      start("L1 hold");
      key(K_L1, '1'); ms(45.0); chk(K_L1, '0', "L1 inside the window");
      ms(10.0); chk(K_L1, '1', "L1 after the window"); ms(140.0); chk(K_L1, '1', "L1 held");
      key(K_L1, '0'); ms(2.0); chk(K_L1, '0', "L1 released"); never(K_R2, "L1 hold");

      start("L1 then R1 inside the window");
      key(K_L1, '1'); ms(20.0); key(K_R1, '1'); ms(5.0); chk(K_R2, '1', "combo R2");
      ms(100.0); chk(K_R2, '1', "combo R2 held");
      key(K_L1, '0'); ms(30.0); chk(K_R2, '1', "R2 while R1 still held"); chk(K_R1, '0', "no R1 after L1 release");
      key(K_R1, '0'); ms(2.0); chk(K_R2, '0', "R2 released"); ms(60.0);
      never(K_L1, "L1 + R1"); never(K_R1, "L1 + R1");

      start("R1 then L1 outside the window");
      key(K_R1, '1'); ms(80.0); chk(K_R1, '1', "R1 after the window");
      key(K_L1, '1'); ms(5.0); chk(K_L1, '1', "L1 passes"); ms(20.0); chk(K_R2, '0', "no combo");
      keys_in(K_L1) <= '0'; key(K_R1, '0'); ms(2.0); chk(K_R1, '0', "R1 off"); chk(K_L1, '0', "L1 off");
      never(K_R2, "outside the window");

      start("L1 and R1 on the same clock");
      keys_in(K_L1) <= '1'; key(K_R1, '1'); ms(2.0); chk(K_R2, '1', "combo at once");
      keys_in(K_L1) <= '0'; key(K_R1, '0'); ms(60.0);
      never(K_L1, "same clock"); never(K_R1, "same clock");

      start("dock R2 in L1 + R1 mode");
      key(K_R2, '1'); ms(2.0); chk(K_R2, '1', "dock R2"); key(K_R2, '0'); ms(2.0); chk(K_R2, '0', "dock R2 off");

      ---------------- R2 and L2 = L1 + R1
      setcfg("10", "10");
      start("L1 + R1 -> L2 and R2");
      key(K_L1, '1'); ms(10.0); key(K_R1, '1'); ms(5.0); chk(K_R2, '1', "R2"); chk(K_L2, '1', "L2");
      keys_in(K_L1) <= '0'; key(K_R1, '0'); ms(60.0);
      never(K_L1, "both pickers"); never(K_R1, "both pickers");

      ---------------- picker changed during a press
      setcfg("10", "00");
      start("L1 + R1 combo, picker set to dock only");
      key(K_L1, '1'); ms(10.0); key(K_R1, '1'); ms(5.0); chk(K_R2, '1', "combo");
      cfg_r2 <= "00"; ms(2.0);
      chk(K_R2, '0', "combo gone"); chk(K_L1, '1', "L1 passes"); chk(K_R1, '1', "R1 passes");
      keys_in(K_L1) <= '0'; key(K_R1, '0'); ms(2.0);
      chk(K_L1, '0', "L1 off"); chk(K_R1, '0', "R1 off"); chk(K_R2, '0', "R2 off");

      setcfg("01", "00");
      start("Select + R1 combo, picker set to dock only");
      key(K_SEL, '1'); ms(10.0); key(K_R1, '1'); ms(5.0); chk(K_R2, '1', "combo");
      cfg_r2 <= "00"; ms(2.0); chk(K_R2, '1', "combo kept until R1 is released"); chk(K_R1, '0', "R1 still off");
      key(K_R1, '0'); ms(2.0); chk(K_R2, '0', "R2 off");
      key(K_SEL, '0'); ms(120.0); chk(K_SEL, '0', "Select off"); chk(K_R1, '0', "R1 off");

      ---------------- R2 = Select + R1 and L2 = L1 + R1 together
      setcfg("01", "10");
      start("both modes: Select + R1");
      key(K_SEL, '1'); ms(10.0); key(K_R1, '1'); ms(5.0); chk(K_R2, '1', "R2"); ms(60.0);
      chk(K_R1, '0', "R1 not passed on by the L1 + R1 stage");
      key(K_R1, '0'); key(K_SEL, '0'); ms(120.0);
      never(K_R1, "both modes"); never(K_L2, "both modes"); never(K_SEL, "both modes");

      start("both modes: L1 + R1");
      key(K_L1, '1'); ms(10.0); key(K_R1, '1'); ms(5.0); chk(K_L2, '1', "L2"); chk(K_R2, '0', "no R2");
      keys_in(K_L1) <= '0'; key(K_R1, '0'); ms(60.0);
      never(K_L1, "both modes L1 + R1"); never(K_R1, "both modes L1 + R1");

      errors := errors + pass_errors;
      report "DONE checks=" & integer'image(checks) & " errors=" & integer'image(errors) &
             " (pass-through errors " & integer'image(pass_errors) & ")";
      if (errors = 0) then report "PASS"; else report "FAIL"; end if;
      done <= true;
      wait;
   end process;

end architecture;
