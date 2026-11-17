# Build MMMC views from $CFG(views). MMMC-2 style (required by Genus 25.1
# and stylus Innovus 25.1).
#
# Caller must have:
#   set ::flow_root ...        (pnr/<design>/)
#   set ::pnr_root ...         (pnr/)
#   set ::sdc_file ...         (constraints file)
#   set ::cfg(views) { ... }   (from config.tcl)
# via sourcing config.tcl first.

if {![info exists ::constraint_mode_name]} {
    set ::constraint_mode_name my_constraint_mode
}

source [file join $::pnr_root flow setup tsmcn28_libs.tcl]

create_constraint_mode -name $::constraint_mode_name -sdc_files [list $::sdc_file]

# Each view in $cfg(views) is:
#   {view_name lib_corner temp qrc_corner use_setup use_hold}
#   lib_corner : "ss" | "ff" | "tt"     (key into tsmcn28_libs_by_corner)
#   qrc_corner : "setup" | "hold" | "tt" (key into tsmcn28_qrc_by_corner)
proc ::_build_mmmc_views {views} {
    upvar 0 ::tsmcn28_libs_by_corner libs
    upvar 0 ::tsmcn28_qrc_by_corner  qrcs
    set setup_views {}
    set hold_views  {}
    foreach v $views {
        lassign $v vname lib_key temp qrc_key use_setup use_hold
        if {![info exists libs($lib_key)]} {
            error "mmmc_build: unknown lib corner '$lib_key' for view $vname"
        }
        if {![info exists qrcs($qrc_key)]} {
            error "mmmc_build: unknown qrc corner '$qrc_key' for view $vname"
        }
        set lib_set "${vname}_libs"
        set tc      "${vname}_cond"
        set rc      "${vname}_rc"
        set dc      "${vname}_delay"
        create_library_set      -name $lib_set -timing $libs($lib_key)
        create_timing_condition -name $tc -library_sets [list $lib_set]
        create_rc_corner        -name $rc -temperature $temp -qrc_tech $qrcs($qrc_key)
        create_delay_corner     -name $dc -timing_condition $tc -rc_corner $rc
        create_analysis_view    -name $vname -delay_corner $dc \
                                -constraint_mode $::constraint_mode_name
        if {$use_setup} { lappend setup_views $vname }
        if {$use_hold}  { lappend hold_views  $vname }
    }
    if {[llength $setup_views] == 0 || [llength $hold_views] == 0} {
        error "mmmc_build: need at least one setup and one hold view"
    }
    set_analysis_view -setup $setup_views -hold $hold_views
    puts "== MMMC set_analysis_view -setup {$setup_views} -hold {$hold_views}"
}

::_build_mmmc_views $::cfg(views)
