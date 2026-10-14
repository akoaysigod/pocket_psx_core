-- One gpu_poly or gpu_line instance with its dividers and a model of the GPU around it
-- (command FIFO, processing handshake, pixel pipeline stalls, VRAM line reads).
-- Every observable output event is emitted on ev_valid/ev_data in order, so two
-- harnesses can be compared as event streams independent of timing.
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use work.pGPU.all;
use work.pGpuDivTb.all;

entity gpu_div_harness is
   generic
   (
      MODULE   : integer := 0;   -- 0: gpu_poly, 1: gpu_line
      IS_NEW   : boolean := false;
      NDIV     : integer := 6;
      NUM_CMDS : integer := 100;
      SEED     : integer := 1;
      ENVSEED  : integer := 1
   );
   port
   (
      clk2x      : in  std_logic;
      reset      : in  std_logic;
      ev_valid   : out std_logic_vector(5 downto 0) := (others => '0');  -- one stream per event type
      ev_data    : out t_ev_array;
      cmds_done  : out integer := 0;
      finished   : out std_logic := '0'
   );
end entity;

architecture sim of gpu_div_harness is

   signal clk2xIndex        : std_logic := '0';
   signal proc_idle         : std_logic := '1';
   signal fifo_Valid        : std_logic := '0';
   signal fifo_data         : std_logic_vector(31 downto 0) := (others => '0');
   signal requestFifo       : std_logic;
   signal done              : std_logic;
   signal CmdDone           : std_logic;
   signal pipeline_busy     : std_logic := '0';
   signal pipeline_stall    : std_logic := '0';
   signal fifoOut_idle      : std_logic := '1';
   signal requestVRAMEnable : std_logic;
   signal requestVRAMXPos   : unsigned(9 downto 0);
   signal requestVRAMYPos   : unsigned(8 downto 0);
   signal requestVRAMSize   : unsigned(10 downto 0);
   signal requestVRAMIdle   : std_logic := '1';
   signal requestVRAMDone   : std_logic := '0';
   signal vramLineEna       : std_logic;
   signal vramLineAddr      : unsigned(9 downto 0);

   signal p_new, p_tex, p_transp, p_raw, p_dith, p_filter : std_logic := '0';
   signal p_x    : unsigned(9 downto 0);
   signal p_y    : unsigned(8 downto 0);
   signal p_cr, p_cg, p_cb, p_u, p_v, p_u11, p_v11, p_uAcc, p_vAcc : unsigned(7 downto 0) := (others => '0');
   signal drawModeRec : unsigned(11 downto 0);
   signal drawModeNew, textPalNew : std_logic := '0';
   signal textPalX : unsigned(9 downto 0);
   signal textPalY : unsigned(8 downto 0);

   type t_div_array is array(0 to 5) of div_type;
   signal divs : t_div_array;

   -- drawing environment (fixed per run)
   constant drawingOffsetX    : signed(10 downto 0)   := to_signed(SEED mod 7 - 3, 11);
   constant drawingOffsetY    : signed(10 downto 0)   := to_signed(SEED mod 5 - 2, 11);
   constant drawingAreaLeft   : unsigned(9 downto 0)  := to_unsigned(8, 10);
   constant drawingAreaRight  : unsigned(9 downto 0)  := to_unsigned(300, 10);
   constant drawingAreaTop    : unsigned(8 downto 0)  := to_unsigned(4, 9);
   constant drawingAreaBottom : unsigned(8 downto 0)  := to_unsigned(220, 9);

