-- Pocket: serves the PSX core's DDR3-style memory port (VRAM, memory card buffer) from the two PSRAM chips,
-- used side by side as one 32-bit wide memory (cram0 = bits 15:0 of each 32-bit half, cram1 = bits 31:16).
-- One 64-bit word = two 32-bit halves at consecutive PSRAM word addresses.
-- Core side (clk2x, like DDRAM on MiSTer): a request is taken when ddr_busy = '0'; writes are single words
-- with byte enables, reads are bursts of ddr_burstcnt words (data returned in order with ddr_dout_ready).
-- Address: the core's byte address bits 27:20 select a region (0 = VRAM, 1 = memory card 1, 4 = VRAM copy);
-- ddr_addr is the 64-bit word address (byte address bits 27:3). PSRAM word address =
-- {region(2:0), word offset(16:0), half} (21 bits, die 0 only, far below the die's last word).
-- Aux port (memory card file load / read back for APF): single 32-bit accesses at a PSRAM word address, served
-- between core accesses (alternating with them when both wait) and between the parts of a core read burst.
--
-- PSRAM use (AS1C8M16PL = two AS1C4M16PL dies, CellularRAM 1.5 with multiplexed address / data):
-- * After reset the bus configuration register (BCR) of die 0 is written (CRE, asynchronous register write) for
--   synchronous burst access with fixed latency, latency code 3: the first word is transferred on the 4th PSRAM
--   clock after the address clock, for READs and WRITEs; allowed up to 52 MHz on every speed grade. WAIT is not
--   used.
-- * The PSRAM clock is clk / 2 (33.9 MHz), made by a register: it rises on the clk edges with an odd step number
--   (step 0 = the edge that starts an access with CE#, ADV# low and the address). Everything the PSRAM samples
--   changes on its falling edges, half a PSRAM clock (14.8 ns) before the rising edge that samples it. A read word
--   is taken on the clk edge that makes the next rising PSRAM clock edge: the PSRAM drives it at most 9 ns
--   (tACLK) after the previous rising edge and holds it 2 ns (tKOH) after this one, which is itself a few ns later
--   at the pins than the clk edge inside the FPGA. So the I/O timing has wide margins without board-level
--   constraints (simulated with board delays up to T_OUT + T_IN = 18 ns).
-- * Writes: a core write is held in a one-word request slot; ddr_busy drops as soon as the slot is free, so
--   while a burst WRITE runs the next write can be taken. If it is the next 64-bit word, it continues the burst
--   (one word every 4 clks); otherwise the burst ends and the request waits.
-- * Bursts never cross an SPLIT-word PSRAM address boundary, well inside a DRAM row (where the PSRAM would insert
--   WAIT states that fixed latency does not expect), and CE# stays low far shorter than tCEM (4 us).
-- * CE# is high for at least two clk cycles (29.5 ns > 15 ns: a refresh opportunity) between all accesses.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vram_psram is
   generic
   (
      CLOCK_SPEED : real := 67.7376;   -- clk in MHz (informational: the timing below is in clk cycles for it)
      SPLIT       : integer := 32;     -- bursts end at every SPLIT-word PSRAM address boundary (power of 2)
      IN_REG      : boolean := false   -- read data taken on the FALLING clk edge, half a clk after the edge the
                                       -- direct path takes it on, by a plain register (an I/O-cell input register,
                                       -- see ap_core.qsf), and used one clk later. Needed at clk3x (PSRAM clock
                                       -- 50.8 MHz): with the PSRAM pins ~10 ns clock-to-output, the word is not at
                                       -- the pins yet on the rising edge
   );
   port
   (
      clk              : in  std_logic;
      reset            : in  std_logic;
      -- core side
      ddr_busy         : out std_logic := '1';
      ddr_burstcnt     : in  std_logic_vector(7 downto 0);
      ddr_addr         : in  std_logic_vector(24 downto 0);
      ddr_dout         : out std_logic_vector(63 downto 0) := (others => '0');   -- valid with ddr_dout_ready
      ddr_dout_ready   : out std_logic := '0';
      ddr_rd           : in  std_logic;
      ddr_din          : in  std_logic_vector(63 downto 0);
      ddr_be           : in  std_logic_vector(7 downto 0);
      ddr_we           : in  std_logic;
      -- aux port: aux_req held until aux_done (one clock)
      aux_req          : in  std_logic := '0';
      aux_we           : in  std_logic := '0';
      aux_addr         : in  std_logic_vector(20 downto 0) := (others => '0');
      aux_din          : in  std_logic_vector(31 downto 0) := (others => '0');
      aux_dout         : out std_logic_vector(31 downto 0) := (others => '0');   -- valid with aux_done, held
      aux_done         : out std_logic := '0';
      card_write       : out std_logic := '0';   -- pulse: a core write to region 1 (memory card 1) starts
      -- PSRAM 0 (low 16 bits)
      cram0_a          : out std_logic_vector(21 downto 16);
      cram0_dq_out     : out std_logic_vector(15 downto 0);
      cram0_dq_oe      : out std_logic;
      cram0_dq_in      : in  std_logic_vector(15 downto 0);
      cram0_clk        : out std_logic;
      cram0_adv_n      : out std_logic;
      cram0_cre        : out std_logic;
      cram0_ce0_n      : out std_logic;
      cram0_ce1_n      : out std_logic;
      cram0_oe_n       : out std_logic;
      cram0_we_n       : out std_logic;
      cram0_ub_n       : out std_logic;
      cram0_lb_n       : out std_logic;
      -- PSRAM 1 (high 16 bits)
      cram1_a          : out std_logic_vector(21 downto 16);
      cram1_dq_out     : out std_logic_vector(15 downto 0);
      cram1_dq_oe      : out std_logic;
      cram1_dq_in      : in  std_logic_vector(15 downto 0);
      cram1_clk        : out std_logic;
      cram1_adv_n      : out std_logic;
      cram1_cre        : out std_logic;
      cram1_ce0_n      : out std_logic;
      cram1_ce1_n      : out std_logic;
      cram1_oe_n       : out std_logic;
      cram1_we_n       : out std_logic;
      cram1_ub_n       : out std_logic;
      cram1_lb_n       : out std_logic
   );
end entity;

architecture arch of vram_psram is

   -- BCR, written as the "address" A[21:0] with CRE high: A[19:18] = 10 selects the BCR; synchronous burst mode
   -- (15 = 0), fixed latency (14 = 1), latency code 3 (13:11 = 011), WAIT active high (10 = 1) and one clock early
   -- (8 = 1) (defaults, WAIT is not used), half drive strength (5:4 = 01), no wrap (3 = 1), continuous burst (2:0)
   constant BCR_WRITE  : unsigned(21 downto 0) := unsigned(std_logic_vector'("001000" & x"5D1F"));
   -- step of the first data transfer: the address is sampled on step 1, latency code 3 transfers the first word on
   -- the 4th rising PSRAM clock edge after it (step 9); the following words on steps 11, 13, ...
   constant FIRST_DATA : integer := 9;
   constant HALF_SPLIT : integer := SPLIT / 2;   -- 64-bit words per SPLIT block

   type tSeq is (S_NONE, S_AWRITE, S_READ, S_BWRITE, S_GAP);   -- current PSRAM access
   signal seq        : tSeq := S_NONE;
   signal step       : unsigned(6 downto 0) := (others => '0');
   type tOwner is (O_INIT, O_CORE, O_AUX);
   signal owner      : tOwner := O_INIT;      -- of the current / last access

   signal initDone   : std_logic := '0';
   signal initCnt    : unsigned(8 downto 0) := (others => '0');
   signal initPhase  : integer range 0 to 2 := 0;   -- 0: wait, 1: BCR written, 2: read after it started

   -- core request slot
   signal slot       : std_logic := '0';   -- a core request is waiting or running
   signal slotWe     : std_logic := '0';
   signal slotAddr   : unsigned(19 downto 0) := (others => '0');   -- 64-bit word address: region(2:0) & offset
   signal slotData   : std_logic_vector(63 downto 0) := (others => '0');
   signal slotBe     : std_logic_vector(7 downto 0) := (others => '0');
   signal remaining  : unsigned(9 downto 0) := (others => '0');    -- PSRAM words of a core read not started yet
   signal rAddr      : unsigned(21 downto 0) := (others => '0');   -- next PSRAM word address of a core read
   signal readOn     : std_logic := '0';                          -- a core read has started parts
   signal lastCore   : std_logic := '0';                          -- the last access was a core access

   -- current access
   signal pLen       : unsigned(6 downto 0) := (others => '0');    -- words of the current read part
   signal rWord      : unsigned(6 downto 0) := (others => '0');    -- words taken of the current read part
   signal pData0     : std_logic_vector(15 downto 0) := (others => '0');   -- asynchronous write data
   signal pData1     : std_logic_vector(15 downto 0) := (others => '0');
   signal bAddr      : unsigned(19 downto 0) := (others => '0');   -- 64-bit word being written in a burst
   signal bData      : std_logic_vector(63 downto 0) := (others => '0');
   signal bBe        : std_logic_vector(7 downto 0) := (others => '0');
   signal rLow       : std_logic_vector(31 downto 0) := (others => '0');
   -- IN_REG: the pins as sampled on the last falling edge, and what the rising edge before it read for
   signal dqIn       : std_logic_vector(31 downto 0) := (others => '0');
   signal rd_1, rdAux_1, rdCore_1 : boolean := false;
   signal rdHigh_1   : std_logic := '0';

   signal aux_a      : std_logic_vector(20 downto 0) := (others => '0');
   signal aux_d      : std_logic_vector(31 downto 0) := (others => '0');
   signal aux_w      : std_logic := '0';
   signal auxOn      : std_logic := '0';   -- the aux access has been started

   -- pins (both chips in lockstep, except the write data)
   signal o_a        : std_logic_vector(21 downto 16) := (others => '0');
   signal o_dq0      : std_logic_vector(15 downto 0) := (others => '0');
   signal o_dq1      : std_logic_vector(15 downto 0) := (others => '0');
   signal o_oe       : std_logic := '0';
   signal o_clk      : std_logic := '0';
   signal o_adv_n    : std_logic := '1';
   signal o_cre      : std_logic := '0';
   signal o_ce_n     : std_logic := '1';
   signal o_oe_n     : std_logic := '1';
   signal o_we_n     : std_logic := '1';
   signal o_be_n     : std_logic_vector(3 downto 0) := (others => '1');   -- ub1, lb1, ub0, lb0

begin

   cram0_a      <= o_a;      cram1_a      <= o_a;
   cram0_dq_out <= o_dq0;    cram1_dq_out <= o_dq1;
   cram0_dq_oe  <= o_oe;     cram1_dq_oe  <= o_oe;
   cram0_clk    <= o_clk;    cram1_clk    <= o_clk;
   cram0_adv_n  <= o_adv_n;  cram1_adv_n  <= o_adv_n;
   cram0_cre    <= o_cre;    cram1_cre    <= o_cre;
   cram0_ce0_n  <= o_ce_n;   cram1_ce0_n  <= o_ce_n;
   cram0_ce1_n  <= '1';      cram1_ce1_n  <= '1';
   cram0_oe_n   <= o_oe_n;   cram1_oe_n   <= o_oe_n;
   cram0_we_n   <= o_we_n;   cram1_we_n   <= o_we_n;
   cram0_lb_n   <= o_be_n(0); cram0_ub_n  <= o_be_n(1);
   cram1_lb_n   <= o_be_n(2); cram1_ub_n  <= o_be_n(3);

   process (clk)
   begin
      if falling_edge(clk) then
         dqIn <= cram1_dq_in & cram0_dq_in;
      end if;
   end process;

   process (clk)
      variable free     : boolean;   -- no access in progress after this edge unless one is started
      variable startAW  : boolean;   -- start an asynchronous write (register write at init)
      variable startR   : boolean;   -- start a synchronous read part (vAddr, vLen)
      variable startBW  : boolean;   -- start a synchronous burst write with the request slot's word
      variable vAddr    : unsigned(21 downto 0);
      variable vLen     : unsigned(6 downto 0);
      variable rdData   : boolean;   -- a read word is taken on this edge
      variable slotFree : boolean;   -- the request slot is emptied on this edge
      variable toB      : integer;
      variable s        : integer;
      variable auxWaiting : boolean;   -- an aux request waits to be started
      variable rdNow, rdAux, rdCore : boolean;   -- read data to take on this edge, and its owner
      variable rdHigh   : std_logic;             -- the 32-bit half it is
      variable dq       : std_logic_vector(31 downto 0);
   begin
      if rising_edge(clk) then
         ddr_dout_ready <= '0';
         aux_done       <= '0';
         card_write     <= '0';
         startAW  := false;
         startR   := false;
         startBW  := false;
         rdData   := false;
         slotFree := false;
         vAddr    := (others => '0');
         vLen     := (others => '0');
         free     := (seq = S_NONE) or (seq = S_GAP and step = 1);
         auxWaiting := aux_req = '1' and aux_done = '0' and auxOn = '0';
         s        := to_integer(step);

         ------------------------------------------------------------------------------------------------
         -- access sequencer
         ------------------------------------------------------------------------------------------------
         case (seq) is
            when S_NONE => null;

            -- asynchronous configuration register write: step 0 (start) = CE#, ADV# low with CRE and the
            -- register value as address; 1: ADV# high; 2: CRE low, WE# low; 6: WE#, CE# high (value latched)
            when S_AWRITE =>
               step <= step + 1;
               case (s) is
                  when 1 => o_adv_n <= '1';
                  when 2 => o_oe <= '0'; o_cre <= '0'; o_we_n <= '0';
                  when 6 =>
                     o_we_n <= '1'; o_ce_n <= '1';
                     seq <= S_GAP; step <= (others => '0');
                  when others => null;
               end case;

            -- synchronous burst read: step 0 (start) = CE#, ADV# low with the address; the PSRAM clock rises on
            -- odd steps; 2: ADV# high; 3: address released; 4: OE# low; words taken on steps 9, 11, ...; on the
            -- last one CE#, OE# go high and the PSRAM clock stays low
            when S_READ =>
               step  <= step + 1;
               o_clk <= step(0);
               case (s) is
                  when 2 => o_adv_n <= '1';
                  when 3 => o_oe <= '0';
                  when 4 => o_oe_n <= '0';
                  when others => null;
               end case;
               if (s >= FIRST_DATA and step(0) = '1') then
                  rdData := true;
                  rWord  <= rWord + 1;
                  if (rWord = pLen - 1) then
                     o_clk <= '0'; o_ce_n <= '1'; o_oe_n <= '1'; o_be_n <= (others => '1');
                     seq <= S_GAP; step <= (others => '0');
                  elsif (owner = O_CORE and rWord(0) = '1' and auxWaiting) then
                     -- an aux access is waiting (APF reads the card back one word every ~1 us): end the part after
                     -- this 64-bit word; the rest of the burst continues after the aux access
                     o_clk <= '0'; o_ce_n <= '1'; o_oe_n <= '1'; o_be_n <= (others => '1');
                     seq <= S_GAP; step <= (others => '0');
                     remaining <= remaining + (pLen - 1 - rWord);
                     rAddr     <= rAddr - (pLen - 1 - rWord);
                  end if;
               end if;

            -- synchronous burst write: step 0 (start) = CE#, ADV#, WE# low with the address; 2: ADV#, WE# high;
            -- the 32-bit halves of each 64-bit word with their byte enables are put on the bus on the falling
            -- PSRAM clock edges before the transfers: steps 8 / 10 for the first word (taken on 9 / 11), 12 / 14
            -- for the second, ... On the steps 12, 16, ... the burst continues with the request slot's word if
            -- it is the next one in the same SPLIT block, or ends (CE# high, PSRAM clock stays low)
            when S_BWRITE =>
               step  <= step + 1;
               o_clk <= step(0);
               if (s = 2) then o_adv_n <= '1'; o_we_n <= '1'; end if;
               if (s >= 8 and step(1 downto 0) = "00") then
                  if (s = 8) then
                     o_dq0 <= bData(15 downto 0); o_dq1 <= bData(31 downto 16); o_be_n <= not bBe(3 downto 0);
                  elsif (owner = O_CORE and slot = '1' and slotWe = '1' and slotAddr = bAddr + 1 and not auxWaiting and
                         (to_integer(bAddr + 1) mod HALF_SPLIT) /= 0) then
                     bAddr <= slotAddr; bData <= slotData; bBe <= slotBe;
                     if (slotAddr(19 downto 17) = "001") then card_write <= '1'; end if;
                     o_dq0 <= slotData(15 downto 0); o_dq1 <= slotData(31 downto 16); o_be_n <= not slotBe(3 downto 0);
                     slotFree := true;
                     step <= to_unsigned(9, 7);   -- steps 9 .. 12 repeat for every further word
                  else
                     o_clk <= '0'; o_ce_n <= '1'; o_be_n <= (others => '1'); o_oe <= '0';
                     seq <= S_GAP; step <= (others => '0');
                  end if;
               elsif (s >= 10 and step(1 downto 0) = "10") then
                  if (owner = O_AUX) then
                     -- aux writes are one 32-bit word: the burst ends after it
                     o_clk <= '0'; o_ce_n <= '1'; o_be_n <= (others => '1'); o_oe <= '0';
                     seq <= S_GAP; step <= (others => '0');
                  else
                     o_dq0 <= bData(47 downto 32); o_dq1 <= bData(63 downto 48); o_be_n <= not bBe(7 downto 4);
                  end if;
               end if;

            -- CE# high for two clks (an access may start on the edge with step 1)
            when S_GAP =>
               step <= step + 1;
               if (step = 1) then seq <= S_NONE; end if;
         end case;

         ------------------------------------------------------------------------------------------------
         -- initialisation: BCR write, then one read (recommended by the datasheet; data unused)
         ------------------------------------------------------------------------------------------------
         if (initDone = '0') then
            if (free) then
               case (initPhase) is
                  when 0 =>
                     initCnt <= initCnt + 1;
                     if (initCnt = 511) then
                        vAddr := BCR_WRITE;
                        startAW := true;
                        initPhase <= 1;
                     end if;
                  when 1 =>
                     vAddr := (others => '0'); vLen := to_unsigned(1, 7);
                     startR := true;
                     owner <= O_INIT;
                     initPhase <= 2;
                  when 2 =>
                     initDone <= '1';
               end case;
            end if;

         ------------------------------------------------------------------------------------------------
         -- next access when the sequencer is free: aux (alternating with core accesses) or the core request
         ------------------------------------------------------------------------------------------------
         elsif (free) then
            if (auxOn = '1') then
               -- the aux access has ended
               aux_done <= '1';
               auxOn    <= '0';
               lastCore <= '0';
            elsif (aux_req = '1' and aux_done = '0' and (lastCore = '1' or slot = '0')) then
               vAddr := '0' & unsigned(aux_addr);
               aux_d <= aux_din;
               auxOn <= '1';
               owner <= O_AUX;
               if (aux_we = '1') then
                  -- as a one-word burst write with all byte enables
                  bData <= x"00000000" & aux_din;
                  bBe   <= x"0F";
                  startBW := true;
               else
                  vLen := to_unsigned(1, 7);
                  startR := true;
               end if;
            elsif (slot = '1' and slotWe = '1') then
               vAddr := '0' & slotAddr & '0';
               bAddr <= slotAddr; bData <= slotData; bBe <= slotBe;
               if (slotAddr(19 downto 17) = "001") then card_write <= '1'; end if;
               startBW  := true;
               slotFree := true;
               owner    <= O_CORE;
               lastCore <= '1';
            elsif (slot = '1') then
               if (readOn = '1' and remaining = 0) then
                  slotFree := true;
                  readOn   <= '0';
               else
                  vAddr := rAddr;   -- set when the request was taken, advanced by every part
                  toB := SPLIT - (to_integer(vAddr) mod SPLIT);
                  if (to_integer(remaining) < toB) then vLen := resize(remaining, 7); else vLen := to_unsigned(toB, 7); end if;
                  startR    := true;
                  rAddr     <= vAddr + vLen;
                  remaining <= remaining - vLen;
                  readOn    <= '1';
                  owner     <= O_CORE;
                  lastCore  <= '1';
               end if;
            end if;
         end if;

         ------------------------------------------------------------------------------------------------
         -- start of an access (step 0)
         ------------------------------------------------------------------------------------------------
         if (startAW or startR or startBW) then
            step    <= to_unsigned(1, 7);
            o_ce_n  <= '0';
            o_adv_n <= '0';
            o_a     <= std_logic_vector(vAddr(21 downto 16));
            o_dq0   <= std_logic_vector(vAddr(15 downto 0));
            o_dq1   <= std_logic_vector(vAddr(15 downto 0));
            o_oe    <= '1';
            o_clk   <= '0';
            o_oe_n  <= '1';
            o_be_n  <= "1111";
            o_cre   <= '0';
            o_we_n  <= '1';
            if (startAW) then
               seq   <= S_AWRITE;
               o_cre <= '1';
            elsif (startR) then
               seq    <= S_READ;
               pLen   <= vLen;
               rWord  <= (others => '0');
               o_be_n <= "0000";
            else
               seq    <= S_BWRITE;
               o_we_n <= '0';
            end if;
         end if;

         ------------------------------------------------------------------------------------------------
         -- read data (taken from the pins on the edge that raises the next PSRAM clock; with IN_REG on the
         -- falling edge after it, through dqIn, used on the next rising edge)
         ------------------------------------------------------------------------------------------------
         rd_1     <= rdData;
         rdAux_1  <= owner = O_AUX;
         rdCore_1 <= owner = O_CORE;
         rdHigh_1 <= rWord(0);
         if (IN_REG) then
            rdNow := rd_1; rdAux := rdAux_1; rdCore := rdCore_1; rdHigh := rdHigh_1; dq := dqIn;
         else
            rdNow := rdData; rdAux := owner = O_AUX; rdCore := owner = O_CORE; rdHigh := rWord(0);
            dq := cram1_dq_in & cram0_dq_in;
         end if;
         if (rdNow) then
            if (rdAux) then
               aux_dout <= dq;
            elsif (rdCore) then
               if (rdHigh = '0') then
                  rLow <= dq;
               else
                  ddr_dout       <= dq & rLow;
                  ddr_dout_ready <= '1';
               end if;
            end if;
         end if;

         ------------------------------------------------------------------------------------------------
         -- core request slot: a request is taken when ddr_busy = '0'
         ------------------------------------------------------------------------------------------------
         if (slotFree) then
            slot     <= '0';
            ddr_busy <= '0';
         end if;
         if (ddr_busy = '0' and initDone = '1' and (ddr_we = '1' or ddr_rd = '1')) then
            slot     <= '1';
            ddr_busy <= '1';
            slotWe   <= ddr_we;
            slotAddr <= unsigned(ddr_addr(19 downto 17)) & unsigned(ddr_addr(16 downto 0));
            slotData <= ddr_din;
            slotBe   <= ddr_be;
            rAddr    <= '0' & unsigned(ddr_addr(19 downto 17)) & unsigned(ddr_addr(16 downto 0)) & '0';
            if (ddr_burstcnt = x"00") then
               remaining <= to_unsigned(512, 10);
            else
               remaining <= "0" & unsigned(ddr_burstcnt) & '0';
            end if;
            readOn   <= '0';
         elsif (initDone = '1' and slot = '0' and not slotFree) then
            ddr_busy <= '0';
         end if;

         ------------------------------------------------------------------------------------------------
         if (reset = '1') then
            initDone   <= '0';
            initPhase  <= 0;
            initCnt    <= (others => '0');
            ddr_busy   <= '1';
            slot       <= '0';
            readOn     <= '0';
            auxOn      <= '0';
            seq        <= S_NONE;
            step       <= (others => '0');
            o_ce_n <= '1'; o_oe_n <= '1'; o_we_n <= '1'; o_adv_n <= '1'; o_cre <= '0'; o_oe <= '0'; o_clk <= '0';
            o_be_n <= (others => '1');
         end if;
      end if;
   end process;

end architecture;
