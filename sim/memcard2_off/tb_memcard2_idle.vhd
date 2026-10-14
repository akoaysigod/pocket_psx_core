-- Proof-by-simulation that memory card slot 2 is inert when no card is present
-- (memcard2_available = '0', memcard2_load = '0', memcard2_mounted = '0'):
-- joypad_mem never touches memory, so memcard never sees a change, so it never
-- leaves IDLE. This justifies removing imemcard2 and tying its outputs to '0'.
-- MUTATE=1: card available + mounted + load pulses -> outputs must move (checker sensitivity).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_memcard2_idle is
   generic (NUM_CYCLES : integer := 200000; SEED : integer := 1; MUTATE : integer := 0);
end entity;

architecture sim of tb_memcard2_idle is
   signal clk1x, clk2x, clk2xIndex : std_logic := '0';
   signal reset        : std_logic := '1';
   signal available    : std_logic := '0';
   signal mounted      : std_logic := '0';
   signal load         : std_logic := '0';
   signal save         : std_logic := '0';
   signal ce           : std_logic := '1';
   signal selected, actionNext, transmitting, slotIdle : std_logic := '0';
   signal transmitValue : std_logic_vector(7 downto 0) := x"00";
   signal jm_ack_in, mc_mem_ack, mc_card_ack, system_paused, dout_ready : std_logic := '0';
   signal mem_DOUT      : std_logic_vector(63 downto 0) := (others => '0');
   signal card_write    : std_logic := '0';
   signal card_addr     : std_logic_vector(8 downto 0) := (others => '0');
   signal card_dataIn   : std_logic_vector(15 downto 0) := (others => '0');

   -- joypad_mem outputs
   signal jm_request, jm_WE, jm_RD, jm_isActive, jm_receiveValid, jm_ack : std_logic;
   signal jm_receiveBuffer : std_logic_vector(7 downto 0);
   signal jm_BURSTCNT, jm_BE : std_logic_vector(7 downto 0);
   signal jm_ADDR : std_logic_vector(19 downto 0);
   signal jm_DIN  : std_logic_vector(63 downto 0);
   -- memcard outputs
   signal mc_pause, mc_changePending, mc_saving, mc_request, mc_WE, mc_RD, mc_rd_card, mc_wr_card : std_logic;
   signal mc_BURSTCNT, mc_BE : std_logic_vector(7 downto 0);
   signal mc_ADDR : std_logic_vector(19 downto 0);
   signal mc_DIN  : std_logic_vector(63 downto 0);
   signal mc_lba  : std_logic_vector(6 downto 0);
   signal mc_dataOut : std_logic_vector(15 downto 0);
   signal done : boolean := false;
