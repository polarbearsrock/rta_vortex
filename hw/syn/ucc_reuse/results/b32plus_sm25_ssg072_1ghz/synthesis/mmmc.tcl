source [file join $run_dir reference tsmcn28_libs.tcl]
foreach mode $modes {
    create_constraint_mode -name $mode -sdc_files [list [file join $run_dir ${mode}.sdc]]
}
set setup_views {}
set hold_views {}
foreach v $cfg(views) {
    lassign $v vname lib_key temp qrc_key use_setup use_hold
    create_library_set -name ${vname}_libs -timing $tsmcn28_libs_by_corner($lib_key)
    create_timing_condition -name ${vname}_cond -library_sets [list ${vname}_libs]
    create_rc_corner -name ${vname}_rc -temperature $temp -qrc_tech $tsmcn28_qrc_by_corner($qrc_key)
    create_delay_corner -name ${vname}_delay -timing_condition ${vname}_cond -rc_corner ${vname}_rc
    foreach mode $modes {
        set name ${mode}.${vname}
        create_analysis_view -name $name -delay_corner ${vname}_delay -constraint_mode $mode
        if {$use_setup} { lappend setup_views $name }
        if {$use_hold} { lappend hold_views $name }
    }
}
set_analysis_view -setup $setup_views -hold $hold_views
