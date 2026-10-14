-- GPU-level equivalence test: the reference gpu.vhd (gpu_ref) and the current gpu.vhd (gpu_new) get identical
-- CPU bus traffic (GP0 fills, CPU->VRAM uploads, VRAM->VRAM copies and VRAM->CPU reads, many of them
-- crossing x = 1024 so VRAM reads wrap), the display runs (video line reads interleave), and each GPU has its
-- own VRAM model with identical random wait states and read latencies. Every clk2x cycle all VRAM request
-- outputs, bus outputs, interrupts and video outputs of the two GPUs are compared.
-- Generated from tb_gpu_vram.tpl.vhd by gen_tb.py (the two GPU port maps).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

entity tb_gpu_vram is
   generic (NUM_CMDS : integer := 300; SEED : integer := 1; COUNT_WRAPS : boolean := true);
end entity;

architecture sim of tb_gpu_vram is

   signal clk1x         : std_logic := '1';
   signal clk2x         : std_logic := '1';
   signal clkvid        : std_logic := '1';
   signal clk1xToggle   : std_logic := '0';
   signal clk1xToggle2x : std_logic := '0';
   signal clk2xIndex    : std_logic := '0';
   signal ce            : std_logic := '1';
   signal reset         : std_logic := '1';
   signal bus_addr      : unsigned(3 downto 0) := (others => '0');
   signal bus_dataWrite : std_logic_vector(31 downto 0) := (others => '0');
   signal bus_read      : std_logic := '0';
   signal bus_write     : std_logic := '0';
   signal vram_pause    : std_logic := '0';
   signal done          : boolean := false;

   type tmem_if is record
      busy  : std_logic;
      dout  : std_logic_vector(63 downto 0);
      ready : std_logic;
   end record;
   type tmem_arr is array(0 to 1) of tmem_if;
   signal m : tmem_arr := (others => ('0', (others => '0'), '0'));

   type tout is record
      bus_dataRead   : std_logic_vector(31 downto 0);
      bus_stall      : std_logic;
      irq_GPU        : std_logic;
      irq_VBLANK     : std_logic;
      gpu_dmaRequest : std_logic;
      vram_BURSTCNT  : std_logic_vector(7 downto 0);
      vram_ADDR      : std_logic_vector(27 downto 0);
      vram_DIN       : std_logic_vector(63 downto 0);
      vram_BE        : std_logic_vector(7 downto 0);
      vram_WE        : std_logic;
      vram_RD        : std_logic;
      video_r        : std_logic_vector(7 downto 0);
      video_g        : std_logic_vector(7 downto 0);
      video_b        : std_logic_vector(7 downto 0);
   end record;
   type tout_arr is array(0 to 1) of tout;
   signal o : tout_arr;

   signal mismatches : integer := 0;
   signal readAccepts : integer := 0;
   signal wrapBursts  : integer := 0;
   signal wrapLoads   : integer := 0;

begin

   clk2x  <= not clk2x after 7 ns when not done;
   clkvid <= not clkvid after 9.3 ns when not done;
   process (clk2x) begin if rising_edge(clk2x) then clk1x <= not clk1x; end if; end process;

   -- same clk2xIndex generation as psx_top
   process (clk1x) begin if rising_edge(clk1x) then clk1xToggle <= not clk1xToggle; end if; end process;
   process (clk2x)
   begin
      if rising_edge(clk2x) then
         clk1xToggle2x <= clk1xToggle;
         clk2xIndex    <= '0';
         if (clk1xToggle2x = clk1xToggle) then clk2xIndex <= '1'; end if;
      end if;
   end process;

   gref : block
   begin
--@REF@
   end block;

   gnew : block
   begin
