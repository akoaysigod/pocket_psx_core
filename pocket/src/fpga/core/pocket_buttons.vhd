-- Analogue Pocket: L2 / R2 for the handheld, which has neither. Two Core Settings pickers (interact.json) choose
-- how each is made; a docked controller's L2 / R2 always pass as well:
--   0  dock only: no change, every key passes
--   1  Select + R1 gives R2 (Select + L1 gives L2). While a Select-picker is chosen, Select is held back while
--      pressed: R1 (L1) pressed while Select is down gives R2 (L2) for as long as R1 (L1) is held, and R1 (L1)
--      itself stays off until it is released, also if Select is let go first. Releasing Select without having
--      made a combo sends Select for SELECT_MS (a tap, which is all SotN's map needs).
--   2  L1 + R1 together give the picker's button. The first of L1 / R1 pressed opens a WINDOW_MS window (the
--      game reads the pad once per frame, so a few frames): the other one pressed inside it gives the combo
--      (L1 / R1 stay off until both are released); when the window runs out the held button passes until
--      released; a button released inside the window is replayed as a TAP_MS press.
-- Keys in the APF cont1_key order (0 up, 1 down, 2 left, 3 right, 4 A, 5 B, 6 X, 7 Y, 8 L1, 9 R1, 10 L2, 11 R2,
-- 12 L3, 13 R3, 14 select, 15 start), already synchronised to clk; one clock of latency. The next state is computed
-- first and the keys come from it, so a key that turns into a combo never shows for even one clock.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pocket_buttons is
   generic
   (
      CLK_PER_MS : integer := 33869;   -- clk1x 33.8688 MHz
      WINDOW_MS  : integer := 50;
      TAP_MS     : integer := 50;
      SELECT_MS  : integer := 100
   );
   port
   (
      clk      : in  std_logic;
      cfg_r2   : in  std_logic_vector(1 downto 0);
      cfg_l2   : in  std_logic_vector(1 downto 0);
      keys_in  : in  std_logic_vector(15 downto 0);
      keys_out : out std_logic_vector(15 downto 0) := (others => '0')
   );
end entity;

architecture arch of pocket_buttons is

   constant K_L1  : integer := 8;
   constant K_R1  : integer := 9;
   constant K_L2  : integer := 10;
   constant K_R2  : integer := 11;
   constant K_SEL : integer := 14;

   signal pre       : integer range 0 to CLK_PER_MS - 1 := 0;
   signal ms_tick   : std_logic := '0';

   -- stage A: Select modifier
   signal sel_1, l1_1, r1_1 : std_logic := '0';
   signal comboL    : std_logic := '0';   -- L1 is being used as L2
   signal comboR    : std_logic := '0';   -- R1 is being used as R2
   signal sel_used  : std_logic := '0';   -- a combo was made during this Select press
   signal sel_pulse : integer range 0 to SELECT_MS := 0;

   -- stage B: L1 + R1
   type tState is (B_IDLE, B_WAIT, B_PASS, B_COMBO, B_TAP);
   signal st        : tState := B_IDLE;
   signal timer     : integer range 0 to 127 := 0;
   signal first_l, first_r : std_logic := '0';

