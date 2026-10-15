`timescale 1ns/1ps
// Test harness for one sdram controller: a behavioural SDRAM chip (x16, 4 banks, CL / BL from the mode register,
// single writes) that checks command timing, and random traffic on every channel the Pocket core uses, the way
// the core drives them:
//   ch1 / ch2 (memorymux, one request at a time, held one clk1x cycle): single reads, cache line reads, writes
//     with byte enables, and DMA reads (pipelined like dma.vhd: the next request right after dma_reqprocessed,
//     1-4 words, never across a 1 KByte row);
//   ch3 (SPU): reads and writes; DMA write fifo (clk3x, fall-through): bursts of sequential words into main RAM;
//   refreshForce.
// The channels use separate address regions, so every read can be checked against a reference memory no matter
// how the channels interleave; at the end the chip's memory is compared with the reference. Latencies (clk1x
// clocks from the request to ready / the first DMA word) are collected per kind of access.
module harness #(
   parameter int    SEED    = 1,
   parameter int    SIM_US  = 20000,
   parameter int    GAP_MIN = 1,
   parameter string NAME    = "dut"
) (
   input               clk1x,
   input               clk3x,
   // SDRAM pins
   input               sclk,
   input               ras_n, cas_n, we_n,
   input        [1:0]  ba,
   input       [12:0]  a,
   input        [1:0]  dqm,
   input       [15:0]  dq_from_ctl,
   input               dq_oe,
   output logic [15:0] dq_to_ctl,
   // channels
   output logic        init,
   output logic [26:0] ram_addr,
   output logic [31:0] ram_din,
   output logic  [3:0] ram_be,
   output logic        rd_req, wr_req, dma, cache,
   output logic  [1:0] cntDMA,
   input        [31:0] dout32,
   input               rd_ready, wr_ready,
   input         [3:0] cache_wr,
   input        [31:0] cache_data,
   input         [7:0] cache_addr,
   input               dma_wr, dma_reqprocessed,
   input        [31:0] dma_data,
   output logic [26:0] ch3_addr,
   output logic [31:0] ch3_din,
   output logic        ch3_req, ch3_rnw,
   output logic  [3:0] ch3_be,
   input        [31:0] ch3_dout,
   input               ch3_ready,
   output logic [26:0] fifo_adr,
   output logic [31:0] fifo_data,
   output logic        fifo_empty,
   input               fifo_read,
   output logic        refreshForce,
   output logic        finished,
   output logic [31:0] errors
);

   // ------------------------------------------------------------------ helpers
   localparam int T_RCD = 2, T_RP = 2, T_RAS = 5, T_RC = 7, T_RRD = 2, T_WR = 2, T_RFC = 7, T_MRD = 2;

   // halfword address h = byte address [25:1]; the controller maps it as
   // {cas_addr[9], BA, A (row), cas_addr[8:0]} = h[24:0] -> chip key {bank, row, column}
   function automatic logic [24:0] key_of(input logic [24:0] h);
      return {h[23:22], h[21:9], h[24], h[8:0]};
   endfunction
   function automatic logic [15:0] dflt(input logic [24:0] key);
      return key[15:0] ^ {key[24:16], 7'h35} ^ 16'hA55A;
   endfunction

   function automatic int unsigned xs(inout int unsigned s);
      s ^= s << 13; s ^= s >> 17; s ^= s << 5;
      return s;
   endfunction

   int nerr = 0;
   assign errors = nerr;
   task automatic err(input string msg);
      nerr++;
      if (nerr <= 20) $display("[%s] ERROR at %0t ns: %s", NAME, $time, msg);
   endtask

   // reference memory, halfwords
   logic [15:0] gold [int unsigned];
   function automatic logic [15:0] gget(input int unsigned h);
      return gold.exists(h) ? gold[h] : dflt(key_of(h[24:0]));
   endfunction
   function automatic logic [31:0] gword(input int unsigned byteaddr);
      return {gget(byteaddr / 2 + 1), gget(byteaddr / 2)};
   endfunction
   task automatic gput(input int unsigned byteaddr, input logic [31:0] d, input logic [3:0] be);
      logic [15:0] lo, hi;
      lo = gget(byteaddr / 2); hi = gget(byteaddr / 2 + 1);
      if (be[0]) lo[7:0]  = d[7:0];
      if (be[1]) lo[15:8] = d[15:8];
      if (be[2]) hi[7:0]  = d[23:16];
      if (be[3]) hi[15:8] = d[31:24];
      gold[byteaddr / 2] = lo; gold[byteaddr / 2 + 1] = hi;
   endtask

   // latency statistics (clk1x clocks): 0 read, 1 cache line, 2 DMA (first word), 3 write, 4 SPU read, 5 SPU write
   localparam int NK = 6;
   string kname [NK] = '{"read", "cache line", "DMA read", "write", "SPU read", "SPU write"};
   longint lsum [NK];
   int     lcnt [NK], lmin [NK], lmax [NK];
   int     hist [NK][32];
   initial for (int k = 0; k < NK; k++) begin lsum[k] = 0; lcnt[k] = 0; lmin[k] = 1000; lmax[k] = 0; for (int i = 0; i < 32; i++) hist[k][i] = 0; end
   task automatic lat(input int k, input int n);
      lsum[k] += n; lcnt[k]++;
      if (n < lmin[k]) lmin[k] = n;
      if (n > lmax[k]) lmax[k] = n;
      hist[k][n > 31 ? 31 : n]++;
   endtask

   longint cyc1 = 0;     // clk1x clocks
   always @(posedge clk1x) cyc1 <= cyc1 + 1;

   bit stop = 0;         // set after SIM_US: no new requests
   bit cpu_idle = 0, spu_idle = 0;

   // ------------------------------------------------------------------ SDRAM chip
   longint cyc = 0;
   bit          act [4];
   logic [12:0] row [4];
   longint      act_cyc [4], pre_cyc [4], wr_cyc [4], ap_at [4];
   bit          ap_pend [4];
   longint      last_act = -100, ref_cyc = -100, mrs_cyc = -100;
   int          cl = 2, bl = 2;
   bit          mode_set = 0;
   longint      nref = 0, prev_ref = -1, max_ref_gap = 0, first_ref = -1;
   int          ref_short = 0;   // AUTO REFRESH one clock short of tRP after an auto precharge
   logic [15:0] cmem  [int unsigned];
   logic [15:0] rsched [longint];
   initial for (int b = 0; b < 4; b++) begin act[b] = 0; act_cyc[b] = -100; pre_cyc[b] = -100; wr_cyc[b] = -100; ap_pend[b] = 0; end

   always @(posedge sclk) begin
      logic [2:0] cmd;
      logic [24:0] k;
      bit drives;
      cyc = cyc + 1;
      for (int b = 0; b < 4; b++)
         if (ap_pend[b] && cyc >= ap_at[b]) begin ap_pend[b] = 0; act[b] = 0; pre_cyc[b] = ap_at[b]; end
      cmd = {ras_n, cas_n, we_n};
      if (cmd != 3'b111) begin
         if (cyc - ref_cyc < T_RFC) err($sformatf("command %b %0d clocks after AUTO REFRESH (tRFC %0d)", cmd, cyc - ref_cyc, T_RFC));
         if (cyc - mrs_cyc < T_MRD) err($sformatf("command %b %0d clocks after LOAD MODE", cmd, cyc - mrs_cyc));
      end
      case (cmd)
         3'b011: begin // ACTIVE
            if (!mode_set) err("ACTIVE before LOAD MODE");
            if (act[ba] || ap_pend[ba]) err($sformatf("ACTIVE to bank %0d that is open", ba));
            if (cyc - pre_cyc[ba] < T_RP) err($sformatf("ACTIVE bank %0d %0d clocks after precharge (tRP)", ba, cyc - pre_cyc[ba]));
            if (cyc - act_cyc[ba] < T_RC) err($sformatf("ACTIVE bank %0d %0d clocks after ACTIVE (tRC)", ba, cyc - act_cyc[ba]));
            if (cyc - last_act < T_RRD) err($sformatf("ACTIVE %0d clocks after ACTIVE (tRRD)", cyc - last_act));
            act[ba] = 1; row[ba] = a; act_cyc[ba] = cyc; last_act = cyc;
         end
         3'b101: begin // READ
            if (!act[ba] || ap_pend[ba]) err($sformatf("READ to bank %0d that is not open (or auto precharging)", ba));
            else if (cyc - act_cyc[ba] < T_RCD) err($sformatf("READ %0d clocks after ACTIVE (tRCD)", cyc - act_cyc[ba]));
            for (int i = 0; i < bl; i++) begin
               logic [9:0] c;
               c = (a[9:0] & ~10'(bl - 1)) | ((a[9:0] + 10'(i)) & 10'(bl - 1));
               k = {ba, row[ba], c};
               rsched[cyc + cl + i] = cmem.exists(k) ? cmem[k] : dflt(k);
            end
            if (a[10]) begin
               ap_pend[ba] = 1;
               ap_at[ba] = (cyc + bl > act_cyc[ba] + T_RAS) ? cyc + bl : act_cyc[ba] + T_RAS;
            end
         end
         3'b100: begin // WRITE (single, NO_WRITE_BURST)
            if (!act[ba] || ap_pend[ba]) err($sformatf("WRITE to bank %0d that is not open (or auto precharging)", ba));
            else if (cyc - act_cyc[ba] < T_RCD) err($sformatf("WRITE %0d clocks after ACTIVE (tRCD)", cyc - act_cyc[ba]));
            if (!dq_oe) err("WRITE without write data driven");
            k = {ba, row[ba], a[9:0]};
            begin
               logic [15:0] v;
               v = cmem.exists(k) ? cmem[k] : dflt(k);
               if (!dqm[0]) v[7:0]  = dq_from_ctl[7:0];
               if (!dqm[1]) v[15:8] = dq_from_ctl[15:8];
               cmem[k] = v;
            end
            wr_cyc[ba] = cyc;
            if (a[10]) begin
               ap_pend[ba] = 1;
               ap_at[ba] = (cyc + T_WR > act_cyc[ba] + T_RAS) ? cyc + T_WR : act_cyc[ba] + T_RAS;
            end
         end
         3'b010: begin // PRECHARGE
            for (int b = 0; b < 4; b++)
               if (a[10] || b == ba) begin
                  if (ap_pend[b]) err($sformatf("PRECHARGE to bank %0d during auto precharge", b));
                  if (act[b]) begin
                     if (cyc - act_cyc[b] < T_RAS) err($sformatf("PRECHARGE bank %0d %0d clocks after ACTIVE (tRAS)", b, cyc - act_cyc[b]));
                     if (cyc - wr_cyc[b] < T_WR) err($sformatf("PRECHARGE bank %0d %0d clocks after WRITE (tWR)", b, cyc - wr_cyc[b]));
                  end
                  act[b] = 0; pre_cyc[b] = cyc;
               end
         end
         3'b001: begin // AUTO REFRESH
            for (int b = 0; b < 4; b++) begin
               if (act[b] || ap_pend[b]) err($sformatf("AUTO REFRESH with bank %0d open", b));
               else if (cyc - pre_cyc[b] < T_RP - 1) err($sformatf("AUTO REFRESH %0d clocks after precharge of bank %0d (tRP)", cyc - pre_cyc[b], b));
               // known in the pk20 controller (and upstream): the refresh in STATE_IDLE_1 can come one clock short of
               // tWR + tRP after a WRITE with auto precharge; counted, not an error, to compare the two controllers
               else if (cyc - pre_cyc[b] < T_RP) ref_short++;
            end
            if (mode_set) begin
               nref++;
               if (first_ref < 0) first_ref = cyc;
               if (prev_ref >= 0 && cyc - prev_ref > max_ref_gap) max_ref_gap = cyc - prev_ref;
               prev_ref = cyc;
            end
            ref_cyc = cyc;
         end
         3'b000: begin // LOAD MODE
            for (int b = 0; b < 4; b++) if (act[b] || ap_pend[b]) err("LOAD MODE with a bank open");
            cl = int'(a[6:4]); bl = 1 << a[2:0];
            if (!a[9]) err("mode register: write burst not single");
            mode_set = 1; mrs_cyc = cyc;
         end
         default: ;
      endcase
      drives = rsched.exists(cyc);
      if (drives) begin
         dq_to_ctl <= rsched[cyc];
         rsched.delete(cyc);
         if (dq_oe) err("data bus driven by the controller and the chip");
      end else
         dq_to_ctl <= 16'hDEAD ^ cyc[15:0];
   end

   // ------------------------------------------------------------------ ch1 / ch2: CPU and DMA (memorymux)
   int unsigned rs_cpu;
   int unsigned hot [64];
   localparam int unsigned A_BASE = 32'h0000000, A_SIZE = 32'h0100000;   // region A: 1 MByte of the 2 MByte main RAM

   function automatic int unsigned pick_a(inout int unsigned s);
      int unsigned r;
      r = xs(s);
      if (r % 100 < 70) return hot[(r >> 8) % 64];
      return A_BASE + ((xs(s) % A_SIZE) & ~32'h3);
   endfunction

   // expected DMA words: address of each word, plus the request each starts
   int unsigned dma_q [$];
   longint      dma_t0 [$];       // issue clock of each request, popped at its first word
   bit          dma_first [$];
   // cache lines in flight: base, first word, words still to come
   int unsigned clq_base [$], clq_idx [$];
   int          clq_left [$];

   task automatic issue_wait_rd(input int kind);
      longint t0;
      t0 = cyc1;
      rd_req = 1;
      @(posedge clk1x); #1 rd_req = 0;
      while (!rd_ready) begin
         @(posedge clk1x); #1;
         if (cyc1 - t0 > 2000) begin err("read: no ready"); return; end
      end
      lat(kind, int'(cyc1 - t0));
   endtask

   initial begin
      int unsigned s;
      rs_cpu = 32'h1234567 ^ (SEED * 32'h9E3779B9);
      for (int i = 0; i < 64; i++) hot[i] = A_BASE + ((xs(rs_cpu) % A_SIZE) & ~32'h3);
      // a few hot words just below a row end and at line ends
      hot[0] = A_BASE + 32'h3FC; hot[1] = A_BASE + 32'h7F8; hot[2] = A_BASE + 32'h1C; hot[3] = A_BASE + 32'h40C;
      init = 1; rd_req = 0; wr_req = 0; dma = 0; cache = 0; cntDMA = 0; ram_addr = 0; ram_din = 0; ram_be = 0;
      refreshForce = 0;
      repeat (4) @(posedge clk1x);
      #1 init = 0;
      #(130000);                                   // SDRAM startup: ~12100 clk3x clocks
      while (!stop) begin
         int unsigned r, op, gap;
         r = xs(rs_cpu);
         gap = GAP_MIN + ((r % 100 < 20) ? (xs(rs_cpu) % 40) : (xs(rs_cpu) % 4));
         repeat (gap) @(posedge clk1x);
         #1;
         op = xs(rs_cpu) % 100;
         if (op < 35) begin                         // single read
            ram_addr = 27'(pick_a(rs_cpu)); dma = 0; cache = 0; cntDMA = 0;
            begin
               int unsigned ad; ad = ram_addr;
               issue_wait_rd(0);
               if (dout32 !== gword(ad)) err($sformatf("read %h: got %h, expected %h", ad, dout32, gword(ad)));
            end
         end else if (op < 55) begin                // cache line read
            int unsigned ad;
            ad = pick_a(rs_cpu);
            ram_addr = 27'(ad); dma = 0; cache = 1; cntDMA = 0;
            clq_base.push_back(ad & ~32'hF); clq_idx.push_back((ad >> 2) & 3); clq_left.push_back(4 - int'((ad >> 2) & 3));
            issue_wait_rd(1);
            if (dout32 !== gword(ad)) err($sformatf("cache read %h: ram_dout32 %h, expected %h", ad, dout32, gword(ad)));
            cache = 0;
         end else if (op < 70) begin                // DMA transfer: 1-6 pipelined requests
            int unsigned ad, n;
            longint t0;
            ad = pick_a(rs_cpu); n = 1 + xs(rs_cpu) % 6;
            dma = 1; cache = 0;
            for (int q = 0; q < n; q++) begin
               int unsigned c;
               c = 3;
               if (((ad >> 2) & 255) == 255) c = 0;  // dma.vhd: never across a 1 KByte row
               if (((ad >> 2) & 255) == 254) c = 1;
               if (((ad >> 2) & 255) == 253) c = 2;
               if (q == n - 1 && (xs(rs_cpu) % 3) == 0 && c > 0) c = xs(rs_cpu) % c;
               ram_addr = 27'(ad); cntDMA = 2'(c);
               for (int w = 0; w <= int'(c); w++) begin dma_q.push_back(ad + 4 * w); dma_first.push_back(w == 0); end
               dma_t0.push_back(cyc1);
               t0 = cyc1;
               rd_req = 1;
               @(posedge clk1x); #1 rd_req = 0;
               while (!dma_reqprocessed) begin
                  @(posedge clk1x); #1;
                  if (cyc1 - t0 > 2000) begin err("DMA: no reqprocessed"); break; end
               end
               ad = ad + 4 * (c + 1);
               if (q < n - 1) begin @(posedge clk1x); #1; end   // dma.vhd: ram_ena on the clock after reqprocessed
            end
            dma = 0;
            t0 = cyc1;
            while (dma_q.size() > 0 && cyc1 - t0 < 2000) begin @(posedge clk1x); #1; end
            if (dma_q.size() > 0) begin err("DMA: words missing"); dma_q.delete(); dma_first.delete(); dma_t0.delete(); end
         end else begin                              // write
            int unsigned ad, b;
            logic [3:0] be;
            longint t0;
            ad = pick_a(rs_cpu);
            b = xs(rs_cpu) % 7;
            be = (b == 0) ? 4'b0001 : (b == 1) ? 4'b0010 : (b == 2) ? 4'b0100 : (b == 3) ? 4'b1000 :
                 (b == 4) ? 4'b0011 : (b == 5) ? 4'b1100 : 4'b1111;
            ram_addr = 27'(ad); ram_din = xs(rs_cpu); ram_be = be; dma = 0; cache = 0;
            gput(ad, ram_din, be);
            t0 = cyc1;
            wr_req = 1;
            @(posedge clk1x); #1 wr_req = 0;
            while (!wr_ready) begin
               @(posedge clk1x); #1;
               if (cyc1 - t0 > 2000) begin err("write: no ready"); break; end
            end
            lat(3, int'(cyc1 - t0));
         end
      end
      cpu_idle = 1;
   end

   // DMA words (clk1x)
   always @(posedge clk1x) begin
      #1;
      if (dma_wr) begin
         if (dma_q.size() == 0) err("DMA: unexpected word");
         else begin
            int unsigned ad;
            ad = dma_q.pop_front();
            if (dma_first.pop_front()) lat(2, int'(cyc1 - dma_t0.pop_front()));
            if (dma_data !== gword(ad)) err($sformatf("DMA word %h: got %h, expected %h", ad, dma_data, gword(ad)));
         end
      end
   end

   // cache line words (clk3x)
   always @(posedge clk3x) begin
      #1;
      if (cache_wr != 0) begin
         int p;
         p = cache_wr[0] ? 0 : cache_wr[1] ? 1 : cache_wr[2] ? 2 : 3;
         if (clq_left.size() == 0) err($sformatf("cache: unexpected write %b", cache_wr));
         else begin
            int unsigned base, idx;
            base = clq_base[0]; idx = clq_idx[0];
            if (cache_addr !== 8'(base >> 4)) err($sformatf("cache: line %h, expected %h", cache_addr, 8'(base >> 4)));
            if (p < int'(idx)) err($sformatf("cache: word %0d before the requested word %0d", p, idx));
            if (cache_data !== gword(base + 4 * p))
               err($sformatf("cache: line %h word %0d got %h, expected %h", base, p, cache_data, gword(base + 4 * p)));
            clq_left[0] = clq_left[0] - 1;
            if (clq_left[0] == 0) begin void'(clq_base.pop_front()); void'(clq_idx.pop_front()); void'(clq_left.pop_front()); end
         end
      end
   end

   // refreshForce now and then (clk1x)
   initial begin
      int unsigned rs;
      rs = 32'h0BADF00D ^ SEED;
      #(140000);
      while (!stop) begin
         repeat (1000 + xs(rs) % 20000) @(posedge clk1x);
         #1 refreshForce = 1;
         @(posedge clk1x); #1 refreshForce = 0;
      end
   end

   // ------------------------------------------------------------------ ch3: SPU
   localparam int unsigned B_BASE = 32'h0800000, B_SIZE = 32'h0080000;   // bank 1
   localparam int unsigned B2_BASE = 32'h2000000;                         // column bit 9 = address bit 25
   initial begin
      int unsigned rs;
      rs = 32'h5EED5EED ^ (SEED * 7);
      ch3_req = 0; ch3_rnw = 1; ch3_be = 4'hF; ch3_addr = 0; ch3_din = 0;
      #(130000);
      while (!stop) begin
         int unsigned ad, r, b;
         longint t0;
         repeat (1 + ((xs(rs) % 100 < 30) ? xs(rs) % 30 : xs(rs) % 3)) @(posedge clk1x);
         #1;
         r = xs(rs);
         ad = ((r % 8) == 0 ? B2_BASE : B_BASE) + ((xs(rs) % (r % 4 == 0 ? 32'h400 : B_SIZE)) & ~32'h3);
         ch3_addr = 27'(ad);
         if (xs(rs) % 100 < 60) begin
            ch3_rnw = 1; ch3_be = 4'hF;
         end else begin
            b = xs(rs) % 3;
            ch3_rnw = 0; ch3_be = (b == 0) ? 4'b0011 : (b == 1) ? 4'b1100 : 4'b1111;
            ch3_din = xs(rs);
            gput(ad, ch3_din, ch3_be);
         end
         t0 = cyc1;
         ch3_req = 1;
         @(posedge clk1x); #1 ch3_req = 0;
         while (!ch3_ready) begin
            @(posedge clk1x); #1;
            if (cyc1 - t0 > 2000) begin err("SPU: no ready"); break; end
         end
         lat(ch3_rnw ? 4 : 5, int'(cyc1 - t0));
         if (ch3_rnw && ch3_dout !== gword(ad)) err($sformatf("SPU read %h: got %h, expected %h", ad, ch3_dout, gword(ad)));
      end
      spu_idle = 1;
   end

   // ------------------------------------------------------------------ DMA write fifo (clk3x, fall-through)
   // the other 1 MByte of main RAM: the controller merges fifo words into the open row comparing address bits
   // [20:10] only, which is complete for the 2 MByte main RAM the DMA writes to (and only there)
   localparam int unsigned C_BASE = 32'h0100000, C_SIZE = 32'h0100000;
   int unsigned fq_a [$];
   logic [31:0] fq_d [$];
   int unsigned rs_fifo;
   int          burst_left = 0;
   int unsigned burst_ad;
   initial begin
      rs_fifo = 32'hF1F0F1F0 ^ (SEED * 13);
      fifo_empty = 1; fifo_adr = 0; fifo_data = 0;
   end
   // (a pure next-state function here: Verilator 5.020 dropped this block's updates through xs()'s inout argument)
   function automatic int unsigned xsn(input int unsigned v);
      v ^= v << 13; v ^= v >> 17; v ^= v << 5;
      return v;
   endfunction
   always @(posedge clk3x) begin
      if (fifo_read) begin
         if (fq_a.size() == 0) err("DMA fifo: read while empty");
         else begin void'(fq_a.pop_front()); void'(fq_d.pop_front()); end
      end
      if (!stop && $time > 135000) begin
         rs_fifo = xsn(rs_fifo);
         if (burst_left == 0 && rs_fifo % 400 == 0) begin
            rs_fifo = xsn(rs_fifo); burst_left = 1 + rs_fifo % 32;
            burst_ad = C_BASE;
            rs_fifo = xsn(rs_fifo); burst_ad = burst_ad + ((rs_fifo % C_SIZE) & ~32'h3);
         end
         rs_fifo = xsn(rs_fifo);
         if (burst_left > 0 && fq_a.size() < 60 && rs_fifo % 3 != 0) begin
            logic [31:0] d;
            rs_fifo = xsn(rs_fifo); d = rs_fifo;
            fq_a.push_back(burst_ad); fq_d.push_back(d);
            gput(burst_ad, d, 4'hF);
            burst_ad += 4; burst_left--;
         end
      end
      fifo_empty <= (fq_a.size() == 0);
      if (fq_a.size() > 0) begin fifo_adr <= 27'(fq_a[0]); fifo_data <= fq_d[0]; end
   end

   // ------------------------------------------------------------------ end
   initial begin
      finished = 0;
      #(longint'(SIM_US) * 1000);
      stop = 1;
      wait (cpu_idle && spu_idle);
      #(20000);
      if (fq_a.size() != 0) err("DMA fifo not drained");
      if (clq_left.size() != 0) err($sformatf("cache: %0d lines incomplete", clq_left.size()));
      // chip memory against the reference
      begin
         int unsigned h;
         int n;
         n = 0;
         if (gold.first(h)) do begin
            logic [24:0] k;
            logic [15:0] v;
            k = key_of(h[24:0]);
            v = cmem.exists(k) ? cmem[k] : dflt(k);
            if (v !== gold[h]) err($sformatf("memory at %h: chip %h, reference %h", h * 2, v, gold[h]));
            n++;
         end while (gold.next(h));
         $display("[%s] %0d halfwords written and compared", NAME, n);
      end
      if (nref == 0) err("no AUTO REFRESH");
      else begin
         $display("[%s] AUTO REFRESH: %0d, average every %0d clocks, longest gap %0d clocks, %0d one clock short of tRP", NAME, nref,
                  (prev_ref - first_ref) / (nref > 1 ? nref - 1 : 1), max_ref_gap, ref_short);
         if ((prev_ref - first_ref) / (nref > 1 ? nref - 1 : 1) > 781) err("refresh rate below 8192 per 64 ms");
         if (max_ref_gap > 9 * 781) err("more than 8 refreshes postponed");
      end
      for (int kk = 0; kk < NK; kk++) begin
         string hs;
         hs = "";
         for (int i = 0; i < 32; i++) if (hist[kk][i] != 0) hs = {hs, $sformatf(" %0d:%0d", i, hist[kk][i])};
         $display("[%s] %-10s n=%6d  mean %0d.%02d  min %0d  max %0d   clocks:count%s", NAME, kname[kk], lcnt[kk],
                  lcnt[kk] ? lsum[kk] / lcnt[kk] : 0, lcnt[kk] ? (lsum[kk] * 100 / lcnt[kk]) % 100 : 0,
                  lcnt[kk] ? lmin[kk] : 0, lmax[kk], hs);
      end
      $display("[%s] errors: %0d", NAME, nerr);
      finished = 1;
   end

endmodule
