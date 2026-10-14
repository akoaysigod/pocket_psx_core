// Pocket clocks for the PSX core, from the 74.25 MHz board clock (same frequencies as the MiSTer pll / pll2):
//   psx_pll_core : clk1x 33.8688 MHz, clk2x 67.7376 MHz, clk3x 101.6064 MHz (exact multiples of one VCO)
//   psx_pll_video: clkvid 53.693175 MHz (the core's video clock) and the Pocket pixel clock at half that rate
//                  (APF accepts pixel clocks up to ~50 MHz), plus the pixel clock shifted by 90 degrees
// Two PLLs because 53.693175 MHz is not an integer ratio of 33.8688 MHz. Quartus computes the fractional
// counters from the frequencies.
`timescale 1 ps / 1 ps

module psx_pll_core (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,
    output wire outclk_1,
    output wire outclk_2,
    output wire locked
);
    altera_pll #(
        .fractional_vco_multiplier("true"),
        .reference_clock_frequency("74.25 MHz"),
        .operation_mode("direct"),
        .number_of_clocks(3),
        .output_clock_frequency0("33.868800 MHz"),
        .phase_shift0("0 ps"),
        .duty_cycle0(50),
        .output_clock_frequency1("67.737600 MHz"),
        .phase_shift1("0 ps"),
        .duty_cycle1(50),
        .output_clock_frequency2("101.606400 MHz"),
        .phase_shift2("0 ps"),
        .duty_cycle2(50),
        .pll_type("General"),
        .pll_subtype("General")
    ) altera_pll_i (
        .rst      (rst),
        .outclk   ({outclk_2, outclk_1, outclk_0}),
        .locked   (locked),
        .fboutclk (),
        .fbclk    (1'b0),
        .refclk   (refclk)
    );
endmodule

module psx_pll_video (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,
    output wire outclk_1,
    output wire outclk_2,
    output wire locked
);
    altera_pll #(
        .fractional_vco_multiplier("true"),
        .reference_clock_frequency("74.25 MHz"),
        .operation_mode("direct"),
        .number_of_clocks(3),
        .output_clock_frequency0("53.693175 MHz"),
        .phase_shift0("0 ps"),
        .duty_cycle0(50),
        .output_clock_frequency1("26.846587 MHz"),
        .phase_shift1("0 ps"),
        .duty_cycle1(50),
        .output_clock_frequency2("26.846587 MHz"),
        .phase_shift2("9312 ps"),
        .duty_cycle2(50),
        .pll_type("General"),
        .pll_subtype("General")
    ) altera_pll_i (
        .rst      (rst),
        .outclk   ({outclk_2, outclk_1, outclk_0}),
        .locked   (locked),
        .fboutclk (),
        .fbclk    (1'b0),
        .refclk   (refclk)
    );
endmodule
