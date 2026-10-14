-- Asynchronous-mode PSRAM (cellular RAM) controller for the Analogue Pocket (AS1C8M16PL), one 16-bit access
-- at a time. VHDL port of psram.sv from agg23/analogue-pocket-utils, same state sequence and timing.
--
-- MIT License
--
-- Copyright (c) 2022 Adam Gastineau
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity psram_async is
   generic
   (
      CLOCK_SPEED                       : real := 67.7376;  -- MHz
      -- shared async
      MIN_ADV_N_PULSE                   : real := 5.0;   -- t_vp
      MIN_ADDRESS_SETUP_BEFORE_ADV_HIGH : real := 5.0;   -- t_avs
      MIN_ADDRESS_HOLD_AFTER_ADV_HIGH   : real := 2.0;   -- t_avh
      MIN_CE_BEFORE_ADV_HIGH            : real := 7.0;   -- t_cvs
      -- writes
      MIN_DATA_SETUP_BEFORE_WE_HIGH     : real := 20.0;  -- t_dw
      MIN_DATA_AFTER_ADDR_UNLATCHED     : real := 8.0;   -- not in the datasheet (guess of the original)
      MIN_WRITE_PULSE                   : real := 45.0;  -- t_wp
      MIN_WRITE_TIME_FROM_ADV           : real := 70.0;  -- t_aw
      -- reads
      MIN_OE_AFTER_ADDR_UNLATCHED       : real := 3.0;   -- not in the datasheet (guess of the original)
      MAX_ACCESS_TIME_FROM_ADV          : real := 70.0
   );
   port
   (
      clk             : in  std_logic;
      bank_sel        : in  std_logic;
      addr            : in  unsigned(21 downto 0);
      write_en        : in  std_logic;
      data_in         : in  std_logic_vector(15 downto 0);
      write_high_byte : in  std_logic;
      write_low_byte  : in  std_logic;
      read_en         : in  std_logic;
      read_avail      : out std_logic := '0';
      data_out        : out std_logic_vector(15 downto 0) := (others => '0');
      busy            : out std_logic := '0';
      -- PSRAM pins
      cram_a          : out std_logic_vector(21 downto 16) := (others => '0');
      cram_dq_out     : out std_logic_vector(15 downto 0);
      cram_dq_oe      : out std_logic;
      cram_dq_in      : in  std_logic_vector(15 downto 0);
      cram_clk        : out std_logic := '0';
      cram_adv_n      : out std_logic := '1';
      cram_cre        : out std_logic := '0';
      cram_ce0_n      : out std_logic := '1';
      cram_ce1_n      : out std_logic := '1';
      cram_oe_n       : out std_logic := '1';
      cram_we_n       : out std_logic := '1';
      cram_ub_n       : out std_logic := '1';
      cram_lb_n       : out std_logic := '1'
   );
end entity;

architecture arch of psram_async is

   -- same rounding as the original CEIL macro: round, and one more if that did not exceed x
   function cyc(ns : real) return integer is
      constant x : real := ns / (1000.0 / CLOCK_SPEED);
      constant r : integer := integer(x);
   begin
      if (real(r) > x) then return r; else return r + 1; end if;
   end function;

   function maxi(a, b : integer) return integer is begin if a > b then return a; else return b; end if; end function;
   function maxr(a, b : real) return real is begin if a > b then return a; else return b; end if; end function;

   constant ADV_PULSE_CYCLE_COUNT                : integer := cyc(MIN_ADV_N_PULSE);
   constant ADDRESS_SETUP_BEFORE_ADV_CYCLE_COUNT : integer := cyc(MIN_ADDRESS_SETUP_BEFORE_ADV_HIGH + 2.0);
   constant CE_BEFORE_ADV_CYCLE_COUNT            : integer := cyc(MIN_CE_BEFORE_ADV_HIGH);
   constant ADV_CYCLE_COUNT                      : integer := maxi(maxi(ADV_PULSE_CYCLE_COUNT, ADDRESS_SETUP_BEFORE_ADV_CYCLE_COUNT), CE_BEFORE_ADV_CYCLE_COUNT);
   constant ADDR_HOLD_AFTER_ADV_CYCLE_COUNT      : integer := cyc(MIN_ADDRESS_HOLD_AFTER_ADV_HIGH);
   constant DATA_AFTER_ADDR_UNLATCH_CYCLE_COUNT  : integer := cyc(MIN_DATA_AFTER_ADDR_UNLATCHED);
   constant TOTAL_WRITE_CYCLE_COUNT              : integer := cyc(maxr(MIN_WRITE_TIME_FROM_ADV, MIN_WRITE_PULSE));
   constant OE_AFTER_ADDR_UNLATCH_CYCLE_COUNT    : integer := cyc(MIN_OE_AFTER_ADDR_UNLATCHED);
   constant TOTAL_READ_CYCLE_COUNT               : integer := cyc(MAX_ACCESS_TIME_FROM_ADV);

   constant STATE_NONE                 : integer := 0;
   constant WRITE_INITIAL_COUNT        : integer := 1;
   constant STATE_WRITE_ADV_END        : integer := WRITE_INITIAL_COUNT - 1 + ADV_CYCLE_COUNT;
   constant STATE_WRITE_ADDR_LATCH_END : integer := STATE_WRITE_ADV_END + ADDR_HOLD_AFTER_ADV_CYCLE_COUNT;
   constant STATE_WRITE_DATA_START     : integer := STATE_WRITE_ADDR_LATCH_END + DATA_AFTER_ADDR_UNLATCH_CYCLE_COUNT;
   constant STATE_WRITE_DATA_END       : integer := WRITE_INITIAL_COUNT + TOTAL_WRITE_CYCLE_COUNT;
   constant READ_INITIAL_COUNT         : integer := 20;
   constant STATE_READ_ADV_END         : integer := READ_INITIAL_COUNT - 1 + ADV_CYCLE_COUNT;
   constant STATE_READ_ADDR_LATCH_END  : integer := STATE_READ_ADV_END + ADDR_HOLD_AFTER_ADV_CYCLE_COUNT;
   constant STATE_READ_DATA_ENABLE     : integer := STATE_READ_ADDR_LATCH_END + OE_AFTER_ADDR_UNLATCH_CYCLE_COUNT;
   constant STATE_READ_DATA_RECEIVED   : integer := READ_INITIAL_COUNT + TOTAL_READ_CYCLE_COUNT;

   signal state           : integer range 0 to 255 := STATE_NONE;
   signal data_out_en     : std_logic := '0';
   signal cram_data       : std_logic_vector(15 downto 0) := (others => '0');
   signal latched_data_in : std_logic_vector(15 downto 0) := (others => '0');

