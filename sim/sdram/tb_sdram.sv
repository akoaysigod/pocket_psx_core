`timescale 1ns/1ps
// rtl/sdram.sv (sdram_new) and the pk20 version (sdram_ref), each with its own SDRAM chip and traffic (harness.sv,
// same random sequence), wired like core_top.v on the Pocket. clk3x 100 MHz, clk1x = clk3x / 3, rising edges
// aligned (the real clocks are 101.6 / 33.9 MHz from one PLL).
module tb_sdram #(
   parameter int SIM_US  = 20000,
   parameter int SEED    = 1,
   parameter int GAP_MIN = 1,
   parameter int LOCKSTEP = 1
);
   logic clk3x = 0, clk1x = 0;
   always #5  clk3x = ~clk3x;
   always #15 clk1x = ~clk1x;

   wire fin_ref, fin_new;
   wire [31:0] err_ref, err_new;

`define DUT(M, P, NM)                                                                                         \
   wire        P``_sclk, P``_ras_n, P``_cas_n, P``_we_n, P``_dqml, P``_dqmh, P``_dq_oe;                        \
   wire  [1:0] P``_ba;                                                                                         \
   wire [12:0] P``_a;                                                                                          \
   wire [15:0] P``_dq_o, P``_dq_i;                                                                             \
   wire        P``_init, P``_rd_req, P``_wr_req, P``_dma, P``_cache, P``_rd_ready, P``_wr_ready;               \
   wire [26:0] P``_ram_addr, P``_ch3_addr, P``_fifo_adr;                                                       \
   wire [31:0] P``_ram_din, P``_dout32, P``_cache_data, P``_dma_data, P``_ch3_din, P``_ch3_dout, P``_fifo_data;\
   wire  [3:0] P``_ram_be, P``_cache_wr, P``_ch3_be;                                                           \
   wire  [1:0] P``_cntDMA;                                                                                     \
   wire  [7:0] P``_cache_addr;                                                                                 \
   wire        P``_dma_wr, P``_dma_reqprocessed, P``_ch3_req, P``_ch3_rnw, P``_ch3_ready;                     \
   wire        P``_fifo_empty, P``_fifo_read, P``_refreshForce, P``_ncs, P``_cke;                              \
   M #(.SINGLE_CHIP(1)) P``_dut (                                                                              \
      .SDRAM_DQ_O(P``_dq_o), .SDRAM_DQ_OE(P``_dq_oe), .SDRAM_DQ_I(P``_dq_i), .SDRAM_A(P``_a),               \
      .SDRAM_DQML(P``_dqml), .SDRAM_DQMH(P``_dqmh), .SDRAM_BA(P``_ba), .SDRAM_nCS(P``_ncs),                  \
      .SDRAM_nWE(P``_we_n), .SDRAM_nRAS(P``_ras_n), .SDRAM_nCAS(P``_cas_n), .SDRAM_CKE(P``_cke),            \
      .SDRAM_CLK(P``_sclk), .SDRAM_EN(1'b1),                                                                   \
      .init(P``_init), .clk(clk3x), .clk_base(clk1x), .refreshForce(P``_refreshForce), .ram_idle(),            \
      .ch1_addr(P``_ram_addr), .ch1_din(16'd0), .ch1_dout(), .ch1_dout32(P``_dout32), .ch1_req(P``_rd_req),    \
      .ch1_rnw(1'b1), .ch1_dma(P``_dma), .ch1_cntDMA(P``_cntDMA), .ch1_cache(P``_cache),                       \
      .ch1_ready(P``_rd_ready), .cache_wr(P``_cache_wr), .cache_data(P``_cache_data),                          \
      .cache_addr(P``_cache_addr), .dma_wr(P``_dma_wr), .dma_reqprocessed(P``_dma_reqprocessed),               \
      .dma_data(P``_dma_data),                                                                                 \
      .ch2_addr(P``_ram_addr), .ch2_dout(), .ch2_din(P``_ram_din), .ch2_req(P``_wr_req), .ch2_rnw(1'b0),       \
      .ch2_be(P``_ram_be), .ch2_ready(P``_wr_ready),                                                           \
      .ch3_addr(P``_ch3_addr), .ch3_dout(P``_ch3_dout), .ch3_din(P``_ch3_din), .ch3_req(P``_ch3_req),          \
      .ch3_rnw(P``_ch3_rnw), .ch3_be(P``_ch3_be), .ch3_ready(P``_ch3_ready),                                   \
      .dmafifo_adr(P``_fifo_adr), .dmafifo_data(P``_fifo_data), .dmafifo_empty(P``_fifo_empty),               \
      .dmafifo_read(P``_fifo_read));                                                                           \
   harness #(.SEED(SEED), .SIM_US(SIM_US), .GAP_MIN(GAP_MIN), .NAME(NM)) P``_h (                               \
      .clk1x(clk1x), .clk3x(clk3x), .sclk(P``_sclk), .ras_n(P``_ras_n), .cas_n(P``_cas_n), .we_n(P``_we_n),   \
      .ba(P``_ba), .a(P``_a), .dqm({P``_dqmh, P``_dqml}), .dq_from_ctl(P``_dq_o), .dq_oe(P``_dq_oe),           \
      .dq_to_ctl(P``_dq_i), .init(P``_init), .ram_addr(P``_ram_addr), .ram_din(P``_ram_din),                   \
      .ram_be(P``_ram_be), .rd_req(P``_rd_req), .wr_req(P``_wr_req), .dma(P``_dma), .cache(P``_cache),         \
      .cntDMA(P``_cntDMA), .dout32(P``_dout32), .rd_ready(P``_rd_ready), .wr_ready(P``_wr_ready),             \
      .cache_wr(P``_cache_wr), .cache_data(P``_cache_data), .cache_addr(P``_cache_addr),                       \
      .dma_wr(P``_dma_wr), .dma_reqprocessed(P``_dma_reqprocessed), .dma_data(P``_dma_data),                   \
      .ch3_addr(P``_ch3_addr), .ch3_din(P``_ch3_din), .ch3_req(P``_ch3_req), .ch3_rnw(P``_ch3_rnw),           \
      .ch3_be(P``_ch3_be), .ch3_dout(P``_ch3_dout), .ch3_ready(P``_ch3_ready),                                 \
      .fifo_adr(P``_fifo_adr), .fifo_data(P``_fifo_data), .fifo_empty(P``_fifo_empty),                         \
      .fifo_read(P``_fifo_read), .refreshForce(P``_refreshForce), .finished(fin_``P), .errors(err_``P));

   `DUT(sdram_ref, ref, "ref")
   `DUT(sdram_new, new, "new")

   // lockstep: with the same traffic both controllers must drive the same values on every clock (LOCKSTEP = 0 for a
   // controller that changes timing on purpose)
   int mism = 0;
   always @(negedge clk3x) if (LOCKSTEP) begin
      if ({ref_a, ref_ba, ref_ras_n, ref_cas_n, ref_we_n, ref_dq_oe, ref_dq_oe ? ref_dq_o : 16'd0} !==
          {new_a, new_ba, new_ras_n, new_cas_n, new_we_n, new_dq_oe, new_dq_oe ? new_dq_o : 16'd0} ||
          {ref_dout32, ref_rd_ready, ref_wr_ready, ref_cache_wr, ref_cache_wr != 0 ? {ref_cache_data, ref_cache_addr} : 40'd0} !==
          {new_dout32, new_rd_ready, new_wr_ready, new_cache_wr, new_cache_wr != 0 ? {new_cache_data, new_cache_addr} : 40'd0} ||
          {ref_dma_wr, ref_dma_reqprocessed, ref_dma_wr ? ref_dma_data : 32'd0, ref_ch3_ready, ref_ch3_dout, ref_fifo_read} !==
          {new_dma_wr, new_dma_reqprocessed, new_dma_wr ? new_dma_data : 32'd0, new_ch3_ready, new_ch3_dout, new_fifo_read}) begin
         mism++;
         if (mism <= 10) $display("LOCKSTEP mismatch at %0t ns: A %h/%h BA %0d/%0d cmd %b/%b", $time, ref_a, new_a, ref_ba,
                                  new_ba, {ref_ras_n, ref_cas_n, ref_we_n}, {new_ras_n, new_cas_n, new_we_n});
      end
   end

   // coverage (reference controller): STATE_IDLE clocks where a ch1 / ch2 request decides against something else
   int cov_fifo = 0, cov_ch3 = 0, cov_req = 0, cov_rq = 0, cov_ref = 0, cov_fifo_idle = 0, cov_fifo_rd = 0;
   always @(posedge clk3x) begin
      if (ref_dut.state == 4 && !(ref_dut.refreshForce_req || ref_dut.refresh_count > 780)) begin
         if (!ref_fifo_empty && (ref_rd_req | ref_wr_req | ref_dut.ch1_rq | ref_dut.ch2_rq)) cov_fifo++;
         else if (ref_fifo_empty && ref_dut.ch3_rq && (ref_rd_req | ref_wr_req | ref_dut.ch1_rq | ref_dut.ch2_rq)) cov_ch3++;
         if (ref_fifo_empty && (ref_rd_req | ref_wr_req) && !(ref_dut.ch1_rq | ref_dut.ch2_rq)) cov_req++;
         if (ref_fifo_empty && (ref_dut.ch1_rq | ref_dut.ch2_rq)) cov_rq++;
      end
      if (ref_dut.state == 4 && !ref_fifo_empty) cov_fifo_idle++;
      if (ref_fifo_read) cov_fifo_rd++;
      if (ref_dut.state == 4 && (ref_dut.refreshForce_req || ref_dut.refresh_count > 780) &&
          (ref_rd_req | ref_wr_req | ref_dut.ch1_rq | ref_dut.ch2_rq)) cov_ref++;
   end

   initial begin
      wait (fin_ref && fin_new);
      $display("coverage (idle clocks with a ch1/ch2 request): over DMA fifo %0d, over ch3 %0d, from ch1_req/ch2_req %0d, from ch1_rq/ch2_rq %0d, behind refresh %0d; idle clocks with fifo data %0d, fifo words written %0d",
               cov_fifo, cov_ch3, cov_req, cov_rq, cov_ref, cov_fifo_idle, cov_fifo_rd);
      if (LOCKSTEP) $display("lockstep: %0d clocks with a difference", mism);
      if (err_ref == 0 && err_new == 0 && mism == 0) $display("PASS");
      else $display("FAIL (errors: ref %0d, new %0d, lockstep differences %0d)", err_ref, err_new, mism);
      $finish;
   end
endmodule
