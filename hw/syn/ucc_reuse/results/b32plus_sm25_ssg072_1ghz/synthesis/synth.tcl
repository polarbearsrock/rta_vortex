set run_dir [file normalize $::env(UCC_RUN_DIR)]
set ::flow_root $run_dir
source [file join $run_dir reference config.tcl]
source [file join $run_dir flow.tcl]
set_db max_cpus_per_server 4
set_db hdl_error_on_blackbox true
set_db hdl_language sv
set_db syn_generic_effort medium
set_db syn_map_effort high
set_db syn_opt_effort high
set_db lp_insert_clock_gating true
set_db auto_ungroup both
source [file join $run_dir mmmc.tcl]
read_physical -lef $tsmcn28_lefs
read_hdl -sv [file join $run_dir design.sv]
if {[llength $elab_parameters]} {
    elaborate $design -parameters $elab_parameters
} else {
    elaborate $design
}
set elaborated [get_db designs .name]
if {[llength $elaborated] != 1} { error "Expected one elaborated design: $elaborated" }
if {$elaborated ne $design} {
    update_names -design -map [list [list $elaborated $design]]
}
init_design -top $design
set_db design:$design .retime false
set_db design:$design .lp_clock_gating_max_flops 100000
set_db design:$design .lp_clock_gating_min_flops 2
set f [open [file join $run_dir settings.rpt] w]
foreach attr {auto_ungroup lp_insert_clock_gating syn_generic_effort syn_map_effort syn_opt_effort interconnect_mode} {
    if {[catch {get_db $attr} value]} { set value "unavailable: $value" }
    puts $f "$attr=$value"
}
foreach attr {retime lp_clock_gating_min_flops lp_clock_gating_max_flops} {
    puts $f "$attr=[get_db design:$design .$attr]"
}
puts $f "setup_views=$setup_views"
puts $f "hold_views=$hold_views"
close $f
check_design -unresolved > [file join $run_dir check_design.rpt]
report_analysis_views > [file join $run_dir analysis_views.rpt]
check_timing_intent > [file join $run_dir timing_intent.rpt]
syn_generic
write_db [file join $run_dir post_generic.db]
report_area > [file join $run_dir generic_area.rpt]
syn_map
write_db [file join $run_dir post_map.db]
syn_opt
write_hdl > [file join $run_dir mapped.v]
write_db [file join $run_dir final.db]
report_area > [file join $run_dir area.rpt]
report_area -depth 8 > [file join $run_dir area_hier.rpt]
foreach mode $modes {
    report_timing -views ${mode}.SS.setup_view -max_paths 30 > [file join $run_dir timing_${mode}.rpt]
    report_qor -view ${mode}.SS.setup_view > [file join $run_dir qor_${mode}.rpt]
    write_sdc -view ${mode}.SS.setup_view > [file join $run_dir mapped_${mode}.sdc]
}
report_gates > [file join $run_dir gates.rpt]
report_clock_gates > [file join $run_dir clock_gating.rpt]
report_analysis_views > [file join $run_dir analysis_views_final.rpt]
check_timing_intent > [file join $run_dir timing_intent_final.rpt]
set f [open [file join $run_dir complete.txt] w]
puts $f "top=$design period_ns=1.0 retiming=false clock_gating=true auto_ungroup=both"
close $f
exit
