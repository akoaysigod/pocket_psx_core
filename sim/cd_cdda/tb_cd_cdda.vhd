-- CD audio (CD-DA) playback test: rtl/cd_top.vhd ("new") against the upstream original (cd_top at cd17b5a, "ref"),
-- both driven by the same CPU model and each fed by its own sector supplier (same answers, same delays).
--  * disc: track 1 data (TRACK1 sectors), track 2 audio (TRACK2 sectors, 2 s pregap inside, as pocket_cd builds it);
--    trackinfo written like pocket/src/fpga/core/pocket_cd.vhd sends it
--  * sector supplier: like pocket_cd (req, ack, one cd_hps_write per 16-bit word every 2 clocks), delay per LBA
--  * audio sector samples: left = (LBA mod 64) << 10 | sample index (0..587), right = left xor 0x5A5A
--  * CPU model: GetStat, Init, SetMode (CD-DA + report), Demute, Play track 2, Setloc + Play, GetlocP, Stop;
--    services interrupts by polling the flag register (reads the response bytes, acknowledges)
-- Checks: every output of the two instances on every clock (lockstep), and on the new one that the CD audio
-- output is the sector samples in order (each sample the one after the previous one, left/right paired); about
-- 24,900 samples play in the two Play phases (the rest is seek time), PASS needs more than 20,000.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cd_supplier is
   generic ( TRACK2_START : integer );   -- first LBA of the audio track (its pregap)
   port
   (
      clk1x : in  std_logic;
      req   : in  std_logic;
      lba   : in  std_logic_vector(31 downto 0);
      ack   : out std_logic := '0';
      wr    : out std_logic := '0';
      data  : out std_logic_vector(15 downto 0) := (others => '0')
   );
end entity;

architecture sim of cd_supplier is
begin
   process
      variable l     : integer;
      variable s     : std_logic_vector(15 downto 0);
      variable delay : integer;
   begin
      wait until rising_edge(clk1x);
      if (req = '1') then
         l     := to_integer(unsigned(lba(19 downto 0)));
         delay := 2000 + (l * 7919) mod 20000;   -- 60 .. 650 us, as APF reads take
         for i in 1 to delay loop wait until rising_edge(clk1x); end loop;
         ack <= '1';
         for i in 1 to 3 loop wait until rising_edge(clk1x); end loop;
         for w in 0 to 1175 loop
            if (l >= TRACK2_START) then
               s := std_logic_vector(to_unsigned(l mod 64, 6)) & std_logic_vector(to_unsigned(w / 2, 10));
               if (w mod 2 = 1) then s := s xor x"5A5A"; end if;
            else
               s := (others => '0');   -- data sectors: not read in this test
            end if;
            wr   <= '1';
            data <= s;
            wait until rising_edge(clk1x);
            wr   <= '0';
            wait until rising_edge(clk1x);
         end loop;
         for i in 1 to 3 loop wait until rising_edge(clk1x); end loop;
         ack <= '0';
         wait until rising_edge(clk1x);
      end if;
   end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_cd_cdda is
   generic
   (
      TRACK1 : integer := 3000;   -- sectors of the data track
      TRACK2 : integer := 2000    -- sectors of the audio track (incl. 150 pregap)
   );
end entity;