--@NEW@
   end block;

   -- VRAM models (64-bit words, linear bursts), identical random wait states / latencies for both GPUs
   gmem : for i in 0 to 1 generate
      process (clk2x)
         type tram is array(0 to 131071) of std_logic_vector(63 downto 0);
         variable ram     : tram;
         variable inited  : boolean := false;
         variable s1      : positive := 17 + SEED;
         variable s2      : positive := 4242;
         variable r       : real;
         variable pend    : integer := 0;
         variable raddr   : integer := 0;
         variable lat     : integer := 0;
         variable a       : integer;
      begin
         if not inited then
            for k in ram'range loop ram(k) := (others => '0'); end loop;
            inited := true;
         end if;
         if rising_edge(clk2x) then
            m(i).ready <= '0';
            -- request acceptance with the current busy
            if (m(i).busy = '0') then
               if (o(i).vram_WE = '1') then
                  a := to_integer(unsigned(o(i).vram_ADDR(19 downto 3)));
                  for b in 0 to 7 loop
                     if (o(i).vram_BE(b) = '1') then ram(a)(b * 8 + 7 downto b * 8) := o(i).vram_DIN(b * 8 + 7 downto b * 8); end if;
                  end loop;
               end if;
               if (o(i).vram_RD = '1') then
                  assert pend = 0 report "read request while a burst is pending" severity warning;
                  pend  := to_integer(unsigned(o(i).vram_BURSTCNT));
                  raddr := to_integer(unsigned(o(i).vram_ADDR(19 downto 3)));
                  uniform(s1, s2, r);
                  lat   := 1 + integer(trunc(r * 8.0));
               end if;
            end if;
            -- read data return (random gaps)
            uniform(s1, s2, r);
            if (pend > 0) then
               if (lat > 0) then
                  lat := lat - 1;
               elsif (r < 0.8) then
                  m(i).ready <= '1';
                  m(i).dout  <= ram(raddr mod 131072);
                  raddr := raddr + 1;
                  pend  := pend - 1;
               end if;
            end if;
            -- wait states
            uniform(s1, s2, r);
            if (r < 0.2) then m(i).busy <= '1'; else m(i).busy <= '0'; end if;
         end if;
      end process;
   end generate;

   -- coverage: requests whose read wraps around x = 1024 (new GPU's pending wrap length > 0)
   gcov : if COUNT_WRAPS generate
      alias wrapPend is << signal .tb_gpu_vram.gnew.idut.wrapPend : std_logic >>;
      alias wrapCalc is << signal .tb_gpu_vram.gnew.idut.wrapCalc : unsigned(7 downto 0) >>;
   begin
      process (clk2x)
      begin
         if rising_edge(clk2x) then
            if (wrapPend = '1' and wrapCalc > 0) then wrapLoads <= wrapLoads + 1; end if;
         end if;
      end process;
   end generate;

   -- compare every clk2x cycle
   process (clk2x)
      variable l : line;
   begin
      if falling_edge(clk2x) and reset = '0' then
         if (o(0) /= o(1)) then
            if (mismatches < 10) then
               write(l, string'("MISMATCH at ") & time'image(now)
                     & string'(" rd ") & std_logic'image(o(0).vram_RD) & std_logic'image(o(1).vram_RD)
                     & string'(" we ") & std_logic'image(o(0).vram_WE) & std_logic'image(o(1).vram_WE)
                     & string'(" addr ") & to_hstring(o(0).vram_ADDR) & string'("/") & to_hstring(o(1).vram_ADDR)
                     & string'(" cnt ") & to_hstring(o(0).vram_BURSTCNT) & string'("/") & to_hstring(o(1).vram_BURSTCNT)
                     & string'(" bus ") & to_hstring(o(0).bus_dataRead) & string'("/") & to_hstring(o(1).bus_dataRead));
               writeline(output, l);
            end if;
            mismatches <= mismatches + 1;
         end if;
         if (o(1).vram_RD = '1' and m(1).busy = '0') then
            readAccepts <= readAccepts + 1;
            -- a wrapped continuation burst starts at x = 0 of the row right after a burst of the same request
            if (o(1).vram_ADDR(10 downto 0) = "00000000000") then wrapBursts <= wrapBursts + 1; end if;
         end if;
      end if;
   end process;

   stim : process
      variable s1 : positive := 5 + SEED;
      variable s2 : positive := 31337;
      variable r  : real;
      variable l  : line;
      variable x, y, w, h, x2, y2 : integer;
      variable words : integer;
      variable cmds  : integer := 0;
      variable k     : integer;
      variable v32   : std_logic_vector(31 downto 0);
      impure function rnd(n : integer) return integer is begin uniform(s1, s2, r); return integer(trunc(r * real(n))); end function;
      impure function rnd32 return std_logic_vector is
         variable v : std_logic_vector(31 downto 0);
      begin
         for b in 0 to 3 loop v(b * 8 + 7 downto b * 8) := std_logic_vector(to_unsigned(rnd(256), 8)); end loop;
         return v;
      end function;
      procedure tick(n : integer := 1) is begin for i in 1 to n loop wait until rising_edge(clk1x); end loop; end procedure;
      procedure busw(a : integer; d : std_logic_vector(31 downto 0)) is
      begin
         bus_addr <= to_unsigned(a, 4); bus_dataWrite <= d; bus_write <= '1';
         tick; bus_write <= '0';
         if rnd(3) = 0 then vram_pause <= '1'; else vram_pause <= '0'; end if;
         tick;
      end procedure;
      impure function stat return std_logic_vector is begin return o(0).bus_dataRead; end function;
      procedure readstat is
      begin
         bus_addr <= to_unsigned(4, 4); bus_read <= '1'; tick; bus_read <= '0'; tick;
      end procedure;
      procedure waitbit(b : integer) is
      begin
         for t in 0 to 200000 loop
            readstat;
            exit when stat(b) = '1';
            tick(rnd(4));
         end loop;
      end procedure;
      procedure gp0(d : std_logic_vector(31 downto 0)) is begin waitbit(28); busw(0, d); end procedure;
      function xy(x, y : integer) return std_logic_vector is
      begin
         return std_logic_vector(to_unsigned(y mod 512, 16)) & std_logic_vector(to_unsigned(x mod 1024, 16));
      end function;
   begin
      reset <= '1'; tick(20); reset <= '0'; tick(20);
      -- display on, 320x240, display area at (0,0), default ranges
      busw(4, x"03000000");
      busw(4, x"08000001");
      busw(4, x"05000000");
      -- drawing area full VRAM, no mask
      gp0(x"E3000000"); gp0(x"E4" & x"07FFFF"); gp0(x"E5000000"); gp0(x"E6000000");

      for c in 1 to NUM_CMDS loop
         waitbit(26);
         k := rnd(10);
         if k < 2 then
            -- fill rectangle
            x := rnd(64) * 16; y := rnd(512); w := 16 * (1 + rnd(16)); h := 1 + rnd(16);
            v32 := rnd32;
            gp0(x"02" & v32(23 downto 0)); gp0(xy(x, y)); gp0(xy(w, h));
         elsif k < 4 then
            -- CPU -> VRAM upload
            x := rnd(1024); y := rnd(512); w := 1 + rnd(32); h := 1 + rnd(8);
            gp0(x"A0000000"); gp0(xy(x, y)); gp0(xy(w, h));
            words := (w * h + 1) / 2;
            for i in 1 to words loop gp0(rnd32); end loop;
         elsif k < 8 then
            -- VRAM -> VRAM copy, often reading across x = 1024
            if rnd(2) = 0 then x := 1024 - 1 - rnd(64); else x := rnd(1024); end if;
            y := rnd(512); x2 := rnd(1024); y2 := rnd(512);
            if rnd(4) = 0 then w := 1 + rnd(1023); h := 1 + rnd(2); else w := 1 + rnd(96); h := 1 + rnd(8); end if;
            gp0(x"80000000"); gp0(xy(x, y)); gp0(xy(x2, y2)); gp0(xy(w, h));
         else
            -- VRAM -> CPU read, often across x = 1024
            if rnd(2) = 0 then x := 1024 - 1 - rnd(64); else x := rnd(1024); end if;
            y := rnd(512); w := 1 + rnd(64); h := 1 + rnd(4);
            if rnd(5) = 0 then w := 1 + rnd(1023); h := 1; end if;
            gp0(x"C0000000"); gp0(xy(x, y)); gp0(xy(w, h));
            words := (w * h + 1) / 2;
            waitbit(27);
            for i in 1 to words loop
               bus_addr <= to_unsigned(0, 4); bus_read <= '1'; tick; bus_read <= '0'; tick;
               while o(0).bus_stall = '1' loop tick; end loop;
            end loop;
         end if;
         cmds := cmds + 1;
         if (c mod 10 = 0) then
            write(l, string'("progress cmds=") & integer'image(c) & string'(" mismatch_cycles=") & integer'image(mismatches)
                  & string'(" read_bursts=") & integer'image(readAccepts) & string'(" bursts_at_x0=") & integer'image(wrapBursts) & string'(" wrapping_reads=") & integer'image(wrapLoads));
            writeline(output, l);
         end if;
      end loop;
      waitbit(26); tick(2000);
      write(l, string'("DONE cmds=") & integer'image(cmds) & string'(" mismatch_cycles=") & integer'image(mismatches)
            & string'(" read_bursts=") & integer'image(readAccepts) & string'(" bursts_at_x0=") & integer'image(wrapBursts) & string'(" wrapping_reads=") & integer'image(wrapLoads));
      writeline(output, l);
      if mismatches = 0 and readAccepts > 0 then write(l, string'("PASS")); else write(l, string'("FAIL")); end if;
      writeline(output, l);
      done <= true;
      std.env.finish;
   end process;

end architecture;
