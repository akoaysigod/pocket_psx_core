-- pocket_memcard + vram_psram + two PSRAM models.
--  APF (clk_74a): loads the card (bridge writes at 0x20000000), later reads it back like APF does with agg23's
--  data_unloader (data for a read is the word fetched by the previous read's bridge_rd).
--  core (clk2x): random VRAM traffic on the DDR port the whole time (checked against a reference), and in
--  between: reads of the card through the DDR port (region 1, as the core's memory card logic sees it) and
--  writes to the card (a game saving).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_pocket_memcard is
   generic (CARD_WORDS : integer := 2048; SEED : integer := 1; GAP : integer := 60; MUTATION : integer := 0;
            CDC : boolean := false);   -- core side on clk2x through vram_cdc, pocket_memcard + vram_psram on clk3x
                                       -- (with vram_psram's IN_REG, as pocket_psx builds it)
end entity;

architecture sim of tb_pocket_memcard is
   signal clk_74a, clk2x : std_logic := '0';
   signal clk3x, clkv : std_logic := '0';   -- clkv: pocket_memcard PSRAM side and vram_psram
   signal p_busy, p_rdy, p_rd, p_we : std_logic := '0';
   signal p_burst, p_be : std_logic_vector(7 downto 0);
   signal p_addr : std_logic_vector(24 downto 0);
   signal p_dout, p_din : std_logic_vector(63 downto 0);
   signal reset : std_logic := '1';
   signal done : boolean := false;

   signal busy, rdy, rd, we : std_logic := '0';
   signal burst : std_logic_vector(7 downto 0) := x"01";
   signal addr  : std_logic_vector(24 downto 0) := (others => '0');
   signal dout, din : std_logic_vector(63 downto 0) := (others => '0');
   signal be : std_logic_vector(7 downto 0) := (others => '0');

   signal aux_req, aux_we, aux_done, card_write : std_logic;
   signal aux_addr : std_logic_vector(20 downto 0);
   signal aux_din, aux_dout : std_logic_vector(31 downto 0);

   signal bridge_addr, bridge_wr_data, bridge_rd_data : std_logic_vector(31 downto 0) := (others => '0');
   signal bridge_wr, bridge_rd, overflow, mc_busy : std_logic := '0';

   type tcram is record
      a : std_logic_vector(21 downto 16); dq_out, dq_in : std_logic_vector(15 downto 0); dq_oe : std_logic;
      clk, adv_n, cre, ce0_n, ce1_n, oe_n, we_n, ub_n, lb_n : std_logic;
   end record;
   signal c0, c1 : tcram;
   signal dq0, dq1 : std_logic_vector(15 downto 0);

   -- card contents expected (32-bit words), shared between the APF and core processes via signals
   type tcard is array(0 to 32767) of std_logic_vector(31 downto 0);
   signal phase     : integer := 0;     -- 0 load, 1 core checks card, 2 core writes card, 3 APF reads back, 4 end
   signal core_ack  : integer := 0;     -- phase the core process has finished
   signal card_mod  : tcard := (others => (others => '0'));   -- core's card writes (phase 2): value
   signal card_modv : std_logic_vector(0 to 32767) := (others => '0');
   signal core_errors : integer := 0;

   function cardword(i : integer) return std_logic_vector is
      variable x : unsigned(31 downto 0);
   begin
      x := resize(to_unsigned(i, 32) * to_unsigned(48271, 16), 32) + to_unsigned(i * 3 + 17, 32);
      return std_logic_vector(x xor shift_right(x, 11));
   end function;

   function loaded(i : integer) return boolean is
   begin
      return i < CARD_WORDS or i >= 32768 - 64;
   end function;
begin
   clk_74a <= not clk_74a after 6734 ps when not done;
   clk2x   <= not clk2x after 7381.5 ps when not done;
   clk3x   <= not clk3x after 4921 ps when not done;   -- rising edges aligned with clk2x every 2 clk2x periods

   gdirect : if not CDC generate
      clkv <= clk2x;
      busy <= p_busy; p_burst <= burst; p_addr <= addr; dout <= p_dout; rdy <= p_rdy; p_rd <= rd; p_din <= din;
      p_be <= be; p_we <= we;
   end generate;
   gcdc : if CDC generate
      clkv <= clk3x;
      icdc : entity work.vram_cdc
      port map (clk2x => clk2x, clk3x => clk3x,
                a_busy => busy, a_burstcnt => burst, a_addr => addr, a_dout => dout, a_dout_ready => rdy, a_rd => rd,
                a_din => din, a_be => be, a_we => we,
                b_busy => p_busy, b_burstcnt => p_burst, b_addr => p_addr, b_dout => p_dout, b_dout_ready => p_rdy,
                b_rd => p_rd, b_din => p_din, b_be => p_be, b_we => p_we);
   end generate;

   imc : entity work.pocket_memcard
   port map (clk_74a => clk_74a, bridge_addr => bridge_addr, bridge_wr => bridge_wr, bridge_wr_data => bridge_wr_data,
             bridge_rd => bridge_rd, bridge_rd_data => bridge_rd_data, overflow => overflow,
             clk2x => clkv, reset_2x => reset, busy => mc_busy, aux_req => aux_req, aux_we => aux_we,
             aux_addr => aux_addr, aux_din => aux_din, aux_dout => aux_dout, aux_done => aux_done,
             card_write => card_write);

   ivram : entity work.vram_psram
   generic map (IN_REG => CDC)
   port map (clk => clkv, reset => reset, ddr_busy => p_busy, ddr_burstcnt => p_burst, ddr_addr => p_addr, ddr_dout => p_dout,
             ddr_dout_ready => p_rdy, ddr_rd => p_rd, ddr_din => p_din, ddr_be => p_be, ddr_we => p_we,
             aux_req => aux_req, aux_we => aux_we, aux_addr => aux_addr, aux_din => aux_din, aux_dout => aux_dout,
             aux_done => aux_done, card_write => card_write,
             cram0_a => c0.a, cram0_dq_out => c0.dq_out, cram0_dq_oe => c0.dq_oe, cram0_dq_in => c0.dq_in, cram0_clk => c0.clk,
             cram0_adv_n => c0.adv_n, cram0_cre => c0.cre, cram0_ce0_n => c0.ce0_n, cram0_ce1_n => c0.ce1_n, cram0_oe_n => c0.oe_n,
             cram0_we_n => c0.we_n, cram0_ub_n => c0.ub_n, cram0_lb_n => c0.lb_n,
             cram1_a => c1.a, cram1_dq_out => c1.dq_out, cram1_dq_oe => c1.dq_oe, cram1_dq_in => c1.dq_in, cram1_clk => c1.clk,
             cram1_adv_n => c1.adv_n, cram1_cre => c1.cre, cram1_ce0_n => c1.ce0_n, cram1_ce1_n => c1.ce1_n, cram1_oe_n => c1.oe_n,
             cram1_we_n => c1.we_n, cram1_ub_n => c1.ub_n, cram1_lb_n => c1.lb_n);

   dq0 <= c0.dq_out when c0.dq_oe = '1' else (others => 'Z');
   dq1 <= c1.dq_out when c1.dq_oe = '1' else (others => 'Z');
   c0.dq_in <= dq0;
   c1.dq_in <= dq1;
   im0 : entity work.psram_model port map (a => c0.a, dq => dq0, clk => c0.clk, cre => c0.cre, adv_n => c0.adv_n, ce0_n => c0.ce0_n, ce1_n => c0.ce1_n, oe_n => c0.oe_n, we_n => c0.we_n, ub_n => c0.ub_n, lb_n => c0.lb_n);
   im1 : entity work.psram_model port map (a => c1.a, dq => dq1, clk => c1.clk, cre => c1.cre, adv_n => c1.adv_n, ce0_n => c1.ce0_n, ce1_n => c1.ce1_n, oe_n => c1.oe_n, we_n => c1.we_n, ub_n => c1.ub_n, lb_n => c1.lb_n);

   ---------------------------------------------------------------- core side (clk2x)
   process
      type tref is array(0 to 4095) of std_logic_vector(63 downto 0);
      variable ref : tref := (others => (others => '0'));
      variable s1 : positive := 11 + SEED;
      variable s2 : positive := 977;
      variable r : real;
      variable a, n, got, w32 : integer;
      variable w : std_logic_vector(63 downto 0);
      variable b : std_logic_vector(7 downto 0);
      variable exp : std_logic_vector(63 downto 0);
      variable errors : integer := 0;
      impure function rnd(k : integer) return integer is begin uniform(s1, s2, r); return integer(trunc(r * real(k))); end function;
      impure function rnd64 return std_logic_vector is
         variable v : std_logic_vector(63 downto 0);
      begin
         for i in 0 to 7 loop v(i * 8 + 7 downto i * 8) := std_logic_vector(to_unsigned(rnd(256), 8)); end loop; return v;
      end function;
      procedure ddr_write(wa : integer; wd : std_logic_vector(63 downto 0); wb : std_logic_vector(7 downto 0)) is
      begin
         addr <= std_logic_vector(to_unsigned(wa, 25)); din <= wd; be <= wb; we <= '1'; burst <= x"01";
         loop wait until rising_edge(clk2x); exit when busy = '0'; end loop;
         we <= '0';
      end procedure;
      procedure ddr_read(ra : integer; rn : integer) is
      begin
         addr <= std_logic_vector(to_unsigned(ra, 25)); burst <= std_logic_vector(to_unsigned(rn mod 256, 8)); rd <= '1';
         loop wait until rising_edge(clk2x); exit when busy = '0'; end loop;
         rd <= '0';
      end procedure;
      -- expected 64-bit card word k (region 1 word k = card 32-bit words 2k, 2k+1)
      impure function cardexp(k : integer) return std_logic_vector is
         variable v : std_logic_vector(63 downto 0);
      begin
         for h in 0 to 1 loop
            if (card_modv(2 * k + h) = '1') then v(32 * h + 31 downto 32 * h) := card_mod(2 * k + h);
            elsif (loaded(2 * k + h)) then v(32 * h + 31 downto 32 * h) := cardword(2 * k + h);
            else v(32 * h + 31 downto 32 * h) := (others => 'X'); end if;
         end loop;
         return v;
      end function;
   begin
      wait until rising_edge(clk2x); wait until rising_edge(clk2x);
      reset <= '0';
      while phase < 4 loop
         if (phase = 1 and core_ack = 0) then
            -- the core reads the card through its DDR port (region 1 = DDR word address 131072 + k)
            for k in 0 to CARD_WORDS / 2 - 1 loop
               if (k mod 64 = 0) then
                  n := 64; if k + n > CARD_WORDS / 2 then n := CARD_WORDS / 2 - k; end if;
                  ddr_read(131072 + k, n);
                  got := 0;
                  while got < n loop
                     wait until rising_edge(clk2x);
                     if rdy = '1' then
                        exp := cardexp(k + got);
                        if (dout /= exp) then
                           errors := errors + 1;
                           if errors <= 10 then report "core card read word " & integer'image(k + got) & " got " & to_hstring(dout) & " exp " & to_hstring(exp) severity error; end if;
                        end if;
                        got := got + 1;
                     end if;
                  end loop;
               end if;
            end loop;
            core_ack <= 1;
            wait until rising_edge(clk2x);   -- let core_ack update before the next phase check
         elsif (phase = 2 and core_ack = 1) then
            -- a game saving: byte-enable writes into the card
            for q in 0 to 199 loop
               a := rnd(CARD_WORDS / 2);
               if (q = 199) then a := 0; end if;   -- word 0 (prefetched while idle) always changes
               w := rnd64;
               case rnd(3) is
                  when 0 => b := x"FF";
                  when 1 => b := x"0F";
                  when others => b := x"F0";
               end case;
               if (q = 199) then b := x"FF"; end if;
               ddr_write(131072 + a, w, b);
               for h in 0 to 1 loop
                  if (b(4 * h) = '1') then
                     card_mod(2 * a + h) <= w(32 * h + 31 downto 32 * h);
                     card_modv(2 * a + h) <= '1';
                  end if;
               end loop;
               wait until rising_edge(clk2x);
            end loop;
            core_ack <= 2;
            wait until rising_edge(clk2x);   -- let core_ack update before the next phase check
         else
            -- random VRAM traffic (region 0, small window)
            a := rnd(4096);
            if rnd(2) = 0 then
               w := rnd64;
               case rnd(3) is
                  when 0 => b := x"FF";
                  when 1 => b := std_logic_vector(to_unsigned(rnd(256), 8));
                  when others => b := x"0F";
               end case;
               ddr_write(a, w, b);
               for k in 0 to 7 loop
                  if b(k) = '1' then ref(a)(k * 8 + 7 downto k * 8) := w(k * 8 + 7 downto k * 8); end if;
               end loop;
            else
               if rnd(4) = 0 then n := 1 + rnd(64); else n := 1 + rnd(16); end if;   -- GPU-like bursts
               if a + n > 4096 then n := 1; end if;
               ddr_read(a, n);
               got := 0;
               while got < n loop
                  wait until rising_edge(clk2x);
                  if rdy = '1' then
                     if dout /= ref(a + got) then
                        errors := errors + 1;
                        if errors <= 10 then report "VRAM read mismatch word " & integer'image(a + got) severity error; end if;
                     end if;
                     got := got + 1;
                  end if;
               end loop;
            end if;
            for i in 0 to rnd(40) loop wait until rising_edge(clk2x); end loop;
         end if;
         core_errors <= errors;
      end loop;
      wait;
   end process;

   ---------------------------------------------------------------- APF side (clk_74a)
   process
      variable s1 : positive := 5 + SEED;
      variable s2 : positive := 31;
      variable r : real;
      variable errors, reads : integer := 0;
      variable prev : integer;
      variable exp, got : std_logic_vector(31 downto 0);
      variable order : integer;
      impure function rnd(k : integer) return integer is begin uniform(s1, s2, r); return integer(trunc(r * real(k))); end function;
      procedure bwrite(ba : integer; bd : std_logic_vector(31 downto 0)) is
      begin
         bridge_addr <= std_logic_vector(to_unsigned(ba, 32)); bridge_wr_data <= bd; bridge_wr <= '1';
         wait until rising_edge(clk_74a);
         bridge_wr <= '0';
      end procedure;
      impure function expect(i : integer) return std_logic_vector is
      begin
         if (card_modv(i) = '1') then return card_mod(i); else return cardword(i); end if;
      end function;
   begin
      for i in 0 to 30 loop wait until rising_edge(clk_74a); end loop;
      -- load: the first CARD_WORDS words and the last 64 (address bits 16:2 all used), unrelated writes in between
      for i in 0 to 32767 loop
         if loaded(i) then
            bwrite(16#20000000# + 4 * i, cardword(i));
            if (i mod 97 = 0) then bwrite(16#10000000# + 4 * i, x"FFFFFFFF"); end if;   -- other slot
            for k in 0 to 60 + rnd(30) loop wait until rising_edge(clk_74a); end loop;   -- APF: a word every ~75 clocks
         end if;
      end loop;
      bwrite(16#20020000#, x"BAD0BAD0");   -- beyond the 128 KB card: must be ignored
      loop wait until rising_edge(clk_74a); exit when mc_busy = '0'; end loop;
      assert overflow = '0' report "load FIFO overflow" severity error;

      phase <= 1;
      wait until core_ack = 1;
      phase <= 2;
      wait until core_ack = 2;
      phase <= 3;
      for i in 0 to 50 loop wait until rising_edge(clk_74a); end loop;

      -- read back like APF: sequential addresses, one transaction per word
      prev := -1;
      for i in 0 to 32767 + 1 loop
         if (i = 32768 or loaded(i)) then
            if (i < 32768) then order := i; else order := 0; end if;
            bridge_addr <= std_logic_vector(to_unsigned(16#20000000# + 4 * order, 32));
            for k in 0 to 3 loop wait until rising_edge(clk_74a); end loop;
            got := bridge_rd_data;               -- sampled 4 clocks after the address (io_bridge_peripheral)
            if (prev >= 0) then
               exp := expect(prev);
               if (MUTATION = 1) then exp := expect(order); end if;   -- self check: no read latency
               if (got /= exp) then
                  errors := errors + 1;
                  if errors <= 10 then report "APF read of word " & integer'image(prev) & " got " & to_hstring(got) & " exp " & to_hstring(exp) severity error; end if;
               end if;
               reads := reads + 1;
            end if;
            wait until rising_edge(clk_74a);
            bridge_rd <= '1';
            wait until rising_edge(clk_74a);
            bridge_rd <= '0';
            for k in 0 to GAP loop wait until rising_edge(clk_74a); end loop;   -- SPI transfer time
            prev := order;
         end if;
      end loop;
      phase <= 4;
      for i in 0 to 50 loop wait until rising_edge(clk_74a); end loop;

      report "DONE card_words_loaded=" & integer'image(CARD_WORDS + 64) & " apf_reads_checked=" & integer'image(reads) &
             " apf_errors=" & integer'image(errors) & " core_errors=" & integer'image(core_errors) &
             " overflow=" & std_logic'image(overflow);
      if (errors = 0 and core_errors = 0 and overflow = '0') then report "PASS"; else report "FAIL"; end if;
      done <= true;
      wait;
   end process;
end architecture;