begin

   process (clk2x) begin
      if rising_edge(clk2x) then clk2xIndex <= not clk2xIndex; end if;
   end process;

   -- dividers: NDIV physical ones, the rest tied off
   gdiv : for i in 0 to 5 generate
      gyes : if i < NDIV generate
         idivider : entity work.divider
         port map (clk => clk2x, start => divs(i).start, done => divs(i).done, dividend => divs(i).dividend,
                   divisor => divs(i).divisor, quotient => divs(i).quotient, remainder => divs(i).remainder);
      end generate;
      gno : if i >= NDIV generate
         divs(i).done <= '0'; divs(i).quotient <= (others => '0'); divs(i).remainder <= (others => '0');
      end generate;
   end generate;

   gpoly : if MODULE = 0 generate
      gref : if not IS_NEW generate
         idut : entity work.gpu_poly_ref
         port map (clk2x => clk2x, clk2xIndex => clk2xIndex, ce => '1', reset => reset, REPRODUCIBLEGPUTIMING => '0',
            textureFilter => "00", textureFilterStrength => "00", textureFilter2DOff => '0', error => open,
            DrawPixelsMask => '0', interlacedDrawing => '0', activeLineLSB => '0',
            drawingOffsetX => drawingOffsetX, drawingOffsetY => drawingOffsetY, drawingAreaLeft => drawingAreaLeft,
            drawingAreaRight => drawingAreaRight, drawingAreaTop => drawingAreaTop, drawingAreaBottom => drawingAreaBottom,
            drawModeRec => drawModeRec, drawModeNew => drawModeNew, drawmode_dithering => '1',
            div1 => divs(0), div2 => divs(1), div3 => divs(2), div4 => divs(3), div5 => divs(4), div6 => divs(5),
            fifoOut_idle => fifoOut_idle, pipeline_busy => pipeline_busy, pipeline_stall => pipeline_stall,
            pipeline_new => p_new, pipeline_texture => p_tex, pipeline_transparent => p_transp,
            pipeline_rawTexture => p_raw, pipeline_dithering => p_dith, pipeline_x => p_x, pipeline_y => p_y,
            pipeline_cr => p_cr, pipeline_cg => p_cg, pipeline_cb => p_cb, pipeline_u => p_u, pipeline_v => p_v,
            pipeline_filter => p_filter, pipeline_u11 => p_u11, pipeline_v11 => p_v11, pipeline_uAcc => p_uAcc, pipeline_vAcc => p_vAcc,
            proc_idle => proc_idle, fifo_Valid => fifo_Valid, fifo_data => fifo_data, requestFifo => requestFifo,
            done => done, CmdDone => CmdDone, requestVRAMEnable => requestVRAMEnable, requestVRAMXPos => requestVRAMXPos,
            requestVRAMYPos => requestVRAMYPos, requestVRAMSize => requestVRAMSize, requestVRAMIdle => requestVRAMIdle,
            requestVRAMDone => requestVRAMDone, textPalNew => textPalNew, textPalX => textPalX, textPalY => textPalY,
            vramLineEna => vramLineEna, vramLineAddr => vramLineAddr);
      end generate;
      gnew : if IS_NEW generate
         idut : entity work.gpu_poly_new
         port map (clk2x => clk2x, clk2xIndex => clk2xIndex, ce => '1', reset => reset, REPRODUCIBLEGPUTIMING => '0',
            textureFilter => "00", textureFilterStrength => "00", textureFilter2DOff => '0', error => open,
            DrawPixelsMask => '0', interlacedDrawing => '0', activeLineLSB => '0',
            drawingOffsetX => drawingOffsetX, drawingOffsetY => drawingOffsetY, drawingAreaLeft => drawingAreaLeft,
            drawingAreaRight => drawingAreaRight, drawingAreaTop => drawingAreaTop, drawingAreaBottom => drawingAreaBottom,
            drawModeRec => drawModeRec, drawModeNew => drawModeNew, drawmode_dithering => '1',
            div1 => divs(0), div2 => divs(1), div3 => divs(2), div4 => divs(3), div5 => divs(4), div6 => divs(5),
            fifoOut_idle => fifoOut_idle, pipeline_busy => pipeline_busy, pipeline_stall => pipeline_stall,
            pipeline_new => p_new, pipeline_texture => p_tex, pipeline_transparent => p_transp,
            pipeline_rawTexture => p_raw, pipeline_dithering => p_dith, pipeline_x => p_x, pipeline_y => p_y,
            pipeline_cr => p_cr, pipeline_cg => p_cg, pipeline_cb => p_cb, pipeline_u => p_u, pipeline_v => p_v,
            pipeline_filter => p_filter, pipeline_u11 => p_u11, pipeline_v11 => p_v11, pipeline_uAcc => p_uAcc, pipeline_vAcc => p_vAcc,
            proc_idle => proc_idle, fifo_Valid => fifo_Valid, fifo_data => fifo_data, requestFifo => requestFifo,
            done => done, CmdDone => CmdDone, requestVRAMEnable => requestVRAMEnable, requestVRAMXPos => requestVRAMXPos,
            requestVRAMYPos => requestVRAMYPos, requestVRAMSize => requestVRAMSize, requestVRAMIdle => requestVRAMIdle,
            requestVRAMDone => requestVRAMDone, textPalNew => textPalNew, textPalX => textPalX, textPalY => textPalY,
            vramLineEna => vramLineEna, vramLineAddr => vramLineAddr);
      end generate;
   end generate;

   gline : if MODULE = 1 generate
      gref : if not IS_NEW generate
         idut : entity work.gpu_line_ref
         port map (clk2x => clk2x, clk2xIndex => clk2xIndex, ce => '1', reset => reset, REPRODUCIBLEGPUTIMING => '0',
            error => open, DrawPixelsMask => '0', interlacedDrawing => '0', activeLineLSB => '0',
            drawingOffsetX => drawingOffsetX, drawingOffsetY => drawingOffsetY, drawingAreaLeft => drawingAreaLeft,
            drawingAreaRight => drawingAreaRight, drawingAreaTop => drawingAreaTop, drawingAreaBottom => drawingAreaBottom,
            div1 => divs(0), div2 => divs(1), div3 => divs(2), div4 => divs(3), div5 => divs(4), div6 => divs(5),
            fifoOut_idle => fifoOut_idle, pipeline_busy => pipeline_busy, pipeline_stall => pipeline_stall,
            pipeline_new => p_new, pipeline_transparent => p_transp, pipeline_x => p_x, pipeline_y => p_y,
            pipeline_cr => p_cr, pipeline_cg => p_cg, pipeline_cb => p_cb,
            proc_idle => proc_idle, fifo_Valid => fifo_Valid, fifo_data => fifo_data, requestFifo => requestFifo,
            done => done, CmdDone => CmdDone, requestVRAMEnable => requestVRAMEnable, requestVRAMXPos => requestVRAMXPos,
            requestVRAMYPos => requestVRAMYPos, requestVRAMSize => requestVRAMSize, requestVRAMIdle => requestVRAMIdle,
            requestVRAMDone => requestVRAMDone, vramLineEna => vramLineEna, vramLineAddr => vramLineAddr);
      end generate;
      gnew : if IS_NEW generate
         idut : entity work.gpu_line_new
         port map (clk2x => clk2x, clk2xIndex => clk2xIndex, ce => '1', reset => reset, REPRODUCIBLEGPUTIMING => '0',
            error => open, DrawPixelsMask => '0', interlacedDrawing => '0', activeLineLSB => '0',
            drawingOffsetX => drawingOffsetX, drawingOffsetY => drawingOffsetY, drawingAreaLeft => drawingAreaLeft,
            drawingAreaRight => drawingAreaRight, drawingAreaTop => drawingAreaTop, drawingAreaBottom => drawingAreaBottom,
            div1 => divs(0), div2 => divs(1), div3 => divs(2), div4 => divs(3), div5 => divs(4), div6 => divs(5),
            fifoOut_idle => fifoOut_idle, pipeline_busy => pipeline_busy, pipeline_stall => pipeline_stall,
            pipeline_new => p_new, pipeline_transparent => p_transp, pipeline_x => p_x, pipeline_y => p_y,
            pipeline_cr => p_cr, pipeline_cg => p_cg, pipeline_cb => p_cb,
            proc_idle => proc_idle, fifo_Valid => fifo_Valid, fifo_data => fifo_data, requestFifo => requestFifo,
            done => done, CmdDone => CmdDone, requestVRAMEnable => requestVRAMEnable, requestVRAMXPos => requestVRAMXPos,
            requestVRAMYPos => requestVRAMYPos, requestVRAMSize => requestVRAMSize, requestVRAMIdle => requestVRAMIdle,
            requestVRAMDone => requestVRAMDone, vramLineEna => vramLineEna, vramLineAddr => vramLineAddr);
      end generate;
   end generate;

   -- output events: one ordered stream per event type (types can coincide in a cycle)
   events : process (clk2x)
      variable e : std_logic_vector(127 downto 0);
   begin
      if rising_edge(clk2x) then
         ev_valid <= (others => '0');
         if (p_new = '1') then
            e := (others => '0');
            e(9 downto 0) := std_logic_vector(p_x); e(18 downto 10) := std_logic_vector(p_y);
            e(26 downto 19) := std_logic_vector(p_cr); e(34 downto 27) := std_logic_vector(p_cg); e(42 downto 35) := std_logic_vector(p_cb);
            e(50 downto 43) := std_logic_vector(p_u); e(58 downto 51) := std_logic_vector(p_v);
            e(59) := p_tex; e(60) := p_transp; e(61) := p_raw; e(62) := p_dith; e(63) := p_filter;
            e(71 downto 64) := std_logic_vector(p_u11); e(79 downto 72) := std_logic_vector(p_v11);
            e(87 downto 80) := std_logic_vector(p_uAcc); e(95 downto 88) := std_logic_vector(p_vAcc);
            ev_valid(0) <= '1'; ev_data(0) <= e;
         end if;
         if (requestVRAMEnable = '1') then
            e := (others => '0');
            e(9 downto 0) := std_logic_vector(requestVRAMXPos); e(18 downto 10) := std_logic_vector(requestVRAMYPos);
            e(29 downto 19) := std_logic_vector(requestVRAMSize);
            ev_valid(1) <= '1'; ev_data(1) <= e;
         end if;
         if (vramLineEna = '1') then
            e := (others => '0'); e(9 downto 0) := std_logic_vector(vramLineAddr);
            ev_valid(2) <= '1'; ev_data(2) <= e;
         end if;
         if (MODULE = 0 and textPalNew = '1') then
            e := (others => '0'); e(9 downto 0) := std_logic_vector(textPalX); e(18 downto 10) := std_logic_vector(textPalY);
            ev_valid(3) <= '1'; ev_data(3) <= e;
         end if;
         if (MODULE = 0 and drawModeNew = '1') then
            e := (others => '0'); e(11 downto 0) := std_logic_vector(drawModeRec);
            ev_valid(4) <= '1'; ev_data(4) <= e;
         end if;
         if (done = '1') then
            ev_valid(5) <= '1'; ev_data(5) <= (others => '0');
         end if;
      end if;
   end process;

   -- GPU environment
   env : process
      variable cs1 : positive := SEED;       -- command stream (identical for both harnesses)
      variable cs2 : positive := 424242;
      variable es1 : positive := ENVSEED;    -- stalls/delays (differs between harnesses)
      variable es2 : positive := 99991;
      variable r   : real;
      type t_words is array(0 to 63) of std_logic_vector(31 downto 0);
      variable words : t_words;
      variable nw, k : integer;
      variable cmd   : std_logic_vector(7 downto 0);
      variable nv    : integer;
      variable big   : boolean;
      variable tmpw  : std_logic_vector(31 downto 0);

      impure function crnd(n : integer) return integer is
      begin
         uniform(cs1, cs2, r); return integer(trunc(r * real(n)));
      end function;
      impure function ernd(n : integer) return integer is
      begin
         uniform(es1, es2, r); return integer(trunc(r * real(n)));
      end function;
      impure function pos return std_logic_vector is
         variable x, y : integer;
      begin
         -- large polygons stay at non-negative coordinates: the original gpu_poly converts the
         -- (then negative) span start with to_integer into a natural compare, which stops nvc
         if (big) then x := crnd(1000); y := crnd(500);
         else          x := 20 + crnd(140);    y := 10 + crnd(120); end if;
         return "00000" & std_logic_vector(to_signed(y, 11)) & "00000" & std_logic_vector(to_signed(x, 11));
      end function;
      impure function col return std_logic_vector is
      begin
         return x"00" & std_logic_vector(to_unsigned(crnd(256), 8)) & std_logic_vector(to_unsigned(crnd(256), 8)) & std_logic_vector(to_unsigned(crnd(256), 8));
      end function;
      impure function tex return std_logic_vector is
      begin
         return std_logic_vector(to_unsigned(crnd(65536), 16)) & std_logic_vector(to_unsigned(crnd(256), 8)) & std_logic_vector(to_unsigned(crnd(256), 8));
      end function;

      procedure tick is
      begin
         wait until rising_edge(clk2x);
         fifo_Valid <= '0';
         -- random pipeline back-pressure
         if (ernd(4) = 0) then pipeline_stall <= '1'; else pipeline_stall <= '0'; end if;
         if (ernd(5) = 0) then pipeline_busy  <= '1'; else pipeline_busy  <= '0'; end if;
         if (ernd(8) = 0) then fifoOut_idle   <= '0'; else fifoOut_idle   <= '1'; end if;
      end procedure;

   begin
      wait until reset = '0';
      for i in 0 to 5 loop tick; end loop;

      for c in 0 to NUM_CMDS - 1 loop
         -- build one command
         nw := 0;
         big := (crnd(10) = 0);
         if (MODULE = 0) then
            cmd := "001" & std_logic_vector(to_unsigned(crnd(32), 5));
            tmpw := col; words(0) := cmd & tmpw(23 downto 0); nw := 1;
            if (cmd(3) = '1') then nv := 4; else nv := 3; end if;
            for v in 0 to nv - 1 loop
               if (v > 0 and cmd(4) = '1') then words(nw) := col; nw := nw + 1; end if;
               words(nw) := pos; nw := nw + 1;
               if (cmd(2) = '1') then words(nw) := tex; nw := nw + 1; end if;
            end loop;
         else
            cmd := "010" & std_logic_vector(to_unsigned(crnd(32), 5));
            tmpw := col; words(0) := cmd & tmpw(23 downto 0); nw := 1;
            words(nw) := pos; nw := nw + 1;
            if (cmd(3) = '0') then
               if (cmd(4) = '1') then words(nw) := col; nw := nw + 1; end if;
               words(nw) := pos; nw := nw + 1;
            else
               -- polyline: 1..5 more vertices, then the terminator
               for v in 1 to 1 + crnd(5) loop
                  if (cmd(4) = '1') then words(nw) := col; nw := nw + 1; end if;
                  words(nw) := pos; nw := nw + 1;
               end loop;
               words(nw) := x"55555555"; nw := nw + 1;
            end if;
         end if;

         -- hand over the command word while idle
         loop
            exit when proc_idle = '1' and pipeline_busy = '0';
            tick;
         end loop;
         fifo_data  <= words(0);
         fifo_Valid <= '1';
         tick;
         proc_idle <= '0';
         k := 1;
         -- feed the remaining words on request, until the module reports done
         loop
            if (k < nw and requestFifo = '1' and fifo_Valid = '0' and pipeline_busy = '0' and ernd(3) /= 0) then
               fifo_data  <= words(k);
               fifo_Valid <= '1';
               k := k + 1;
               wait until rising_edge(clk2x);
               fifo_Valid <= '0';
            else
               tick;
            end if;
            exit when done = '1';
         end loop;
         proc_idle <= '1';
         cmds_done <= c + 1;
         tick;
      end loop;
      for i in 0 to 100 loop tick; end loop;
      finished <= '1';
      wait;
   end process;

   -- VRAM line read model
   vram : process (clk2x)
      variable s1 : positive := ENVSEED + 7;
      variable s2 : positive := 31337;
      variable r  : real;
      variable cnt : integer := -1;
   begin
      if rising_edge(clk2x) then
         requestVRAMDone <= '0';
         if (requestVRAMEnable = '1') then
            requestVRAMIdle <= '0';
            uniform(s1, s2, r);
            cnt := 2 + integer(trunc(r * 8.0));
         elsif (cnt > 0) then
            cnt := cnt - 1;
         elsif (cnt = 0) then
            requestVRAMDone <= '1';
            requestVRAMIdle <= '1';
            cnt := -1;
         end if;
      end if;
   end process;

end architecture;
