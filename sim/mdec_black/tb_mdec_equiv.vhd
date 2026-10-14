-- Equivalence test: mdec_black against the original mdec (renamed mdec_ref).
-- A DMA-controller model feeds random command streams (quant/scale tables and
-- macroblock decodes in all depths) through DMA0 and drains DMA1. Request lines,
-- idle flag and status reads must match every cycle; every output word of the
-- black MDEC must be zero except the 15-bit mask bit, which must match.
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use STD.textio.all;

entity tb_mdec_equiv is
   generic
   (
      NUM_CMDS : integer := 200;
      SEED     : integer := 1;
      CE_RAND  : integer := 1    -- 1: randomly drop clock enable 1 cycle in 16
   );
end entity;

architecture sim of tb_mdec_equiv is

   signal clk1x, clk2x    : std_logic := '1';
   signal clk1xToggle     : std_logic := '0';
   signal clk1xToggle2x   : std_logic := '0';
   signal clk2xIndex      : std_logic := '0';
   signal ce              : std_logic := '1';
   signal reset           : std_logic := '1';

   signal bus_addr        : unsigned(3 downto 0) := (others => '0');
   signal bus_dataWrite   : std_logic_vector(31 downto 0) := (others => '0');
   signal bus_read        : std_logic := '0';
   signal bus_write       : std_logic := '0';
   signal dma_write       : std_logic := '0';
   signal dma_writedata   : std_logic_vector(31 downto 0) := (others => '0');
   signal dma_read        : std_logic := '0';

   signal busRd_ref, busRd_new   : std_logic_vector(31 downto 0);
   signal dmaWr_ref, dmaWr_new   : std_logic;
   signal dmaRd_ref, dmaRd_new   : std_logic;
   signal dmaDat_ref, dmaDat_new : std_logic_vector(31 downto 0);
   signal idle_ref, idle_new     : std_logic;

   signal ctrlMismatch   : integer := 0;
   signal dataMismatch   : integer := 0;
   signal wordsOut       : integer := 0;
   signal statusReads    : integer := 0;
   signal depthNow       : std_logic_vector(1 downto 0) := "00";
   signal lastBusRead    : std_logic_vector(3 downto 0) := x"F";
   signal dmaReadPending : std_logic := '0';
   signal done           : boolean := false;
   signal hangs          : integer := 0;
   signal fifoCtrlMis    : integer := 0;
   signal fifoDataMis    : integer := 0;
   signal fifoWrites     : integer := 0;
   signal mode16         : std_logic := '0';