architecture sim of tb_cd_cdda is

   constant T2START : integer := 150 + TRACK1;
   constant TOTAL   : integer := T2START + TRACK2;

   signal clk1x     : std_logic := '0';
   signal reset     : std_logic := '1';
   signal ss_reset  : std_logic := '0';
   signal spu_tick  : std_logic := '0';
   signal tickcnt   : integer range 0 to 767 := 0;
   signal finish    : boolean := false;   -- CPU model done: the checker reports and stops the clock
   signal done      : boolean := false;

   signal bus_addr      : unsigned(3 downto 0) := (others => '0');
   signal bus_dataWrite : std_logic_vector(7 downto 0) := (others => '0');
   signal bus_read      : std_logic := '0';
   signal bus_write     : std_logic := '0';

   signal ti_data  : std_logic_vector(31 downto 0) := (others => '0');
   signal ti_addr  : std_logic_vector(8 downto 0) := (others => '0');
   signal ti_write : std_logic := '0';

   -- per instance outputs (0 = ref, 1 = new)
   type tslv32 is array (0 to 1) of std_logic_vector(31 downto 0);
   type tslv16 is array (0 to 1) of std_logic_vector(15 downto 0);
   type tslv8  is array (0 to 1) of std_logic_vector(7 downto 0);
   type tsig16 is array (0 to 1) of signed(15 downto 0);
   type tuns20 is array (0 to 1) of unsigned(19 downto 0);
   type tslv2  is array (0 to 1) of std_logic_vector(1 downto 0);
   type tsl    is array (0 to 1) of std_logic;
   signal o_region : tslv2;
   signal o_pauseCD, o_pauseIdle, o_fullyIdle, o_cdSlow, o_error, o_irq, o_hpsreq, o_resetFromCD, o_ssidle : tsl;
   signal o_lbadisp : tuns20;
   signal o_left, o_right : tsig16;
   signal o_busread, o_dmaread : tslv8;
   signal o_hpslba : tslv32;
   signal hps_ack, hps_wr : tsl;
   signal hps_data : tslv16;

   signal mismatches : integer := 0;

   -- CPU model results
   signal int_count : integer := 0;

