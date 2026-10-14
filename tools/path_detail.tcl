# quartus_sta -t path_detail.tcl : full detail of the worst paths into sdram SDRAM_A / SDRAM_BA (slow 85C), written to
# path_detail.out / path_detail_ba.out in the project folder
project_open ap_core -revision ap_core
create_timing_netlist
read_sdc
update_timing_netlist
report_timing -setup -to [get_registers {*sdram:isdram|SDRAM_A*}] -npaths 1 -detail full_path -file path_detail.out
report_timing -setup -to [get_registers {*sdram:isdram|SDRAM_BA*}] -npaths 1 -detail full_path -file path_detail_ba.out
project_close
