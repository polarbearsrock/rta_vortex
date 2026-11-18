# Auto-generated PE-area sweep config.tcl
array set cfg {}
set cfg(design)         fpu_block_top
set cfg(rtl_filelist)   [file join $::flow_root syn filelist.f]
set cfg(netlist_mapped) [file join $::flow_root syn outputs $cfg(design).mapped.v]
set cfg(sdc)            [file join $::flow_root constraints $cfg(design).sdc]

# -------------------------------------------------------------------------
# 2. PROCESS / POWER INTENT
# -------------------------------------------------------------------------
set cfg(process_node) 28
set cfg(core_site)    core
set cfg(power_nets)   {VDD}
set cfg(ground_nets)  {VSS}

# -------------------------------------------------------------------------
# 3. MMMC VIEWS — same triple as the example_pe_ttsa reference.
# -------------------------------------------------------------------------
set cfg(views) {
    {SS.setup_view ss  125.0 setup 1 0}
    {FF.hold_view  ff  -40.0 hold  0 1}
    {TT.extra_view tt   25.0 tt    0 1}
}

# -------------------------------------------------------------------------
# 4. FLOORPLAN — density-driven for a unit-level PE, leave the tool to
#    size the die. We tune this once we know the gate count.
# -------------------------------------------------------------------------
set cfg(fp_mode)         util
set cfg(fp_util)         0.50
set cfg(fp_aspect_ratio) 1.0
set cfg(fp_core_margins) {4 4 4 4}
set cfg(fp_die_size)     {200 200}   ;# only used if fp_mode == die
set cfg(fp_flip)         f

# -------------------------------------------------------------------------
# 5. MACRO PLACEMENT — none, PE is stdcell-only.
# -------------------------------------------------------------------------
set cfg(macros) {}
set cfg(macro_halo) 2.0
set cfg(macro_block_top) 1

# -------------------------------------------------------------------------
# 6. PIN / PORT PLACEMENT — auto for now; switch to file mode + pins.tcl
#    when we know which edge each cascade chain wants to exit on.
# -------------------------------------------------------------------------
set cfg(pin_mode) auto
set cfg(pin_file) [file join $::flow_root pins.tcl]
set cfg(pin_layer_min) M3
set cfg(pin_layer_max) M6

# -------------------------------------------------------------------------
# 7. POWER GRID — copy the example_pe_ttsa values.
# -------------------------------------------------------------------------
set cfg(ring_layers)  {bottom M7 top M7 left M6 right M6}
set cfg(ring_width)   1.0
set cfg(ring_spacing) 0.3
set cfg(ring_offset)  0.5
set cfg(stripes) {
    {layer M6 dir vertical   width 0.6 spacing 0.3 pitch 10.0 offset 2.0}
    {layer M7 dir horizontal width 0.6 spacing 0.3 pitch 10.0 offset 2.0}
}
set cfg(rail_layer)   M1

# -------------------------------------------------------------------------
# 8. WELL-TAPS / TIE-OFFS / FILLERS
# -------------------------------------------------------------------------
set cfg(tap_cell)          TAPCELLBWP30P140
set cfg(tap_interval_um)   29.0
set cfg(tie_cells)         {TIEHBWP30P140 TIELBWP30P140}
set cfg(tie_max_distance)  50
set cfg(filler_cells) {
    FILL64BWP30P140 FILL32BWP30P140 FILL16BWP30P140
    FILL8BWP30P140  FILL4BWP30P140  FILL3BWP30P140  FILL2BWP30P140
}

# -------------------------------------------------------------------------
# 9. ROUTING
# -------------------------------------------------------------------------
set cfg(route_min_layer) 2
set cfg(route_max_layer) 7

# -------------------------------------------------------------------------
# 10. CTS — LVT buffers / inverters.
# -------------------------------------------------------------------------
set cfg(cts_buffers) {
    DCCKBD4BWP30P140LVT DCCKBD8BWP30P140LVT DCCKBD12BWP30P140LVT
    CKBD4BWP30P140LVT   CKBD8BWP30P140LVT   CKBD12BWP30P140LVT
}
set cfg(cts_inverters) {
    DCCKND4BWP30P140LVT DCCKND8BWP30P140LVT DCCKND12BWP30P140LVT
    CKND4BWP30P140LVT   CKND8BWP30P140LVT   CKND12BWP30P140LVT
}

# -------------------------------------------------------------------------
# 11. EFFORT KNOBS — high across the board for an honest area number.
# -------------------------------------------------------------------------
set cfg(place_effort) high
set cfg(cts_effort)   high
set cfg(route_effort) high
set cfg(opt_effort)   high

# -------------------------------------------------------------------------
# 12. TIMING ANALYSIS
# -------------------------------------------------------------------------
set cfg(enable_si)          1
set cfg(analysis_type)      ocv
set cfg(timing_cppr)        both

# -------------------------------------------------------------------------
# 13. OUTPUTS — we want LEF + LIB for Phase B's hierarchical array synth.
# -------------------------------------------------------------------------
set cfg(emit_spef_for_all_views) 1
set cfg(emit_gds)                1
set cfg(emit_lef)                1   ;# abstract LEF for use as a hard macro
set cfg(emit_lib)                1   ;# extracted timing model for Phase B