begin
   clk2x <= not clk2x after 7 ns when not done;
   process (clk2x) begin if rising_edge(clk2x) then clk1x <= not clk1x; clk2xIndex <= not clk1x; end if; end process;

   ijm : entity work.joypad_mem
   port map (clk1x => clk1x, clk2x => clk2x, clk2xIndex => clk2xIndex, ce => ce, reset => reset,
      memcard_available => available,
      mem_request => jm_request, mem_BURSTCNT => jm_BURSTCNT, mem_ADDR => jm_ADDR, mem_DIN => jm_DIN,
      mem_BE => jm_BE, mem_WE => jm_WE, mem_RD => jm_RD, mem_ack => jm_ack_in, mem_DOUT => mem_DOUT, mem_DOUT_READY => dout_ready,
      selected => selected, actionNext => actionNext, transmitting => transmitting, transmitValue => transmitValue,
      isActive => jm_isActive, slotIdle => slotIdle, receiveValid => jm_receiveValid, receiveBuffer => jm_receiveBuffer, ack => jm_ack);

   imc : entity work.memcard
   port map (clk2x => clk2x, ce => ce, reset => reset, save => save, load => load,
      pause => mc_pause, system_paused => system_paused, mounted => mounted, anyChange => jm_WE,
      changePending => mc_changePending, saving_memcard => mc_saving,
      mem_request => mc_request, mem_BURSTCNT => mc_BURSTCNT, mem_ADDR => mc_ADDR, mem_DIN => mc_DIN, mem_BE => mc_BE,
      mem_WE => mc_WE, mem_RD => mc_RD, mem_ack => mc_mem_ack, mem_DOUT => mem_DOUT, mem_DOUT_READY => dout_ready,
      memcard_rd => mc_rd_card, memcard_wr => mc_wr_card, memcard_lba => mc_lba, memcard_ack => mc_card_ack,
      memcard_write => card_write, memcard_addr => card_addr, memcard_dataIn => card_dataIn, memcard_dataOut => mc_dataOut);

   stim : process
      variable s1 : positive := 7 + SEED;
      variable s2 : positive := 1234567;
      variable r  : real;
      variable activity : integer := 0;
      variable resets   : integer := 0;
      variable saves    : integer := 0;
      variable jm_moves : integer := 0;
      impure function rnd return std_logic is begin uniform(s1, s2, r); if r < 0.5 then return '0'; else return '1'; end if; end function;
      impure function rndp(p : real) return std_logic is begin uniform(s1, s2, r); if r < p then return '1'; else return '0'; end if; end function;
      impure function rndv(n : integer) return std_logic_vector is
         variable v : std_logic_vector(n - 1 downto 0);
      begin for i in v'range loop v(i) := rnd; end loop; return v; end function;
   begin
      if MUTATE = 1 then available <= '1'; mounted <= '1'; end if;
      for i in 1 to 20 loop wait until rising_edge(clk2x); end loop;
      reset <= '0';
      for c in 1 to NUM_CYCLES loop
         wait until rising_edge(clk2x);
         -- random environment
         ce            <= rndp(0.9);
         selected      <= rndp(0.6);
         actionNext    <= rndp(0.2);
         transmitting  <= rndp(0.5);
         slotIdle      <= rndp(0.7);
         transmitValue <= rndv(8);
         if rndp(0.3) = '1' then transmitValue <= x"81"; end if;           -- memory card address byte
         if rndp(0.1) = '1' then transmitValue <= x"57"; end if;           -- write command
         if rndp(0.1) = '1' then transmitValue <= x"52"; end if;           -- read command
         jm_ack_in     <= rndp(0.3);
         mc_mem_ack    <= rndp(0.3);
         mc_card_ack   <= rndp(0.3);
         system_paused <= rndp(0.5);
         dout_ready    <= rndp(0.5);
         mem_DOUT      <= rndv(64);
         card_write    <= rndp(0.2);
         card_addr     <= rndv(9);
         card_dataIn   <= rndv(16);
         save          <= rndp(0.01);
         if save = '1' then saves := saves + 1; end if;
         if MUTATE = 1 then load <= rndp(0.001); end if;
         if rndp(0.0005) = '1' then reset <= '1'; resets := resets + 1; else reset <= '0'; end if;
         -- the claim: everything memory card 2 drives stays inactive
         if (jm_request /= '0' or jm_WE /= '0' or jm_RD /= '0' or jm_isActive /= '0' or jm_receiveValid /= '0' or jm_ack /= '0' or jm_receiveBuffer /= x"00") then
            jm_moves := jm_moves + 1;
         end if;
         if (mc_pause /= '0' or mc_changePending /= '0' or mc_saving /= '0' or mc_request /= '0' or
             mc_WE /= '0' or mc_RD /= '0' or mc_rd_card /= '0' or mc_wr_card /= '0') then
            activity := activity + 1;
         end if;
      end loop;
      report "DONE cycles=" & integer'image(NUM_CYCLES) & " resets=" & integer'image(resets) & " save_pulses=" & integer'image(saves) &
             " joypad_mem_active_cycles=" & integer'image(jm_moves) & " memcard_active_cycles=" & integer'image(activity);
      if (activity = 0 and jm_moves = 0) then report "PASS (slot 2 inert)"; else report "FAIL / slot active"; end if;
      done <= true;
      wait;
   end process;
end architecture;
