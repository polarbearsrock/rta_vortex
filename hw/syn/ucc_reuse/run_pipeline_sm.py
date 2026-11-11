#!/usr/bin/env python3
"""Measure frozen pipeline RTL in the SM Genus25 LEF/QRC flow."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess

from run_sm_corner import GENUS, LIBS, SM, digest


def prepare(baseline, run):
    old = json.loads((baseline / 'manifest.json').read_text())
    if digest(baseline / 'design.sv') != old['design_sha256']:
        raise RuntimeError('Frozen RTL hash mismatch')
    top = old['top']
    if top == 'ucc_b32_pipe5':
        modes, params, latency = ['dpa', 'cuda'], {}, 'all operations: 5 cycles, II=1'
        if old.get('sfu_latency', 5) != 5:
            latency = (f'FP32/INT32/DPA: 5 cycles; SFU: {old["sfu_latency"]} cycles; '
                       'homogeneous II=1; dispatcher follows fixed reservations')
    elif top == 'ucc_dpa16_baseline':
        modes, params, latency = ['dpa'], {'DpaStages': 5}, 'DPA: 5 cycles, II=1'
    elif top == 'ucc_lane':
        modes, params = ['all'], {'EnableFp64': 0, 'PackedIntLow': 1,
                                  'CompactAccumulator': 1, 'FixedScalarAlign': 1}
        latency = 'Original reference: DPA 4 / FMA 3 / MUFU 5 cycles'
    else:
        raise ValueError('Unsupported frozen top: ' + top)
    run.mkdir(parents=True, exist_ok=False)
    ref = run / 'reference'
    ref.mkdir()
    refs = {'config.tcl': SM / 'config.tcl',
            'fpu_block_top.sdc': SM / 'constraints/fpu_block_top.sdc',
            'mmmc_build_macros.tcl': SM / 'syn/mmmc_build_macros.tcl',
            'run_genus.tcl': SM / 'syn/run_genus.tcl', 'tsmcn28_libs.tcl': LIBS}
    for name, path in refs.items():
        shutil.copyfile(path, ref / name)
    shutil.copyfile(baseline / 'design.sv', run / 'design.sv')
    shutil.copyfile(baseline / 'manifest.json', run / 'source_manifest.json')
    sdc = refs['fpu_block_top.sdc'].read_text()
    replacements = {'[get_ports clk]': '[get_ports clk_i]',
                    '[get_ports {clk reset}]': '[get_ports {clk_i rst_ni}]',
                    '[get_ports reset]': '[get_ports rst_ni]'}
    for before, after in replacements.items():
        if sdc.count(before) != 1:
            raise RuntimeError('Reference SDC changed: ' + before)
        sdc = sdc.replace(before, after)
    sdc = '\n'.join(x for x in sdc.splitlines() if not x.startswith('#')) + '\n'
    for mode in modes:
        content = sdc
        if top == 'ucc_b32_pipe5':
            content = content.replace('{clk_i rst_ni}', '{clk_i rst_ni dpa_mode_i}')
            content += f'set_case_analysis {int(mode == "dpa")} [get_ports dpa_mode_i]\n'
        (run / f'{mode}.sdc').write_text(content)
    query = f'''set ::flow_root {{{SM}}}
source {{{ref / 'config.tcl'}}}
source {{{ref / 'tsmcn28_libs.tcl'}}}
foreach v $cfg(views) {{puts "VIEW\t[join $v ,]"}}
foreach c {{ss ff tt}} {{foreach p $tsmcn28_libs_by_corner($c) {{puts "LIB\t$c\t$p"}}}}
foreach p $tsmcn28_lefs {{puts "LEF\t$p"}}
foreach c {{setup hold tt}} {{puts "QRC\t$c\t$tsmcn28_qrc_by_corner($c)"}}
'''
    resolved = subprocess.check_output(['tclsh'], input=query, text=True)
    views, pdk = [], []
    for line in resolved.splitlines():
        fields = line.split('\t')
        if fields[0] == 'VIEW':
            views.append(fields[1].split(','))
        elif fields[0] in ('LIB', 'LEF', 'QRC'):
            path = Path(fields[-1])
            pdk.append(dict(kind=fields[0], corner=fields[1] if len(fields) == 3 else None,
                            path=str(path), sha256=digest(path)))
    if views != [['SS.setup_view', 'ss', '125.0', 'setup', '1', '0'],
                 ['FF.hold_view', 'ff', '-40.0', 'hold', '0', '1'],
                 ['TT.extra_view', 'tt', '25.0', 'tt', '0', '1']]:
        raise RuntimeError('Reference MMMC view definitions changed')
    flow = (f'set design {top}\nset modes {{{" ".join(modes)}}}\n'
            'set elab_parameters {' + ' '.join(f'{{{k} {v}}}' for k, v in params.items()) + '}\n')
    (run / 'flow.tcl').write_text(flow)
    for name, source in [('synth.tcl', 'synth_pipeline_sm.tcl'),
                         ('mmmc.tcl', 'mmmc_pipeline_sm.tcl')]:
        shutil.copyfile(Path(__file__).with_name(source), run / name)
    inputs = [run / name for name in ['design.sv', 'source_manifest.json', 'flow.tcl',
                                      'synth.tcl', 'mmmc.tcl']]
    inputs += [run / f'{m}.sdc' for m in modes] + sorted(ref.iterdir())
    manifest = dict(source_run=str(baseline), top=top, latency=latency,
                    design_sha256=old['design_sha256'], elaboration_parameters=params,
                    genus_executable=str(GENUS), corner='SSG 0.72 V /125 C', voltage_v=0.72,
                    views=views, modes=modes, setup_views=[m + '.SS.setup_view' for m in modes],
                    period_ns=1.0, input_delay_ns=0.30, output_delay_ns=0.30,
                    setup_uncertainty_ns=0.05, clock_transition_ns=0.05,
                    max_transition_ns=0.10, max_fanout=32, driving_cell='BUFFD4BWP30P140',
                    output_load_pf=0.005, reset_timing='false path from rst_ni',
                    generic_effort='medium', map_effort='high', opt_effort='high',
                    automatic_ungroup='both', clock_gating=True, retiming=False,
                    clock_gating_min_flops=2, clock_gating_max_flops=100000,
                    physical_inputs='SM technology/cell LEFs and QRC corners; PLE, no placement/routing',
                    mode_assumption=('dpa_mode_i static in DPA/CUDA views; drain pipeline before switch'
                                     if top == 'ucc_b32_pipe5' else 'all opcode/format inputs dynamic'),
                    pdk_files=pdk, reference_files={str(p): digest(p) for p in refs.values()},
                    prior_validation='Unchanged RTL: retain source-run validation; no new gate replay',
                    input_sha256={str(p.relative_to(run)): digest(p) for p in inputs})
    if top == 'ucc_b32_pipe5':
        manifest.update(normal_latency=5, sfu_latency=old.get('sfu_latency', 5),
                        reservation_contract=old.get('reservation_contract', 'arbitrary CUDA mixed issue, II=1'),
                        rtl_validation=old.get('rtl_validation', 'See frozen source manifest'))
    (run / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


def launch(run):
    manifest = json.loads((run / 'manifest.json').read_text())
    for name, expected in manifest['input_sha256'].items():
        if digest(run / name) != expected:
            raise RuntimeError('Prepared input changed: ' + name)
    env = dict(os.environ, UCC_RUN_DIR=str(run),
               CDS_LIC_FILE=os.environ.get('CDS_LIC_FILE', '27006@cadencels.s.uw.edu'))
    env.pop('CDN_SYNTH_ROOT', None)
    env['PATH'] = str(GENUS.parent) + ':' + env['PATH']
    state = dict(started_utc=datetime.now(timezone.utc).isoformat())
    with (run / 'run.log').open('x') as log:
        child = subprocess.Popen([str(GENUS), '-batch', '-files', 'synth.tcl', '-log', 'genus'],
                                 cwd=run, env=env, stdout=log, stderr=subprocess.STDOUT)
        (run / 'genus.pid').write_text(str(child.pid) + '\n')
        state['pid'] = child.pid
        (run / 'launch.json').write_text(json.dumps(state, indent=2) + '\n')
        code = child.wait()
    state.update(returncode=code, finished_utc=datetime.now(timezone.utc).isoformat(),
                 complete=(run / 'complete.txt').exists())
    (run / 'launch.json').write_text(json.dumps(state, indent=2) + '\n')
    if code or not state['complete']:
        raise RuntimeError('Synthesis incomplete; inspect ' + str(run / 'run.log'))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline', type=Path)
    p.add_argument('--run-dir', type=Path, required=True)
    p.add_argument('--launch', action='store_true')
    args = p.parse_args()
    if args.baseline:
        prepare(args.baseline.resolve(), args.run_dir.resolve())
    if args.launch:
        launch(args.run_dir.resolve())
    elif not args.baseline:
        p.error('Supply --baseline to prepare or --launch to execute a prepared run')


if __name__ == '__main__':
    main()
