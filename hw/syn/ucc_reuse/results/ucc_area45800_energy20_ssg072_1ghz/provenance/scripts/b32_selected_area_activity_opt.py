#!/usr/bin/env python3
"""Incrementally optimize the audited selected mapping with fixed state and activity."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

from b32_clockoff_data_pin_power import checked, dump
from b32_collect_manual_synthesis_v2 import run as collect
from b32_fixed_four_activity_prepare import quoted
from b32_fixed_four_power_flow import compare_inputs
from b32_macro_restore_guard_boundaries import GUARDS
from b32_manual_cut_synthesize_v2 import TCL as SYNTH_TCL
from b32_mapped_structural_parser import parse_netlist
from b32_pipeline_import_timing_full import TCL as IMPORT_TCL
from b32_power import now
from b32_tcf_rate_audit import audit as rate_audit
from run_sm_corner import digest


def execute(root, script):
    env = dict(os.environ, UCC_RUN_DIR=str(root), CDS_LIC_FILE='27006@cadencels.s.uw.edu')
    env.pop('CDN_SYNTH_ROOT', None)
    launch = dict(started_utc=now(), complete=False)
    with (root / 'driver.log').open('w') as log:
        child = subprocess.Popen(['/data/eda_tools/cadence/DDI251/GENUS251/bin/genus',
            '-batch', '-files', script, '-log', 'genus'], cwd=root, env=env,
            stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT)
        launch['pid'] = child.pid
        dump(root / 'launch.json', launch)
        print('TEMPORAL_CAPTURE_GENUS_LAUNCHED', child.pid, str(root), flush=True)
        code = child.wait()
    launch.update(returncode=code, complete=code == 0 and (root / 'complete.txt').exists(), finished_utc=now())
    dump(root / 'launch.json', launch)
    assert launch['complete'], (str(root), code)


def run(candidate, check, reference, power, contract, selected, out):
    assert not out.exists()
    record = checked(candidate / 'candidate.json')
    verified = checked(check / 'result.json')
    measured = checked(power / 'comparison.json')
    base = checked(reference / 'manifest.json')
    limits = checked(contract)
    pm = json.loads((power / 'manifest.json').read_text())
    assert verified['passed'] and verified['checks'] >= 143744
    selection = checked(selected / 'selection.json')
    audit = checked(selected / 'audit.json')
    assert selection['mapped_sha256'] == record['mapped_sha256'] == audit['mapped_sha256']
    assert all(audit['checks'].values())
    assert record['control_clamp_relational_proved'] and record['residual_capture_hold_proved']
    assert sum(t == 'ICG' for t, n, pins in parse_netlist(candidate / 'mapped.v')[0]) == 170
    assert measured['complete'] and record['mapped_sha256'] == verified['mapped_sha256'] == digest(power / 'mapped.v') == digest(candidate / 'mapped.v')
    assert base['period_ns'] == 1 and base['input_delay_ns'] == base['output_delay_ns'] == .3 and base['retiming'] is False
    assert pm['period_ps'] == 1000 and pm['latency_policy']['sfu'] == 6
    streams = ['fma32', 'add32', 'mul32', 'sfu_ex2']
    assert limits['scalar_equal_weight_streams'] == streams
    compare_inputs(power, limits)
    for row in base['pdk_files']:
        assert digest(Path(row['path'])) == row['sha256']
    out.mkdir(parents=True)
    export, mean, opt = out / 'activity_export', out / 'activity_mean', out / 'opt'
    export.mkdir()
    for name in ['flow.tcl', 'mmmc.tcl', 'dpa.sdc', 'cuda.sdc']:
        shutil.copy2(reference / name, export / name)
    shutil.copytree(reference / 'reference', export / 'reference')
    shutil.copy2(candidate / 'mapped.v', export / 'input.v')
    prefix = IMPORT_TCL[:IMPORT_TCL.index('check_design -unresolved')]
    prefix += GUARDS
    prefix += 'set cg_pins [get_db pins */RC_CGIC_INST/E]\nif {[llength $cg_pins] != 170} {error "Unexpected capture clock gate count"}\nforeach mode $modes {\n    set_analysis_view -setup [list ${mode}.SS.setup_view] -hold [list ${mode}.FF.hold_view ${mode}.TT.extra_view]\n    set_clock_gating_check -setup 0.0\n    if {![llength [get_db cost_groups cg_enable_group_clk]]} {define_cost_group -name cg_enable_group_clk -weight 1}\n    path_group -to $cg_pins -group cg_enable_group_clk -view ${mode}.SS.setup_view\n}\nset_analysis_view -setup $setup_views -hold $hold_views -dynamic cuda.SS.setup_view\n'
    prefix += '''set_analysis_view -setup $setup_views -hold $hold_views -dynamic cuda.SS.setup_view
write_db [file join $run_dir imported.db]
write_hdl > [file join $run_dir imported.v]
'''
    evidence = [selected / 'selection.json', selected / 'audit.json', candidate / 'candidate.json', candidate / 'mapped.v', check / 'result.json',
                reference / 'manifest.json', power / 'manifest.json', power / 'comparison.json', contract,
                Path(__file__).resolve(), Path(__file__).with_name('b32_pipeline_import_timing_full.py'),
                Path(__file__).with_name('b32_macro_restore_guard_boundaries.py')]
    records = {}
    for op in streams:
        sim = pm['gate_simulation'][op]
        assert sim['checked'] == 1100 and sim['window_ps'] == [109000, 1109000]
        vcd = power / (op + '.vcd')
        assert digest(vcd) == sim['vcd_sha256']
        actual = json.loads((power / ('power_' + op) / 'result.json').read_text())
        assert all(row['percent'] == 100 for row in actual['annotation'].values())
        prefix += f'read_vcd -static -vcd_scope tb.dut -start_time 109000 -end_time 1109000 {quoted(vcd)}\n'
        prefix += f'write_tcf > {quoted(export / (op + ".tcf"))}\n'
        records[op] = dict(checked_rows=1100, window_ps=sim['window_ps'], vcd_sha256=sim['vcd_sha256'])
        evidence += [vcd, power / (op + '.txt'), power / ('power_' + op) / 'result.json']
    prefix += '''set f [open [file join $run_dir complete.txt] w]
puts $f "Mapped import and activity export only; no optimization"
close $f
exit
'''
    (export / 'export.tcl').write_text(prefix)
    dump(out / 'status.json', dict(state='importing_activity', selected_changed=False, updated_utc=now()))
    execute(export, 'export.tcl')
    before = {n: (t, p) for t, n, p in parse_netlist(candidate / 'mapped.v')[0]}
    after = {n: (t, p) for t, n, p in parse_netlist(export / 'imported.v')[0]}
    assert before == after
    evidence += [p for p in export.rglob('*') if p.is_file() and p.name != 'manifest.json']
    dump(export / 'manifest.json', dict(source_database=str(export / 'imported.db'),
        source_database_sha256=digest(export / 'imported.db'), power=str(power),
        fixed_sfu_opcode='0x7a', streams=records, synthesis_performed=False, optimization_performed=False,
        imported_connectivity_unchanged=True, evidence_sha256={str(p): digest(p) for p in evidence}))
    subprocess.run([sys.executable, str(Path(__file__).with_name('b32_fixed_four_activity_mean.py')),
                    '--source', str(export), '--out', str(mean)], check=True)
    activity = json.loads((mean / 'manifest.json').read_text())
    assert activity['source_database_sha256'] == digest(export / 'imported.db')
    opt.mkdir()
    for name in ['flow.tcl', 'mmmc.tcl', 'dpa.sdc', 'cuda.sdc']:
        shutil.copy2(reference / name, opt / name)
    shutil.copytree(reference / 'reference', opt / 'reference')
    shutil.copy2(mean / 'cuda_equal4.tcf', opt / 'cuda_equal4.tcf')
    start = f'''set run_dir [file normalize $::env(UCC_RUN_DIR)]
read_db {quoted(export / 'imported.db')}
set design ucc_b32_pipe5
set modes {{dpa cuda}}
set setup_views {{dpa.SS.setup_view cuda.SS.setup_view}}
set hold_views {{dpa.FF.hold_view cuda.FF.hold_view dpa.TT.extra_view cuda.TT.extra_view}}
set_db max_cpus_per_server 4
set_analysis_view -setup $setup_views -hold $hold_views -dynamic cuda.SS.setup_view
if {{[get_db design:$design .retime] ne "false"}} {{error "Unexpected retiming"}}
set_db [get_db insts] .preserve false
set protected [open [file join $run_dir fixed_registers.rpt] w]
foreach cell [get_db insts] {{
    if {{[get_db $cell .is_sequential]}} {{
        set_db $cell .preserve size_ok
        puts $protected "[get_db $cell .name] [get_db $cell .preserve]"
    }}
}}
close $protected
'''
    start += GUARDS
    start += 'set cg_pins [get_db pins */RC_CGIC_INST/E]\nif {[llength $cg_pins] != 170} {error "Unexpected capture clock gate count"}\nforeach mode $modes {\n    set_analysis_view -setup [list ${mode}.SS.setup_view] -hold [list ${mode}.FF.hold_view ${mode}.TT.extra_view]\n    set_clock_gating_check -setup 0.0\n    if {![llength [get_db cost_groups cg_enable_group_clk]]} {define_cost_group -name cg_enable_group_clk -weight 1}\n    path_group -to $cg_pins -group cg_enable_group_clk -view ${mode}.SS.setup_view\n}\nset_analysis_view -setup $setup_views -hold $hold_views -dynamic cuda.SS.setup_view\n'
    start += '''read_tcf [file join $run_dir cuda_equal4.tcf]
write_tcf > [file join $run_dir activity_roundtrip.tcf]
set_db design_power_effort high
set_db opt_leakage_to_dynamic_ratio 0.0
set_db drc_first true
set f [open [file join $run_dir settings.rpt] w]
foreach attr {auto_ungroup lp_insert_clock_gating syn_generic_effort syn_map_effort syn_opt_effort interconnect_mode use_scan_seqs_for_non_dft design_power_effort opt_leakage_to_dynamic_ratio drc_first} {
    puts $f "$attr=[get_db $attr]"
}
puts $f "retime=[get_db design:$design .retime]"
puts $f "optimization_performed=true"
puts $f "setup_views=$setup_views"
puts $f "hold_views=$hold_views"
close $f
check_design -unresolved > [file join $run_dir unresolved.rpt]
report_power -view cuda.SS.setup_view > [file join $run_dir power_before.rpt]
syn_opt -incremental
report_power -view cuda.SS.setup_view > [file join $run_dir power_after.rpt]
'''
    marker = 'if {[get_db design:$design .retime] ne "false"} {error "Retiming was enabled"}\n'
    script = start + SYNTH_TCL[SYNTH_TCL.index(marker):]
    script = script.replace('Manual RTL captures; generic/map/opt with retiming=false',
                            'Mapped guard cut; incremental optimization with register locations fixed')
    (opt / 'synth.tcl').write_text(script)
    sources = [p for p in opt.rglob('*') if p.is_file()]
    sources += [export / 'manifest.json', export / 'imported.db', mean / 'manifest.json', candidate / 'candidate.json',
                check / 'result.json', reference / 'manifest.json', Path(__file__).resolve(),
                Path(__file__).with_name('b32_manual_cut_synthesize_v2.py'),
                Path(__file__).with_name('b32_collect_manual_synthesis_v2.py')]
    manifest = dict(candidate=str(candidate), rtl=base['rtl'], native_rtl_reference_only=True,
        input_mapping=str(candidate / 'mapped.v'), input_mapping_sha256=record['mapped_sha256'],
        reference=str(reference), pdk_files=base['pdk_files'], period_ns=1, input_delay_ns=.3, output_delay_ns=.3,
        retiming=False, register_preservation='size_ok', synthesis_performed=True, optimization_performed=True,
        full_rtl_remap=False, normal_latency=5, sfu_latency=6, instruction_latencies=pm['latency_policy'],
        check=str(check), activity_profile=str(mean), design_power_effort='high',
        opt_leakage_to_dynamic_ratio=0.0, evidence_sha256={str(p): digest(p) for p in sources})
    dump(opt / 'manifest.json', manifest)
    dump(out / 'status.json', dict(state='optimizing_fixed_cut', selected_changed=False, updated_utc=now()))
    execute(opt, 'synth.tcl')
    dump(opt / 'activity_rate_audit.json', rate_audit(opt / 'cuda_equal4.tcf', opt / 'activity_roundtrip.tcf'))
    collect(opt, opt / 'collected.json')
    result = json.loads((opt / 'collected.json').read_text())
    result.update(full_rtl_remap=False, native_rtl_reference_only=True, register_locations_fixed=True,
                  scope='Incremental optimization of the verified mapped guard cut with fixed register locations, '
                        'unchanged SM constraints and equal-count fixed-four activity. Fresh Joules is still required.')
    result['evidence_sha256'][str(opt / 'collected.json')] = digest(opt / 'collected.json')
    dump(opt / 'result.json', result)
    dump(out / 'status.json', dict(state='complete', selected_changed=False, objective_complete=False, updated_utc=now()))
    print('TEMPORAL_CAPTURE_OPT_COMPLETE', result['cell_area_um2'], result['views'], flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    names = ['candidate', 'check', 'reference', 'power', 'contract', 'selected', 'out']
    for name in names:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    run(*(getattr(args, name).resolve() for name in names))
