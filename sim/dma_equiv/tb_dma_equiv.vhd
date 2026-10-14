-- Equivalence test: current rtl/dma.vhd (dma_new) against dma.vhd of a reference git revision
-- (dma_ref). Random CPU register traffic biased towards starting transfers on all channels,
-- device requests and data, a RAM model answering the reference's requests, a RAM write-FIFO
-- reader, CPU pause/canDMA activity, and reset sequences with savestate zero-writes. Every output
-- is compared on every clk3x edge.
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use STD.textio.all;

entity tb_dma_equiv is
   generic
   (
      NUM_CYCLES : integer := 1000000;  -- clk1x cycles
      SEED       : integer := 1;
      REALISTIC  : boolean := false     -- true: no CPU register access while the CPU is paused for DMA (as in psx_top)
   );
end entity;

architecture sim of tb_dma_equiv is

   signal clk1x, clk2x, clk3x : std_logic := '1';
   signal clk1xToggle, clk1xToggle3x, clk1xToggle3x_1 : std_logic := '0';
   signal clk3xIndex      : std_logic := '0';
   signal ce              : std_logic := '1';
   signal reset           : std_logic := '1';

   signal canDMA, cpuPaused : std_logic := '0';
   signal dma_wr, dma_reqprocessed : std_logic := '0';
   signal dma_data        : std_logic_vector(31 downto 0) := (others => '0');
   signal ram_dmafifo_read : std_logic := '0';
   signal gpu_dmaRequest, mdec_dmaWriteRequest, mdec_dmaReadRequest, spu_dmaRequest : std_logic := '0';
   signal DMA_GPU_read, DMA_MDEC_read : std_logic_vector(31 downto 0) := (others => '0');
   signal DMA_CD_read     : std_logic_vector(7 downto 0) := (others => '0');
   signal DMA_SPU_read    : std_logic_vector(15 downto 0) := (others => '0');
   signal cd_memctrl      : unsigned(13 downto 0) := (others => '0');
   signal com0_delay      : unsigned(3 downto 0) := (others => '0');
   signal spu_timing_on   : std_logic := '0';
   signal spu_timing_value: unsigned(3 downto 0) := (others => '0');
   signal bus_addr        : unsigned(6 downto 0) := (others => '0');
   signal bus_dataWrite   : std_logic_vector(31 downto 0) := (others => '0');
   signal bus_read, bus_write : std_logic := '0';
   signal loading_savestate, SS_reset, SS_wren : std_logic := '0';
   signal SS_Adr          : unsigned(5 downto 0) := (others => '0');

   type tOut is record
      errorCHOP, errorDMACPU, errorDMAFIFO, dmaRequest, dmaStallCPU, dmaOn, irqOut : std_logic;
      ram_Adr          : std_logic_vector(22 downto 0);
      ram_cnt          : std_logic_vector(1 downto 0);
      ram_ena          : std_logic;
      ram_dmafifo_adr  : std_logic_vector(22 downto 0);
      ram_dmafifo_data : std_logic_vector(31 downto 0);
      ram_dmafifo_empty: std_logic;
      dma_cache_Adr    : std_logic_vector(20 downto 0);
      dma_cache_data   : std_logic_vector(31 downto 0);
      dma_cache_write  : std_logic;
      DMA_GPU_waiting, DMA_GPU_writeEna, DMA_GPU_readEna : std_logic;
      DMA_GPU_write    : std_logic_vector(31 downto 0);
      DMA_MDEC_writeEna, DMA_MDEC_readEna : std_logic;
      DMA_MDEC_write   : std_logic_vector(31 downto 0);
      DMA_CD_readEna   : std_logic;
      DMA_SPU_writeEna, DMA_SPU_readEna : std_logic;
      DMA_SPU_write    : std_logic_vector(15 downto 0);
      bus_dataRead     : std_logic_vector(31 downto 0);
      SS_idle          : std_logic;
   end record;
   signal o_ref, o_new : tOut;

   signal mismatches : integer := 0;
   signal transfers  : integer := 0;
   signal words      : integer := 0;
   signal resets     : integer := 0;

   function differs(a, b : tOut) return boolean is
   begin
      return a.errorCHOP /= b.errorCHOP or a.errorDMACPU /= b.errorDMACPU or a.errorDMAFIFO /= b.errorDMAFIFO or
         a.dmaRequest /= b.dmaRequest or a.dmaStallCPU /= b.dmaStallCPU or a.dmaOn /= b.dmaOn or a.irqOut /= b.irqOut or
         a.ram_ena /= b.ram_ena or a.ram_Adr /= b.ram_Adr or a.ram_cnt /= b.ram_cnt or
         a.ram_dmafifo_empty /= b.ram_dmafifo_empty or
         (a.ram_dmafifo_empty = '0' and (a.ram_dmafifo_adr /= b.ram_dmafifo_adr or a.ram_dmafifo_data /= b.ram_dmafifo_data)) or
         a.dma_cache_write /= b.dma_cache_write or
         (a.dma_cache_write = '1' and (a.dma_cache_Adr /= b.dma_cache_Adr or a.dma_cache_data /= b.dma_cache_data)) or
         a.DMA_GPU_waiting /= b.DMA_GPU_waiting or a.DMA_GPU_writeEna /= b.DMA_GPU_writeEna or a.DMA_GPU_readEna /= b.DMA_GPU_readEna or
         (a.DMA_GPU_writeEna = '1' and a.DMA_GPU_write /= b.DMA_GPU_write) or
         a.DMA_MDEC_writeEna /= b.DMA_MDEC_writeEna or a.DMA_MDEC_readEna /= b.DMA_MDEC_readEna or
         (a.DMA_MDEC_writeEna = '1' and a.DMA_MDEC_write /= b.DMA_MDEC_write) or
         a.DMA_CD_readEna /= b.DMA_CD_readEna or
         a.DMA_SPU_writeEna /= b.DMA_SPU_writeEna or a.DMA_SPU_readEna /= b.DMA_SPU_readEna or
         (a.DMA_SPU_writeEna = '1' and a.DMA_SPU_write /= b.DMA_SPU_write) or
         (not is_x(a.bus_dataRead) and a.bus_dataRead /= b.bus_dataRead) or  -- undefined until the first read
         a.SS_idle /= b.SS_idle;
   end function;

