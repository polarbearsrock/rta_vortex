#!/usr/bin/env python3
"""Repair timing by cell sizing with every existing instance preserved."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from b32_mapped_structural_parser import parse_netlist
from b32_macro_restore_guard_boundaries import GUARDS
from run_sm_corner import digest


TCL = '''set run_dir [file normalize $::env(UCC_RUN_DIR)]
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
puts $f "optimization_performed=true"
close $f
set cg_pins [get_db pins */RC_CGIC_INST/E]
foreach mode $modes {
    set_analysis_view -setup [list ${mode}.SS.setup_view] -hold [list ${mode}.FF.hold_view ${mode}.TT.extra_view]
    set_clock_gating_check -setup 0.0
    if {![llength [get_db cost_groups cg_enable_group_clk]]} {define_cost_group -name cg_enable_group_clk -weight 1}
    path_group -to $cg_pins -group cg_enable_group_clk -view ${mode}.SS.setup_view
}
set_analysis_view -setup $setup_views -hold $hold_views
set_db max_cpus_per_server 4
set_db [get_db insts] .preserve size_ok
set_db drc_first true
set f [open [file join $run_dir fixed_instances.rpt] w]
foreach cell [get_db insts] {puts $f "[get_db $cell .name] [get_db $cell .preserve]"}
close $f
syn_opt -incremental
write_hdl > [file join $run_dir optimized.v]
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
puts $f "Instance-preserving incremental sizing; retiming disabled"
close $f
exit
'''


TCL = TCL.replace('set_db [get_db insts] .preserve size_ok', GUARDS + 'set_db [get_db insts] .preserve size_ok')

def dump(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def run(reference, mapped, out):
    assert not out.exists()
    original = json.loads((reference / 'manifest.json').read_text())
    assert original['period_ns'] == 1 and original['retiming'] is False
    for entry in original['pdk_files']:
        assert digest(Path(entry['path'])) == entry['sha256'], entry['path']
    cells, _ = parse_netlist(mapped)
    expected = {name: typ for typ, name, pins in cells}
    out.mkdir(parents=True)
    for name in ['flow.tcl', 'mmmc.tcl', 'dpa.sdc', 'cuda.sdc']:
        shutil.copy2(reference / name, out / name)
    shutil.copytree(reference / 'reference', out / 'reference')
    shutil.copy2(mapped, out / 'input.v')
    guard_modules = []
    source_text = mapped.read_text()
    for instance in ['shared_alignment_dpa_guard', 'shared_alignment_scalar_guard']:
        found = re.search(r'^\s*(\w+)\s+' + instance + r'\s*\(', source_text, re.M)
        assert found, instance
        guard_modules.append(found[1])
    assert len(set(guard_modules)) == 2
    selection = 'set mode_guards [concat ' + ' '.join('[get_db modules {' + name + '}]' for name in guard_modules) + ']'
    script = TCL.replace('set mode_guards [get_db modules *ucc_mode_output_guard*]', selection)
    assert script != TCL
    (out / 'timing.tcl').write_text(script)
    files = [p for p in out.rglob('*') if p.is_file()]
    files += [Path(__file__).resolve(), Path(__file__).with_name('b32_mapped_structural_parser.py'),
              reference / 'manifest.json', mapped, Path(__file__).with_name('b32_macro_restore_guard_boundaries.py')]
    manifest = dict(reference=str(reference), mapped=str(mapped), mapped_sha256=digest(mapped),
                    expected_cell_count=len(cells), pdk_files=original['pdk_files'],
                    optimization_performed=True, synthesis_performed=False,
                    evidence_sha256={str(p): digest(p) for p in files})
    dump(out / 'manifest.json', manifest)
    env = dict(os.environ, UCC_RUN_DIR=str(out), UCC_EXPECTED_CELLS=str(len(cells)), UCC_EXPECTED_ICGS=str(sum(t == 'ICG' for t, n, p in cells)),
               CDS_LIC_FILE='27006@cadencels.s.uw.edu')
    env.pop('CDN_SYNTH_ROOT', None)
    command = ['/data/eda_tools/cadence/DDI251/GENUS251/bin/genus', '-batch',
               '-files', 'timing.tcl', '-log', 'genus']
    launch = dict(command=command, started_utc=datetime.now(timezone.utc).isoformat(), complete=False)
    with (out / 'driver.log').open('w') as log:
        child = subprocess.Popen(command, cwd=out, env=env, stdin=subprocess.DEVNULL,
                                 stdout=log, stderr=subprocess.STDOUT)
        launch['pid'] = child.pid
        dump(out / 'launch.json', launch)
        print('PIPELINE_TIMING_IMPORT_LAUNCHED', child.pid, str(out), flush=True)
        code = child.wait()
    launch.update(returncode=code, complete=code == 0 and (out / 'complete.txt').exists(),
                  finished_utc=datetime.now(timezone.utc).isoformat())
    dump(out / 'launch.json', launch)
    assert launch['complete'], (code, (out / 'driver.log').read_text()[-3000:])
    invariants = dict(re.findall(r'(\w+)=(\d+)', (out / 'invariants.rpt').read_text()))
    assert invariants == {'dpa_cuts': '0', 'dpa_cells': str(len(cells)),
                          'cuda_cuts': '0', 'cuda_cells': str(len(cells))}
    actual = {name: typ for typ, name, pins in parse_netlist(out / 'checked.v')[0]}
    assert actual.keys() == expected.keys(), 'Instance preservation was violated'
    source_graph = {n: p for t, n, p in cells}
    final_graph = {n: p for t, n, p in parse_netlist(out / 'checked.v')[0]}
    assert final_graph == source_graph, 'Cell sizing changed connectivity'
    master_changes = {n: dict(before=expected[n], after=t) for n, t in actual.items() if t != expected[n]}
    dump(out / 'master_changes.json', dict(mapped_sha256=digest(mapped), resized_cells=master_changes, cloned_drivers={}))
    timing, violations = {}, {}
    for mode in ['dpa', 'cuda']:
        report = (out / f'timing_{mode}.rpt').read_text()
        match = re.search(r'Path 1: \w+ \(([-\d.]+) ps\)', report)
        assert match, report[:1000]
        timing[mode] = float(match[1])
        violations[mode] = {kind: len(re.findall(r'\|(pin|port):',
            (out / f'{mode}_{kind}.rpt').read_text()))
            for kind in ['max_transition', 'max_fanout', 'max_capacitance']}
    area = re.search(r'^ucc_b32_pipe5\s+NA\s+(\d+)\s+([\d.]+)',
                     (out / 'area.rpt').read_text(), re.M)
    assert area and int(area[1]) == len(cells)
    for name, sha in manifest['evidence_sha256'].items():
        assert digest(Path(name)) == sha, name
    files = [p for p in out.rglob('*') if p.is_file()]
    result = dict(complete=True, cell_count=len(cells), cell_area_um2=float(area[2]),
                  worst_slack_ps=timing, drv_violation_rows=violations,
                  original_cell_masters_preserved=not master_changes, optimization_performed=True,
                  mapped_sha256=digest(out / 'checked.v'), source_mapped_sha256=digest(mapped), final_goal_accepted=False,
                  scope='Paired mapped-netlist import under matched 1 GHz LEF/QRC constraints. '
                        'Every instance is preserved with sizing allowed. No retiming or connectivity changes; fresh power is still required.',
                  evidence_sha256={str(p): digest(p) for p in files})
    dump(out / 'result.json', result)
    print('PRESERVED_INSTANCE_SIZING_COMPLETE', result['cell_area_um2'], timing, violations, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['reference', 'mapped', 'out']:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    run(*(getattr(args, name).resolve() for name in ['reference', 'mapped', 'out']))
