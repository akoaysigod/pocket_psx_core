# quartus_sta -t worst_paths.tcl : worst setup and hold paths per clock at all corners (slack < 0.3 ns)
project_open ap_core -revision ap_core
create_timing_netlist
read_sdc
update_timing_netlist
foreach corner {slow_85 slow_0 fast_0} {
   if {$corner eq "slow_85"} {set_operating_conditions 8_slow_1100mv_85c}
   if {$corner eq "slow_0"}  {set_operating_conditions 8_slow_1100mv_0c}
   if {$corner eq "fast_0"}  {set_operating_conditions MIN_fast_1100mv_0c}
   update_timing_netlist
   foreach kind {setup hold} {
      foreach_in_collection c [get_clocks] {
         set cn [get_clock_info -name $c]
         set paths [get_timing_paths -$kind -to_clock $c -npaths 12 -less_than_slack 0.3]
         foreach_in_collection p $paths {
            set s [get_path_info -slack $p]
            set f [get_node_info -name [get_path_info -from $p]]
            set t [get_node_info -name [get_path_info -to $p]]
            set fc [get_clock_info -name [get_path_info -from_clock $p]]
            regsub -all {core_top:ic\|pocket_psx:ipsx\|psx_pocket_core:ipsx\|psx_mister:ipsx\|psx_top:ipsx_top\|} $f {} f
            regsub -all {core_top:ic\|pocket_psx:ipsx\|psx_pocket_core:ipsx\|psx_mister:ipsx\|psx_top:ipsx_top\|} $t {} t
            regsub -all {ic\|ipll_core\|altera_pll_i\|general\[(\d)\].gpll~PLL_OUTPUT_COUNTER\|divclk} $fc {core\1} fc
            regsub -all {ic\|ipll_core\|altera_pll_i\|general\[(\d)\].gpll~PLL_OUTPUT_COUNTER\|divclk} $cn {core\1} cn2
            regsub -all {ic\|ipll_video\|altera_pll_i\|general\[(\d)\].gpll~PLL_OUTPUT_COUNTER\|divclk} $fc {video\1} fc
            regsub -all {ic\|ipll_video\|altera_pll_i\|general\[(\d)\].gpll~PLL_OUTPUT_COUNTER\|divclk} $cn2 {video\1} cn2
            puts [format "%-7s %-5s %7.3f  %s -> %s   %s => %s" $corner $kind $s $fc $cn2 [string range $f 0 110] [string range $t 0 110]]
         }
      }
   }
}
project_close