begin

   -- clk1x 30 ns, clk3x 10 ns (exactly 3x, aligned)
   clk3x <= not clk3x after 5 ns;
   clk1x <= not clk1x after 15 ns;
   clk2x <= not clk2x after 7.5 ns;

   process (clk1x) begin
      if rising_edge(clk1x) then clk1xToggle <= not clk1xToggle; end if;
   end process;
   process (clk3x) begin
      if rising_edge(clk3x) then
         clk1xToggle3x   <= clk1xToggle;
         clk1xToggle3x_1 <= clk1xToggle3x;
         clk3xIndex <= '0';
         if (clk1xToggle3x_1 = clk1xToggle) then clk3xIndex <= '1'; end if;
      end if;
   end process;

   gdut : for i in 0 to 1 generate
      signal o : tOut;
   begin
      gref : if i = 0 generate
         idut : entity work.dma_ref
         port map (clk1x => clk1x, clk3x => clk3x, clk3xIndex => clk3xIndex, ce => ce, reset => reset,
            errorCHOP => o.errorCHOP, errorDMACPU => o.errorDMACPU, errorDMAFIFO => o.errorDMAFIFO,
            TURBO => '0', TURBO_CACHE => '0', ram8mb => '0', ignoreCDTiming => '0',
            canDMA => canDMA, cpuPaused => cpuPaused, dmaRequest => o.dmaRequest, dmaStallCPU => o.dmaStallCPU,
            dmaOn => o.dmaOn, irqOut => o.irqOut, ram_Adr => o.ram_Adr, ram_cnt => o.ram_cnt, ram_ena => o.ram_ena,
            dma_wr => dma_wr, dma_reqprocessed => dma_reqprocessed, dma_data => dma_data,
            ram_dmafifo_adr => o.ram_dmafifo_adr, ram_dmafifo_data => o.ram_dmafifo_data,
            ram_dmafifo_empty => o.ram_dmafifo_empty, ram_dmafifo_read => ram_dmafifo_read,
            dma_cache_Adr => o.dma_cache_Adr, dma_cache_data => o.dma_cache_data, dma_cache_write => o.dma_cache_write,
            gpu_dmaRequest => gpu_dmaRequest, DMA_GPU_waiting => o.DMA_GPU_waiting, DMA_GPU_writeEna => o.DMA_GPU_writeEna,
            DMA_GPU_readEna => o.DMA_GPU_readEna, DMA_GPU_write => o.DMA_GPU_write, DMA_GPU_read => DMA_GPU_read,
            mdec_dmaWriteRequest => mdec_dmaWriteRequest, mdec_dmaReadRequest => mdec_dmaReadRequest,
            DMA_MDEC_writeEna => o.DMA_MDEC_writeEna, DMA_MDEC_readEna => o.DMA_MDEC_readEna,
            DMA_MDEC_write => o.DMA_MDEC_write, DMA_MDEC_read => DMA_MDEC_read,
            cd_memctrl => cd_memctrl, com0_delay => com0_delay, DMA_CD_readEna => o.DMA_CD_readEna, DMA_CD_read => DMA_CD_read,
            spu_timing_on => spu_timing_on, spu_timing_value => spu_timing_value,
            spu_dmaRequest => spu_dmaRequest, DMA_SPU_writeEna => o.DMA_SPU_writeEna, DMA_SPU_readEna => o.DMA_SPU_readEna,
            DMA_SPU_write => o.DMA_SPU_write, DMA_SPU_read => DMA_SPU_read,
            bus_addr => bus_addr, bus_dataWrite => bus_dataWrite, bus_read => bus_read, bus_write => bus_write,
            bus_dataRead => o.bus_dataRead, loading_savestate => loading_savestate, SS_reset => SS_reset,
            SS_DataWrite => (others => '0'), SS_Adr => SS_Adr, SS_wren => SS_wren, SS_rden => '0',
            SS_DataRead => open, SS_idle => o.SS_idle);
         o_ref <= o;
      end generate;
      gnew : if i = 1 generate
         idut : entity work.dma_new
         port map (clk1x => clk1x, clk3x => clk3x, clk3xIndex => clk3xIndex, ce => ce, reset => reset,
            errorCHOP => o.errorCHOP, errorDMACPU => o.errorDMACPU, errorDMAFIFO => o.errorDMAFIFO,
            TURBO => '0', TURBO_CACHE => '0', ram8mb => '0', ignoreCDTiming => '0',
            canDMA => canDMA, cpuPaused => cpuPaused, dmaRequest => o.dmaRequest, dmaStallCPU => o.dmaStallCPU,
            dmaOn => o.dmaOn, irqOut => o.irqOut, ram_Adr => o.ram_Adr, ram_cnt => o.ram_cnt, ram_ena => o.ram_ena,
            dma_wr => dma_wr, dma_reqprocessed => dma_reqprocessed, dma_data => dma_data,
            ram_dmafifo_adr => o.ram_dmafifo_adr, ram_dmafifo_data => o.ram_dmafifo_data,
            ram_dmafifo_empty => o.ram_dmafifo_empty, ram_dmafifo_read => ram_dmafifo_read,
            dma_cache_Adr => o.dma_cache_Adr, dma_cache_data => o.dma_cache_data, dma_cache_write => o.dma_cache_write,
            gpu_dmaRequest => gpu_dmaRequest, DMA_GPU_waiting => o.DMA_GPU_waiting, DMA_GPU_writeEna => o.DMA_GPU_writeEna,
            DMA_GPU_readEna => o.DMA_GPU_readEna, DMA_GPU_write => o.DMA_GPU_write, DMA_GPU_read => DMA_GPU_read,
            mdec_dmaWriteRequest => mdec_dmaWriteRequest, mdec_dmaReadRequest => mdec_dmaReadRequest,
            DMA_MDEC_writeEna => o.DMA_MDEC_writeEna, DMA_MDEC_readEna => o.DMA_MDEC_readEna,
            DMA_MDEC_write => o.DMA_MDEC_write, DMA_MDEC_read => DMA_MDEC_read,
            cd_memctrl => cd_memctrl, com0_delay => com0_delay, DMA_CD_readEna => o.DMA_CD_readEna, DMA_CD_read => DMA_CD_read,
            spu_timing_on => spu_timing_on, spu_timing_value => spu_timing_value,
            spu_dmaRequest => spu_dmaRequest, DMA_SPU_writeEna => o.DMA_SPU_writeEna, DMA_SPU_readEna => o.DMA_SPU_readEna,
            DMA_SPU_write => o.DMA_SPU_write, DMA_SPU_read => DMA_SPU_read,
            bus_addr => bus_addr, bus_dataWrite => bus_dataWrite, bus_read => bus_read, bus_write => bus_write,
            bus_dataRead => o.bus_dataRead, loading_savestate => loading_savestate, SS_reset => SS_reset,
            SS_DataWrite => (others => '0'), SS_Adr => SS_Adr, SS_wren => SS_wren, SS_rden => '0',
            SS_DataRead => open, SS_idle => o.SS_idle);
         o_new <= o;
      end generate;
   end generate;

   cmp : process (clk3x)
      variable l : line;
   begin
      if rising_edge(clk3x) then
         if (reset = '0' and differs(o_ref, o_new)) then
            if (mismatches < 10) then
               write(l, string'("MISMATCH at ") & time'image(now) & string'(" ram_ena ") & std_logic'image(o_ref.ram_ena) & string'("/") & std_logic'image(o_new.ram_ena)
                     & string'(" adr ") & to_hstring(o_ref.ram_Adr) & string'("/") & to_hstring(o_new.ram_Adr)
                     & string'(" busRd ") & to_hstring(o_ref.bus_dataRead) & string'("/") & to_hstring(o_new.bus_dataRead)
                     & string'(" dmaOn ") & std_logic'image(o_ref.dmaOn) & string'("/") & std_logic'image(o_new.dmaOn)
                     & string'(" irq ") & std_logic'image(o_ref.irqOut) & string'("/") & std_logic'image(o_new.irqOut));
               writeline(output, l);
            end if;
            mismatches <= mismatches + 1;
         end if;
      end if;
   end process;

   -- RAM model (clk1x), driven from the reference's requests: each request is acknowledged with
   -- dma_reqprocessed after a delay; read data words arrive on dma_wr with random gaps
   ram : process (clk1x)
      variable s1 : positive := SEED + 11;
      variable s2 : positive := 5555;
      variable r  : real;
      variable reqDelay : integer := -1;
      variable pendingWords : integer := 0;
   begin
      if rising_edge(clk1x) then
         dma_reqprocessed <= '0';
         dma_wr           <= '0';
         if (o_ref.ram_ena = '1') then
            uniform(s1, s2, r); reqDelay := 1 + integer(trunc(r * 4.0));
            pendingWords := pendingWords + 1 + to_integer(unsigned(o_ref.ram_cnt));
         elsif (reqDelay > 0) then
            reqDelay := reqDelay - 1;
         elsif (reqDelay = 0) then
            dma_reqprocessed <= '1';
            reqDelay := -1;
         end if;
         uniform(s1, s2, r);
         if (pendingWords > 0 and r < 0.6) then
            dma_wr <= '1';
            pendingWords := pendingWords - 1;
            words <= words + 1;
            uniform(s1, s2, r);
            -- linked-list headers: mostly short packets, sometimes the end marker
            if (r < 0.15) then dma_data <= x"00FFFFFF";
            else dma_data <= std_logic_vector(to_unsigned(integer(trunc(r * 4.0)), 8)) & std_logic_vector(to_unsigned(integer(trunc(r * 16777215.0)), 24));
            end if;
         end if;
         if (o_ref.dmaOn = '0' and o_ref.ram_ena = '0') then pendingWords := 0; end if;
      end if;
   end process;

   -- RAM write-FIFO reader (memory side, clk3x)
   fiford : process (clk3x)
      variable s1 : positive := SEED + 23;
      variable s2 : positive := 777;
      variable r  : real;
   begin
      if rising_edge(clk3x) then
         ram_dmafifo_read <= '0';
         uniform(s1, s2, r);
         if (o_ref.ram_dmafifo_empty = '0' and ram_dmafifo_read = '0' and r < 0.4) then
            ram_dmafifo_read <= '1';
         end if;
      end if;
   end process;

   stim : process
      variable s1 : positive := SEED;
      variable s2 : positive := 1234567;
      variable r  : real;
      variable l  : line;
      variable ch : integer;
      variable pick : integer;
      variable d  : std_logic_vector(31 downto 0);

      impure function rnd(k : integer) return integer is
      begin
         uniform(s1, s2, r); return integer(trunc(r * real(k)));
      end function;
      impure function rnd32 return std_logic_vector is
      begin
         return std_logic_vector(to_unsigned(rnd(65536), 16)) & std_logic_vector(to_unsigned(rnd(65536), 16));
      end function;

      procedure resetSeq is
      begin
         reset <= '1';
         for i in 0 to 3 loop wait until rising_edge(clk1x); end loop;
         SS_reset <= '1';
         wait until rising_edge(clk1x);
         SS_reset <= '0';
         for i in 0 to 10 loop wait until rising_edge(clk1x); end loop;
         reset <= '0';
         -- savestate module writes zeros to the state words after reset
         for i in 0 to 63 loop
            wait until rising_edge(clk1x);
            SS_Adr <= to_unsigned(i, 6); SS_wren <= '1';
         end loop;
         wait until rising_edge(clk1x);
         SS_wren <= '0';
         -- game init: enable all channels
         wait until rising_edge(clk1x);
         bus_addr <= to_unsigned(16#70#, 7); bus_dataWrite <= x"0FEDCBA8"; bus_write <= '1';
         wait until rising_edge(clk1x);
         bus_write <= '0';
      end procedure;
   begin
      resetSeq;

      for c in 0 to NUM_CYCLES - 1 loop
         wait until rising_edge(clk1x);
         bus_read <= '0'; bus_write <= '0';
         if (rnd(4) = 0) then canDMA <= '0'; else canDMA <= '1'; end if;
         -- the CPU is paused while DMA runs (it stalls on the DMA request)
         cpuPaused <= o_ref.dmaOn;
         if (rnd(50) = 0) then gpu_dmaRequest <= not gpu_dmaRequest; end if;
         if (rnd(50) = 0) then mdec_dmaWriteRequest <= not mdec_dmaWriteRequest; end if;
         if (rnd(50) = 0) then mdec_dmaReadRequest <= not mdec_dmaReadRequest; end if;
         if (rnd(50) = 0) then spu_dmaRequest <= not spu_dmaRequest; end if;
         if (rnd(8) = 0) then DMA_GPU_read <= rnd32; DMA_MDEC_read <= rnd32; d := rnd32; DMA_SPU_read <= d(15 downto 0); DMA_CD_read <= d(23 downto 16); end if;
         if (rnd(5000) = 0) then cd_memctrl <= to_unsigned(rnd(16384), 14); com0_delay <= to_unsigned(rnd(16), 4); end if;
         if (rnd(5000) = 0) then spu_timing_on <= not spu_timing_on; spu_timing_value <= to_unsigned(rnd(16), 4); end if;
         if (rnd(200000) = 0) then
            resets <= resets + 1;
            resetSeq;
         end if;

         pick := rnd(60);
         if (REALISTIC and o_ref.dmaOn = '1') then pick := 59; end if;   -- CPU paused: no register access
         case pick is
            when 0 | 1 =>
               -- channel register write: MADR, BCR (small blocks) or CHCR (often starting the channel)
               ch := rnd(7);
               case rnd(3) is
                  when 0 => d := rnd32; bus_addr <= to_unsigned(ch * 16 + 0, 7);
                  when 1 => d := std_logic_vector(to_unsigned(1 + rnd(4), 16)) & std_logic_vector(to_unsigned(1 + rnd(16), 16));
                            if (rnd(4) = 0) then d := std_logic_vector(to_unsigned(1 + rnd(8), 16)) & std_logic_vector(to_unsigned(1 + rnd(256), 16)); end if;
                            bus_addr <= to_unsigned(ch * 16 + 4, 7);
                  when others =>
                            d := rnd32;
                            if (rnd(3) /= 0) then d(24) := '1'; end if;                 -- start/busy
                            if (rnd(3) = 0) then d(28) := '1'; end if;                  -- manual trigger
                            if (rnd(2) = 0) then d(10 downto 9) := "10"; end if;        -- linked list
                            -- directions real software uses: MDEC in = to device, MDEC out/CD/OTC = from device;
                            -- channel 5 (PIO) is never started
                            if (ch = 0) then d(0) := '1'; end if;
                            if (ch = 1 or ch = 3 or ch = 6) then d(0) := '0'; end if;
                            if (ch = 5) then d(24) := '0'; d(28) := '0'; end if;
                            bus_addr <= to_unsigned(ch * 16 + 8, 7);
               end case;
               bus_dataWrite <= d; bus_write <= '1';
            when 2 =>
               -- DPCR / DICR
               if (rnd(2) = 0) then bus_addr <= to_unsigned(16#70#, 7); d := rnd32; d(31 downto 28) := x"0"; d := d or x"08888888";
               else bus_addr <= to_unsigned(16#74#, 7); d := rnd32; end if;
               bus_dataWrite <= d; bus_write <= '1';
            when 3 | 4 | 5 =>
               bus_addr <= to_unsigned(4 * rnd(32), 7); bus_read <= '1';
            when others => null;
         end case;

         if (c mod 100000 = 0) then
            write(l, string'("progress cycle ") & integer'image(c) & string'(" mismatches=") & integer'image(mismatches)
                  & string'(" ram_words=") & integer'image(words) & string'(" resets=") & integer'image(resets));
            writeline(output, l);
         end if;
      end loop;

      write(l, string'("DONE cycles=") & integer'image(NUM_CYCLES) & string'(" transfers=") & integer'image(transfers) & string'(" ram_words=") & integer'image(words)
            & string'(" resets=") & integer'image(resets) & string'(" mismatch_cycles=") & integer'image(mismatches));
      writeline(output, l);
      if (mismatches = 0 and words > 0) then write(l, string'("PASS")); else write(l, string'("FAIL")); end if;
      writeline(output, l);
      std.env.finish;
   end process;

   -- count started transfers (reference)
   process (clk1x)
      variable last : std_logic := '0';
   begin
      if rising_edge(clk1x) then
         if (o_ref.dmaOn = '1' and last = '0') then transfers <= transfers + 1; end if;
         last := o_ref.dmaOn;
      end if;
   end process;

end architecture;
