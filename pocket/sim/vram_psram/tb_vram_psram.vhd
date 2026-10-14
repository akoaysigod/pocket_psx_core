-- vram_psram + two PSRAM models with board delays (FPGA outputs reach the PSRAM T_OUT later, PSRAM outputs reach
-- the FPGA's input registers T_IN later): random single-word writes with random byte enables and random read
-- bursts (1-128 words), issued like the PSX core does (hold the request while busy), plus random aux (memory card)
-- reads and writes to a region of their own. Read data is checked against reference memories; the PSRAM models
-- check the access timing (see psram_model.vhd).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_vram_psram is
   generic
   (
      NUM_REQ   : integer := 5000;
      SEED      : integer := 1;
      T_OUT     : time := 4 ns;
      T_IN      : time := 3 ns;
      ROW_WORDS : integer := 128;
      AUX       : boolean := true;
      SEQ_PCT   : integer := 60      -- % chance that a write continues a run (next word, issued at once)
   );
end entity;

architecture sim of tb_vram_psram is
   signal clk : std_logic := '0';
   signal reset : std_logic := '1';
   signal done : boolean := false;
   signal busy, rdy, rd, we : std_logic := '0';
   signal burst : std_logic_vector(7 downto 0) := x"01";
   signal addr  : std_logic_vector(24 downto 0) := (others => '0');
   signal dout, din : std_logic_vector(63 downto 0) := (others => '0');
   signal be : std_logic_vector(7 downto 0) := (others => '0');
   signal aux_req, aux_we, aux_done : std_logic := '0';
   signal aux_addr : std_logic_vector(20 downto 0) := (others => '0');
   signal aux_din, aux_dout : std_logic_vector(31 downto 0) := (others => '0');
   signal aux_ops, aux_errors : integer := 0;
   type tcram is record
      a : std_logic_vector(21 downto 16); dq_out, dq_in : std_logic_vector(15 downto 0); dq_oe : std_logic;
      clk, adv_n, cre, ce0_n, ce1_n, oe_n, we_n, ub_n, lb_n : std_logic;
   end record;
   signal c0, c1 : tcram;   -- FPGA side
   signal m0, m1 : tcram;   -- PSRAM side (delayed)
   signal f0, f1 : std_logic_vector(15 downto 0);   -- FPGA data drivers
   signal dq0, dq1 : std_logic_vector(15 downto 0); -- PSRAM side data buses
begin
   clk <= not clk after 7.3815 ns when not done;   -- 67.7376 MHz

   idut : entity work.vram_psram
   port map (clk => clk, reset => reset, ddr_busy => busy, ddr_burstcnt => burst, ddr_addr => addr, ddr_dout => dout,
             ddr_dout_ready => rdy, ddr_rd => rd, ddr_din => din, ddr_be => be, ddr_we => we,
             aux_req => aux_req, aux_we => aux_we, aux_addr => aux_addr, aux_din => aux_din, aux_dout => aux_dout,
             aux_done => aux_done,
             cram0_a => c0.a, cram0_dq_out => c0.dq_out, cram0_dq_oe => c0.dq_oe, cram0_dq_in => c0.dq_in, cram0_clk => c0.clk,
             cram0_adv_n => c0.adv_n, cram0_cre => c0.cre, cram0_ce0_n => c0.ce0_n, cram0_ce1_n => c0.ce1_n, cram0_oe_n => c0.oe_n,
             cram0_we_n => c0.we_n, cram0_ub_n => c0.ub_n, cram0_lb_n => c0.lb_n,
             cram1_a => c1.a, cram1_dq_out => c1.dq_out, cram1_dq_oe => c1.dq_oe, cram1_dq_in => c1.dq_in, cram1_clk => c1.clk,
             cram1_adv_n => c1.adv_n, cram1_cre => c1.cre, cram1_ce0_n => c1.ce0_n, cram1_ce1_n => c1.ce1_n, cram1_oe_n => c1.oe_n,
             cram1_we_n => c1.we_n, cram1_ub_n => c1.ub_n, cram1_lb_n => c1.lb_n);

   -- board: FPGA outputs -> PSRAM after T_OUT, PSRAM data -> FPGA inputs after T_IN
   m0.a <= transport c0.a after T_OUT;   m0.clk <= transport c0.clk after T_OUT;   m0.adv_n <= transport c0.adv_n after T_OUT;
   m0.cre <= transport c0.cre after T_OUT;   m0.ce0_n <= transport c0.ce0_n after T_OUT;   m0.ce1_n <= transport c0.ce1_n after T_OUT;
   m0.oe_n <= transport c0.oe_n after T_OUT;   m0.we_n <= transport c0.we_n after T_OUT;   m0.ub_n <= transport c0.ub_n after T_OUT;
   m0.lb_n <= transport c0.lb_n after T_OUT;
   m1.a <= transport c1.a after T_OUT;   m1.clk <= transport c1.clk after T_OUT;   m1.adv_n <= transport c1.adv_n after T_OUT;
   m1.cre <= transport c1.cre after T_OUT;   m1.ce0_n <= transport c1.ce0_n after T_OUT;   m1.ce1_n <= transport c1.ce1_n after T_OUT;
   m1.oe_n <= transport c1.oe_n after T_OUT;   m1.we_n <= transport c1.we_n after T_OUT;   m1.ub_n <= transport c1.ub_n after T_OUT;
   m1.lb_n <= transport c1.lb_n after T_OUT;
   f0 <= c0.dq_out when c0.dq_oe = '1' else (others => 'Z');
   f1 <= c1.dq_out when c1.dq_oe = '1' else (others => 'Z');
   dq0 <= transport f0 after T_OUT;
   dq1 <= transport f1 after T_OUT;
   c0.dq_in <= transport dq0 after T_IN;
   c1.dq_in <= transport dq1 after T_IN;

   im0 : entity work.psram_model generic map (ROW_WORDS => ROW_WORDS)
   port map (a => m0.a, dq => dq0, clk => m0.clk, cre => m0.cre, adv_n => m0.adv_n, ce0_n => m0.ce0_n, ce1_n => m0.ce1_n,
             oe_n => m0.oe_n, we_n => m0.we_n, ub_n => m0.ub_n, lb_n => m0.lb_n);
   im1 : entity work.psram_model generic map (ROW_WORDS => ROW_WORDS)
   port map (a => m1.a, dq => dq1, clk => m1.clk, cre => m1.cre, adv_n => m1.adv_n, ce0_n => m1.ce0_n, ce1_n => m1.ce1_n,
             oe_n => m1.oe_n, we_n => m1.we_n, ub_n => m1.ub_n, lb_n => m1.lb_n);

   -- aux (memory card) traffic in PSRAM words 0x80000-0x80FFF (region 2, never used by the core requests)
   gaux : if AUX generate
      process
         type tref is array(0 to 4095) of std_logic_vector(31 downto 0);
         variable ref : tref := (others => (others => '0'));
         variable s1 : positive := 77 + SEED;
         variable s2 : positive := 1234;
         variable r : real;
         variable a : integer;
         variable w : std_logic_vector(31 downto 0);
         impure function rnd(k : integer) return integer is begin uniform(s1, s2, r); return integer(trunc(r * real(k))); end function;
      begin
         wait until reset = '0';
         while not done loop
            for i in 1 to rnd(400) loop wait until rising_edge(clk); end loop;
            a := rnd(4096);
            aux_addr <= std_logic_vector(to_unsigned(16#80000# + a, 21));
            if rnd(2) = 0 then
               w := std_logic_vector(to_unsigned(rnd(65536), 16)) & std_logic_vector(to_unsigned(rnd(65536), 16));
               aux_din <= w; aux_we <= '1'; aux_req <= '1';
               loop wait until rising_edge(clk); exit when aux_done = '1' or done; end loop;
               ref(a) := w;
            else
               aux_we <= '0'; aux_req <= '1';
               loop wait until rising_edge(clk); exit when aux_done = '1' or done; end loop;
               if (aux_done = '1' and aux_dout /= ref(a)) then
                  aux_errors <= aux_errors + 1;
                  report "aux read mismatch " & integer'image(a) & " got " & to_hstring(aux_dout) & " exp " & to_hstring(ref(a)) severity warning;
               end if;
            end if;
            aux_req <= '0';
            aux_ops <= aux_ops + 1;
         end loop;
         wait;
      end process;
   end generate;

   process
      type tref is array(0 to 2 ** 20 - 1) of std_logic_vector(63 downto 0);
      variable ref : tref;
      variable s1 : positive := 3 + SEED;
      variable s2 : positive := 2718;
      variable r : real;
      variable a, n, got : integer;
      variable w : std_logic_vector(63 downto 0);
      variable b : std_logic_vector(7 downto 0);
      variable errors, writes, reads, words : integer := 0;
      variable t0 : time;
      variable tRead, tWrite : time := 0 ns;
      variable ts : time;
      variable lastW : integer := -10;
      variable forceW, seqW : boolean;
      impure function rnd(k : integer) return integer is begin uniform(s1, s2, r); return integer(trunc(r * real(k))); end function;
      impure function rnd64 return std_logic_vector is
         variable v : std_logic_vector(63 downto 0);
      begin
         for i in 0 to 7 loop v(i * 8 + 7 downto i * 8) := std_logic_vector(to_unsigned(rnd(256), 8)); end loop; return v;
      end function;
      impure function raddr return integer is
      begin
         -- mostly a small window (read-after-write hits), sometimes VRAM top / memory card region
         case rnd(4) is
            when 0      => return 131072 - 1 - rnd(256);               -- end of VRAM region
            when 1      => return 131072 + rnd(16384);                 -- memory card region
            when others => return rnd(4096);
         end case;
      end function;
   begin
      for i in ref'range loop ref(i) := (others => '0'); end loop;
      wait until rising_edge(clk); wait until rising_edge(clk);
      reset <= '0';
      -- wait for the configuration after reset
      loop wait until rising_edge(clk); exit when busy = '0'; end loop;
      t0 := now;
      for q in 1 to NUM_REQ loop
         seqW := lastW >= 0 and lastW + 1 < 2 ** 20 and rnd(100) < SEQ_PCT;
         if seqW then a := lastW + 1; else a := raddr; end if;
         addr <= std_logic_vector(to_unsigned(a, 25));
         ts := now;
         if seqW or rnd(2) = 0 then
            w := rnd64;
            case rnd(4) is
               when 0 => b := x"FF";
               when 1 => b := std_logic_vector(to_unsigned(rnd(256), 8));
               when 2 => b := x"0F";
               when others => b := x"F0";
            end case;
            din <= w; be <= b; we <= '1'; burst <= x"01";
            loop wait until rising_edge(clk); exit when busy = '0'; end loop;   -- taken at this edge
            we <= '0';
            for k in 0 to 7 loop
               if b(k) = '1' then ref(a)(k * 8 + 7 downto k * 8) := w(k * 8 + 7 downto k * 8); end if;
            end loop;
            writes := writes + 1;
            tWrite := tWrite + (now - ts);
            lastW := a;
         else
            if rnd(4) = 0 then n := 1 + rnd(128); else n := 1 + rnd(8); end if;
            if a + n > 2 ** 20 then n := 1; end if;
            burst <= std_logic_vector(to_unsigned(n mod 256, 8)); rd <= '1';
            loop wait until rising_edge(clk); exit when busy = '0'; end loop;
            rd <= '0';
            got := 0;
            while got < n loop
               wait until rising_edge(clk);
               if rdy = '1' then
                  if dout /= ref(a + got) then
                     errors := errors + 1;
                     if errors <= 10 then report "read mismatch word " & integer'image(a + got) & " got " & to_hstring(dout) & " exp " & to_hstring(ref(a + got)) severity warning; end if;
                  end if;
                  got := got + 1; words := words + 1;
               end if;
            end loop;
            reads := reads + 1;
            tRead := tRead + (now - ts);
            lastW := -10;
         end if;
         if not seqW and rnd(3) = 0 then wait until rising_edge(clk); end if;
      end loop;
      -- let a pending aux access finish
      for i in 1 to 200 loop wait until rising_edge(clk); end loop;
      report "DONE requests=" & integer'image(NUM_REQ) & " writes=" & integer'image(writes) & " read_bursts=" & integer'image(reads)
             & " words_read=" & integer'image(words) & " errors=" & integer'image(errors)
             & " aux_ops=" & integer'image(aux_ops) & " aux_errors=" & integer'image(aux_errors)
             & " ns_per_write=" & integer'image(integer(real(tWrite / 1 ns) / real(writes)))
             & " ns_per_read_word=" & integer'image(integer(real(tRead / 1 ns) / real(words)));
      if errors = 0 and aux_errors = 0 and (aux_ops > 0 or not AUX) then report "PASS"; else report "FAIL"; end if;
      done <= true;
      wait;
   end process;
end architecture;
