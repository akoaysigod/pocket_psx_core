#
# PSX core constraints (loaded by apf/apf_constraints.sdc after derive_pll_clocks)
#
# clk1x / clk2x / clk3x come from one PLL (psx_pll_core) and are related (exact multiples); the video PLL
# (clkvid, clkvid_90), the APF clocks and the bridge SPI clock are asynchronous to everything else.
set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group [get_clocks {*ipll_core*}] \
 -group [get_clocks {*ipll_video*}]

# pocket_video: v_rgb (clkvid) changes together with the v_pix toggle and is used by video_rgb (clkpix) only on
# the clkpix clock after the toggle is seen; on the clock where it changes the pixel is a skip pixel. So a value
# taken early at that edge does not matter and the same-edge hold check does not apply.
set_false_path -from [get_registers {*|pocket_video:ivideo|v_rgb[*]}] -to [get_registers {*|pocket_video:ivideo|video_rgb[*]}]

# PSRAM pins (cram0 / cram1, vram_psram), when vram_psram runs on clk3x (VRAM_CLK3X in pocket_psx.vhd: PSRAM
# clock clk3x / 2 = 50.8 MHz, read data taken on the falling clk3x edge by the dqIn I/O-cell registers; with
# VRAM_CLK3X false, the clk2x build has no dqIn registers and gets none of this).
# The PSRAM clock is the o_clk register, forwarded to cram*_clk: the generated clocks carry its delay out of the
# FPGA, and the PSRAM's times are given against them (AS1C8M16PL, latency code 3):
#   reads:  word valid tACLK (<= 9 ns) after a rising PSRAM clock edge, held tKOH (>= 2 ns) after the next one
#   address / control / write data: setup tSP 3 ns (CE# tCSP 4 ns), hold tHD 2 ns to the rising PSRAM clock
# Board traces, each way: 0 to psram_brd ns (not measured).
# Reads: the word of PSRAM clock edge k is taken on the falling clk3x edge half a clk3x after the edge that makes
# edge k+1, i.e. 2.5 clk3x after the edge that made edge k (setup 24.6 ns), and it must still be there then
# (hold: 4.92 ns after edge k+1). Outputs change only on the clk3x edges that make the PSRAM clock fall (setup
# 9.84 ns to the next rising one), so the hold check is against the rising edge before them (-9.84 ns).
# psram_hold_guard: extra hold margin asked of the fitter on the reads, so that it moves the sample point into
# the window with the dq input delay chains instead of stopping at zero slack. Read hold slacks in the report
# are the margin beyond it.
set psram_cap [get_registers -nowarn {*|vram_psram:ivram|dqIn[*]}]
if {[get_collection_size $psram_cap] > 0} {
   set psram_brd 0.5
   set psram_hold_guard 1.5
   set psram_clk3x [get_clocks {*ipll_core*general[2]*divclk}]
   create_generated_clock -name psram_clk -source [get_pins -compatibility_mode {*|ivram|o_clk|clk}] -divide_by 2 \
      [get_pins -compatibility_mode {*|ivram|o_clk|q}]
   foreach c {cram0 cram1} {
      create_generated_clock -name ${c}_clk -source [get_pins -compatibility_mode {*|ivram|o_clk|q}] [get_ports ${c}_clk]
      set_input_delay  -clock ${c}_clk -max [expr {9.0 + 2 * $psram_brd}] [get_ports ${c}_dq[*]]
      set_input_delay  -clock ${c}_clk -min 2.0 [get_ports ${c}_dq[*]]
      set outs [get_ports [list ${c}_a[*] ${c}_adv_n ${c}_we_n ${c}_lb_n ${c}_ub_n ${c}_dq[*]]]
      set_output_delay -clock ${c}_clk -max [expr {3.0 + $psram_brd}] $outs
      set_output_delay -clock ${c}_clk -min [expr {-2.0 - $psram_brd}] $outs
      set_output_delay -clock ${c}_clk -max [expr {4.0 + $psram_brd}] [get_ports ${c}_ce0_n]
      set_output_delay -clock ${c}_clk -min [expr {-2.0 - $psram_brd}] [get_ports ${c}_ce0_n]
      set_multicycle_path -setup -end 3 -from [get_clocks ${c}_clk] -to $psram_clk3x
      set_multicycle_path -hold  -end 1 -from [get_clocks ${c}_clk] -to $psram_clk3x
      set_multicycle_path -hold  -start 1 -from $psram_clk3x -to [get_clocks ${c}_clk]
      set_clock_uncertainty -hold -add -from [get_clocks ${c}_clk] -to $psram_clk3x $psram_hold_guard
   }
}

# TODO (hardware bring-up): SDRAM and video pin timing (set_input_delay / set_output_delay).
