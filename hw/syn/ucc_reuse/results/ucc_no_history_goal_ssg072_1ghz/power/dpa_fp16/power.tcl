if {[catch {
set_db max_cpus_per_server 4
source libraries_power.tcl
read_netlist -top ucc_b32_pipe5 mapped.v
read_sdc power.sdc
read_stimulus -file dpa_fp16.vcd -dut_instance tb.dut -start 109000ps -end 1109000ps -disable_rtlstim2gate -allow_n_nets
report_sdb_annotation > annotation.rpt
compute_power -mode average
report_power -by_hierarchy -levels 8 -unit mW > power.rpt
puts ENERGY_POWER_DONE
} msg]} { puts "ENERGY_ERROR $msg"; exit 1 }
exit
