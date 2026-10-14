-- Main RAM / BIOS model for the boot simulation: the core's SDRAM interface (ram_*, cache fill, DMA reads,
-- DMA write FIFO) with the same handshake and latencies as upstream's sim/system/src/tb/sdram_model3x.vhd
-- (which models rtl/sdram.sv at the channel level), without refresh. Byte array of 16 MB: main RAM at 0,
-- BIOS at 0x800000, loaded at time 0 from a text file with one little-endian 32-bit word per line (hex).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity ram_model is
   generic
   (
      BIOS_FILE  : string := "bios.hex";
      BIOS_ADDR  : integer := 16#800000#;
      -- simulation shortcut: the BIOS's byte-by-byte shell copy memcpy(80030000, BFC18000, 67FF0) at BFC0700C
      -- (~2.6 s of console time) is replaced by a NOP and done instantly when preload_shell rises
      FAST_SHELL : boolean := false;
      -- with FAST_SHELL: the shell's boot intro (80040490, the SCE logo animation, ~10 s of console time) returns
      -- at once, so the main menu comes right after the shell's initialisation
      SKIP_INTRO : boolean := false
   );
   port
   (
      clk               : in  std_logic;                       -- clk1x
      clk3x             : in  std_logic;
      addr              : in  std_logic_vector(26 downto 0);
      req               : in  std_logic;
      ram_dma           : in  std_logic;
      ram_dmacnt        : in  std_logic_vector(1 downto 0);
      ram_iscache       : in  std_logic;
      rnw               : in  std_logic;
      be                : in  std_logic_vector(3 downto 0);
      di                : in  std_logic_vector(31 downto 0);
      do32              : out std_logic_vector(31 downto 0) := (others => '0');
      done              : buffer std_logic := '0';
      cache_wr          : out std_logic_vector(3 downto 0) := (others => '0');
      cache_data        : out std_logic_vector(31 downto 0) := (others => '0');
      cache_addr        : out std_logic_vector(7 downto 0) := (others => '0');
      dma_wr            : buffer std_logic := '0';
      dma_data          : out std_logic_vector(31 downto 0) := (others => '0');
      reqprocessed      : buffer std_logic := '0';
      ram_dmafifo_adr   : in  std_logic_vector(22 downto 0);
      ram_dmafifo_data  : in  std_logic_vector(31 downto 0);
      ram_dmafifo_empty : in  std_logic;
      ram_dmafifo_read  : out std_logic := '0';
      preload_shell     : in  std_logic := '0'
   );
end entity;

architecture sim of ram_model is

   constant BURST_LENGTH : integer := 8;
   constant CAS_LATENCY  : integer := 2;

   type t_data is array(0 to 2 ** 24 - 1) of natural range 0 to 255;
   shared variable data : t_data := (others => 0);

   signal do                : std_logic_vector(127 downto 0) := (others => '0');
   signal clk1xToggle       : std_logic := '0';
   signal clk1xToggle3X     : std_logic := '0';
   signal clk1xToggle3X_1   : std_logic := '0';
   signal clk3xIndex        : std_logic := '0';
   signal data_ready_delay1 : std_logic_vector(BURST_LENGTH + CAS_LATENCY downto 0) := (others => '0');
   signal req_buffer        : std_logic := '0';
   signal addr_buffer       : std_logic_vector(26 downto 0) := (others => '0');
   signal rnw_buffer        : std_logic := '0';
   signal lastbank          : std_logic_vector(12 downto 0) := (others => '0');
   signal reqprocessed_3x   : std_logic := '0';
   signal done_3x           : std_logic := '0';
   signal cache_buffer      : std_logic := '0';
   signal cache_buffer_next : std_logic := '0';
   signal cache_done_0, cache_done_1, cache_done_2, cache_done_3 : std_logic := '0';
   signal cache_wr_next     : std_logic_vector(3 downto 0) := (others => '0');
   signal dma_buffer        : std_logic := '0';
   signal dma_done          : std_logic := '0';
   signal dma_ack           : std_logic := '0';
   signal dma_count_3x      : unsigned(1 downto 0) := (others => '0');
   signal dma_count         : unsigned(1 downto 0) := (others => '0');
   signal dma_counter       : unsigned(1 downto 0) := (others => '0');
   signal dma_do            : std_logic_vector(127 downto 0) := (others => '0');

   type tstate is (STATE_IDLE, STATE_WAIT, STATE_RW1, STATE_RW2, STATE_IDLE_9, STATE_IDLE_8, STATE_IDLE_7, STATE_IDLE_6,
                   STATE_IDLE_5, STATE_IDLE_4, STATE_IDLE_3, STATE_IDLE_2, STATE_IDLE_1);
   signal state : tstate := STATE_IDLE;

   procedure write32(a : integer; d : std_logic_vector(31 downto 0); b : std_logic_vector(3 downto 0)) is
   begin
      for i in 0 to 3 loop
         if (b(i) = '1') then data(a + i) := to_integer(unsigned(d(i * 8 + 7 downto i * 8))); end if;
      end loop;
   end procedure;

