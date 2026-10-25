# quartus_sta -t psram_sta.tcl : PSRAM interface timing with the project constraints (core_constraints.sdc, only
# for VRAM_CLK3X builds): worst read (cram*_dq -> dqIn) and write (-> cram* pins) path per corner, setup and
# hold, with the clock relationship; full path reports in psram_{read,write}_{setup,hold}_<corner>.txt. Read hold
# slacks are the margin beyond psram_hold_guard.
project_open ap_core -revision ap_core
create_timing_netlist
read_sdc
update_timing_netlist
foreach_in_collection c [get_clocks {cram*}] { puts "CLK [get_clock_info -name $c] period [get_clock_info -period $c] master [get_clock_info -master_clock $c]" }
foreach corner {slow_85 slow_0 fast_0} {
   if {$corner eq "slow_85"} {set_operating_conditions 8_slow_1100mv_85c}
   if {$corner eq "slow_0"}  {set_operating_conditions 8_slow_1100mv_0c}
   if {$corner eq "fast_0"}  {set_operating_conditions MIN_fast_1100mv_0c}
   update_timing_netlist
   foreach kind {setup hold} {
      set r [get_timing_paths -$kind -from [get_ports {cram*_dq[*]}] -to [get_registers {*ivram|dqIn[*]}] -npaths 1]
      set w [get_timing_paths -$kind -to [get_ports {cram*}] -npaths 1]
      foreach dir {read write} p [list $r $w] {
         foreach_in_collection q $p {
            set fc [get_clock_info -name [get_path_info -from_clock $q]]
            set tc [get_clock_info -name [get_path_info -to_clock $q]]
            regsub {.*general\[2\].*} $fc clk3x fc
            regsub {.*general\[2\].*} $tc clk3x tc
            puts [format "%-7s %-5s %-5s slack %7.3f rel %7.3f  %s -> %s  (%s -> %s)" $corner $kind $dir \
               [get_path_info -slack $q] [get_path_info -clock_relationship $q] \
               [get_node_info -name [get_path_info -from $q]] [get_node_info -name [get_path_info -to $q]] $fc $tc]
         }
      }
      report_timing -$kind -from [get_ports {cram*_dq[*]}] -to [get_registers {*ivram|dqIn[*]}] -npaths 1 -detail full_path -file psram_read_${kind}_$corner.txt
      report_timing -$kind -to [get_ports {cram*}] -npaths 1 -detail full_path -file psram_write_${kind}_$corner.txt
   }
}