begin

   assert STATE_WRITE_DATA_START < STATE_WRITE_DATA_END and STATE_WRITE_DATA_END < READ_INITIAL_COUNT
      report "psram_async: write timing does not fit the state numbering" severity failure;

   cram_dq_out <= cram_data;
   cram_dq_oe  <= data_out_en;

   process (clk)
   begin
      if rising_edge(clk) then
         if (state /= STATE_NONE) then
            state <= state + 1;
         end if;
         if (state = STATE_NONE) then busy <= '0'; else busy <= '1'; end if;

         if (state = STATE_NONE) then
            read_avail <= '0';
            cram_clk   <= '0';
            cram_adv_n <= '1';
            cram_cre   <= '0';
            cram_ce0_n <= '1';
            cram_ce1_n <= '1';
            cram_oe_n  <= '1';
            cram_we_n  <= '1';
            cram_ub_n  <= '1';
            cram_lb_n  <= '1';
            if (write_en = '1') then
               state <= WRITE_INITIAL_COUNT;
               if (bank_sel = '1') then cram_ce1_n <= '0'; else cram_ce0_n <= '0'; end if;
               cram_a          <= std_logic_vector(addr(21 downto 16));
               cram_data       <= std_logic_vector(addr(15 downto 0));
               data_out_en     <= '1';
               latched_data_in <= data_in;
               cram_we_n       <= '0';
               cram_adv_n      <= '0';
               if (write_high_byte = '1') then cram_ub_n <= '0'; end if;
               if (write_low_byte = '1') then cram_lb_n <= '0'; end if;
               busy <= '1';
            elsif (read_en = '1') then
               state <= READ_INITIAL_COUNT;
               if (bank_sel = '1') then cram_ce1_n <= '0'; else cram_ce0_n <= '0'; end if;
               cram_a      <= std_logic_vector(addr(21 downto 16));
               cram_data   <= std_logic_vector(addr(15 downto 0));
               data_out_en <= '1';
               cram_adv_n  <= '0';
               cram_ub_n   <= '0';
               cram_lb_n   <= '0';
               busy <= '1';
            end if;
         end if;

         -- writes
         if (state = STATE_WRITE_ADV_END) then
            cram_adv_n <= '1';
         end if;
         if (state = STATE_WRITE_ADDR_LATCH_END) then
            data_out_en <= '0';
         end if;
         if (state = STATE_WRITE_DATA_START) then
            data_out_en <= '1';
            cram_data   <= latched_data_in;
         end if;
         if (state = STATE_WRITE_DATA_END) then
            state       <= STATE_NONE;
            data_out_en <= '0';
            cram_we_n   <= '1';
            cram_ce0_n  <= '1';
            cram_ce1_n  <= '1';
            cram_ub_n   <= '1';
            cram_lb_n   <= '1';
            busy        <= '0';
         end if;

         -- reads
         if (state = STATE_READ_ADV_END) then
            cram_adv_n <= '1';
         end if;
         if (state = STATE_READ_ADDR_LATCH_END) then
            data_out_en <= '0';
         end if;
         if (state = STATE_READ_DATA_ENABLE) then
            cram_oe_n <= '0';
         end if;
         if (state = STATE_READ_DATA_RECEIVED) then
            state      <= STATE_NONE;
            read_avail <= '1';
            data_out   <= cram_dq_in;
            cram_ce0_n <= '1';
            cram_ce1_n <= '1';
            cram_ub_n  <= '1';
            cram_lb_n  <= '1';
            cram_oe_n  <= '1';
            busy       <= '0';
         end if;
      end if;
   end process;

end architecture;