begin

   clk1x <= not clk1x after 14763 ps when not done;   -- 33.8688 MHz

   -- 44.1 kHz SPU tick
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         spu_tick <= '0';
         if (tickcnt = 767) then
            tickcnt  <= 0;
            spu_tick <= '1';
         else
            tickcnt <= tickcnt + 1;
         end if;
      end if;
   end process;

   ginst : for i in 0 to 1 generate
   begin
      gref : if i = 0 generate
         icd : entity work.cd_top_ref
         port map
         (
            clk1x => clk1x, ce => '1', reset => reset,
            INSTANTSEEK => '0', FORCECDSPEED => "000", LIMITREADSPEED => '0', hasCD => '1', LIDopen => '0',
            fastCD => '0', testSeek => '0', pauseOnCDSlow => '0', region => "00", region_out => o_region(i),
            pauseCD => o_pauseCD(i), Pause_idle_cd => o_pauseIdle(i), fullyIdle => o_fullyIdle(i), cdSlow => o_cdSlow(i),
            error => o_error(i), LBAdisplay => o_lbadisp(i), irqOut => o_irq(i),
            spu_tick => spu_tick, cd_left => o_left(i), cd_right => o_right(i), mdec_idle => '1',
            bus_addr => bus_addr, bus_dataWrite => bus_dataWrite, bus_read => bus_read, bus_write => bus_write,
            bus_dataRead => o_busread(i), dma_read => '0', dma_readdata => o_dmaread(i),
            cd_hps_req => o_hpsreq(i), cd_hps_lba => o_hpslba(i), cd_hps_lba_sim => open,
            cd_hps_ack => hps_ack(i), cd_hps_write => hps_wr(i), cd_hps_data => hps_data(i),
            trackinfo_data => ti_data, trackinfo_addr => ti_addr, trackinfo_write => ti_write,
            resetFromCD => o_resetFromCD(i),
            SS_reset => ss_reset, SS_DataWrite => (others => '0'), SS_Adr => (others => '0'), SS_wren => '0',
            SS_rden => '0', SS_DataRead => open, SS_idle => o_ssidle(i)
         );
      end generate;
      gnew : if i = 1 generate
         icd : entity work.cd_top_new
         port map
         (
            clk1x => clk1x, ce => '1', reset => reset,
            INSTANTSEEK => '0', FORCECDSPEED => "000", LIMITREADSPEED => '0', hasCD => '1', LIDopen => '0',
            fastCD => '0', testSeek => '0', pauseOnCDSlow => '0', region => "00", region_out => o_region(i),
            pauseCD => o_pauseCD(i), Pause_idle_cd => o_pauseIdle(i), fullyIdle => o_fullyIdle(i), cdSlow => o_cdSlow(i),
            error => o_error(i), LBAdisplay => o_lbadisp(i), irqOut => o_irq(i),
            spu_tick => spu_tick, cd_left => o_left(i), cd_right => o_right(i), mdec_idle => '1',
            bus_addr => bus_addr, bus_dataWrite => bus_dataWrite, bus_read => bus_read, bus_write => bus_write,
            bus_dataRead => o_busread(i), dma_read => '0', dma_readdata => o_dmaread(i),
            cd_hps_req => o_hpsreq(i), cd_hps_lba => o_hpslba(i), cd_hps_lba_sim => open,
            cd_hps_ack => hps_ack(i), cd_hps_write => hps_wr(i), cd_hps_data => hps_data(i),
            trackinfo_data => ti_data, trackinfo_addr => ti_addr, trackinfo_write => ti_write,
            resetFromCD => o_resetFromCD(i),
            SS_reset => ss_reset, SS_DataWrite => (others => '0'), SS_Adr => (others => '0'), SS_wren => '0',
            SS_rden => '0', SS_DataRead => open, SS_idle => o_ssidle(i)
         );
      end generate;
      isup : entity work.cd_supplier
      generic map (TRACK2_START => T2START)
      port map (clk1x => clk1x, req => o_hpsreq(i), lba => o_hpslba(i), ack => hps_ack(i), wr => hps_wr(i), data => hps_data(i));
   end generate;

   -- lockstep: every output on every clock
   process (clk1x)
      procedure diff(name : string; a, b : std_logic_vector) is
      begin
         if (a /= b and reset = '0') then
            if (mismatches < 20) then
               report "lockstep: " & name & " ref " & to_hstring(a) & " new " & to_hstring(b) severity warning;
            end if;
            mismatches <= mismatches + 1;
         end if;
      end procedure;
   begin
      if rising_edge(clk1x) then
         diff("cd_left", std_logic_vector(o_left(0)), std_logic_vector(o_left(1)));
         diff("cd_right", std_logic_vector(o_right(0)), std_logic_vector(o_right(1)));
         diff("irqOut", (0 => o_irq(0)), (0 => o_irq(1)));
         diff("bus_dataRead", o_busread(0), o_busread(1));
         diff("dma_readdata", o_dmaread(0), o_dmaread(1));
         diff("cd_hps_req", (0 => o_hpsreq(0)), (0 => o_hpsreq(1)));
         diff("cd_hps_lba", o_hpslba(0), o_hpslba(1));
         diff("LBAdisplay", std_logic_vector(o_lbadisp(0)), std_logic_vector(o_lbadisp(1)));
         diff("pauseCD/idle/fullyIdle/cdSlow/error/resetFromCD",
              o_pauseCD(0) & o_pauseIdle(0) & o_fullyIdle(0) & o_cdSlow(0) & o_error(0) & o_resetFromCD(0),
              o_pauseCD(1) & o_pauseIdle(1) & o_fullyIdle(1) & o_cdSlow(1) & o_error(1) & o_resetFromCD(1));
         diff("region_out", o_region(0), o_region(1));
      end if;
   end process;

   -- CPU model and checks
   process
      variable rd      : std_logic_vector(7 downto 0);
      variable flags   : integer;
      variable resp    : integer;
      variable cmd_int : integer;   -- last INT number seen by service
      variable ints    : integer := 0;
      variable reports : integer := 0;

      procedure clk(n : integer := 1) is
      begin
         for i in 1 to n loop wait until rising_edge(clk1x); end loop;
      end procedure;

      procedure wr(a : integer; d : integer) is
      begin
         bus_addr      <= to_unsigned(a, 4);
         bus_dataWrite <= std_logic_vector(to_unsigned(d, 8));
         bus_write     <= '1';
         clk;
         bus_write     <= '0';
         clk(3);
      end procedure;

      procedure rdb(a : integer; d : out std_logic_vector(7 downto 0)) is
      begin
         bus_addr <= to_unsigned(a, 4);
         bus_read <= '1';
         clk;
         bus_read <= '0';
         clk(2);
         d := o_busread(0);
         clk(1);
      end procedure;

      -- one pending interrupt: read and print the response, acknowledge; cmd_int = INT number (0 = none)
      procedure service(quiet : boolean) is
         variable s    : std_logic_vector(7 downto 0);
         variable line : string(1 to 64);
         variable n    : integer;
      begin
         wr(0, 1);
         rdb(3, rd);
         flags := to_integer(unsigned(rd(2 downto 0)));
         cmd_int := flags;
         if (flags /= 0) then
            n := 0;
            for i in 1 to 16 loop
               rdb(0, s);
               exit when s(5) = '0';
               rdb(1, s);
               if (n < 16) then
                  line(n * 3 + 1 to n * 3 + 3) := to_hstring(s) & " ";
                  n := n + 1;
               end if;
            end loop;
            if (flags = 1 and n = 8) then reports := reports + 1; end if;
            if (not quiet or flags /= 1) then
               report "  INT" & integer'image(flags) & ": " & line(1 to n * 3);
            end if;
            wr(3, 16#1F#);   -- index 1: acknowledge all
            ints := ints + 1;
         end if;
         wr(0, 0);
      end procedure;

      -- run n clocks, servicing interrupts (polled every 1000 clocks)
      procedure run(n : integer; quiet : boolean := true) is
         variable t : integer := 0;
      begin
         while (t < n) loop
            clk(1000);
            t := t + 1000;
            service(quiet);
         end loop;
      end procedure;

      procedure command(name : string; c : integer; p0 : integer := -1; p1 : integer := -1; p2 : integer := -1) is
         variable t : integer := 0;
      begin
         report "command " & name;
         wr(0, 0);
         if (p0 >= 0) then wr(2, p0); end if;
         if (p1 >= 0) then wr(2, p1); end if;
         if (p2 >= 0) then wr(2, p2); end if;
         wr(1, c);
         loop   -- wait for the INT3 / INT5 answer
            clk(200);
            service(true);
            exit when cmd_int = 3 or cmd_int = 5;
            t := t + 1;
            assert t < 20000 report "no answer to " & name severity failure;
         end loop;
      end procedure;

      function ms(m : real) return integer is
      begin
         return integer(m * 33868.8);
      end function;

      function bcd(n : integer) return integer is
      begin
         return (n / 10) * 16 + n mod 10;
      end function;

      procedure ti(a : integer; d : std_logic_vector(31 downto 0)) is
      begin
         ti_addr  <= std_logic_vector(to_unsigned(a, 9));
         ti_data  <= d;
         ti_write <= '1';
         clk;
         ti_write <= '0';
         clk(3);
      end procedure;

      function msf_word(lba : integer; audio : std_logic) return std_logic_vector is
         variable s : integer := lba / 75;
      begin
         return x"000" & "000" & audio & std_logic_vector(to_unsigned(bcd(s / 60), 8)) & std_logic_vector(to_unsigned(bcd(s mod 60), 8));
      end function;

      variable p2m, p2s, p2f : integer;
   begin
      ss_reset <= '1';
      clk(10);
      ss_reset <= '0';
      clk(10);
      reset <= '0';
      clk(100);

      -- trackinfo as pocket_cd sends it
      ti(0, x"0000" & std_logic_vector(to_unsigned(bcd(2), 8)) & x"02");
      ti(1, std_logic_vector(to_unsigned(TOTAL, 32)));
      ti(2, msf_word(TOTAL, '0'));
      ti(3, x"00000000");
      ti(4, x"00000000");                                            -- track 1: start 0
      ti(5, std_logic_vector(to_unsigned(T2START - 1, 32)));         --          end
      ti(6, msf_word(150, '0'));
      ti(7, x"00000000");
      ti(8, std_logic_vector(to_unsigned(T2START, 32)));             -- track 2: start
      ti(9, std_logic_vector(to_unsigned(TOTAL - 1, 32)));           --          end
      ti(10, msf_word(T2START + 150, '1'));
      ti(11, x"00000000");

      wr(0, 1);
      wr(2, 16#1F#);   -- index 1: enable all interrupts
      wr(0, 0);

      run(ms(5.0), false);
      command("GetStat", 16#01#);
      run(ms(400.0), false);   -- motor spin up
      command("GetStat", 16#01#);
      command("Init", 16#0A#);
      run(ms(200.0), false);
      command("SetMode CD-DA + report", 16#0E#, 16#05#);
      command("Demute", 16#0C#);
      command("Play track 2", 16#03#, 16#02#);
      run(ms(700.0));
      report "reports so far: " & integer'image(reports);
      -- Setloc 20 s into track 2, Play without track
      p2s := (T2START + 150 + 20 * 75) / 75;
      p2f := (T2START + 150 + 20 * 75) mod 75;
      command("Setloc", 16#02#, bcd(p2s / 60), bcd(p2s mod 60), bcd(p2f));
      command("Play", 16#03#);
      run(ms(500.0));
      command("GetlocP", 16#11#);
      command("Stop", 16#08#);
      run(ms(300.0), false);
      report "interrupts " & integer'image(ints) & ", CD-DA reports " & integer'image(reports);
      int_count <= reports;
      clk(10);
      finish <= true;
      wait;
   end process;

   -- CD audio output of the new instance: consecutive samples of the sector data
   process
      variable l, r       : std_logic_vector(15 downto 0);
      variable has_prev   : boolean := false;
      variable pl, pj     : integer;
      variable cl, cj     : integer;
      variable good, jumps, bad, silent, repeats : integer := 0;
   begin
      wait until rising_edge(clk1x);
      if (finish) then
         report "audio samples in order " & integer'image(good) & ", jumps " & integer'image(jumps) &
                ", bad " & integer'image(bad) & ", silent " & integer'image(silent) &
                ", repeated (CD-DA fifo empty) " & integer'image(repeats);
         report "lockstep mismatches " & integer'image(mismatches);
         if (mismatches = 0 and bad = 0 and jumps <= 4 and good > 20000 and int_count > 0) then
            report "PASS";
         else
            report "FAIL" severity failure;
         end if;
         done <= true;
         wait;
      end if;
      if (spu_tick = '1') then
         l := std_logic_vector(o_left(1));
         r := std_logic_vector(o_right(1));
         if (l = x"0000" and r = x"0000") then
            silent   := silent + 1;
            has_prev := false;
         elsif (r /= (l xor x"5A5A") or to_integer(unsigned(l(9 downto 0))) > 587) then
            if (bad < 10) then report "bad sample " & to_hstring(l) & " " & to_hstring(r) severity warning; end if;
            bad := bad + 1;
            has_prev := false;
         else
            cl := to_integer(unsigned(l(15 downto 10)));
            cj := to_integer(unsigned(l(9 downto 0)));
            if (has_prev) then
               if ((cj = pj + 1 and cl = pl) or (cj = 0 and pj = 587 and cl = (pl + 1) mod 64) or (cj = pj and cl = pl)) then
                  if (cj = pj and cl = pl) then repeats := repeats + 1; else good := good + 1; end if;
               else
                  if (jumps < 10) then
                     report "jump from " & integer'image(pl) & ":" & integer'image(pj) & " to " &
                            integer'image(cl) & ":" & integer'image(cj);
                  end if;
                  jumps := jumps + 1;
               end if;
            end if;
            has_prev := true;
            pl := cl;
            pj := cj;
         end if;
      end if;
   end process;

end architecture;
