set run_dir [file normalize $::env(UCC_RUN_DIR)]
set ::flow_root $run_dir
source [file join $run_dir reference config.tcl]
source [file join $run_dir flow.tcl]
set_db max_cpus_per_server 2
set_db hdl_error_on_blackbox true
set_db syn_generic_effort medium
set_db syn_map_effort high
set_db syn_opt_effort high
set_db lp_insert_clock_gating true
set_db auto_ungroup both
source [file join $run_dir mmmc.tcl]
read_physical -lef $tsmcn28_lefs
read_netlist [file join $run_dir input.v] -top $design
init_design -top $design
set_db interconnect_mode ple
set_db use_scan_seqs_for_non_dft false
set_db design:$design .retime false
set_db design:$design .lp_clock_gating_min_flops 2
set_db design:$design .lp_clock_gating_max_flops 100000
check_design -unresolved > [file join $run_dir unresolved.rpt]
set f [open [file join $run_dir settings.rpt] w]
foreach attr {auto_ungroup lp_insert_clock_gating syn_generic_effort syn_map_effort syn_opt_effort interconnect_mode} {
    puts $f "$attr=[get_db $attr]"
}
puts $f "retime=[get_db design:$design .retime]"
puts $f "optimization_performed=false"
close $f
set f [open [file join $run_dir invariants.rpt] w]
foreach mode $modes {
    set_analysis_view -setup [list ${mode}.SS.setup_view] -hold [list ${mode}.FF.hold_view ${mode}.TT.extra_view]
    set_clock_gating_check -setup 0.0
    if {![llength [get_db cost_groups cg_enable_group_clk]]} {define_cost_group -name cg_enable_group_clk -weight 1}
    set cg_pins [get_db pins */RC_CGIC_INST/E]
    if {[llength $cg_pins] != $::env(UCC_EXPECTED_ICGS)} {error "Unexpected number of clock-enable pins"}
    path_group -to $cg_pins -group cg_enable_group_clk -view ${mode}.SS.setup_view
    remove_cdn_loop_breaker
    report_analysis_views > [file join $run_dir views_${mode}.rpt]
    report_case_analysis > [file join $run_dir cases_${mode}.rpt]
    report_timing -views ${mode}.SS.setup_view -max_paths 1000 > [file join $run_dir timing_${mode}.rpt]
    report_timing -views ${mode}.SS.setup_view -group cg_enable_group_clk -max_paths 30 > [file join $run_dir timing_clockgate_${mode}.rpt]
    report_qor -view ${mode}.SS.setup_view > [file join $run_dir qor_${mode}.rpt]
    foreach kind {max_transition max_fanout max_capacitance} {
        report_constraint -view ${mode}.SS.setup_view -drv_violation_type $kind -all_violators -no_wrap > [file join $run_dir ${mode}_${kind}.rpt]
    }
    report_loop > [file join $run_dir loops_${mode}.rpt]
    set cuts [llength [get_db insts *cdn_loop_breaker*]]
    set count [llength [get_db insts]]
    puts $f "${mode}_cuts=$cuts ${mode}_cells=$count"
    flush $f
    if {$cuts != 0 || $count != $::env(UCC_EXPECTED_CELLS)} {error "Changed cell count or automatic loop cuts"}
}
close $f
report_area > [file join $run_dir area.rpt]
report_area -depth 8 > [file join $run_dir area_hier.rpt]
report_gates > [file join $run_dir gates.rpt]
report_clock_gates > [file join $run_dir clock_gating.rpt]
write_hdl > [file join $run_dir checked.v]
set f [open [file join $run_dir complete.txt] w]
puts $f "Mapped pipeline timing import only; no optimization or resizing"
close $f
exit
