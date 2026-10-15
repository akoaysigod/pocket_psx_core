`timescale 1ns/1ps
// Simulation stand-in for Intel's altddio_out (used by sdram.sv for SDRAM_CLK): datain_h while outclock is high,
// datain_l while it is low. sdram.sv gives h = 0, l = 1, so SDRAM_CLK is the inverted clk3x.
module altddio_out #(
   parameter extend_oe_disable = "OFF", parameter intended_device_family = "Cyclone V",
   parameter invert_output = "OFF", parameter lpm_hint = "UNUSED", parameter lpm_type = "altddio_out",
   parameter oe_reg = "UNREGISTERED", parameter power_up_high = "OFF", parameter width = 1
) (
   input  [width-1:0] datain_h, input [width-1:0] datain_l, input outclock,
   output [width-1:0] dataout,
   input aclr, input aset, input oe, input outclocken, input sclr, input sset
);
   assign dataout = outclock ? datain_h : datain_l;
endmodule
