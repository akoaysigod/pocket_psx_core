# quartus_sta -t psram_io.tcl : PSRAM pin timing per corner (from the datasheet report: clock-to-output times of
# the cram*_ outputs, setup / hold times of the cram*_dq inputs), to check the PSRAM I/O margins by hand
# (the fit checks them with the constraints in core_constraints.sdc; tools/psram_sta.tcl reports those paths).
project_open ap_core -revision ap_core
create_timing_netlist
read_sdc
update_timing_netlist
foreach corner {slow_85 slow_0 fast_0} {
   if {$corner eq "slow_85"} {set_operating_conditions 8_slow_1100mv_85c}
   if {$corner eq "slow_0"}  {set_operating_conditions 8_slow_1100mv_0c}
   if {$corner eq "fast_0"}  {set_operating_conditions MIN_fast_1100mv_0c}
   update_timing_netlist
   set f "psram_io_$corner.txt"
   report_datasheet -file $f
   puts "== $corner"
   set fh [open $f r]
   set section ""
   while {[gets $fh line] >= 0} {
      if {[regexp {^; (Setup Times|Hold Times|Clock to Output Times|Minimum Clock to Output Times)} $line -> s]} { set section $s }
      if {[regexp {cram[01]_} $line]} {
         regsub -all {ic\|ipll_core\|altera_pll_i\|general\[(\d)\].gpll~PLL_OUTPUT_COUNTER\|divclk} $line {core\1} line
         regsub -all { +} $line { } line
         puts "$section: $line"
      }
   }
   close $fh
}