begin

   -- BIOS image
   process
      file f      : text;
      variable st : file_open_status;
      variable l  : line;
      variable w  : std_logic_vector(31 downto 0);
      variable a  : integer := BIOS_ADDR;
   begin
      file_open(st, f, BIOS_FILE, read_mode);
      assert st = open_ok report "cannot open " & BIOS_FILE severity failure;
      while not endfile(f) loop
         readline(f, l);
         hread(l, w);
         write32(a, w, "1111");
         a := a + 4;
      end loop;
      file_close(f);
      report "BIOS loaded: " & integer'image((a - BIOS_ADDR) / 4) & " words";
      if FAST_SHELL then
         -- the memcpy call (jal BFC02B50 = 0FF00AD4) becomes a NOP
         assert data(BIOS_ADDR + 16#700C#) = 16#D4# and data(BIOS_ADDR + 16#700F#) = 16#0F# report "unexpected BIOS at 700C" severity failure;
         write32(BIOS_ADDR + 16#700C#, x"00000000", "1111");
         wait until rising_edge(preload_shell);
         for i in 0 to 16#67FF0# - 1 loop
            data(16#30000# + i) := data(BIOS_ADDR + 16#18000# + i);
         end loop;
         -- the shell's busy-wait between SPU RAM clear blocks (80054140: count to 240, twice "slti at,rN,240")
         -- counts to 24 instead: still longer than the SPU needs for a 32-halfword block
         assert data(16#54150#) = 16#F0# and data(16#54188#) = 16#F0# report "unexpected shell code at 80054150" severity failure;
         data(16#54150#) := 16#18#;
         data(16#54188#) := 16#18#;
         report "shell preloaded to 80030000 (simulation shortcut, SPU clear delay 240 -> 24)";
         if SKIP_INTRO then
            assert data(16#40490#) = 16#E0# and data(16#40493#) = 16#27# report "unexpected shell code at 80040490" severity failure;
            write32(16#40490#, x"03E00008", "1111");   -- jr ra
            write32(16#40494#, x"00001021", "1111");   -- addu v0,zero,zero
            report "shell intro skipped (simulation shortcut)";
         end if;
      end if;
      wait;
   end process;

   process (clk)
   begin
      if rising_edge(clk) then
         clk1xToggle  <= not clk1xToggle;
         done         <= done_3x;
         reqprocessed <= reqprocessed_3x;

         if (done_3x = '1') then
            if (addr_buffer(0) = '1') then do32 <= x"00" & do(31 downto 8); else do32 <= do(31 downto 0); end if;
         end if;

         dma_wr  <= '0';
         dma_ack <= '0';
         if (dma_wr = '1') then
            if (dma_counter < dma_count) then
               dma_wr      <= '1';
               dma_counter <= dma_counter + 1;
               if (dma_counter = 0) then dma_data <= dma_do( 63 downto 32); end if;
               if (dma_counter = 1) then dma_data <= dma_do( 95 downto 64); end if;
               if (dma_counter = 2) then dma_data <= dma_do(127 downto 96); end if;
            end if;
         end if;
         if (dma_done = '1') then
            dma_ack     <= '1';
            dma_wr      <= '1';
            dma_data    <= do(31 downto 0);
            dma_do      <= do;
            dma_counter <= (others => '0');
            dma_count   <= dma_count_3x;
         end if;
      end if;
   end process;

   process (clk3x)
      variable a : std_logic_vector(26 downto 0);
      variable w : integer;
   begin
      if rising_edge(clk3x) then
         clk1xToggle3X   <= clk1xToggle;
         clk1xToggle3X_1 <= clk1xToggle3X;
         clk3xIndex      <= '0';
         if (clk1xToggle3X_1 = clk1xToggle) then clk3xIndex <= '1'; end if;

         if (done = '1') then done_3x <= '0'; end if;
         if (dma_ack = '1') then dma_done <= '0'; end if;

         cache_wr     <= (others => '0');
         cache_done_0 <= '0';
         cache_done_1 <= '0';
         cache_done_2 <= '0';
         cache_done_3 <= '0';
         if (cache_done_0 = '1') then cache_data <= do( 31 downto  0); cache_wr <= cache_wr_next; cache_wr_next <= cache_wr_next(2 downto 0) & '0'; end if;
         if (cache_done_1 = '1') then cache_data <= do( 63 downto 32); cache_wr <= cache_wr_next; cache_wr_next <= cache_wr_next(2 downto 0) & '0'; end if;
         if (cache_done_2 = '1') then cache_data <= do( 95 downto 64); cache_wr <= cache_wr_next; cache_wr_next <= cache_wr_next(2 downto 0) & '0'; end if;
         if (cache_done_3 = '1') then cache_data <= do(127 downto 96); cache_wr <= cache_wr_next; cache_wr_next <= cache_wr_next(2 downto 0) & '0'; end if;

         if (reqprocessed = '1') then reqprocessed_3x <= '0'; end if;
         ram_dmafifo_read <= '0';

         if (clk3xIndex = '1' and req = '1') then req_buffer <= '1'; end if;

         data_ready_delay1 <= '0' & data_ready_delay1(data_ready_delay1'left downto 1);

         if (data_ready_delay1(6) = '1' and dma_buffer = '0' and cache_buffer_next = '0') then done_3x  <= '1'; end if;
         if (data_ready_delay1(4) = '1' and cache_buffer_next = '1')                      then done_3x  <= '1'; end if;
         if (data_ready_delay1(6) = '1' and dma_buffer = '1')                             then dma_done <= '1'; end if;

         if (data_ready_delay1(7) = '1') then cache_buffer_next <= cache_buffer; end if;
         if (data_ready_delay1(6) = '1' and cache_buffer_next = '1') then cache_done_0 <= '1'; end if;
         if (data_ready_delay1(4) = '1' and cache_buffer_next = '1') then cache_done_1 <= '1'; end if;
         if (data_ready_delay1(2) = '1' and cache_buffer_next = '1') then cache_done_2 <= '1'; end if;
         if (data_ready_delay1(0) = '1' and cache_buffer_next = '1') then cache_done_3 <= '1'; end if;

         -- burst of 8 halfwords, column address wraps within the 512-halfword row (as sdram.sv)
         if (data_ready_delay1(7) = '1') then
            a := addr_buffer;
            for i in 0 to 7 loop
               w := to_integer(unsigned(a(23 downto 1)) & '0');
               do(7  + i * 16 downto     i * 16) <= std_logic_vector(to_unsigned(data(w + 0), 8));
               do(15 + i * 16 downto 8 + i * 16) <= std_logic_vector(to_unsigned(data(w + 1), 8));
               a(9 downto 1) := std_logic_vector(unsigned(a(9 downto 1)) + 1);
            end loop;
         end if;

         case (state) is
            when STATE_IDLE =>
               if (ram_dmafifo_empty = '0') then
                  write32(to_integer(unsigned(ram_dmafifo_adr(22 downto 1)) & '0'), ram_dmafifo_data, "1111");
                  lastbank         <= ram_dmafifo_adr(22 downto 10);
                  ram_dmafifo_read <= '1';
                  rnw_buffer       <= '0';
                  state            <= STATE_WAIT;
               elsif ((req = '1' or req_buffer = '1') and rnw = '0') then
                  write32(to_integer(unsigned(addr(23 downto 1)) & '0'), di, be);
                  req_buffer <= '0';
                  rnw_buffer <= '0';
                  done_3x    <= '1';
                  state      <= STATE_WAIT;
               elsif ((req = '1' or req_buffer = '1') and rnw = '1') then
                  req_buffer      <= '0';
                  addr_buffer     <= addr;
                  rnw_buffer      <= '1';
                  state           <= STATE_WAIT;
                  cache_buffer    <= ram_iscache;
                  cache_addr      <= addr(11 downto 4);
                  case addr(3 downto 2) is
                     when "00"   => cache_wr_next <= "0001";
                     when "01"   => cache_wr_next <= "0010";
                     when "10"   => cache_wr_next <= "0100";
                     when others => cache_wr_next <= "1000";
                  end case;
                  dma_buffer      <= ram_dma;
                  reqprocessed_3x <= ram_dma;
                  dma_count_3x    <= unsigned(ram_dmacnt);
               end if;
            when STATE_WAIT => state <= STATE_RW1;
            when STATE_RW1 =>
               if (rnw_buffer = '1') then
                  state <= STATE_IDLE_9;
                  data_ready_delay1(CAS_LATENCY + BURST_LENGTH) <= '1';
               else
                  state <= STATE_RW2;
               end if;
            when STATE_RW2 =>
               if (ram_dmafifo_empty = '0' and ram_dmafifo_adr(22 downto 10) = lastbank) then
                  write32(to_integer(unsigned(ram_dmafifo_adr(22 downto 1)) & '0'), ram_dmafifo_data, "1111");
                  ram_dmafifo_read <= '1';
                  state            <= STATE_RW1;
               else
                  state <= STATE_IDLE_2;
               end if;
            when STATE_IDLE_9 => state <= STATE_IDLE_8;
            when STATE_IDLE_8 => state <= STATE_IDLE_7;
            when STATE_IDLE_7 => state <= STATE_IDLE_6;
            when STATE_IDLE_6 => state <= STATE_IDLE_5;
            when STATE_IDLE_5 => state <= STATE_IDLE_4;
            when STATE_IDLE_4 => state <= STATE_IDLE_3;
            when STATE_IDLE_3 => state <= STATE_IDLE_2;
            when STATE_IDLE_2 => state <= STATE_IDLE_1;
            when STATE_IDLE_1 => state <= STATE_IDLE;
         end case;
      end if;
   end process;

end architecture;
