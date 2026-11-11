# TSMC N28 (CLN28HPC+) PDK paths — shared across all designs in this repo.
# Only DEFINES variables; no create_* commands. Sourced by setup/mmmc_build.tcl
# and by Innovus init step.
#
# Sources of truth:
#   /data2/tools-additional/pdk/N28/cadence_ref/    (apr_tlef, qrc)
#   /data2/tools-additional/pdk/N28/installed/standard_cell/TSMCHOME/

if {![info exists tsmcn28_ref_root]} {
    set tsmcn28_ref_root "/data2/tools-additional/pdk/N28/cadence_ref"
}
if {![info exists tsmcn28_stdcell_root]} {
    set tsmcn28_stdcell_root "/data2/tools-additional/pdk/N28/installed/standard_cell/TSMCHOME"
}
if {![info exists tsmcn28_route_style]} {
    set tsmcn28_route_style "HVH"
}

# Tech LEF (10-metal, 5X2Y2R + RDL)
set tsmcn28_tech_lef [file join $tsmcn28_ref_root apr_tlef $tsmcn28_route_style tsmcn28_10lm5X2Y2RRDL.tlef]

# Standard-cell LEFs (RVT / HVT / LVT)
set tsmcn28_std_lefs [list \
    [file join $tsmcn28_stdcell_root digital Back_End lef tcbn28hpcplusbwp30p140_110a    lef tcbn28hpcplusbwp30p140.lef] \
    [file join $tsmcn28_stdcell_root digital Back_End lef tcbn28hpcplusbwp30p140hvt_110a lef tcbn28hpcplusbwp30p140hvt.lef] \
    [file join $tsmcn28_stdcell_root digital Back_End lef tcbn28hpcplusbwp30p140lvt_110a lef tcbn28hpcplusbwp30p140lvt.lef] \
]
set tsmcn28_lefs [concat [list $tsmcn28_tech_lef] $tsmcn28_std_lefs]

# Liberty libraries keyed by corner name. config.tcl references these keys.
set tsmcn28_libs_ss [list \
    [file join $tsmcn28_stdcell_root digital Front_End timing_power_noise NLDM tcbn28hpcplusbwp30p140_180a    tcbn28hpcplusbwp30p140ssg0p72v125c.lib]     \
    [file join $tsmcn28_stdcell_root digital Front_End timing_power_noise NLDM tcbn28hpcplusbwp30p140hvt_180a tcbn28hpcplusbwp30p140hvtssg0p72v125c.lib] \
    [file join $tsmcn28_stdcell_root digital Front_End timing_power_noise NLDM tcbn28hpcplusbwp30p140lvt_180a tcbn28hpcplusbwp30p140lvtssg0p72v125c.lib] \
]
set tsmcn28_libs_ff [list \
    [file join $tsmcn28_stdcell_root digital Front_End timing_power_noise NLDM tcbn28hpcplusbwp30p140_180a    tcbn28hpcplusbwp30p140ffg0p88vm40c.lib]     \
    [file join $tsmcn28_stdcell_root digital Front_End timing_power_noise NLDM tcbn28hpcplusbwp30p140hvt_180a tcbn28hpcplusbwp30p140hvtffg0p88vm40c.lib] \
    [file join $tsmcn28_stdcell_root digital Front_End timing_power_noise NLDM tcbn28hpcplusbwp30p140lvt_180a tcbn28hpcplusbwp30p140lvtffg0p88vm40c.lib] \
]
set tsmcn28_libs_tt [list \
    [file join $tsmcn28_stdcell_root digital Front_End timing_power_noise NLDM tcbn28hpcplusbwp30p140_180a    tcbn28hpcplusbwp30p140tt0p8v25c.lib]     \
    [file join $tsmcn28_stdcell_root digital Front_End timing_power_noise NLDM tcbn28hpcplusbwp30p140hvt_180a tcbn28hpcplusbwp30p140hvttt0p8v25c.lib] \
    [file join $tsmcn28_stdcell_root digital Front_End timing_power_noise NLDM tcbn28hpcplusbwp30p140lvt_180a tcbn28hpcplusbwp30p140lvttt0p8v25c.lib] \
]
array set tsmcn28_libs_by_corner [list \
    ss $tsmcn28_libs_ss \
    ff $tsmcn28_libs_ff \
    tt $tsmcn28_libs_tt \
]

# QRC tech files
set tsmcn28_qrc_setup [file join $tsmcn28_ref_root qrc cln28hpcplus_1p10m_5x2y2r rcworst qrcTechFile]
set tsmcn28_qrc_hold  [file join $tsmcn28_ref_root qrc cln28hpcplus_1p10m_5x2y2r rcbest  qrcTechFile]
set tsmcn28_qrc_tt    [file join $tsmcn28_ref_root qrc cln28hpcplus_1p10m_5x2y2r typical qrcTechFile]
array set tsmcn28_qrc_by_corner [list \
    setup $tsmcn28_qrc_setup \
    hold  $tsmcn28_qrc_hold  \
    tt    $tsmcn28_qrc_tt    \
]

# Sanity: every referenced file must exist.
foreach f [concat $tsmcn28_lefs $tsmcn28_libs_ss $tsmcn28_libs_ff $tsmcn28_libs_tt \
               [list $tsmcn28_qrc_setup $tsmcn28_qrc_hold $tsmcn28_qrc_tt]] {
    if {![file exists $f]} {
        error "tsmcn28_libs.tcl: missing PDK file: $f"
    }
}
