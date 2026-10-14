# quartus_sta -t m10kn_clocks.tcl : for every RamM10Kn (falling-edge M10K) instance, list the launch clocks
# of all paths that end at its ports, with path count and worst setup slack. Only the instance's own
# rising-edge clock is allowed as a launch clock (plus its falling edge from other RamM10Kn).
project_open ap_core -revision ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set dst [get_keepers -nowarn {*RamM10Kn:*}]
puts "RAMM10KN keepers: [get_collection_size $dst]"
foreach_in_collection c [get_clocks] {
   set cn [get_clock_info -name $c]
   set paths [get_timing_paths -setup -from_clock $cn -to $dst -npaths 100000 -pairs_only]
   set n [get_collection_size $paths]
   if {$n == 0} continue
   set worst 1e9
   array unset inst
   foreach_in_collection p $paths {
      set s [get_path_info -slack $p]
      if {$s < $worst} {set worst $s}
      set to [get_node_info -name [get_path_info -to $p]]
      regsub {\|altsyncram:.*} $to {} to
      regsub {.*psx_top:ipsx_top\|} $to {} to
      set k "[get_clock_info -name [get_path_info -to_clock $p]] <- $cn : $to"
      if {[info exists inst($k)]} {incr inst($k)} else {set inst($k) 1}
   }
   puts "FROM $cn : $n paths, worst setup slack $worst"
   foreach k [lsort [array names inst]] { puts "   $inst($k)  $k" }
}
project_close
