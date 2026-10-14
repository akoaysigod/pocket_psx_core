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

# TODO (hardware bring-up): SDRAM, PSRAM and video pin timing (set_input_delay / set_output_delay).