begin

   process (clk)
      variable sel, l1, r1          : std_logic;
      variable selR, selL, selmode  : std_logic;
      variable pairR, pairL, pair   : std_logic;
      variable v_comboL, v_comboR, v_used : std_logic;
      variable v_pulse              : integer range 0 to SELECT_MS;
      variable sela, l1a, r1a       : std_logic;
      variable v_st                 : tState;
      variable v_timer              : integer range 0 to 127;
      variable v_first_l, v_first_r : std_logic;
      variable l1b, r1b, cb         : std_logic;
      variable k                    : std_logic_vector(15 downto 0);
   begin
      if rising_edge(clk) then
         ms_tick <= '0';
         if (pre = CLK_PER_MS - 1) then
            pre     <= 0;
            ms_tick <= '1';
         else
            pre <= pre + 1;
         end if;

         sel := keys_in(K_SEL);
         l1  := keys_in(K_L1);
         r1  := keys_in(K_R1);
         if (cfg_r2 = "01") then selR := '1'; else selR := '0'; end if;
         if (cfg_l2 = "01") then selL := '1'; else selL := '0'; end if;
         if (cfg_r2 = "10") then pairR := '1'; else pairR := '0'; end if;
         if (cfg_l2 = "10") then pairL := '1'; else pairL := '0'; end if;
         selmode := selR or selL;
         pair    := pairR or pairL;

         ------------------------------------------------ stage A: Select + L1 / R1
         v_comboL := comboL and l1;            -- a combo ends when its button is released
         v_comboR := comboR and r1;
         v_used   := sel_used;
         v_pulse  := sel_pulse;
         if (sel = '1' and sel_1 = '0') then
            v_used := '0';
         end if;
         if (selR = '1' and sel = '1' and r1 = '1' and r1_1 = '0') then
            v_comboR := '1';
            v_used   := '1';
         end if;
         if (selL = '1' and sel = '1' and l1 = '1' and l1_1 = '0') then
            v_comboL := '1';
            v_used   := '1';
         end if;
         if (ms_tick = '1' and v_pulse > 0) then
            v_pulse := v_pulse - 1;
         end if;
         if (selmode = '1' and sel = '0' and sel_1 = '1' and v_used = '0') then
            v_pulse := SELECT_MS;
         end if;

         if (selmode = '0') then
            sela := sel;
         elsif (v_pulse > 0) then
            sela := '1';
         else
            sela := '0';
         end if;
         l1a := l1 and not v_comboL;
         r1a := r1 and not v_comboR;

         ------------------------------------------------ stage B: L1 + R1
         v_st      := st;
         v_timer   := timer;
         v_first_l := first_l;
         v_first_r := first_r;
         if (pair = '0') then
            v_st := B_IDLE;
         else
            if (ms_tick = '1' and v_timer > 0) then
               v_timer := v_timer - 1;
            end if;
            case (st) is
               when B_IDLE =>
                  if (l1a = '1' and r1a = '1') then
                     v_st := B_COMBO;
                  elsif (l1a = '1' or r1a = '1') then
                     v_st      := B_WAIT;
                     v_timer   := WINDOW_MS;
                     v_first_l := l1a;
                     v_first_r := r1a;
                  end if;
               when B_WAIT =>
                  if (l1a = '1' and r1a = '1') then
                     v_st := B_COMBO;
                  elsif (l1a = '0' and r1a = '0') then   -- released inside the window: replay it
                     v_st    := B_TAP;
                     v_timer := TAP_MS;
                  elsif (v_timer = 0) then
                     v_st := B_PASS;
                  end if;
               when B_PASS | B_COMBO =>
                  if (l1a = '0' and r1a = '0') then
                     v_st := B_IDLE;
                  end if;
               when B_TAP =>
                  if (v_timer = 0) then
                     v_st := B_IDLE;
                  end if;
            end case;
         end if;

         l1b := '0';
         r1b := '0';
         cb  := '0';
         if (pair = '0') then
            l1b := l1a;
            r1b := r1a;
         else
            case (v_st) is
               when B_PASS  => l1b := l1a;       r1b := r1a;
               when B_TAP   => l1b := v_first_l; r1b := v_first_r;
               when B_COMBO => cb := '1';
               when others  => null;
            end case;
         end if;

         ------------------------------------------------ keys
         k         := keys_in;
         k(K_L1)   := l1b;
         k(K_R1)   := r1b;
         k(K_L2)   := keys_in(K_L2) or v_comboL or (cb and pairL);
         k(K_R2)   := keys_in(K_R2) or v_comboR or (cb and pairR);
         k(K_SEL)  := sela;
         keys_out  <= k;

         sel_1     <= sel;
         l1_1      <= l1;
         r1_1      <= r1;
         comboL    <= v_comboL;
         comboR    <= v_comboR;
         sel_used  <= v_used;
         sel_pulse <= v_pulse;
         st        <= v_st;
         timer     <= v_timer;
         first_l   <= v_first_l;
         first_r   <= v_first_r;
      end if;
   end process;

end architecture;
