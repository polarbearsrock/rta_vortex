set run_dir [file normalize $::env(UCC_RUN_DIR)]
set design $::env(UCC_TOP)
set budget_ns 5.0
if {[info exists ::env(UCC_BUDGET_NS)]} {
    set budget_ns $::env(UCC_BUDGET_NS)
}
source /data/eda_tools/script/pnr/tsmcn28/flow/setup/tsmcn28_libs.tcl
set_db library $tsmcn28_libs_tt
set_db max_cpus_per_server 4
set_db hdl_error_on_blackbox true
set_db syn_generic_effort high
set_db syn_map_effort high
set_db syn_opt_effort high
read_hdl -sv [file join $run_dir design.sv]
elaborate $design
check_design -unresolved
create_clock -name virtual_clock -period $budget_ns
set_input_delay 0 -clock virtual_clock [all_inputs]
set_output_delay 0 -clock virtual_clock [all_outputs]
set_input_transition 0.05 [all_inputs]
set_load 0.005 [all_outputs]
set_max_delay $budget_ns -from [all_inputs] -to [all_outputs]
check_timing_intent > [file join $run_dir timing_intent.rpt]
syn_generic
syn_map
syn_opt
report_area > [file join $run_dir area.rpt]
report_area -depth 8 > [file join $run_dir area_hier.rpt]
report_timing > [file join $run_dir timing.rpt]
report_qor > [file join $run_dir qor.rpt]
report_gates > [file join $run_dir gates.rpt]
report_power > [file join $run_dir power_vectorless.rpt]
write_hdl > [file join $run_dir mapped.v]
write_sdc > [file join $run_dir mapped.sdc]
set f [open [file join $run_dir complete.txt] w]
puts $f "top=$design budget_ns=$budget_ns corner=TT_0.8V_25C libraries=$tsmcn28_libs_tt"
close $f
exit