begin

   clk2x <= not clk2x after 5 ns;
   clk1x <= not clk1x after 10 ns;

   process (clk1x) begin
      if rising_edge(clk1x) then clk1xToggle <= not clk1xToggle; end if;
   end process;
   process (clk2x) begin
      if rising_edge(clk2x) then
         clk1xToggle2x <= clk1xToggle;
         clk2xIndex <= '0';
         if (clk1xToggle2x = clk1xToggle) then clk2xIndex <= '1'; end if;
      end if;
   end process;

   iref : entity work.mdec_ref
   port map (clk1x => clk1x, clk2x => clk2x, clk2xIndex => clk2xIndex, ce => ce, reset => reset,
      bus_addr => bus_addr, bus_dataWrite => bus_dataWrite, bus_read => bus_read, bus_write => bus_write,
      bus_dataRead => busRd_ref, dmaWriteRequest => dmaWr_ref, dmaReadRequest => dmaRd_ref,
      dma_write => dma_write, dma_writedata => dma_writedata, dma_read => dma_read, dma_readdata => dmaDat_ref,
      SS_reset => '0', SS_DataWrite => (others => '0'), SS_Adr => (others => '0'), SS_wren => '0', SS_rden => '0',
      SS_DataRead => open, SS_Idle => idle_ref);

   inew : entity work.mdec_new
   port map (clk1x => clk1x, clk2x => clk2x, clk2xIndex => clk2xIndex, ce => ce, reset => reset,
      bus_addr => bus_addr, bus_dataWrite => bus_dataWrite, bus_read => bus_read, bus_write => bus_write,
      bus_dataRead => busRd_new, dmaWriteRequest => dmaWr_new, dmaReadRequest => dmaRd_new,
      dma_write => dma_write, dma_writedata => dma_writedata, dma_read => dma_read, dma_readdata => dmaDat_new,
      SS_reset => '0', SS_DataWrite => (others => '0'), SS_Adr => (others => '0'), SS_wren => '0', SS_rden => '0',
      SS_DataRead => open, SS_Idle => idle_new);

   -- expected black word: zero, except the mask bits in 15-bit mode follow the reference
   cmp : process (clk1x)
      variable l : line;
      function black(ref : std_logic_vector(31 downto 0); depth : std_logic_vector(1 downto 0)) return std_logic_vector is
         variable v : std_logic_vector(31 downto 0) := (others => '0');
      begin
         -- the output FIFO is checked exactly at write time (fifo_cmp); here only require
         -- that no pixel data leaks out: everything except the 15-bit mask bits is zero
         v(15) := ref(15); v(31) := ref(31);
         return v;
      end function;
   begin
      if rising_edge(clk1x) then
         if (reset = '0') then
            if (dmaWr_ref /= dmaWr_new or dmaRd_ref /= dmaRd_new or idle_ref /= idle_new) then
               if (ctrlMismatch < 10) then
                  write(l, string'("CONTROL MISMATCH at ") & time'image(now)); writeline(output, l);
               end if;
               ctrlMismatch <= ctrlMismatch + 1;
            end if;
            -- DMA read data is sampled in the cycle dma_read is high
            if (dma_read = '1') then
               wordsOut <= wordsOut + 1;
               if ((dmaDat_new and x"7FFF7FFF") /= x"00000000") then
                  if (dataMismatch < 10) then
                     write(l, string'("DATA MISMATCH ref ") & to_hstring(dmaDat_ref) & string'(" new ") & to_hstring(dmaDat_new));
                     writeline(output, l);
                  end if;
                  dataMismatch <= dataMismatch + 1;
               end if;
            end if;
            -- bus reads: status (addr 4) exact, data (addr 0) black
            if (lastBusRead = x"4") then
               statusReads <= statusReads + 1;
               if (busRd_ref /= busRd_new) then
                  if (ctrlMismatch < 10) then
                     write(l, string'("STATUS MISMATCH ref ") & to_hstring(busRd_ref) & string'(" new ") & to_hstring(busRd_new));
                     writeline(output, l);
                  end if;
                  ctrlMismatch <= ctrlMismatch + 1;
               end if;
            elsif (lastBusRead = x"0") then
               if ((busRd_new and x"7FFF7FFF") /= x"00000000" and busRd_ref /= x"FFFFFFFF") or
                  (busRd_ref = x"FFFFFFFF" and busRd_new /= x"FFFFFFFF") then
                  dataMismatch <= dataMismatch + 1;
               end if;
            end if;
         end if;
      end if;
   end process;

   -- exact check of every word written into the output FIFO: same write timing, and the
   -- black word is zero except the mask bits, which in 15-bit mode must equal the reference
   fifo_cmp : block
      alias refWr    is <<signal .tb_mdec_equiv.iref.FifoOut_Wr  : std_logic>>;
      alias newWr    is <<signal .tb_mdec_equiv.inew.FifoOut_Wr  : std_logic>>;
      alias refDin   is <<signal .tb_mdec_equiv.iref.FifoOut_Din : std_logic_vector(31 downto 0)>>;
      alias newDin   is <<signal .tb_mdec_equiv.inew.FifoOut_Din : std_logic_vector(31 downto 0)>>;
      alias refDepth is <<signal .tb_mdec_equiv.iref.rec_depth   : std_logic_vector(1 downto 0)>>;
      alias refStart is <<signal .tb_mdec_equiv.iref.color_done  : std_logic>>;
   begin
      process (clk2x)
         variable l   : line;
         variable exp : std_logic_vector(31 downto 0);
      begin
         if rising_edge(clk2x) then
            -- output mapping mode is chosen when a block's colour output starts
            if (refStart = '1') then
               if (refDepth = "11") then mode16 <= '1'; else mode16 <= '0'; end if;
            end if;
            if (refWr /= newWr) then
               if (fifoCtrlMis < 10) then
                  write(l, string'("FIFO WRITE TIMING MISMATCH at ") & time'image(now)); writeline(output, l);
               end if;
               fifoCtrlMis <= fifoCtrlMis + 1;
            elsif (refWr = '1') then
               fifoWrites <= fifoWrites + 1;
               exp := (others => '0');
               if (mode16 = '1') then exp(15) := refDin(15); exp(31) := refDin(31); end if;
               if (newDin /= exp) then
                  if (fifoDataMis < 10) then
                     write(l, string'("FIFO DATA MISMATCH ref ") & to_hstring(refDin) & string'(" new ") & to_hstring(newDin)
                           & string'(" expected ") & to_hstring(exp)); writeline(output, l);
                  end if;
                  fifoDataMis <= fifoDataMis + 1;
               end if;
            end if;
         end if;
      end process;
   end block;

   -- DMA1 (out) drain: read one word whenever requested, sometimes stalling
   drain : process (clk1x)
      variable s1 : positive := SEED + 3;
      variable s2 : positive := 99991;
      variable r  : real;
   begin
      if rising_edge(clk1x) then
         dma_read <= '0';
         uniform(s1, s2, r);
         if (dmaRd_ref = '1' and dma_read = '0' and r < 0.7 and bus_read = '0') then
            dma_read <= '1';
         end if;
      end if;
   end process;

   stim : process
      alias dbg_decodeDone  is <<signal .tb_mdec_equiv.iref.decodeDone   : std_logic>>;
      alias dbg_fifoOutDone is <<signal .tb_mdec_equiv.iref.fifoOut_done : std_logic>>;
      alias dbg_inEmpty     is <<signal .tb_mdec_equiv.iref.FifoIn_Empty : std_logic>>;
      alias dbg_outEmpty    is <<signal .tb_mdec_equiv.iref.FifoOut_Empty : std_logic>>;
      alias dbg_words       is <<signal .tb_mdec_equiv.iref.wordsRemain  : unsigned(15 downto 0)>>;
      alias dbg_block       is <<signal .tb_mdec_equiv.iref.currentBlock : unsigned(2 downto 0)>>;
      alias dbg_depth       is <<signal .tb_mdec_equiv.iref.rec_depth    : std_logic_vector(1 downto 0)>>;
      variable s1      : positive := SEED;
      variable s2      : positive := 1234567;
      variable r       : real;
      variable l       : line;
      variable n       : integer;
      variable cmd     : std_logic_vector(31 downto 0);
      variable depth   : std_logic_vector(1 downto 0);
      type t_hw is array (0 to 8191) of std_logic_vector(15 downto 0);
      variable hw      : t_hw;
      variable nhw     : integer;
      variable coef    : integer;
      variable run     : integer;
      variable nblk    : integer;
      variable wedged  : boolean := false;
      variable lastCmd : std_logic_vector(31 downto 0) := (others => '0');

      impure function rnd(k : integer) return integer is
      begin
         uniform(s1, s2, r); return integer(trunc(r * real(k)));
      end function;
      impure function rnd16 return std_logic_vector is
      begin
         return std_logic_vector(to_unsigned(rnd(65536), 16));
      end function;

      procedure tick is
      begin
         wait until rising_edge(clk1x);
         bus_read <= '0'; bus_write <= '0'; dma_write <= '0';
         lastBusRead <= x"F";
         if (CE_RAND = 1 and rnd(16) = 0) then ce <= '0'; else ce <= '1'; end if;
      end procedure;

      -- push one word through DMA0, waiting for the request; random status reads in between
      procedure push(w : std_logic_vector(31 downto 0)) is
         variable waitc : integer := 0;
      begin
         if (wedged) then return; end if;  -- rest of an aborted command is dropped
         loop
            waitc := waitc + 1;
            if (waitc > 50000) then
               -- random data can wedge the MDEC (both copies identically); recover via control reset
               hangs <= hangs + 1;
               write(l, string'("wedge: decodeDone=") & std_logic'image(dbg_decodeDone) & string'(" fifoOut_done=") & std_logic'image(dbg_fifoOutDone)
                     & string'(" inEmpty=") & std_logic'image(dbg_inEmpty) & string'(" outEmpty=") & std_logic'image(dbg_outEmpty)
                     & string'(" wordsRemain=") & integer'image(to_integer(dbg_words)) & string'(" block=") & integer'image(to_integer(dbg_block))
                     & string'(" depth=") & to_string(dbg_depth) & string'(" lastcmd=") & to_hstring(lastCmd));
               writeline(output, l);
               bus_addr <= x"4"; bus_dataWrite <= x"E0000000"; bus_write <= '1';
               wait until rising_edge(clk1x);
               bus_write <= '0';
               wait until rising_edge(clk1x);
               bus_addr <= x"4"; bus_dataWrite <= x"60000000"; bus_write <= '1';
               wait until rising_edge(clk1x);
               bus_write <= '0';
               waitc := 0;
               wedged := true;
               return;
            end if;
            if (rnd(40) = 0) then
               bus_addr <= x"4"; bus_read <= '1'; lastBusRead <= x"4";
               wait until rising_edge(clk1x);
               bus_read <= '0'; lastBusRead <= x"4";
            end if;
            exit when dmaWr_ref = '1' and ce = '1';
            tick;
         end loop;
         dma_writedata <= w; dma_write <= '1';
         wait until rising_edge(clk1x);
         dma_write <= '0'; lastBusRead <= x"F";
         if (CE_RAND = 1 and rnd(16) = 0) then ce <= '0'; else ce <= '1'; end if;
      end procedure;

      -- random RL halfword: mostly real-looking runs, sometimes the FE00 padding code
      impure function rl return std_logic_vector is
         variable k : integer;
      begin
         k := rnd(10);
         if (k = 0) then return x"FE00";
         elsif (k < 6) then return std_logic_vector(to_unsigned(rnd(8), 6)) & std_logic_vector(to_unsigned(rnd(1024), 10));
         else return rnd16;
         end if;
      end function;

   begin
      reset <= '1';
      for i in 0 to 9 loop wait until rising_edge(clk1x); end loop;
      reset <= '0';
      wait until rising_edge(clk1x);
      -- enable DMA in/out
      bus_addr <= x"4"; bus_dataWrite <= x"60000000"; bus_write <= '1';
      tick;

      for c in 0 to NUM_CMDS - 1 loop
         if (c mod 10 = 0) then
            write(l, string'("progress cmd ") & integer'image(c) & string'(" words_out=") & integer'image(wordsOut)
                  & string'(" mismatches=") & integer'image(ctrlMismatch + dataMismatch + fifoCtrlMis + fifoDataMis) & string'(" fifo_writes=") & integer'image(fifoWrites) & string'(" wedge_resets=") & integer'image(hangs)); writeline(output, l);
         end if;
         wedged := false;
         case rnd(8) is
            when 0 =>
               -- quant table (luma only or luma+chroma)
               if (rnd(2) = 0) then
                  push(x"40000001"); for i in 1 to 32 loop push(rnd16 & rnd16); end loop;
               else
                  push(x"40000000"); for i in 1 to 16 loop push(rnd16 & rnd16); end loop;
               end if;
            when 1 =>
               push(x"60000000"); for i in 1 to 32 loop push(rnd16 & rnd16); end loop;
            when 2 =>
               -- occasional MDEC reset through the control register
               if (rnd(4) = 0) then
                  bus_addr <= x"4"; bus_dataWrite <= x"E0000000"; bus_write <= '1';
                  tick;
                  bus_addr <= x"4"; bus_dataWrite <= x"60000000"; bus_write <= '1';
                  tick;
               end if;
            when others =>
               -- decode macroblocks
               depth := std_logic_vector(to_unsigned(rnd(4), 2));
               depthNow <= depth;
               if (rnd(5) = 0) then
                  -- unstructured data (robustness)
                  n := 1 + rnd(400);
                  cmd := "001" & depth & std_logic_vector(to_unsigned(rnd(2), 1)) & std_logic_vector(to_unsigned(rnd(2), 1)) &
                         "000000000" & std_logic_vector(to_unsigned(n, 16));
                  push(cmd);
                  for i in 1 to n loop push(rl & rl); end loop;
               else
                  -- well-formed macroblocks like real STR video: per block a qscale/DC header,
                  -- run-level codes, then the FE00 end-of-block code
                  nhw := 0;
                  if (depth(1) = '1') then nblk := 6 * (1 + rnd(8)); else nblk := 1 + rnd(8); end if;
                  for b in 1 to nblk loop
                     hw(nhw) := std_logic_vector(to_unsigned(1 + rnd(63), 6)) & std_logic_vector(to_unsigned(rnd(1024), 10)); nhw := nhw + 1;
                     coef := 0;
                     for k in 1 to rnd(20) loop
                        run := rnd(6);
                        exit when coef + run + 1 >= 63;
                        coef := coef + run + 1;
                        hw(nhw) := std_logic_vector(to_unsigned(run, 6)) & std_logic_vector(to_unsigned(rnd(1024), 10)); nhw := nhw + 1;
                     end loop;
                     hw(nhw) := x"FE00"; nhw := nhw + 1;
                  end loop;
                  if (nhw mod 2 = 1) then hw(nhw) := x"FE00"; nhw := nhw + 1; end if;
                  n := nhw / 2;
                  cmd := "001" & depth & std_logic_vector(to_unsigned(rnd(2), 1)) & std_logic_vector(to_unsigned(rnd(2), 1)) &
                         "000000000" & std_logic_vector(to_unsigned(n, 16));
                  lastCmd := cmd;
                  push(cmd);
                  for i in 0 to n - 1 loop push(hw(2 * i + 1) & hw(2 * i)); end loop;
               end if;
               -- let the output drain
               for i in 0 to 3000 + rnd(3000) loop tick; end loop;
         end case;
      end loop;
      for i in 0 to 20000 loop tick; end loop;

      write(l, string'("DONE commands=") & integer'image(NUM_CMDS) & string'(" words_out=") & integer'image(wordsOut)
            & string'(" status_reads=") & integer'image(statusReads)
            & string'(" fifo_writes=") & integer'image(fifoWrites) & string'(" wedge_resets=") & integer'image(hangs)
            & string'(" control_mismatches=") & integer'image(ctrlMismatch + fifoCtrlMis) & string'(" data_mismatches=") & integer'image(dataMismatch + fifoDataMis));
      writeline(output, l);
      if (ctrlMismatch + fifoCtrlMis = 0 and dataMismatch + fifoDataMis = 0 and wordsOut > 0 and fifoWrites > 0) then write(l, string'("PASS")); else write(l, string'("FAIL")); end if;
      writeline(output, l);
      std.env.finish;
   end process;

end architecture;
